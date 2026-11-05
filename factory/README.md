# Factory

Agentic pipeline for this repository. Roles are OpenCode subagents, procedures
are skills, state is files in this directory.

## Lifecycle

```
idea ─▶ G0 ─▶ brief ─▶ spec ─▶ design ─▶ tasks ─▶ build ─▶ qa ─▶ validate ─▶ PR ─▶ review ─▶ merge
         │     🔒       🔒       🔒(risco)           │        │       │                  │
         ├─ kill ─▶ ideas/killed/                    └────────┴───────┴── fail? ─────────┘
         └─ test ─▶ experiments/                                              attempt++ (max 2)
```

`🔒` is a human gate. Everything else is automatic and recorded.

## Gate schema

Every gate uses the same shape. The schema, the 11 gate names and the defaults
live in `~/.config/opencode/factory/default-policy.yaml`; `factory/policy.yaml`
only overrides values.

```yaml
spec:
  applies_if: []        # gate runs only if all are true; empty means always
  mode: human_if        # human | auto | human_if | auto_if
  when: [risk_high]     # human_if: stop on match; auto_if: proceed on match
  block_on: []          # gate failures that return to build, not to a human
```

Semantics: `human_if` stops when any `when` matches, otherwise automatic.
`auto_if` proceeds only when **all** `when` match, otherwise stops. A gate missing
from the file does not exist; the orchestrator stops and asks.

Merge never uses `risk_low` (declared). It uses `verified_risk_low`, computed by
the reviewer from the diff: paths, files and lines. A declared/verified mismatch
is a block.

The only valid tokens for `applies_if` and `when` are listed under `conditions:`
in the default policy, each with its meaning. An unknown token is a config error
and the orchestrator stops instead of guessing. `risk_*` come from the `risk` field
in the spec or task frontmatter (`low`, `medium`, `high`); `touches_ui` comes
from the task frontmatter.

## Layout

| path | owner | purpose |
| --- | --- | --- |
| `policy.yaml` | human | models, limits, gates, escalation rules |
| `verify.yaml` | human, via `factory-discover-verify` | what "green" means here |
| `verify-state.yaml` | `factory-discover-verify` | last measured baseline |
| `inbox.md` | orchestrator writes, human answers | escalations |
| `ideas/` | `factory-idea-gate` | verdicts and killed ideas |
| `experiments/` | `factory-idea-gate` | tests that are not product work |
| `specs/<id>/` | spec and design agents | brief, spec, design, tasks |
| `runs/<task>/` | qa, validator, reviewer | state, reports, evidence |

Templates are global: `~/.config/opencode/factory/templates/`. The repo does not
carry copies.

Author context for G0 lives at `~/.config/opencode/factory-profile.md`, outside
any repo. It contains capital, network and constraints; never version it.

## Skills and roles

| Step | Skill | Agent |
| --- | --- | --- |
| drive the loop | `factory-orchestrate` | primary session |
| G0 | `factory-idea-gate` | `idea-validator` |
| spec | `factory-spec` | `factory-spec` |
| design | (design contract in the agent) | `factory-design` |
| breakdown | `factory-breakdown` | `factory-design` |
| verify profile | `factory-discover-verify` | primary session |
| build | (builder rules in the agent) | `factory-builder` |
| QA | `factory-qa` | `factory-qa` |
| functional | `factory-validate` | `factory-validator` |
| UI direction and UI review | `factory-ui-design` | `factory-ui-designer` |
| PR mechanics | `factory-pr` | primary session |
| review | `factory-review` | `factory-reviewer` |
| second opinion | `plan-arbiter` | any |
| audit a session | `agent-watchdog` | any |

## Start here

### Phase 0, instrumentation

- [x] `policy.yaml`, `verify.yaml`, `inbox.md` (templates are global)
- [x] PR template
- [x] `gh` installed and authenticated
- [x] Author profile filled at `~/.config/opencode/factory-profile.md`
- [ ] Fix the red baseline: see `inbox.md`

### Phase 1, front half

- [ ] Run `factory-idea-gate` on a real idea and produce `ideas/<slug>/idea.md`
- [ ] Approve a brief, run `factory-spec`, approve a spec
- [ ] Run the design agent, then `factory-breakdown`
- [ ] Stop. Do not build until the task list is approved.

### Phase 2, one task end to end

- [ ] Take one low-risk task
- [ ] `factory-builder` in a worktree, `factory-qa`, `factory-validator`
- [ ] `factory-pr`, `factory-review`
- [ ] Merge by the policy. If `merge` resolves to human, merge by hand.

### Phase 3, reliability

- [ ] 5 tasks in a row with no manual fix
- [ ] Record `false_green` when QA passed and a defect shows up later
- [ ] `factory-discover-verify` after any CI change

### Phase 4, parallelism

- [ ] `max_open_prs: 3`, one worktree per task
- [ ] Add `factory-review-prs` and `factory-babysit-pr` from the Builder catalog
- [ ] Escalate only on the policy risk list

### Phase 5, operation

- [ ] `factory-collect` and `factory-lookback` feeding the G0
- [ ] `factory-human-digest` as the daily inbox
- [ ] `factory-ship` only after 10 clean merges

## Worktrees

```sh
git worktree add .worktrees/<task> -b <type>/<slug>
git worktree remove .worktrees/<task>
git worktree list
```

One task per worktree. The builder never works in the main checkout.

## Rules that are not negotiable

1. Green comes from `verify.yaml`. If a command is not there, the criterion is
   `manual` and a human decides.
2. `verify.yaml` changes are a human gate. An agent that redefines green can pass
   any gate.
3. The builder does not review. The reviewer does not write.
4. QA and validation are different gates. Unit tests are not functional proof.
5. Any task with `touches_ui: true` needs a declared direction and a UI review
   with screenshots before the PR. Missing empty or error state is a block.
6. No merge without evidence files, and no closing a PR the run did not open.
7. Attempt limit is 2. Then `blocked` and one row in `inbox.md`.
8. Every gate quotes the command and its result. "All good" is not a result.

## Current status

Baseline is **green** as of 2026-11-05, after PR #10. The definition lives in
`verify.yaml`; the measured result lives in `verify-state.yaml`, which agents can
update. Only a human changes `verify.yaml`.
