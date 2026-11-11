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
`develop` is the integration branch. `release/<x.y.z>` is cut from `master` with
`develop` merged in, stabilised, and merged into `master`. The release proposal
workflow creates it on every push to `develop`; see `docs/RELEASING.md`.

Work branches use `<type>/<slug>` and target `develop`.

Allowed types: `feature`, `fix`, `chore`, `docs`, `test`, `refactor`,
`perf`, `ci`, `build`, `revert`.

Slug: lowercase letters, digits, and hyphens. Example: `feature/request-timeout`.

Rules:

- Never commit or push directly to `master` or `develop`. Open a pull request.
- Never force-push a branch with an open pull request or a released tag.
- Keep one behaviour per branch. If the title needs "and", split the work.
- Hotfix: `fix/<slug>` from `master`, pull request to `master`, then merge
  `master` back into `develop`.

Flow:

1. `develop` -> `release/x.y.z` on every push to `develop`, opened by the
   release proposal workflow.
2. `release/x.y.z` -> `master` after stabilisation.
3. The release pull request merge creates tag `vX.Y.Z` on `master`.
4. Merging `master` back into `develop` is optional: the next proposal computes
   the version from `master`.

## Pull requests

- Every pull request closes an issue. The body contains `Closes #N`; the
  `linked-issue` check fails otherwise, and the merge is blocked.
- Exempt by design: `dependabot/*` branches, `release/*` branches, and the
  author `dependabot[bot]`. Nothing else is exempt.
- Keep every section of `.github/pull_request_template.md`. An empty section is a
  missing section.
- Required checks: `branch-name`, `secret-scan`, `linked-issue`, `build-test`.

## New feature checklist

- The branch starts from `develop` and is named `<type>/<slug>`.
- The issue exists and states the problem and the expected behaviour.
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

Required checks are `branch-name`, `secret-scan`, `linked-issue` and `build-test`.
Do not bypass a red check. Fix the cause or ask a human.

- `ci.yml` runs on push, once per commit. A pull request from this repository
  does not rebuild; the push run supplies the checks. Fork pull requests run the
  same build jobs in `pull-request.yml`, gated on the head repository being a
  fork.
- `linked-issue` and `dependency-review` run in `pull-request.yml`, because they
  need the pull request body and the branch diff.
- Keep workflow permissions minimal.
- Do not use `pull_request_target` to run untrusted code with a write token.
- Pin third-party actions to a commit SHA with the version in a comment.

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
