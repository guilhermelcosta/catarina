---
id: 001-fix-unresolved-assert
spec: 000-baseline-green
title: Align unresolved-status assertion with the capitalized message
state: pending
attempt: 0
risk: low
touches_ui: false
screens: []
depends_on: []
branch: factory/000-baseline-green/001-fix-unresolved-assert
pr: null
files_hint: [tests/app/tst_app.qml]
acceptance:
  - kind: profile
    profile: ui
  - kind: profile
    profile: full
---

# Align unresolved-status assertion with the capitalized message

## Scope

Correct the stale assertion in `test_unresolved_status_is_concise` in
`tests/app/tst_app.qml` so it matches the plural message the product already
emits: `Unresolved variables in the request`, capital `U`. The assertion that the
status line does not list individual missing variable names (`missing0`) must
remain and must keep failing if a name is listed.

One behaviour: the test stops rejecting a correctly capitalized message. No
runtime behaviour changes.

## Out of scope

- `qml/Strings.js` in any form, including the leading space in the plural message.
- The singular (`n = 1`) path.
- New tests or new assertions; only the stale expectation is aligned.
- Product code, QML components, UI, docs.
- `factory/verify.yaml`: it must not be edited, before or after merge.
- Merge, and the post-merge baseline metadata closeout (spec M1).

## Criteria covered

| # | criterion | kind | profile | expect |
| --- | --- | --- | --- | --- |
| 1 | The UI suite, including the unresolved-status test and the real binary smoke, is green | profile | `ui` | `100% tests passed, 0 tests failed out of 3` |
| 2 | The full baseline suite is green, which is the point of the slice | profile | `full` | `100% tests passed, 0 tests failed out of 7` |

## Notes for the builder

- `configure` and `build` from `factory/verify.yaml` are preconditions. If either
  fails, report blocked with the failing command; that is not green.
- Run both acceptance profiles. Criteria 1 and 2 are the only gates; no command
  outside `factory/verify.yaml` counts.
- Keep the `missing0` assertion. Removing or weakening it contradicts the spec and
  the reviewer will block.
- Do not edit `factory/verify.yaml`, do not commit product changes, do not merge.
- The leading space in the plural message stays. Do not "fix" it here.
