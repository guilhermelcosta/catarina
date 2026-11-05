# Agent instructions — Catarina

API client app built with Qt 6 / QML / Kirigami. UI in English.

## Design and components

Before creating or changing any UI element, read and follow **[`docs/DESIGN.md`](docs/DESIGN.md)**.
It defines the spacing, opacity, button, icon, and shared-component patterns
(`KvTable`, `SaveBar`, `HeaderTable`, `JsonTree`, `VarCompleter`, `NetworkView`, `Util.js`).

Quick rules:
- **Reuse components**; don't reimplement something that repeats locally.
- Every editable table uses `KvTable` (extend it with a new option if needed).
- Editable sections use `SaveBar` (title + "unsaved changes" + Revert + Save).
- Empty states use `EmptyState` (icon/title/message/action; transparent background).
- Panel padding: `Kirigami.Units.largeSpacing`; between controls: `Kirigami.Units.smallSpacing`.
- `StackLayout` ignores `Layout.margins` — use `anchors.margins` (via `Item`) or `ScrollView.padding`.
- Confirm every Breeze icon exists in the theme before using it.
- New pattern? Document it in `docs/DESIGN.md`.

## Tests

Run `ctest` in the `build/` directory (build: `cmake --build build`). There is also
`./build/bin/check_storage` (backend logic, hermetic) and `./build/bin/bench_storage`
(benchmark of the hot paths).

## Factory

This repo uses the agentic factory in `factory/`. Read `factory/README.md` before
running it.

Hard rules:

- **Green is defined by `factory/verify.yaml`**, not by assumption. If a criterion
  has no command there, it is `manual` and a human decides.
- Never edit `factory/verify.yaml` outside `factory-discover-verify`. Changing
  what counts as green is a human gate.
- One task = one branch `factory/<spec>/<task>` = one worktree under
  `.worktrees/`. Never build in the main checkout.
- The builder never reviews its own work. The reviewer never writes to the
  branch. The validator never fixes what it finds.
- Never merge, deploy or close a PR unless `factory/policy.yaml` allows it and
  the evidence files exist. Never push to the default branch.
- Every gate quotes the command and its result line. No gate is "all good".
- Retry limit is 2. Then the task is `blocked` and gets one row in
  `factory/inbox.md`.
- Human gates come from `factory/policy.yaml` over the global default: `mode: human`,
  or `human_if` with a matching `when`. Never hardcode a gate.
- Any task with `touches_ui: true` needs a declared direction and a UI review
  with screenshots before the PR. Follow `factory-ui-design`.
- End factory work with a status line: 🟢 done, 🟡 pending a named step,
  🔴 blocked on a human decision.
