# Design and component guide — Catarina

Visual and implementation rules for the app. **Before creating/changing any UI element,
check here what the pattern is.** If the pattern doesn't exist, define it, implement it in a
reusable way, and **add it to this document**.

Golden rule: if an element repeats (or could repeat) in more than one place, it is a
**shared component** — never reimplement it locally.

---

## 0. Direction

- **Three adjectives**: dense, calm, keyboard-first. It must **not** be playful.
- **References from shipped products**: Postman (request/response split, density, method
  badges) and Insomnia (neutral surfaces, per-section save). Borrow density and hierarchy,
  never branding.
- **Platform convention**: Kirigami/Breeze. Native controls, `Kirigami.Units`, Breeze icon
  names; no custom chrome where a control exists.
- **Density and primary input**: compact, keyboard and mouse. Every primary action has a
  shortcut and a visible affordance; tree, tabs, dialogs and palette work without a mouse.
- **Innovation budget**: one interaction, the URL query preview in `RequestEditor`, which
  shows the effective URL without editing the field. Novelty stays there; the rest remains
  conventional.

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
| Empty-state message ("Nothing here yet.", "No response.", etc.) | `0.75` |
| Table column header (`font.bold: true`) | `0.65` |
| Secondary/help text ("globals appear in every view", descriptions) | `0.75` |
| Decoration only (separator glyphs, colons) | `0.5` |
| Disabled table row | `0.45` |
| Disabled effective variable (list) | `0.4` |

Muted text must keep at least 4.5:1 against its background (WCAG AA). On the
light theme 0.6 sampled at about 3.9:1, so informational text starts at 0.75;
0.5 is reserved for decoration and disabled states.

### Selection and hover

List selection has exactly one state, `ItemDelegate.highlighted`. A
selection/hover surface paints its own background from `app.theme`
(`qml/Theme.qml`, exposed through `AppController.theme`):

| Row state | Background |
|---|---|
| selected (`highlighted`) | `app.theme.selectionTint` |
| hovered, not selected | `app.theme.hoverTint` |
| hovered **and** selected | `app.theme.selectionTint` |
| neither | `"transparent"` |

- Selection alpha stays in **0.12–0.20**, hover in **0.04–0.08**, and hover is
  strictly quieter: hovering a selected row must not brighten it.
- Drag/drop-target borders, the collapse-icon hover accent and text selection
  keep the Kirigami `highlightColor`; they are affordances, not selection
  surfaces.
- An explicit `background` replaces the Breeze full-saturation highlight and its
  pressed/focus ring; keep the replacement minimal (transparent / hover / selection).
- The tinted surface is **not** a solid highlight, so a selected row's label keeps
  `Kirigami.Theme.textColor`. Breeze's `ItemDelegate` content item switches to
  `highlightedTextColor` while `highlighted`, which makes the name vanish into the
  pale tint in the light theme; give the delegate an explicit `contentItem` with
  the normal text role instead of darkening the tint.

### Tokens

`qml/Theme.qml` is the single source for the selection/hover tints, the radius
scale and the text opacity tiers. Views read them as `app.theme.<token>`; a
literal that duplicates a token is a bug.

| Token | Value |
|---|---|
| `selectionTint` | `Kirigami.Theme.highlightColor` at alpha 0.16 |
| `hoverTint` | `Kirigami.Theme.highlightColor` at alpha 0.06 |
| `radiusChip` / `radiusControl` / `radiusPanel` | 4 / 6 / 8 px |
| `textInformational` / `textTableHeader` / `textDecoration` | 0.75 / 0.65 / 0.5 |
| `textDisabledRow` / `textDisabledVariable` | 0.45 / 0.4 |
| fontSizeMeta / Secondary / Base / Emphasis | 11 / 12 / 13 / 14 px |
| fontSizeScreenTitle / fontSizeCollectionTitle | 16 / 20 px |
| controlToolbar / controlField / controlDialogButton | 28 / 32 / 36 px |
| iconSize / hitTarget | 16 / 28 px |
| topBarHeight / hoverDurationMs / focusRingWidth | 40 px / 120 ms / 2 px |
| chromeBorder | `Kirigami.Theme.textColor` at alpha 0.45 |

