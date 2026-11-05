# Functional evidence — 001-fix-unresolved-assert

Task: `factory/specs/000-baseline-green/tasks/001-fix-unresolved-assert.md`
Spec: `factory/specs/000-baseline-green/spec.md`
Commit under validation: `65ffe90` (`fix: align unresolved-status assertion with capitalized message`)
Environment: Linux, offscreen Qt (`QT_QPA_PLATFORM=offscreen` set by the CMake test properties), no display, no network, no keyring.
Worktree: `/home/guilherme/Repositories/catarina/.worktrees/001-fix-unresolved-assert`

## Verdict: pass

## Scope fact, stated plainly

`git show --stat 65ffe90` is one line in `tests/app/tst_app.qml`:

```
 tests/app/tst_app.qml | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

The only diff is the expected substring `unresolved variables in the request` →
`Unresolved variables in the request`. No product code, no QML, no string
resource changed. This slice therefore claims that the user-visible status line
already carries the capitalized plural message and that the test now observes it
instead of rejecting it. The runs below are proof of that claim plus proof of no
regression; they are not proof of new behaviour, because there is none.

Path from send to the visible label (read-only inspection, no edits):

- `qml/screens/ResponsePane.qml:154-157` — `onError(code, args)` sets
  `statusLabel.text = Strings.backendError(code, args)`; `statusLabel` is the
  object with `objectName: "statusLabel"` (`ResponsePane.qml:233-234`), i.e. the
  same element the test looks up with `findChild(win, "statusLabel")`.
- `qml/Strings.js:336-337` — `backendError("unresolved", args)` →
  `unresolvedInRequest(args[0].length)`.
- `qml/Strings.js:302-304` — for `n != 1` returns
  `" Unresolved variables" + " in the request"`, containing
  `Unresolved variables in the request` (capital `U`, leading space retained).
- `src/backend.cpp:274-279` — `Backend::send` emits
  `error("unresolved", {missing})` before any network I/O when variables are
  unresolved, so the label is set without a request leaving the machine.

## Criteria

| # | criterion | method | artifact | result |
|---|---|---|---|---|
| F1 | With more than one unresolved variable, the status line shows the capitalized plural message containing `Unresolved variables in the request` and does not list individual missing names | `tst_app::AppBehavior::test_unresolved_status_is_concise` — real `Main` instance and real `Backend` (injected like `main.cpp` via `tests/tst_app.cpp`), 20 missing vars, real send, real `statusLabel` read after the send | this file §F1; raw capture `/tmp/opencode/val-tst_app.log` | pass |
| F2 | The real application still starts and the UI surface is not regressed by the change | `qml_smoke` — launches the built `bin/catarina` offscreen for 6 s in a temp HOME and fails on any QML load error; plus the full `ui` profile for the surrounding UI suites | this file §F2; raw capture `/tmp/opencode/val-qml_smoke.log`, `/tmp/opencode/val-ui.log` | pass |

### F1 — plural unresolved status message

Command (full verbose output in `/tmp/opencode/val-tst_app.log`):

```
ctest --test-dir build -R '^tst_app$' --output-on-failure -V
```

Result lines:

```
4: PASS   : tst_app::AppBehavior::test_unresolved_status_is_concise()
4: PASS   : tst_app::AppBehavior::cleanupTestCase()
4: Totals: 33 passed, 0 failed, 0 skipped, 0 blacklisted, 7289ms
1/1 Test #4: tst_app ..........................   Passed    7.39 sec
100% tests passed, 0 tests failed out of 1
```

Assertions executed by that test (`tests/app/tst_app.qml:393-405`) are the
substring check for `Unresolved variables in the request` and the exclusion
check `label.text.indexOf("missing0") < 0`. Both passed in this run, so the
message the product sets on the real label is capitalized and does not name
individual variables.

Surface honesty: this is an integration/UI test that hosts the shipped `Main`
and shipped `Backend` inside the Qt Quick Test harness, not the installed
binary driven by a human. It is the highest available surface for this
behaviour and it exercises the real label object and the real product string,
so it is not a unit-test proxy. It does not cover a human typing variables into
the real window; that residual gap is listed under Not covered.

### F2 — application starts, UI not regressed

Command:

```
ctest --test-dir build -R 'qml_smoke' --output-on-failure
```

Result lines:

```
1/1 Test #7: qml_smoke ........................   Passed    6.02 sec
100% tests passed, 0 tests failed out of 1
```

`tests/qml_smoke.sh` starts the built `catarina` binary with
`QT_QPA_PLATFORM=offscreen`, a temp `HOME`/`XDG_*`, `CATARINA_SECRETS_BACKEND=file`
and `timeout 6`; it passes only if the process is still alive at the timeout
(`rc=124`) and the log contains no `QQmlApplicationEngine failed`, type,
reference, assignment or "No such" error. Passed.

Supporting profile runs (same worktree, same build):

`ctest --test-dir build -R "tst_components|tst_app|qml_smoke" --output-on-failure`
(`ui` profile, `/tmp/opencode/val-ui.log`):

```
2/3 Test #4: tst_app ..........................   Passed    7.52 sec
3/3 Test #7: qml_smoke ........................   Passed    6.02 sec
100% tests passed, 0 tests failed out of 3
```

`ctest --test-dir build --output-on-failure` (`full` profile,
`/tmp/opencode/val-full.log`):

```
100% tests passed, 0 tests failed out of 7
```

Both match the task's expected result lines (`out of 3`, `out of 7`).

## Not covered

| criterion | why | who decides |
|---|---|---|
| F1 observed through the shipped binary with a human typing 20 variables into the request editor | Needs interactive display input; not automatable unattended without writing new fixtures, which this gate must not do | human maintainer (manual spot check, optional; `tst_app` already drives the same label and strings) |
| Singular (`n = 1`) unresolved message | Explicitly out of scope in the spec ("not corrected here") and untouched by the diff | human maintainer, a later task |
| Leading space in the plural message (`" Unresolved variables..."`) | Known separate defect the spec tolerates because the assertion is a substring check | human maintainer, a later task |
| Spec criterion 2 as a factory gate (`full` = 7/7) | It is QA/task acceptance, not one of the two functional criteria I was asked to prove; I ran it as supporting evidence only | factory-qa / reviewer |
| M1 post-merge baseline metadata (`factory/verify.yaml#baseline` green) | Post-merge closeout, out of this task's build scope, and `verify.yaml` must not be edited by the factory | human maintainer |

