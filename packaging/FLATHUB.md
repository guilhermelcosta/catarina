# Flathub submission checklist

Everything below is prepared in the repo. The remaining steps need your GitHub
account and are done in the browser.

## Ready in the repo

- App ID: `io.github.guilhermelcosta.Catarina` (matches the GitHub repo, required
  by Flathub's [ID rules](https://docs.flathub.org/docs/for-app-authors/requirements#application-id)).
- `packaging/io.github.guilhermelcosta.Catarina.metainfo.xml` — AppStream metadata.
  Passes `appstreamcli validate`.
- `packaging/io.github.guilhermelcosta.Catarina.desktop.cmake` — launcher.
- `packaging/io.github.guilhermelcosta.Catarina.yml` — Flatpak manifest, pulls the
  app from the `v0.1.0` git tag (Flathub forbids local/`type: dir` sources).
- `LICENSE` — GPL-3.0-or-later. **Change it now if you want another license**: it
  must match `<project_license>` in the metainfo file.

## Still on you

1. **Confirm the license.** GPL-3.0-or-later is a placeholder choice. If you want
   MIT or anything else, change both `LICENSE` and the `<project_license>` tag
   (the tag must be an [SPDX identifier](https://spdx.org/licenses/)).
2. **Re-tag after any change.** The manifest pins `v0.1.0`. Any source change must
   be released as a new tag, and the manifest updated to point at it.
3. **Grow a little history.** Flathub rejects apps that "have only existed for a
   very short period of time" and wants evidence of ongoing maintenance. You have
   61 commits since October, which is thin. Keep committing; do not submit the same
   day you created the repo.
4. **Push the tag.** `git push origin v0.1.0` (already done for the current tag).

## Submission

```sh
# fork flathub/flathub (do NOT copy master only), then:
git clone --branch=new-pr git@github.com:<you>/flathub.git
cd flathub && git checkout -b catarina-submission new-pr
```

Copy the manifest and metainfo into the submission repo at the **top level**:

- `io.github.guilhermelcosta.Catarina.yml` (manifest, top level, named after the ID)
- `io.github.guilhermelcosta.Catarina.metainfo.xml` is **not** copied — Flathub
  requires the app to ship its own metainfo. It is already installed by CMake.

Then commit and open a PR against the **`new-pr` base branch**, title
`Add io.github.guilhermelcosta.Catarina`.

## Before opening the PR

```sh
# build and run locally (done, see below)
flatpak run io.github.guilhermelcosta.Catarina

# lint, both are required by reviewers
flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest \
    io.github.guilhermelcosta.Catarina.yml
flatpak run --command=flatpak-builder-lint org.flatpak.Builder repo repo
```

Fix every error **and** warning before submitting. Both are fatal to reviewers.

## Generative AI policy

Flathub asks submitters to disclose AI-generated material, and its manifests must
not be AI-generated. Review the manifest and commit messages yourself before
submitting and state the disclosure in the PR if any part is AI-assisted.