Both tints derive from the live `Kirigami.Theme`, so a desktop theme change
retints the app without a restart.

**Forced scheme.** The status-bar toggle persists `colorScheme` (`system` /
`light` / `dark`) and `Backend::applyColorScheme` sets the Qt colour-scheme hint
plus a resolved `QPalette`. A platform theme can ignore that palette: the KDE
Kirigami theme reads the Plasma colour scheme, so the hint says dark while every
surface stays light. `Theme.applyScheme(window, scheme)` in `qml/Theme.qml`
therefore also writes the resolved palette roles into the window's content
theme (`Kirigami.Theme.inherit: false` for the subtree, reset to `true` for
`system`); `Main.qml` calls it at startup and on `colorSchemeChanged`. Never
bind a surface to the raw palette when a token exists.

QtQuick Controls paint their style surfaces from the *window* palette, which the
platform theme supplies independently of `QGuiApplication::setPalette`. `Main.qml`
therefore binds the window palette roles to the same `SystemPalette` the Kirigami
theme uses, so fields, buttons and default label colours follow the forced scheme
too. When the platform theme has no usable accent (a neutral highlight, as under
an isolated config), `schemePalette` falls back to Breeze's selection blue and
derives the highlighted text from its luminance, so a checked control can never
paint white on white.

**Type scale.** Every visible text uses one of the six sizes. The only
exceptions are the editor-font content surfaces (URL field, request body,
response body), which the zoom control scales; they are declared in the
`tst_app` walk. The four sidebar `font.pixelSize` literals that used to sit
off-scale now read `fontSizeMeta`; the fixed method column widened from 42 to
46 px so a three-letter method still fits at 11 px bold.

**Control sizes.** Toolbar buttons are `controlToolbar` (28) tall, inline fields
`controlField` (32), dialog buttons `controlDialogButton` (36), icons `iconSize`
(16), and no click area is smaller than `hitTarget` (28). The request bar's Save
and Discard buttons moved from 24 to 28 in this slice.

### Chrome: top bar and footer

- **Top bar (`qml/TopBar.qml`, 40 px, `topBarHeight`).** One row, no logo and no
  wordmark. Left: a breadcrumb label (`fontSizeSecondary`, collection normal,
  request normal, placeholder at `textInformational`, one `/` separator at
  `textDecoration`, `ElideRight`, capped at 45% of the bar). Right: the two
  panel toggles, the environment pill, and one overflow button holding History
  and Settings. Extract it as a component; `Main.qml` stays wiring-only.
- **One outlined control in the chrome: the environment pill.** Transparent
  fill, 1 px `chromeBorder`, `radiusControl`, chevron at `iconSize`, text
  `fontSizeSecondary`, max 160 px. Hover paints `hoverTint` over 120 ms — never
  a filled chip, never `highlighted`. Its popup is a `Popup` with
  `parent: envPill`, never a fixed page x/y. This is the single deliberate
  break in border contrast: `disabledTextColor` measured below the 3:1 WCAG
  floor for a control boundary, so `chromeBorder` (textColor at 0.45) is shared
  by the pill and every popup this chrome opens.
- **Footer (`qml/StatusBar.qml`, 28 px, `controlToolbar`).** Readouts on the
  left (`Secrets: keyring|file`, `Timeout: 30 s`), controls on the right (zoom,
  theme toggle, `Ctrl+/ shortcuts`). 11 px (`fontSizeMeta`) informational text,
  no background of its own, no border-top, no colour coding. `file` is a
  legitimate mode, not a warning: the tooltip carries the explanation. Labels
  elide before controls shrink; the bar never wraps or grows. The theme toggle
  is hidden (not disabled) when `canToggleTheme` is false.
- **Palette row anatomy:** 16 px icon (`iconSize`), 8 px gap, label at 13 px,
  elastic gap, shortcut at 11 px informational with `Font.TabularNums`. 520 px,
  no title, no footer. Recents are in-session, bounded to 5 and appear as a
  `Recent` group above the categories when the query is empty. Fuzzy
  subsequence matching (`Util.fuzzyMatch`) keeps ties in the original order and
  paints matched runs bold in `highlightColor` through rich text (HTML-escaped).
