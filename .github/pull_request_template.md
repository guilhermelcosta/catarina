## Issue

Closes #

<!-- Every pull request closes an issue. Exempt: dependabot, release/*. -->

## What

<!-- One behaviour. If the title needs "and", split the work. -->

## Why

<!-- The problem, the user impact, and any linked issue. -->

## How

<!-- The approach, the files that matter, and any trade-off. -->

## Evidence

- [ ] `ctest --test-dir build --output-on-failure`
- [ ] `appstreamcli validate --no-net packaging/io.github.guilhermelcosta.Catarina.metainfo.xml`
- [ ] `desktop-file-validate build/io.github.guilhermelcosta.Catarina.desktop`
- [ ] Screenshots before/after for UI changes

Commands and result lines:

```sh
```

## Risk

- [ ] low: docs, tests, isolated behaviour
- [ ] medium: shared code, storage format, visible UI
- [ ] high: auth, secrets, migrations, packaging, network protocol

## Rollback

<!-- How to undo this without data loss. -->

## Out of scope

<!-- Changes you deliberately did not make. -->