## Reproduction

From a clean shell (tests are offscreen; no display, network or keyring needed):

```
cd /home/guilherme/Repositories/catarina/.worktrees/001-fix-unresolved-assert

# preconditions
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j

# F1
ctest --test-dir build -R '^tst_app$' --output-on-failure -V

# F2
ctest --test-dir build -R 'qml_smoke' --output-on-failure

# supporting: ui and full profiles
ctest --test-dir build -R "tst_components|tst_app|qml_smoke" --output-on-failure
ctest --test-dir build --output-on-failure
```

Expected result lines: `PASS   : tst_app::AppBehavior::test_unresolved_status_is_concise()`,
`Totals: 33 passed, 0 failed`, `100% tests passed, 0 tests failed out of 3`,
`100% tests passed, 0 tests failed out of 7`.

## Environment left behind

- No background processes started; every command ran to completion. `qml_smoke`
  self-terminates the binary via `timeout` and removes its `mktemp` log and temp
  dir with a `trap`.
- Tests used their own temporary `HOME`/`XDG_*` (Qt `QTemporaryDir` in
  `tst_app`, `mktemp -d` in `qml_smoke`), so no user settings, collections or
  secrets were touched.
- Rebuilt the pre-existing `build/` directory in place (gitignored; `git status`
  shows only the untracked `factory/runs/` and `factory/specs/` trees).
- Raw console captures left at `/tmp/opencode/val-tst_app.log`,
  `/tmp/opencode/val-qml_smoke.log`, `/tmp/opencode/val-ui.log`,
  `/tmp/opencode/val-full.log`; safe to delete.
- No code, test, fixture, config, task, spec, QA report or `factory/verify.yaml`
  file was changed.