- **Section counts are label text:** `Parameters 2`, `Headers 5`, `Variables 3`
  (`Strings.t.parameters` + count), same size and colour, plain labels when the
  model is empty. Body and Authentication never carry a count.

### Hover fade, focus ring, popup chrome

- **Hover fade:** every surface that paints `selectionTint`/`hoverTint` adds
  `Behavior on color { ColorAnimation { duration: app.theme.hoverDurationMs } }`
  (120 ms, `Easing.InOutQuad`). Applied to `Sidebar` tree rows, `TabStrip` tabs
  and `CommandPalette` rows. Hover stays quieter than selection, a selected row
  never brightens, and the 2 px tab underline does not fade.
- **Focus ring:** only controls that stripped the platform chrome draw
  `focusRingWidth` (2 px) `highlightColor`: the request-bar container (overlay
  only, no geometry change) and the tab-strip tabs. Standard Breeze controls
  keep their native ring; custom rings never fade.
- **Popup chrome:** popups opened by the chrome (`envPopup`, the overflow menu
  and the command palette) paint `radiusPanel` (8) + a 1 px `chromeBorder`.


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
| Send request | `Button { highlighted }`, icon only | `document-send` | inside the request bar, right edge |

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
- **Multiline editor inside a dialog**: consume Tab with `Keys.onTabPressed` (focus the first
  action) and `Keys.onBacktabPressed` (focus the previous field). Without it, Tab inserts a
  literal tab into the content (an imported cURL command, a body). `KeyNavigation.tab` alone
  does not stop QML `TextArea` from inserting the tab; `TextArea` has no `tabChangesFocus`.
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
`ResponsePane`, `Sidebar`, `TabStrip`); window chrome in `qml/` (`TopBar`, `StatusBar`);
modals/popups in `qml/dialogs/`; pure logic in
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
- **`EmptyState.qml`** — standardized empty state (placeholder): optional icon (fixed 72px area,
  `iconOpacity` defaults to `0.35`), title, message (`opacity 0.6`), shortcut, and optional
  action (`highlighted`). Transparent background (inherits the panel). For a monochrome icon,
  pass `iconIsMask: true` (it takes the theme color). A full-color app icon such as
  `assets/icons/catarina-badge.svg` stays unmasked and uses a higher `iconOpacity` (the app uses `0.9`) so
  the badge does not wash out. **Every placeholder uses this component** — center
  it with `anchors.centerIn: parent; width: Math.min(parent.width - largeSpacing*2, 340)`.
- **`HeaderTable.qml`** — read-only table (response HTTP headers); selectable cells + "Copy all".
- **`ResolvedVarsTable.qml`** — read-only table of effective variables (Source/Name/Value).
  The Source column has **color and icon per scope** (global/collection/request) and the list is
  sorted by source (global → collection → request) and then by name.
- **`SourceChip.qml`** — variable source chip (tinted background + icon + text, color/icon per
  scope: global/collection/request, plus `dynamic` = purple + `tools-wizard`). Used by
  `ResolvedVarsTable` and `VarCompleter`.
- **`MethodBadge.qml`** — HTTP method badge (colored abbreviation; color comes from
  `app.methodColor`). Used in tabs, collection view, and history. **The sidebar tree does not use
  it**: request rows render the method as plain uppercase 10 px bold coloured text
  (`objectName: "treeMethodLabel"`, fixed 42 px column so names align). A value that is scanned
  down a column is text, not a badge.
