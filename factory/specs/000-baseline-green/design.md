---
spec: 000-baseline-green
status: approved
risk: low
requires_human: false
---

# Design: Restore a green baseline

## Approach

Change one expectation string in `tests/app/tst_app.qml::test_unresolved_status_is_concise`
from the lowercase `unresolved variables in the request` to the capitalized
`Unresolved variables in the request` that `qml/Strings.js:303` already returns for
`n != 1`. The second assertion, which rejects any individual `missing<N>` name in
the status line, stays byte-for-byte identical. No runtime behaviour, no product
string and no other test changes.

The test is stale, not the product: the human decision of 2026-11-05 chose the test
side, and the capitalized plural message is the source of truth. Rebuilding the
expectation from the product string would hide a future divergence, so the test
keeps a literal expected substring rather than calling `Strings.unresolvedInRequest`,
and keeps the conciseness check that pins "no variable names listed".

## Data model and storage

None. No file format, no schema, no persistence, no migration.

The only durable record affected outside the test file is
`factory/verify.yaml#baseline`, and this task must not edit it. It stays
`result: red` with the known failing entry until the human closeout (spec M1)
after merge.

Rollback for this change: revert one line in one test file. No data to restore.

## Contracts

- **Product contract (unchanged):** for `n != 1` unresolved variables, the status
  text contains `Unresolved variables in the request` (capital `U`, leading space
  included at `qml/Strings.js:303`). For `n === 1` it contains `Unresolved variable
  in the request`. Neither is modified by this slice.
- **Test contract:** the plural assertion must match the capitalized substring and
  must not require lowercase.
- **Test contract (kept):** the same test must still assert that the status text
  does not contain `missing0`, i.e. individual variable names are not listed.
- **Gate contract:** acceptance is the `ui` and `full` profiles in
  `factory/verify.yaml`, unchanged. Expected result lines:
  `100% tests passed, 0 tests failed out of 3` and
  `100% tests passed, 0 tests failed out of 7`.
- **Error shapes:** none. No API, no signal, no endpoint, no user-visible string
  changes.

## File map

| file | change | why |
| --- | --- | --- |
| `tests/app/tst_app.qml` | one expectation literal inside `test_unresolved_status_is_concise` (line 403) | stale after the capitalization change; matches the current product message |
| `factory/specs/000-baseline-green/tasks/001-fix-unresolved-assert.md` | created | task record |
| `factory/runs/001-fix-unresolved-assert/state.json` | created | run state |

Out of scope, must not change: `qml/Strings.js` (including the leading space in
the plural branch), the singular path, `factory/verify.yaml`, all other tests, all
product code, `docs/DESIGN.md` (no UI element is created or changed).

## Task outline

| task | closes criteria | risk | deps |
| --- | --- | --- | --- |
| `001-fix-unresolved-assert` — align the unresolved-status assertion with the capitalized plural message | spec criteria 1 and 2 | low | none |

One task, one branch, one PR, one reviewing unit. The cut is not arbitrary: the
two criteria are the `ui` and `full` runs of the same single change, so splitting
them would produce a task that cannot pass on its own. `touches_ui: false`, no
screens, no UI review.

## Risks

| risk | likelihood | impact | mitigation |
| --- | --- | --- | --- |
| Assertion loosened to something meaningless (e.g. `indexOf("in the request")`) or the `missing0` check deleted, making green meaningless | low | medium | Task scope names both assertions as preserved; reviewer blocks on a changed or removed second assertion |
| `full` fails in a suite other than `tst_app` after the change | low | high | Task is `blocked`, not retried into a product fix; raw output goes to the human, since the slice promised the baseline fix |
| Someone edits `factory/verify.yaml` to make `full` green | low | high | Forbidden in task and spec; `verify_yaml_unchanged` is a merge precondition and `verify_yaml_changed` escalates |
| The leading space in the plural message tempts a drive-by fix in `Strings.js` | medium | low | Explicitly out of scope; the assertion is a substring check, so the space is tolerated and stays a separate defect |
| Broken build or missing configure makes the profile fail before the test runs | low | medium | `configure` and `build` from `verify.yaml` are preconditions; a precondition failure is reported as blocked, not as green |
| Baseline metadata is left red after merge, so the repo still looks red | medium | medium | Spec M1 human closeout: set `#baseline` to green on 2026-11-05, outside the task's build scope |

Irreversible: nothing. The change is one test literal and is reverted by `git revert`.

## Alternatives

| option | why rejected |
| --- | --- |
| Change `qml/Strings.js` back to the lowercase plural message | Rejected by the human decision of 2026-11-05. It would change runtime user-visible text to satisfy a test, and the capitalized message is the intended product state |
| Fix the leading space in the plural message in the same slice | Out of scope: a separate known defect, and touching `Strings.js` would make this a runtime change, expand the diff and mix two behaviours in one task |
| Replace the literal with a call to `Strings.unresolvedInRequest(20)` | Tautological: the test would then pass whatever the product renders, deleting the conciseness and wording contract |
| Assert `indexOf("Unresolved variables") >= 0` only | Too loose: drops `in the request` and weakens the message contract beyond the case fix |
| Delete the failing test | Removes the regression guard that keeps the status concise; the spec requires the check to remain |

## Rollback

Revert the single commit that changes the assertion. The product string, the
suite count and every other test are untouched, so no follow-up migration or
cleanup is needed. If the merged change is later found to have hidden a product
defect, the human restores the failing expectation and re-opens the baseline in
`factory/verify.yaml` via `factory-discover-verify`.

## Human gates

- Design gate: policy lists `design: human_if` only for new dependency, schema,
  auth, payment, infra or secrets. None apply, so no design gate is required.
- Task list: `factory/README.md` Phase 1 requires a human to approve the task list
  before build. This design and its one task stop there.
- Merge: `policy.yaml` sets `merge: human`. The factory never merges this slice.
- Closeout: spec M1, baseline metadata to green, is a human step after merge.
