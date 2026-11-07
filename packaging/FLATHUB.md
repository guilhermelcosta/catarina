# Flathub submission checklist

Everything below is prepared in the repo. The remaining steps need your GitHub
account and are done in the browser.

## Ready in the repo

- App ID: `io.github.guilhermelcosta.Catarina` (matches the GitHub repo, required
  by Flathub's [ID rules](https://docs.flathub.org/docs/for-app-authors/requirements#application-id)).
- `packaging/io.github.guilhermelcosta.Catarina.metainfo.xml`: AppStream metadata.
  Passes `appstreamcli validate --no-net`.
- `packaging/io.github.guilhermelcosta.Catarina.desktop.cmake`: launcher.
- `packaging/io.github.guilhermelcosta.Catarina.yml`: Flatpak manifest, pulls the
  app from the release tag (Flathub forbids local/`type: dir` sources).
- `LICENSE`: GPL-3.0-or-later. Keep it in sync with `<project_license>` in the
  metainfo file.

## Still on you

1. **Make the repository public.** This is the hard blocker. Flathub fetches the
   app from `https://github.com/guilhermelcosta/catarina.git` with no credentials,
   and the homepage/screenshot URLs must be reachable. While the repo is private,
   the linter reports `appid-url-not-reachable` (HTTP 404) and the Flatpak build
   fails at the source download step.
2. **Replace the placeholder icon.** `icons/catarina.svg` says so in a comment.
   Flathub expects a distinct, own-identity icon, and the metainfo brand colour
   (`#1d99f3`) is currently the KDE blue. Set it to the app's own colour, with a
   distinct light and dark variant.
3. **Take store-quality screenshots.** The current `docs/screenshot.png` shows a
   debug state. Flathub wants the app window with its decoration, real content,
   no empty state, 1000x700 or smaller, and a caption. Three to six screenshots is
   a good range for this app.
4. **Cut a release.** The release workflow creates `vX.Y.Z` on `master` after the
   `release/x.y.z` pull request is merged. The tag must exist on the public remote
   and must match the version in `CMakeLists.txt` and the metainfo file. See
   `docs/RELEASING.md`.
5. **Add the tag commit to the submission manifest.** The repository copy uses
   `tag:` only. In the Flathub submission copy, add `commit:` with the output of
   `git rev-list -n 1 vX.Y.Z`.
6. **Grow a little history.** Flathub rejects apps that "have only existed for a
   very short period of time" and wants evidence of ongoing maintenance. Keep
   committing and keep releases flowing. Do not submit the same day the repo
   becomes public.
7. **Re-tag after any source change.** Never reuse a tag. Any new source change
   needs a new patch release and a manifest updated to match.

## Submission

```sh
# fork flathub/flathub (do NOT copy master only), then:
git clone --branch=new-pr git@github.com:<you>/flathub.git
cd flathub && git checkout -b catarina-submission new-pr
```

Copy the manifest to the **top level** of the submission repo, named exactly
`io.github.guilhermelcosta.Catarina.yml`. The metainfo is **not** copied: Flathub
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

Re-run the linter after the repository is public. `appid-url-not-reachable` is
the expected failure while the repo is private.

## Generative AI policy

Flathub's [Generative AI policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy)
states that manifests **must not** be AI-generated, that AI assistance in the app
or its packaging must be disclosed in the PR, and that **AI agents must not open
the submission PR** or write its description. This manifest was drafted with AI
assistance: review it line by line yourself, own it, and disclose it. Open the PR
by hand.
