---
spec: 000-baseline-green
idea: none
status: approved
approved_by: human
approved_at: 2026-11-05
---

# Brief: Restore a green baseline

This is a baseline repair, not a new idea. There is no G0 and no
`factory/ideas/<slug>/idea.md`. The work is authorized by
`factory/verify.yaml#baseline` and by the human decision of 2026-11-05.

## Problem

The repository's full test profile is red. One UI test still expects the
unresolved-variable status message in lowercase, while the product has produced
the capitalized message since a previous capitalization change. The test is
stale, not the product. `verify.yaml` records the consequence: until `full` is
green, every factory gate built on top of it is untrustworthy, because a red
baseline hides real regressions behind a known failure.

## Who feels it

The maintainer and operator of the factory, and any contributor who runs
`ctest` before opening a PR. They cannot tell a new failure from the known one
without reading the log.

## How they solve it today

They ignore the known failing test, or patch the assertion by hand before
running the suite. Both cost signal: an ignored red suite stops being a gate,
and a hand patch is not reproducible.

## Non-goals

- No change to the product string in `qml/Strings.js`; the capitalized message
  stays.
- No fix of the leading space in the plural message, a known separate defect.
- No fix of the singular (`n = 1`) path.
- No new tests and no product code changes.
- No UI changes; this slice must be declared `touches_ui: false`.
- No edit of `factory/verify.yaml` by the factory.
- No merge performed by the factory.

## Success metric

On 2026-11-05 the `full` profile reports `100% tests passed, 0 tests failed out
of 7`, and the human closeout updates `factory/verify.yaml#baseline` to green in
the same day.

## Premises inherited from G0

None. This is a baseline repair with no G0 and no idea file; no premise is
assumed beyond the human decision above and the baseline record in
`factory/verify.yaml`.
