## What

<!-- One behaviour. If the title needs "and", split the task. -->

## Why

- Spec: `factory/specs/<id>/spec.md`
- Task: `factory/specs/<id>/tasks/<task>.md`
- Idea: `factory/ideas/<slug>/idea.md`

## Evidence

- QA: `factory/runs/<task>/qa-report.md` (verdict, criteria table)
- Functional: `factory/runs/<task>/evidence.md` (artifact per criterion)
- Commands run:
  ```sh
  ctest --test-dir build --output-on-failure
  ```

## Risk

- [ ] low: docs, tests, isolated behaviour
- [ ] medium: shared code, storage format, visible UI
- [ ] high: auth, secrets, migrations, packaging, network protocol

## Rollback

<!-- How to undo this without a data loss. -->

## Out of scope

<!-- Changes you deliberately did not make. -->
