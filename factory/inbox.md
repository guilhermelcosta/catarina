# Factory inbox

One row per thing that needs a human. The last column must be answerable without
opening another file.

| task | gate | evidence | smallest decision needed |
| --- | --- | --- | --- |
| baseline | full | `factory/verify.yaml#baseline` | Fix the stale test assertion or the string capitalization, then re-run `full` and set baseline to green |
