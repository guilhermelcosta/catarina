# Agent instructions: Catarina

API client app built with Qt 6 / QML / Kirigami. Code, comments, docs, and the
UI are in English.

## Start here

- Read `docs/DESIGN.md` before creating or changing any UI element.
- Read `docs/RELEASING.md` before cutting a release.
- The `factory/` directory is a local-only workflow. It is gitignored and is not
  part of the published repository. Do not commit it and do not assume another
  checkout has it.

## Branch model

`master` is the source of truth and the only branch that receives release tags.
`develop` is the integration branch. `release/<x.y.z>` is cut from `develop`,
stabilised, and merged into `master`.

Work branches use `<type>/<slug>` and target `develop`.

Allowed types: `feat`, `feature`, `fix`, `chore`, `docs`, `test`, `refactor`,
`perf`, `ci`, `build`, `revert`.

Slug: lowercase letters, digits, and hyphens. Example: `feat/request-timeout`.

Rules:

- Never commit or push directly to `master` or `develop`. Open a pull request.
- Never force-push a branch with an open pull request or a released tag.
- Keep one behaviour per branch. If the title needs "and", split the work.
- Hotfix: `fix/<slug>` from `master`, pull request to `master`, then merge
  `master` back into `develop`.

Flow:

1. `develop` -> `release/x.y.z` when the scope is frozen.
2. `release/x.y.z` -> `master` after stabilisation.
3. The release pull request merge creates tag `vX.Y.Z` on `master`.
4. Merge `master` back into `develop`.

## New feature checklist

- The branch starts from `develop` and is named `<type>/<slug>`.
- The change has tests, or the pull request explains why a test is not possible.
- `ctest --test-dir build --output-on-failure` passes locally.
- UI changes follow `docs/DESIGN.md` and reuse the existing components.
- A new dependency needs a reason, a license check, and a note in the pull request.
- Do not mix unrelated refactors into a feature branch.
- Commit messages use Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`,
  `test:`, `refactor:`, `perf:`, `ci:`.
- The pull request body states what changed, why, how it was tested, and the risk.

## Security

- Never commit credentials, tokens, private keys, cookies, or real collection data.
- Secrets belong in the system keyring or in local files that are gitignored.
- Screenshots must not show tokens, personal data, or internal URLs.
- When in doubt, run `gitleaks detect --source . --redact` before pushing.
- Report vulnerabilities privately. See `SECURITY.md`.

## CI and protection

Required checks are `branch-name`, `secret-scan`, and `build-test`. Do not bypass
a red check. Fix the cause or ask a human.

- Keep workflow permissions minimal.
- Do not use `pull_request_target` to run untrusted code with a write token.
- Pin third-party actions to a major version or, preferably, a commit SHA.

## Tests

Run `ctest` in the `build/` directory (build: `cmake --build build`). There is also
`./build/bin/check_storage` (backend logic, hermetic) and `./build/bin/bench_storage`
(benchmark of the hot paths).

## Design and components

Before creating or changing any UI element, read and follow **[`docs/DESIGN.md`](docs/DESIGN.md)**.
It defines the spacing, opacity, button, icon, and shared-component patterns
(`KvTable`, `SaveBar`, `HeaderTable`, `JsonTree`, `VarCompleter`, `NetworkView`, `Util.js`).

Quick rules:

- **Reuse components**; do not reimplement something that repeats locally.
- Every editable table uses `KvTable` (extend it with a new option if needed).
- Editable sections use `SaveBar` (title + "unsaved changes" + Revert + Save).
- Empty states use `EmptyState` (icon/title/message/action; transparent background).
- Panel padding: `Kirigami.Units.largeSpacing`; between controls: `Kirigami.Units.smallSpacing`.
- `StackLayout` ignores `Layout.margins`; use `anchors.margins` (via `Item`) or `ScrollView.padding`.
- Confirm every Breeze icon exists in the theme before using it.
- New pattern? Document it in `docs/DESIGN.md`.
