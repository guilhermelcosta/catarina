---
id: 000-baseline-green
brief: factory/specs/000-baseline-green/brief.md
idea: none
status: approved
approved_by: human
approved_at: 2026-11-05
risk: low
---

# Spec: Restore a green baseline

## Behaviour

Observable behaviour, from the outside:

- When a request carries more than one unresolved variable, the status line
  still shows the current capitalized plural message: it contains
  `Unresolved variables in the request`.
- The existing test that pins this message passes instead of failing on
  letter case.
- With a fresh configure and build, the `ui` profile is green and the `full`
  profile is green, so a red suite means a new defect again.

This slice changes no runtime behaviour. It aligns the expectation with the
message the product already emits.

## Contracts

- For `n != 1` unresolved variables, the status message contains the substring
  `Unresolved variables in the request` (capital `U`).
- The assertion that checks the plural message must not require the lowercase
  form.
- The same test must still assert that no individual missing variable name is
  listed in the status line.
- Product strings are unchanged by this slice; the message is the source of
  truth for the test, not the reverse.

## Edge cases

| input / state | expected behaviour |
| --- | --- |
| `n = 1` unresolved variable (singular) | Unchanged message; not exercised by this slice and not corrected here |
| `n = 20` unresolved variables (the existing test case) | Capitalized plural message, no variable names listed |
| `n = 0` unresolved variables | Not applicable; this failure is not about the empty case |
| Leading space on the plural message | Known separate defect; tolerated because the assertion is a substring check, not fixed here |

## Failure modes

| condition | required response |
| --- | --- |
| `ui` profile fails | Task is blocked; no product behaviour changes; escalate to the human with the raw output |
| `ui` passes but `full` fails in another suite | Task is blocked; the change is not the baseline fix it claimed to be |
| The assertion is loosened to something meaningless, or the variable-name exclusion check is removed | The reviewer must block |
| The product message differs from the expected substring after the change | Stop; the human decides which side is stale. The product string is out of scope |
| Configure or build fails | Precondition failure, not green; report as blocked with the failing command |

## Acceptance criteria

`configure` and `build` from `factory/verify.yaml` are preconditions and must
succeed before either profile runs. Both criteria are `profile` kind; no command
outside `factory/verify.yaml` is used.

| # | criterion | kind | command / profile | expect |
| --- | --- | --- | --- | --- |
| 1 | The UI suite, including the unresolved-status test and the real binary smoke, is green | profile | `ui` | `100% tests passed, 0 tests failed out of 3` |
| 2 | The full baseline suite is green, which is the point of the slice | profile | `full` | `100% tests passed, 0 tests failed out of 7` |

Manual criteria are listed under Manual checks and are decided by the human
maintainer.

## Manual checks

| # | how a human verifies | who |
| --- | --- | --- |
| M1 | After merge, confirm `factory/verify.yaml#baseline` records `result: green`, `verified_at: 2026-11-05`, and no `failing` entry; preferably done through `factory-discover-verify`. This is outside the task's build scope and is the closeout step | human maintainer |

## Non-goals

- No change to `qml/Strings.js`; the capitalized message and the known leading
  space stay as they are.
- No fix of the singular (`n = 1`) path.
- No new tests and no product code changes.
- No UI changes; this slice must be declared `touches_ui: false`.
- No edit of `factory/verify.yaml` by the factory, before or after merge.
- No merge performed by the factory.

## Open questions

None blocking.
