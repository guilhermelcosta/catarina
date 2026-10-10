# Design and component guide — Catarina

Visual and implementation rules for the app. **Before creating/changing any UI element,
check here what the pattern is.** If the pattern doesn't exist, define it, implement it in a
reusable way, and **add it to this document**.

Golden rule: if an element repeats (or could repeat) in more than one place, it is a
**shared component** — never reimplement it locally.

---

## 1. Spacing (breathing room)

- **Padding of a panel/tab**: `Kirigami.Units.largeSpacing` on all edges.
- **Between controls** and internal margins of table rows/headers: `Kirigami.Units.smallSpacing`.
- **Table columns**: `smallSpacing` spacing (in `KvTable`, `colSpacing`).
- **Empty-state label below a `ComboBox`** ("No body.", "No authentication."): the vertical
  distance comes **only** from the `ColumnLayout` `spacing` (`smallSpacing`) — use only
  `Layout.leftMargin` to align. Do **not** add `Layout.topMargin` (the "No body." label was
  adding it and ended up with double the distance of "No authentication.").

### ⚠️ `StackLayout` ignores `Layout.margins`
Children of a `StackLayout` do **not** respect `Layout.margins` (verified). To give breathing room:
- wrap the content in an `Item` and use `anchors.fill: parent; anchors.margins: <value>` on the
  inner `ColumnLayout`/`RowLayout`; **or**
- use `padding: <value>` on the `ScrollView`.

### ⚠️ `StackLayout` squeezes a child that is a `Layout` with a `ScrollView`
The `StackLayout` sizes the current child with `newSize.expandedTo(min).boundedTo(max)`; for a
child that is a `ColumnLayout`/`RowLayout` (nested layout) containing a `ScrollView`, the
computed `max` comes out small and the content appears **squeezed** (e.g. the payload body
collapsed to a single line when switching to the tab). Verified in the app (xcb).
- On the `Layout` child of the `StackLayout`, set `Layout.maximumHeight: Number.POSITIVE_INFINITY`
  (or `Layout.maximumWidth`, on the corresponding axis).
- Children that are an `Item`, `KvTable`, or `ScrollView` directly do not suffer from this.
- With the maximum released, the `ColumnLayout` starts occupying the full height of the
  `StackLayout`; if no visible child has `Layout.fillHeight: true`, Qt **redistributes** the
  leftover space among the ordinary children and the header "stretches" (the combo ended up in
  the middle of the page). End the `ColumnLayout` with an `Item { Layout.fillHeight: true }`,
  leaving it `visible` only when no other child fills (e.g. body set to "none", empty effective
  variables).

### Draggable dividers (`SplitView`): generous grab area
The area the mouse actually hits to resize is the **implicit size of the `handle`**, not the
drawn line. A `1px` handle is nearly impossible to grab. The app's pattern:
`SplitGrip` (`qml/Main.qml`) — a **transparent** square of `smallSpacing*2 + 1` (drag zone) with
a centered `1px` line (visual), `cursorShape` according to orientation, and hover/drag
highlighting. Every new `SplitView` uses `handle: SplitGrip {}`.