- **Tree (`qml/Sidebar.qml`)** — nested collections/requests. **12px indent per level**.
  **Indent guides** (VS Code style): a vertical `1px` line per ancestor level, aligned to the
  center of that level's triangle (`x = level*12 + 9`), in `Kirigami.Theme.textColor` with
  `opacity: 0.15`. The delegate stores `itemDepth` and the guide `Repeater` uses
  `treeItem.itemDepth` (inside a `Repeater`, `model` is shadowed by its own model). Regression:
  `tests/app/tst_app.qml::test_indent_guides_por_profundidade`.
  **Filter field** (`sidebarFilterField`): single-line control (`gridUnit * 1.7`) between the
  header and the tree, hidden when there is no collection; no magnifier, no clear button — `Esc`
  clears and returns focus to the tree. It binds `controller.treeFilter`; `applyCollapse()` makes
  a row visible when it or a descendant matches (case-insensitive, name or path), so ancestors of
  a hit never hide. A selected row that stops matching keeps `selectedPath` but clears
  `currentIndex` until the filter clears. No match shows `sidebarFilterEmpty` (transparent
  `EmptyState`, no icon, `Esc` hint).
  **Header**: exactly two actions — primary `list-add` and one `overflow-menu` button
  (`sidebarOverflowButton`, disabled without a selection) for Delete, Rename, Collapse all and
  Reveal. Destructive actions do not get a permanent icon.
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
  would insert a line break in the value). It does **not** scroll by itself, so it scrolls the
  *text* by offsetting the horizontal padding (`horizontalPadding`, `scroll` + `ensureVisible`) —
  the background/border stays fixed (moving the item would drag the frame too).
- **`NetworkView.qml`** — "Network" tab.
- **`Util.js`** — pure/testable logic (cURL, formatting, tab reordering). Put any function with no
  UI dependency here.
- **`Strings.js`** — **all UI texts** (English), in a single file. Use
  `import "Strings.js" as Strings` and `text: Strings.t.<key>` (or `Strings.<function>(...)`
  for parameterized messages). **Never** put a visible text literal directly in QML, nor logic
  values (method, type, scope, id) in `Strings.js`. The backend returns **codes** (e.g.
  `variableNoteFor`, `error` signal), and QML translates via `Strings.variableNote` /
  `Strings.backendError`.

### Tab strip (rule)
The open-request strip (`qml/TabStrip.qml`) follows these rules; it consumes
`app.theme` for surfaces and radii.

- **Bounded width:** `tabMinWidth: 90`, `tabMaxWidth: 200`. A long name clamps
  at 200 px and elides right (`Text.ElideRight`); a short one floors at 90 px and
  the label absorbs the slack. Never reintroduce a per-label width cap.
