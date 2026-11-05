---
id: <nnn-slug>
spec: <id>
title: <one behaviour>
state: pending         # pending | building | built | qa | validate | pr | review | merge | done | blocked
attempt: 0
risk: low
type: fix              # feature | fix | chore | docs | test | refactor | perf | ci
touches_ui: false
screens: []
depends_on: []
branch: fix/<slug>
pr: null
files_hint: []
acceptance:
  - kind: profile
    profile: fast
  - kind: auto
    cmd: ""
    expect: ""
---

# <Task title>

## Scope

What changes. One behaviour.

## Out of scope

What this task deliberately does not touch.

## Criteria covered

Copy the ids and text from the spec. Do not invent new ones.

## Notes for the builder

Only constraints the builder cannot infer from the design. No hints about the
solution.
