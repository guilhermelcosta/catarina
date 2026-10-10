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
