#!/usr/bin/env python3
"""Propose the next patch release.

Runs on every push to `develop` and keeps exactly one open pull request from
`release/x.y.z` to `master`. The branch is cut from `master`, `develop` is
merged into it, the patch version is bumped and the notes are filled in. Merging
that pull request is the release decision; `release.yml` tags it.

The branch is only moved by a manual run with `refresh` enabled. Pushing
`develop` into the release branch on every develop push would rebuild the same
tree a second time, so a normal run only refreshes the pull request body.

The version bump happens on top of the merge, never before it, so the version
line never conflicts between `master` and `develop`.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CMAKE = ROOT / "CMakeLists.txt"
METAINFO = ROOT / "packaging" / "io.github.guilhermelcosta.Catarina.metainfo.xml"
FLATPAK = ROOT / "packaging" / "io.github.guilhermelcosta.Catarina.yml"
MAX_NOTES = 20

PR_IN_SUBJECT = re.compile(r"\(#(\d+)\)$|^Merge pull request #(\d+)")
CLOSING = re.compile(
    r"^\s*(?:closes|fixes|resolves)\s+#(\d+)", re.IGNORECASE | re.MULTILINE
)


def run(*argv: str, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(argv, cwd=ROOT, text=True, capture_output=True)
    if check and proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(f"`{' '.join(argv)}` failed")
    return proc


def out(*argv: str) -> str:
    return run(*argv).stdout.strip()


def current_version() -> str:
    """Version on master, which is the released state."""
    proc = run("git", "show", "origin/master:CMakeLists.txt", check=False)
    text = proc.stdout if proc.returncode == 0 else CMAKE.read_text()
    match = re.search(r"project\(catarina VERSION ([0-9]+\.[0-9]+\.[0-9]+)", text)
    if not match:
        raise SystemExit("cannot read the version from CMakeLists.txt")
    return match.group(1)


def bump(version: str) -> str:
    major, minor, patch = (int(part) for part in version.split("."))
    return f"{major}.{minor}.{patch + 1}"


def latest_tag() -> str | None:
    """Last released tag, from master: develop does not carry the release bump."""
    proc = run("git", "describe", "--tags", "--abbrev=0", "origin/master", check=False)
    return proc.stdout.strip() if proc.returncode == 0 else None


def changes(since: str | None, branch: str = "origin/develop") -> list[str]:
    revision = f"{since}..{branch}" if since else branch
    subjects = out("git", "log", "--no-merges", "--format=%s", revision).splitlines()
    return [
        subject
        for subject in subjects
        if subject and not subject.startswith("chore(release):")
    ]


def resolved_issues(since: str | None, branch: str = "origin/develop") -> list[int]:
    """Issues closed by the pull requests merged since the last release.

    They are listed in the proposal body, so GitHub closes them when the
    proposal reaches master, never before.
    """
    revision = f"{since}..{branch}" if since else branch
    subjects = out("git", "log", "--format=%s", revision).splitlines()
    pulls = set()
    for subject in subjects:
        match = PR_IN_SUBJECT.search(subject)
        if match:
            pulls.add(int(match.group(1) or match.group(2)))
    if not pulls:
        return []

    listing = json.loads(
        out("gh", "pr", "list", "--state", "merged", "--limit", "200", "--json", "number,body")
    )
    issues = set()
    for pull in listing:
        if pull["number"] in pulls:
            issues.update(int(number) for number in CLOSING.findall(pull["body"] or ""))
    return sorted(issues)


def body(version: str, since: str | None, subjects: list[str], issues: list[int], behind: int = 0) -> str:
    lines = [f"Release {version}", ""]
    if issues:
        lines += [f"Closes #{number}" for number in issues]
        lines.append("")
    if subjects:
        lines.append(f"Changes since {since}:" if since else "Changes:")
        lines += [f"- {subject}" for subject in subjects[:MAX_NOTES]]
        hidden = len(subjects) - MAX_NOTES
        if hidden > 0:
            lines.append(f"- and {hidden} more, see the commit log")
        lines.append("")
    if behind:
        lines += [
            f"This branch is {behind} commit(s) behind `develop`. Merging it now "
            "releases the tree as it is, and those commits ship in the next "
            "release. Run the Release proposal workflow with `refresh` enabled "
            "to include them now.",
            "",
        ]
    lines += [
        f"Merging this pull request creates tag v{version} on `master`.",
        "",
        "Edit this branch before merging to change the version or the notes.",
    ]
    return "\n".join(lines) + "\n"


def xml(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def release_entry(version: str, subjects: list[str]) -> str:
    bullets = "".join(f"          <li>{xml(subject)}</li>\n" for subject in subjects)
    description = f"        <ul>\n{bullets}        </ul>\n" if bullets else "        <p>Fixes and small improvements.</p>\n"
    return (
        f'    <release version="{version}" date="{date.today().isoformat()}">\n'
        f"      <description>\n{description}      </description>\n"
        f"    </release>\n"
    )


def write_version(version: str, subjects: list[str]) -> None:
    CMAKE.write_text(re.sub(r"(project\(catarina VERSION )[0-9.]+", rf"\g<1>{version}", CMAKE.read_text()))

    metainfo = METAINFO.read_text()
    if f'<release version="{version}"' in metainfo:
        raise SystemExit(f"metainfo already has a release entry for {version}")
    METAINFO.write_text(metainfo.replace("  <releases>\n", "  <releases>\n" + release_entry(version, subjects), 1))

    FLATPAK.write_text(re.sub(r"tag: v[0-9.]+", f"tag: v{version}", FLATPAK.read_text()))


def open_proposal() -> dict | None:
    listing = json.loads(out("gh", "pr", "list", "--base", "master", "--state", "open", "--json", "number,headRefName"))
    for pull in listing:
        if pull["headRefName"].startswith("release/"):
            return pull
    return None


def refresh(pull: dict, since: str | None, force: bool) -> None:
    branch = pull["headRefName"]
    version = branch.split("/", 1)[1]
    run("git", "fetch", "--quiet", "origin", branch, "develop")
    behind = int(out("git", "rev-list", "--count", f"origin/{branch}..origin/develop"))

    if force and behind:
        run("git", "switch", "--quiet", "-C", branch, f"origin/{branch}")
        merged = run("git", "merge", "--no-edit", "origin/develop", check=False)
        if merged.returncode != 0:
            raise SystemExit(
                f"`{branch}` conflicts with `develop`. Merge `origin/develop` into it by hand, "
                "then push. The proposal is unchanged."
            )
        run("git", "push", "--quiet", "origin", branch)
        run("git", "fetch", "--quiet", "origin", branch)
        behind = 0

    subjects = changes(since, f"origin/{branch}")
    issues = resolved_issues(since, f"origin/{branch}")
    notes = Path(tempfile.gettempdir()) / "proposal.md"
    notes.write_text(body(version, since, subjects, issues, behind))
    run("gh", "pr", "edit", str(pull["number"]), "--body-file", str(notes))
    print(f"updated proposal #{pull['number']} ({branch}, {behind} behind develop)")


def create(version: str, since: str | None, subjects: list[str], issues: list[int]) -> None:
    branch = f"release/{version}"
    run("git", "fetch", "--quiet", "origin", "master", "develop")
    run("git", "switch", "--quiet", "-C", branch, "origin/master")
    merges = run("git", "merge", "--no-edit", "origin/develop", check=False)
    if merges.returncode != 0:
        raise SystemExit(f"`develop` conflicts with `master`. Resolve it before proposing {version}.")

    write_version(version, subjects)
    run("git", "commit", "--quiet", "-am", f"chore(release): {version}")
    run("git", "push", "--quiet", "-u", "origin", branch)

    notes = Path(tempfile.gettempdir()) / "proposal.md"
    notes.write_text(body(version, since, subjects, issues))
    run(
        "gh", "pr", "create",
        "--base", "master", "--head", branch,
        "--title", f"chore(release): {version}",
        "--body-file", str(notes),
    )
    print(f"opened proposal {branch}")


def main() -> None:
    run("git", "fetch", "--quiet", "--tags", "--force", "origin")
    ahead = int(out("git", "rev-list", "--count", "origin/master..origin/develop"))
    if ahead == 0:
        print("develop has nothing that master lacks")
        return

    force = os.environ.get("REFRESH", "").strip().lower() in {"1", "true", "yes"}
    since = latest_tag()
    pull = open_proposal()
    if pull:
        refresh(pull, since, force)
        return

    subjects = changes(since)
    issues = resolved_issues(since)

    version = bump(current_version())
    for _ in range(10):
        tag_exists = run("git", "rev-parse", "--quiet", "--verify", f"v{version}", check=False).returncode == 0
        branch_exists = (
            run("git", "ls-remote", "--exit-code", "--heads", "origin", f"release/{version}", check=False).returncode == 0
        )
        if not tag_exists and not branch_exists:
            break
        version = bump(version)
    create(version, since, subjects, issues)


if __name__ == "__main__":
    main()