- **Surfaces:** active tab paints `Kirigami.Theme.backgroundColor` (raised over
  the strip's `alternateBackgroundColor`) with `radius: app.theme.radiusControl`;
  hovered-not-active is `app.theme.hoverTint`; neither is transparent; hovering
  an active tab never brightens it. The active tab keeps the 2 px
  `highlightColor` underline (an affordance, not a selection surface).
- **Controls appear on hover, not dimmed:** close `×` only on the active or
  hovered tab, pin only on a hovered or pinned tab, both fully opaque when
  visible, hit area at least 24×24. Pinned tabs never show `×`.
- **Tooltip without the steal trap:** the strip owns one `ToolTip`, opens it only
  when the label is actually elided and positions it **below** the tab band.
  Never attach `ToolTip.visible: hovered` to the tab, pin or `×` (section 1).
- **Scroll into view:** switching tabs (click, shortcut, new tab, session
  restore) scrolls the active tab into view one frame later, so a freshly
  appended delegate has its geometry.

### Responsive tables (rule)
- Flexible columns: `Layout.fillWidth: true` + **explicit `Layout.preferredWidth` and
  `Layout.minimumWidth`** (never rely on the implicit size of `Label` vs `TextField` — that's what
  misaligned things).
- Small fixed columns: `preferred = minimum = maximum` (Active 48, Type 90, Secret 64, Remove 40
  in `KvTable`).
- **Header and rows use the same `preferred`/`minimum`** → they stay aligned.
- **Never** derive a column width from the table's own `width` (creates a layout polish loop).

### Request bar (rule)
The request editor's top row is one object: `alternateBackgroundColor`, 1 px
`disabledTextColor`, `radiusControl`, `gridUnit * 2`.
- Method (`ComboBox`, `background: null`, `app.methodColor`, 88 px preferred,
  56 minimum), URL (the shared `VarField`, `background: null` at the call site)
  and Send (highlighted icon-only `Button`) share one border; Send is the only
  primary.
- Fixed 160 px budget; URL floor 220 px; when space runs out the icons clip.
- Discard then Save are 24×24 icon-only `ToolButton`s after the container; the
  tab dot carries the dirty state, so there is no "unsaved" label.
- The container draws the 1 px `highlightColor` focus overlay; never change
  `border.width` or the padding.

---

## 6. Data / UX rules

- **Variables** have `enabled`; a disabled one doesn't resolve in `{{...}}`, is dimmed, and
  autocomplete doesn't offer it. Resolution is unique (`Backend::variableChain`) for all scopes.
- **Unresolved variables**: a `{{name}}` that doesn't resolve is painted **red (Breeze negative) +
  bold** by the highlighter — same visual language as a repeated name in `KvTable`. There is **no
  banner** under the request bar. The scan (`VariableResolver::collectTexts`) covers URL, params,
  headers, body, auth **and the name/value of the variables themselves** — in the request, the
  collection and the environment editors — so a `{{ref}}` inside a variable definition is flagged
  too. `AppController.setMissingVars` feeds the names to `varSupport.setMissing(names)`
  (`VarSupport` keeps the attached highlighters and rehighlights them; `AppController.missingVars`
  exposes the last set for tests). `{{name}}` with a value keeps the variable color (`#c678dd`).
- **Dynamic variables**: `{{$randomUuid}}`, `{{$randomTimestamp}}`, `{{$randomIsoTimestamp}}`,
  `{{$randomInt}}`, `{{$randomBoolean}}`, `{{$randomDecimal}}`, `{{$randomName}}`, `{{$randomEmail}}`.
  Every name is
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
- **Response**: one header row (`responseHeaderRow`): 8 px status dot + status text, tabular
  `· time · size`, format selector (JSON/HTML/XML/Raw), wrap toggle, copy, find and one overflow.
  The row never wraps; at the 230 px minimum the fixed actions demote into the overflow in this
  order: find, copy, wrap — status and format stay, the meta line elides before the status does.
  The header likes status as text: no pill, no badge, one filled colour (the dot), dot absent on
  errors without a status code. Ctrl+F routes by focus: inside the sidebar it focuses the filter,
  otherwise with a displayed body it opens the body find (else the sidebar filter while visible).
  The body find searches the displayed body; the format selector only
  re-renders it (`bodySource` keeps the stored body, never mutated; resets to JSON on the next
  send). Wrap off is `TextEdit.NoWrap` with horizontal scrolling. Tab labels carry counts when a
  response exists (`Headers 12`, `Cookies 2`); plain labels otherwise.
  **Line reference** (`responseLineRef`): scrollable text areas that wrap show `Ln, Col`
  right-aligned in the bottom strip, tabular figures, informational opacity, Body tab only and
  only with a non-empty body. Never a gutter: a wrapped logical line spans several visual rows,
  and the gutter would cost 30–40 px at the 230 px pane minimum. The strip else carries the
  hover hint. The status area reserves a **minimum** height (`gridUnit * 2`) but **wraps** long
  messages instead of clipping. Error texts carry no "Error:" prefix, and the
  unresolved-variable error is **concise** (a count, not the list of names).
- **Single-line fields with long content**: `TextArea` does **not** scroll itself, and moving the
  item would drag its native border, so every `VarField` scrolls the *text* by offsetting
  `horizontalPadding` (`scroll` + `ensureVisible(cursorRectangle)`) — the frame stays put, only the
  text shifts — for the URL bar and the `KvTable` cells (header/param/variable values). The
  query-suffix preview hides once the URL is scrolled.
- **Example collection**: on first use (empty storage, `.catarina/.seeded` marker) the backend
  copies `seed/` (resources `:/seed`, embedded in the binary) — the demo **DummyJSON** collection
  (GET/POST/PUT/DELETE, params, variables, and inherited auth; `Add user` also uses dynamic
  variables `{{$randomInt}}`/`{{$randomEmail}}`) and a **Demo environment** with a global variable
  (`locale`), so the example already shows the variable scopes (global/collection/request) and the
  dynamic ones. It doesn't overwrite anyone who already has collections and
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
8. Selection/hover backgrounds come from `app.theme` (`selectionTint` / `hoverTint`), never a literal — section 2.
9. If a new pattern emerged → **document it here**.
10. Tab strip: bounded width, hover-only controls, tooltip below the band —
    section 5 (Tab strip).
