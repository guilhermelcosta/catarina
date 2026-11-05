## Verdict: escalate

| criterion | covered | evidence | note |
|---|---|---|---|
| 1. `ui` profile: `100% tests passed, 0 tests failed out of 3` | yes | `qa-report.md:12`; `/tmp/opencode/val-ui.log:9`; `/tmp/opencode/val-tst_app.log:304,306`; `/tmp/opencode/val-qml_smoke.log:3,5` | `tst_app::AppBehavior::test_unresolved_status_is_concise()` PASS; `qml_smoke` PASS; result line matches the task exactly |
| 2. `full` profile: `100% tests passed, 0 tests failed out of 7` | yes | `qa-report.md:13`; `/tmp/opencode/val-full.log:17` | all 7 tests pass; result line matches the task exactly |
| Contract: capitalized substring required, lowercase not required | yes | `tests/app/tst_app.qml:403`; `qml/Strings.js:303` | line 403 asserts `indexOf("Unresolved variables in the request") >= 0`; product returns `" Unresolved variables in the request"` for `n != 1` |
| Contract: `missing0` exclusion retained | yes | `tests/app/tst_app.qml:404` | byte-identical to master; still fails if an individual name is listed |
| Contract: product strings unchanged | yes | `qml/Strings.js:303` worktree vs master; `factory/verify.yaml` worktree vs master | leading space retained; no product or `verify.yaml` edit |
| M1: baseline metadata green | n/a | `factory/verify.yaml:37` `result: red`; spec M1 | human post-merge closeout, not a task criterion |

Commands and result lines used:

```
ctest --test-dir build -R "tst_components|tst_app|qml_smoke" --output-on-failure
100% tests passed, 0 tests failed out of 3

ctest --test-dir build --output-on-failure
100% tests passed, 0 tests failed out of 7

ctest --test-dir build -R '^tst_app$' --output-on-failure -V
4: PASS   : tst_app::AppBehavior::test_unresolved_status_is_concise()
4: Totals: 33 passed, 0 failed, 0 skipped, 0 blacklisted, 7289ms

ctest --test-dir build -R 'qml_smoke' --output-on-failure
1/1 Test #7: qml_smoke ........................   Passed    6.02 sec
100% tests passed, 0 tests failed out of 1
```

Input note: this runtime exposes no shell and `fetch` to `api.github.com` returned `Permission denied: webfetch`, so `gh pr diff 10` and `gh pr view 10` could not be executed. I verified the diff from the worktree at `fix/align-unresolved-status-assert` (HEAD `04b3875`) against `master` (`d2f8a78`), and read the prepared body at `/tmp/opencode/pr-body-001-fix-unresolved-assert.md` (8 files, 592 insertions, 1 deletion; matches the stated PR size).

## Must fix (block)

None. Both acceptance criteria pass, the contracts hold, and the product diff is exactly `tests/app/tst_app.qml` (1 insertion, 1 deletion). The stop is a policy escalation, not a defect in the change.

## Unrequested

- None in product scope. The 7 factory-record files are process evidence, not out-of-scope noise: `factory/README.md:47-59` assigns `specs/<id>/` to spec/design and `runs/<task>/` to QA/validator/reviewer; `design.md:53-59` names the task record and `state.json`; the PR body documents the rest. The human approved the `pr` gate for the size they add.
- No dependency, no secret, no `AGENTS.md` or `docs/DESIGN.md` edit, and no `factory/verify.yaml` change.
- The post-validation commits `6ef0255` and `04b3875` changed factory records only (design human-gates section, task branch/PR fields, `state.json`); the test line is unchanged. This is record bookkeeping, not product work.

## Risk

- declared: low
- verified: low for the product change; 8 files and 593 changed lines at PR level
- facts: one test file, one line (`tests/app/tst_app.qml:403`); seven factory-record files, about 592 inserted lines; no product code, no `qml/Strings.js`, no `factory/verify.yaml`, no dependency, no secrets; `verify.yaml` identical in worktree and master; `qml/Strings.js:303` identical in worktree and master.
- reason: test-only change plus process records. The volume is documentation, not a high-risk code category. The 593 changed lines still match `pr_lines_gt_400`; that condition was already resolved by the human approving the `pr` gate.
- policy escalation: `factory/verify.yaml:37` has `result: red`, so `baseline_red: true` matches `escalate_if`; `pr_lines_gt_400` also matches. The merge gate cannot proceed (`auto_if` requires `verified_risk_low`, `qa_pass`, `validate_pass`, `review_approve`, `scope_clean`, `verify_yaml_unchanged`, and `baseline_red` remains). This is predicted by `design.md:113-118`.
- smallest human decision: merge PR #10 by hand (squash), then run the M1 closeout to set `factory/verify.yaml#baseline` to `result: green`.
- process observations for the human, not blocks: QA and evidence were produced at `65ffe90` while the PR head is `04b3875`; the delta is factory records only, and `tests/app/tst_app.qml:403` is identical at head. The PR body's rollback names `65ffe90`, which is not on this branch; use the squash commit or the current test line.
