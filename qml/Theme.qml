import QtQuick
import org.kde.kirigami as Kirigami

// Design tokens, derived from the live Kirigami theme so every binding retints
// when the desktop theme changes. Exposed to the views as `app.theme`
// (see docs/DESIGN.md §2 "Selection and hover").
QtObject {
    // selection/hover tints: selection 0.12-0.20, hover 0.04-0.08 and strictly
    // quieter. Chosen 0.16/0.06: mid-bounds, visibly separated.
    readonly property color selectionTint: Qt.rgba(
        Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
        Kirigami.Theme.highlightColor.b, 0.16)
    readonly property color hoverTint: Qt.rgba(
        Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
        Kirigami.Theme.highlightColor.b, 0.06)

    // radius scale (px): 4 chip, 6 control, 8 panel/popup
    readonly property int radiusChip: 4
    readonly property int radiusControl: 6
    readonly property int radiusPanel: 8

    // text opacity tiers, docs/DESIGN.md §2
    readonly property real textInformational: 0.75   // empty-state, secondary, help
    readonly property real textTableHeader: 0.65     // bold table column header
    readonly property real textDecoration: 0.5       // separator glyphs, colons
    readonly property real textDisabledRow: 0.45
    readonly property real textDisabledVariable: 0.4
}