### ⚠️ `ListModel`: declare roles in `append`, not via `setProperty`
A role created by `setProperty` **after** the delegate already exists **does not reach the
delegate**: `model.<role>` stays `undefined` forever (`get(i)` even sees the value, but the UI
doesn't). This once broke the tab pin — when restoring the session, tabs were inserted without
`pinned`/`preview`, and `setProperty(k, "pinned", true)` didn't show up on the tab (the X stayed).
- Always include **all** roles in **every** `append` (e.g. `pinned: false, preview: false`).
- Regression test in `tests/tst_components.qml` (`test_listmodel_roles_declaradas`).

### ⚠️ `ToolTip.visible: hovered` steals the click
Showing a tooltip on hover for an item that must be **clicked** (tab pin/X, icon buttons) makes
the tooltip popup swallow the click — the item's `TapHandler`/`MouseArea` never fires. Verified
in `qmltestrunner` (offscreen and xcb).
- Prefer a `ToolButton` (control) with `ToolTip.text` + `ToolTip.delay` (native tooltip, doesn't
  break the click); **or**
- simply don't auto-show tooltips on those items.

### ⚠️ Programmatic `text` does not emit `textEdited`
Setting `TextArea.text` from code (e.g. `VarCompleter.choose`) does **not** fire `textEdited` —
that only comes from user editing. Whoever listens to `onTextEdited` (the `KvTable` writes the
model, the body/URL mark dirty) becomes stale. That's why `VarCompleter.choose` emits
`target.textEdited()` by hand (QML allows emitting a C++ signal). Regression in
`tests/tst_components.qml` (`test_varcompleter_choose_notifica_edicao`).

---

## 2. Opacities (default values)

| Element | Opacity |
|---|---|
| Empty-state message ("Nothing here yet.", "No response.", etc.) | `0.6` |
| Table column header (`font.bold: true`) | `0.65` |
| Secondary/help text ("globals appear in every view", descriptions) | `0.6` |
| Disabled table row | `0.45` |
| Disabled effective variable (list) | `0.4` |

---

## 3. Buttons and actions

**Positioning** pattern: actions at the **top right**; "Add" at the **footer** of the list.
Difference in importance: primary = `highlighted` (or `Accessible.defaultButton` inside a dialog —
see below); secondary = `ToolButton` with icon only + tooltip.

| Action | Form | Icon | Where |
|---|---|---|---|
| Save (primary) | `Button { highlighted: true }` with text | `document-save` | top right; enabled only when there are changes |
| Revert/Discard (secondary) | `ToolButton` with icon only + tooltip | `edit-undo` | before Save |
| Rename | `ToolButton` with icon only | `edit-rename` | next to the title |
| Add ("Add"/"New …") | `Button`/`ToolButton` with text | `list-add` | footer of the list/table |
| Remove row | `ToolButton` | `list-remove` | last column |
| Delete (destructive) | `Button`/`ToolButton` | `edit-delete` | toolbar (tree) / footer (environment list) |
| Duplicate | `MenuItem` | `edit-duplicate` | menus |
| Send request | `Button { highlighted }` | `document-send` | request toolbar |

- **Dialogs (pattern)** — use the shared pieces, all with the same distances:
  1. `header: DialogHeader { dialogTitle: <id>.title }` (bold title; the auxiliary text is not).
  2. body = **the `contentItem` itself**, so the dialog sizes to its content:
     `contentItem: ColumnLayout { spacing: Kirigami.Units.smallSpacing; ... }`.
     Field label above the input: `Layout.bottomMargin: smallSpacing`.
  3. actions at the end, inside the body: `DialogActions { Button {...}; Button {...} }` — it
     already pushes the buttons to the right, with `spacing`/`Layout.bottomMargin: smallSpacing`
     and the primary one `Accessible.defaultButton: true` (see above).
  - Do **not** fix `height` nor use `Item { Layout.fillHeight: true }`: the dialog auto-sizes and
    the input ↔ buttons distance always stays `smallSpacing`. Only use `height` when the body has
    a list/`ScrollView` (then the `contentItem` is still the `ColumnLayout`).
  - Simple confirmation/toast dialog: same pattern (it's what gives the uniform breathing room).
  - **A dialog's primary action uses `Accessible.defaultButton: true`, not `highlighted`.** In the
    Breeze style (`org.kde.desktop/Button.qml`), `hasFocus: activeFocus || highlighted` — that is, a
    `highlighted` button is drawn **as if it were focused** even without focus. In a dialog, this
    made the primary look focused and, when pressing Tab, the primary and the actually focused
    button both showed a focus border (it looked like duplicated/stuck focus). `Accessible.defaultButton`
    draws the "default action" highlight (tinted background + soft border), distinct from the focus
    border. Use `highlighted: true` only for primary actions **outside** a dialog
    (toolbar/SaveBar/EmptyState).
- **Dialog validation is live** (as you type): a red `Label` below the field
  (`negativeTextColor`) + primary button disabled while invalid. The dialog has a **fixed height**
  already reserving the message space (otherwise it grows as you type, or the buttons leak out).
  Don't use click-only errors.
- **Form label above the field**: non-bold + `Layout.bottomMargin: smallSpacing`
  (a `2×smallSpacing` gap to the field) — the `ColumnLayout` `spacing` alone leaves the text
  "glued".
- **Small contextual editor**: prefer an **anchored, non-modal popover** (applies live) over a
  modal dialog; the cell that opens it can be a **chip** (icon + text, `alternateBackgroundColor`,
  `disabledTextColor` border, `radius: 4`). E.g. variable scope.
- **Editable section** (title + "unsaved changes" + Revert + Save): use **`SaveBar.qml`**.
  Don't recreate that header by hand.

---

## 4. Icons

Use Breeze names and **confirm they exist in the theme** (missing icons show up broken; e.g.
`vcs-repo` doesn't exist). Fixed convention:

| Concept | Icon |
|---|---|
| Collection (root level) | `folder-documents` |
| Folder/subfolder | `folder` |
| New folder | `folder-new` |
| Environment(s) | `vcs-branch` |
| Dynamic variable badge | `tools-wizard` (purple `#b180d7`) |
| New request | `document-new` |
| Save / Revert / Rename | `document-save` / `edit-undo` / `edit-rename` |
| Delete / Remove row | `edit-delete` / `list-remove` |
| Reveal/hide secret | `view-visible` / `view-hidden` |

Quick check: `find /usr/share/icons -iname "<name>.svg"`.

---

## 5. Shared components (reuse)

**Organization:** atomic components in `qml/`; screens in `qml/screens/` (`CollectionScreen`,
`EnvironmentScreen`, `SettingsScreen`, `RequestEditor` + `BodyEditor`/`ReqVarsEditor`,
`ResponsePane`, `Sidebar`, `TabStrip`); modals/popups in `qml/dialogs/`; pure logic in
`qml/Util.js` and `qml/js/` (`VarTokens.js`).

**State and orchestration:** `Main.qml` is **just the window + wiring**. State and actions (tree,
tabs, collection, environments, session, sending) live in `AppController.qml` — a non-visual
`QtObject`. Screens and dialogs receive `property var app`, which points to the **AppController**,
and talk to it via `app.<property|function>`. **Don't access window ids from inside a screen**; if
you need something new from the controller, expose a property/function on it.

In `qml/` (atomic and shell components):

- **`KvTable.qml`** — editable key/value table (params, headers, fields, request/collection/
  environment variables). Options: `secretColumn`, `allowFiles`, `scopeColumn`
  (+ `scopeText`/`scopeIcon`/`scopeColor`/`scopeRequested`), `rowFilter`, `resolved`/`collection`,
  `uniqueNames` (duplicate name in the same scope: text in **red and bold** + reason in a popup on
  field hover). `scopeColor(index)` paints the scope chip per scope (green = global, blue =
  restricted to collections; **null** = neutral). **Every new editable table uses this component** —
  extend it with a new option instead of creating another table.
- **`DialogHeader.qml`** — standard dialog header (bold title, same padding).
- **`DialogActions.qml`** — standard dialog footer: buttons to the right, same `spacing` and
  `Layout.bottomMargin`. **Every dialog uses both** — so the distances (title ↔ input ↔ buttons)
  are the same across all of them and a new modal is born on-pattern.
- **`SaveBar.qml`** — section header with a draft indicator + Revert + Save; options
  `showDiscard`, `showRename`/`canRename` (rename pencil) and signals `save`/`discard`/`rename`.
- **`EmptyState.qml`** — standardized empty state (placeholder): optional icon (fixed 72px area),
  title, message (`opacity 0.6`), shortcut, and optional action (`highlighted`). Transparent
  background (inherits the panel). For your own monochrome icon (e.g. `catarina.svg`), pass
  `iconIsMask: true` (it takes the theme color). **Every placeholder uses this component** — center
  it with `anchors.centerIn: parent; width: Math.min(parent.width - largeSpacing*2, 340)`.
- **`HeaderTable.qml`** — read-only table (response HTTP headers); selectable cells + "Copy all".
- **`ResolvedVarsTable.qml`** — read-only table of effective variables (Source/Name/Value).
  The Source column has **color and icon per scope** (global/collection/request) and the list is
  sorted by source (global → collection → request) and then by name.
- **`SourceChip.qml`** — variable source chip (tinted background + icon + text, color/icon per
  scope: global/collection/request, plus `dynamic` = purple + `tools-wizard`). Used by
  `ResolvedVarsTable` and `VarCompleter`.
- **`MethodBadge.qml`** — HTTP method badge (colored abbreviation; color comes from
  `app.methodColor`). Used in the tree, tabs, collection view, and history.
- **Tree (`qml/Sidebar.qml`)** — nested collections/requests. **12px indent per level**.
  **Indent guides** (VS Code style): a vertical `1px` line per ancestor level, aligned to the
  center of that level's triangle (`x = level*12 + 9`), in `Kirigami.Theme.textColor` with
  `opacity: 0.15`. The delegate stores `itemDepth` and the guide `Repeater` uses
  `treeItem.itemDepth` (inside a `Repeater`, `model` is shadowed by its own model). Regression:
  `tests/app/tst_app.qml::test_indent_guides_por_profundidade`.
- **`JsonTree.qml`** — JSON tree of the response (lazy: only parses when the "Tree" tab is active).
- **`AuthEditor.qml`** — shared authentication editor (request and collection Authentication tab).
  `load(auth)` fills it in, `value()` returns the map, `edited` signal when the user changes it.
  With `allowInherit: true` (request) it offers the **inherit** option, which applies the
  collection's auth to the request (`Backend::effectiveAuth`). **Every auth editor uses this
  component.**
- **`VarCompleter.qml`** — autocomplete/hover for `{{variable}}` (used by `VarField`). The hover
  popup shows `name = value` + a **scope chip** (same color/icon as the source: global/collection/
  request), instead of `(scope)` in parentheses.
- **`VarField.qml`** — single-line text field with `{{variable}}` **built in** (highlight +
  autocomplete + hover). **Every field that accepts variables uses this component** (URL, body,
  auth, Name/Value columns of the `KvTable`). It is a `TextArea` because the highlight needs the
  `QQuickTextDocument` — hence masked fields (`echoMode`, password/secret) have no highlight.
  Being a `TextArea`, it **blocks Enter/Return** (it's a single-line field; without that, Enter
  would insert a line break in the value).
- **`NetworkView.qml`** — "Network" tab.
- **`Util.js`** — pure/testable logic (cURL, formatting, tab reordering). Put any function with no
  UI dependency here.
- **`Strings.js`** — **all UI texts** (English), in a single file. Use
  `import "Strings.js" as Strings` and `text: Strings.t.<key>` (or `Strings.<function>(...)`
  for parameterized messages). **Never** put a visible text literal directly in QML, nor logic
  values (method, type, scope, id) in `Strings.js`. The backend returns **codes** (e.g.
  `variableNoteFor`, `error` signal), and QML translates via `Strings.variableNote` /
  `Strings.backendError`.

### Responsive tables (rule)
- Flexible columns: `Layout.fillWidth: true` + **explicit `Layout.preferredWidth` and
  `Layout.minimumWidth`** (never rely on the implicit size of `Label` vs `TextField` — that's what
  misaligned things).
- Small fixed columns: `preferred = minimum = maximum` (Active 48, Type 90, Secret 64, Remove 40
  in `KvTable`).
- **Header and rows use the same `preferred`/`minimum`** → they stay aligned.
- **Never** derive a column width from the table's own `width` (creates a layout polish loop).

---

## 6. Data / UX rules

- **Variables** have `enabled`; a disabled one doesn't resolve in `{{...}}`, is dimmed, and
  autocomplete doesn't offer it. Resolution is unique (`Backend::variableChain`) for all scopes.
- **Dynamic variables**: `{{$randomUuid}}`, `{{$randomTimestamp}}`, `{{$randomIsoTimestamp}}`,
  `{{$randomInt}}`, `{{$randomBoolean}}`, `{{$randomDecimal}}`, `{{$randomName}}`. Every name is
  built by `RequestLogic::dynamicName(suffix)` as `"$random" + suffix`, so the prefix can't be
  forgotten. The **single source of truth** is the `dynamicTable()` in
  `src/core/request_logic.cpp` — add one line there and it flows to generation (`dynamicValue`),
  the "missing" filter (`isDynamicVariable`) and the autocomplete. `VariableResolver::state`
  appends them to `resolved` with `source: "dynamic"`, so they show up in `{{}}` autocomplete
  (only after the user types `$`) and hover, but are hidden from the "Effective variables" table
  (`ResolvedVarsTable`). Nothing is written to the file — they exist only at send. A user variable
  with the same name wins.
- **A variable name is unique per scope** (environment, collection, or request). The same name in
  different scopes is ok (they overlap); repeated in the same scope is rejected
  (`Backend::duplicateVariableName`, trimmed names). The UI blocks **Save** and the duplicated
  field shows the reason in a **popup on hover** (same style as the `{{variable}}` hover).
- **Name and value can reference another variable** via `{{other}}` (e.g. name `{{env}}_url`
  becomes the value of `env`; value `{{host}}/x` chains). Resolved in `Backend::variableChain`
  (name **and** value in a single loop, rebuilding the name map each pass until it stabilizes —
  covers chained references, e.g. `{{variable-1}}` → `value 1` and `{{value 1}}` → `value 2`).
  The maximum number of passes is the constant `kMaxVariableResolvePasses` (`src/backend.cpp`):
  ~1 pass per chained level and, at the same time, a safety ceiling for cyclic references
  (`{{a}}`↔`{{b}}`), which doesn't converge.
- **Secrets**: the real value is loaded from the keyring for editing (masked in the field with a
  secret), but is **never** written to the versioned file; unchecking "secret" writes it in clear
  and clears the keyring. Storage is the **OS keyring** via QtKeychain (Secret
  Service/KWallet/Keychain) — a JSON blob under the service `catarina`; without QtKeychain in the
  build, it falls back to `~/.local/share/catarina/catarina/secrets.json` (`0600`). An old
  `secrets.json` is migrated to the keyring and removed on first use
  (`CATARINA_SECRETS_BACKEND=file` forces the file — used in tests). The masked field (`KvTable`)
  brings an **eye** (`view-visible`/`view-hidden`) that toggles `echoMode` to peek at the value
  without unchecking secret. This `TextField` repeats the `implicitHeight`/padding of `VarField`
  (`gridUnit * 1.7`), otherwise the `echoMode` dots change the row height depending on the font.
- **Delete confirmations**: all follow `settings.confirmDelete` (either confirm on everything, or
  on nothing).
- **Response**: Ctrl+F searches the full body; JSON always pretty; the status area reserves a fixed
  height.
- **Example collection**: on first use (empty storage, `.catarina/.seeded` marker) the backend
  copies `seed/` (resources `:/seed`, embedded in the binary) — the demo **DummyJSON** collection
  (GET/POST/PUT/DELETE, params, variables, and inherited auth) and a **Demo environment** with a
  global variable (`locale`), so the example already shows the three variable types
  (global/collection/request). It doesn't overwrite anyone who already has collections and
  doesn't recreate after the user deletes it. Only the app calls it (`main.cpp`), not the
  `Backend` constructor.
- **Query preview in the URL bar**: the active params appear concatenated right after the typed
  text, highlighted (`Kirigami.Theme.highlightColor`, background at 14%), to show what will be
  sent without opening the Network tab. It's visual only — it doesn't enter the editable text — and
  disappears if the URL overflows the field (clipped to the field when the preview itself doesn't
  fit). Pure logic in `Util.querySuffix` (same semantics as
  `Backend::buildUrl`), tested in `tst_components`.
- **Session**: only **pinned** tabs come back when reopening the app (`Util.sessionPaths`);
  preview and other non-pinned ones are transient. `restoreSessionTabs` recreates the pinned ones
  already pinned.
- **Rename collection**: repoints the scope (`collections`) of the environment variables that
  reference it (`Backend::renameCollectionScope`), otherwise the scope is left orphaned.
- **Collection authentication**: lives in `.auth.json` (same folder as the collection,
  versionable) and is applied to every request whose auth is `inherit`
  (`Backend::effectiveAuth`); any other type uses the request's own auth. The request takes
  priority, as with headers.
- **UI language**: English, **centralized in `qml/Strings.js`**. Changing any text = editing only
  that file.
- **Variable source**: values `"global"` / `"collection"` / `"request"` (used by logic and shown
  in the source chips). In the collection overview, the variables being edited are resolved by
  `Backend::resolvedCollectionVariables` to keep the source `"collection"` (not `"request"`).
- **Unsaved changes (dirty)**: the draft indicator (SaveBar/tab) only appears when the current
  state **differs from the saved one** — changing and undoing by hand clears the dirty flag. The
  comparison uses `Util.stableStringify` (canonical JSON, ignores key order). Each scope keeps its
  own baseline: the request tab's `savedJson`, `collectionVarsBaseline`/`Headers`/`Auth`, and
  `envVarsBaseline`. When editing, **recompute** against the baseline (don't flip a boolean);
  when loading/saving/reverting, update the baseline.
- **Keyboard navigation**:
  - `KvTable`: Tab/Shift+Tab move cell by cell (`moveFocus`), by row/column; `VarField` fields
    receive a `tabHandler` and the delegate covers the remaining controls.
  - Modals with input: focus automatically on the field (`onOpened`); Left/Right navigate between
    buttons (`KeyNavigation`), Up/Down link field ↔ buttons. The `TextField` keeps Left/Right for
    the cursor.
  - Modals: **Enter/Return clicks the focused button** (in addition to Space), via
    `Keys.onReturnPressed` on `DialogActions` — the button doesn't consume Return, so the key rises
    to the footer, which calls `click()` on `Window.activeFocusItem`. Text fields consume Return
    themselves (`onAccepted`).

---

## 7. Checklist when creating a new element

1. Does a component/pattern for this already exist? Reuse it (section 5).
2. Spacing: `largeSpacing` (panel) / `smallSpacing` (internal) — section 1.
3. Opacity per the table — section 2.
4. Buttons: position and form per section 3 (`SaveBar` for editable sections).
5. Icon exists in the theme and follows the convention — section 4.
6. If it's a table: use `KvTable`; if you need a new column/option, **extend the `KvTable`**.
7. A new screen/delegate talks to the app via `app` (AppController) — do **not** access window ids.
8. If a new pattern emerged → **document it here**.
