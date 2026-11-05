# Factory inbox

One row per thing that needs a human. The last column must be answerable without
opening another file.

| task | gate | evidence | smallest decision needed |
| --- | --- | --- | --- |
| baseline | full | `factory/verify.yaml#baseline`; fix validated on `factory/000-baseline-green/001-fix-unresolved-assert` | After merging the validated fix, set `baseline.result` to green via `factory-discover-verify` |
| 001-fix-unresolved-assert | pr | branch `factory/000-baseline-green/001-fix-unresolved-assert` @ `ce018ae`; test commit `65ffe90`; QA `pass`; validate `pass`; PR gate approved (`pr_lines_gt_400`); body `/tmp/opencode/pr-body-001-fix-unresolved-assert.md` | Run `git push -u origin factory/000-baseline-green/001-fix-unresolved-assert` in `.worktrees/001-fix-unresolved-assert`, then create the PR with the prepared body |
