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

1. **Make the repository public.** This is the hard blocker. Flathub fetches the
   app from `https://github.com/guilhermelcosta/catarina.git` with no credentials,
   and the homepage/screenshot URLs must be reachable. The repo is currently private,
   so the linter reports `appid-url-not-reachable` (HTTP 404) and the Flatpak build
   fails at the source download step.
2. **Decide the license.** GPL-3.0-or-later is a placeholder. If you want another
   license, change both `LICENSE` and `<project_license>` in the metainfo (the tag
   must be a valid [SPDX identifier](https://spdx.org/licenses/)).
3. **Replace the placeholder icon.** `icons/catarina.svg` says so in a comment.
   Flathub expects a distinct, own-identity icon, and the metainfo brand colour
   (`#1d99f3`) is currently the KDE blue — set it to the app's own colour.
4. **Push the tag.** `git push --force origin v0.1.0`. The manifest pins `v0.1.0`
   (commit `1a118dd`); the tag must exist on the public remote.
5. **Grow a little history.** Flathub rejects apps that "have only existed for a
   very short period of time" and wants evidence of ongoing maintenance. Keep
   committing; do not submit the same day you opened the repo.
6. **Re-tag after any source change.** The manifest pins a tag and a commit. Any
   new source change needs a new tag, and the manifest updated to match.

## Submission

```sh
# fork flathub/flathub (do NOT copy master only), then:
git clone --branch=new-pr git@github.com:<you>/flathub.git
cd flathub && git checkout -b catarina-submission new-pr
```

Copy the manifest to the **top level** of the submission repo, named exactly
`io.github.guilhermelcosta.Catarina.yml`. The metainfo is **not** copied — Flathub
requires the app to ship its own, which CMake already installs.

Then commit and open a PR against the **`new-pr` base branch**, title
`Add io.github.guilhermelcosta.Catarina`.

## Before opening the PR

```sh
# lint, both are required by reviewers (errors AND warnings are fatal)
flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest \
    packaging/io.github.guilhermelcosta.Catarina.yml
flatpak run --command=flatpak-builder-lint org.flatpak.Builder repo repo
```

Current state: the manifest linter is clean except `appid-url-not-reachable`,
which item 1 above fixes.

## Generative AI policy

Flathub's [Generative AI policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy)
states that manifests **must not** be AI-generated, that AI assistance in the app
or its packaging must be disclosed in the PR, and that **AI agents must not open
the submission PR** or write its description. This manifest was drafted with AI
assistance: review it line by line yourself, own it, and disclose it. Open the PR
by hand.
