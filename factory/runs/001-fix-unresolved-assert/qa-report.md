# QA report — 001-fix-unresolved-assert

Task: `factory/specs/000-baseline-green/tasks/001-fix-unresolved-assert.md`
Spec: `factory/specs/000-baseline-green/spec.md`
Worktree: `/home/guilherme/Repositories/catarina/.worktrees/001-fix-unresolved-assert`
HEAD: `65ffe90` (`fix: align unresolved-status assertion with capitalized message`)

## Verdict: pass

| # | criterion | command | result | evidence |
|---|---|---|---|---|
| 1 | UI suite green (profile `ui`) | `ctest --test-dir build -R "tst_components\|tst_app\|qml_smoke" --output-on-failure` | pass | `100% tests passed, 0 tests failed out of 3` (exit 0; tst_components 1.44s, tst_app 7.34s, qml_smoke 6.02s) |
| 2 | Full baseline suite green (profile `full`) | `ctest --test-dir build --output-on-failure` | pass | `100% tests passed, 0 tests failed out of 7` (exit 0; total test time 15.03s) |
| S | Supporting (not a criterion): the specific test | `ctest --test-dir build -R '^tst_app$' --output-on-failure -V` | pass | `4: PASS   : tst_app::AppBehavior::test_unresolved_status_is_concise()` and `4: Totals: 33 passed, 0 failed, 0 skipped, 0 blacklisted, 7413ms` |

Both profile commands are verbatim from `factory/verify.yaml` (`profiles.ui`, `profiles.full`). No command outside `verify.yaml` was used as a gate.

## Adversarial

| case | expected | observed | pass |
|---|---|---|---|
| Second assertion preserved and unchanged | `verify(label.text.indexOf("missing0") < 0, "does not list the variable names");` still present | `tests/app/tst_app.qml:404: verify(label.text.indexOf("missing0") < 0, "does not list the variable names");` — unchanged by the commit | pass |
| Commit touches only `tests/app/tst_app.qml` | `git diff --name-only 65ffe90^ 65ffe90` = exactly one path | `tests/app/tst_app.qml` (one file, 1 insertion, 1 deletion); no other paths | pass |
| Diff content | only the lowercase expectation replaced by the capitalized one | `-        verify(label.text.indexOf("unresolved variables in the request") >= 0, "concise message");` / `+        verify(label.text.indexOf("Unresolved variables in the request") >= 0, "concise message");` | pass |
| Test requires the capitalized substring | assertion requires `Unresolved variables in the request` (capital `U`) | line 403: `verify(label.text.indexOf("Unresolved variables in the request") >= 0, "concise message");` | pass |
| Assertion is a substring check, not weakened to something meaningless | still a substring check on the status label text | unchanged `indexOf(...) >= 0` form, only the case of the needle changed | pass |
| `qml/Strings.js` unchanged, leading space in plural branch retained | plural branch keeps `" Unresolved variables"` with leading space | line 303: `return (n === 1 ? "Unresolved variable" : " Unresolved variables") + " in the request";` — byte-verified with `cat -A`, leading space present; file absent from the commit's name list | pass |
| `n = 20` case still exercised | existing test drives 20 unresolved variables | `tests/app/tst_app.qml:396: for (var i = 0; i < 20; i++) vars.push("{{missing" + i + "}}");` | pass |
| No product/UI/config change | working tree clean for `qml/`, `tests/`, `src/` | `git status --porcelain qml tests src` empty; only untracked `factory/runs/001-fix-unresolved-assert/` and `factory/specs/000-baseline-green/` | pass |
| Singular `n = 1` path | explicitly out of scope | **not covered** — no assertion or run exercises it; recorded as out of scope per task lines 36-37 and spec line 43, not as a failure | n/a |

## Failures

None.

No failing test, no flake observed: both profiles passed on their single run, and `tst_app` reported `33 passed, 0 failed` on the supporting run. Per the skill, no failing command was retried.

## Not run / blocked

- Singular (`n = 1`) unresolved message: out of scope by the task and spec; not asserted and not run. Not a criterion.
- `configure` and `build` were not re-executed by QA. The builder's preconditions were accepted as observed: `build/` present, HEAD `65ffe90`, and all 7 test binaries registered by `ctest -N`. Every gate ran against that build.

## Environment

- Workdir: `/home/guilherme/Repositories/catarina/.worktrees/001-fix-unresolved-assert`
- Profiles: `ui`, `full` from `factory/verify.yaml`; both in `workdir: .`
- Durations: `ui` 14.80s (3 tests), `full` 15.03s (7 tests), supporting `tst_app` 7.41s (33 tests)
- Display/platform: `QT_QPA_PLATFORM` unset in the shell; tests run offscreen via CMake test properties as documented in `verify.yaml`. `qml_smoke` (real binary, offscreen) passed with no display.
- Network: none required; `check_http` is hermetic and passed.
- Only noise: repeated `qt.svg: Cannot open file ':/icons/catarina.svg'` QWARN lines inside `test_unresolved_status_is_concise`; non-fatal, test still PASS. Noted, not a finding for this task.
- Reproducible: read-only inspection plus the two profile commands; nothing environment-specific beyond the existing `build/`.
