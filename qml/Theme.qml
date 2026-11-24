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

    // type scale (px), docs/DESIGN.md §2 "Tokens". The only text sizes in the
    // chrome; editor-font surfaces are the declared exception.
    readonly property int fontSizeMeta: 11           // badges, section headers, hints
    readonly property int fontSizeSecondary: 12      // secondary/help/status-bar text
    readonly property int fontSizeBase: 13           // default UI text
    readonly property int fontSizeEmphasis: 14       // emphasised rows/labels
    readonly property int fontSizeScreenTitle: 16    // screen title
    readonly property int fontSizeCollectionTitle: 20

    // control sizes (px)
    readonly property int controlToolbar: 28         // toolbar button / status bar height
    readonly property int controlField: 32           // inline field (request bar)
    readonly property int controlDialogButton: 36    // dialog button height
    readonly property int iconSize: 16
    readonly property int hitTarget: 28              // minimum click area

    // Forced colour scheme. The KDE Kirigami platform theme reports the Plasma
    // colour scheme and ignores the QGuiApplication palette, so
    // QStyleHints::setColorScheme alone leaves the UI in the desktop scheme while
    // the hint says otherwise. Backend::applyColorScheme resolves the scheme into
    // that palette anyway; SystemPalette sees it here, and the resolved roles are
    // pushed into the window's content theme (which every view inherits), so the
    // forced scheme reaches every surface on every platform.
    // assigned by Main.qml (a QtObject cannot own SystemPalette children)
    property var systemPalette
    property var systemDisabledPalette

    function applyScheme(window, scheme) {
        const forced = scheme === "light" || scheme === "dark";
        const target = window.contentItem.Kirigami.Theme;
        if (!forced) {
            target.backgroundColor = undefined;
            target.alternateBackgroundColor = undefined;
            target.textColor = undefined;
            target.disabledTextColor = undefined;
            target.highlightColor = undefined;
            target.highlightedTextColor = undefined;
            target.focusColor = undefined;
            target.inherit = true;      // back to the desktop theme
            return;
        }
        target.inherit = false;         // own the theme data for the whole tree
        target.backgroundColor = systemPalette.window;
        target.alternateBackgroundColor = Qt.darker(systemPalette.window, 1.05);
        target.textColor = systemPalette.text;
        target.disabledTextColor = systemDisabledPalette.windowText;
        target.highlightColor = systemPalette.highlight;
        target.highlightedTextColor = systemPalette.highlightedText;
        target.focusColor = systemPalette.highlight;
    }

    // chrome
    readonly property int topBarHeight: 40
    readonly property int hoverDurationMs: 120
    readonly property int focusRingWidth: 2
    // control/popup boundary: disabledTextColor falls under the 3:1 WCAG floor
    // against the panel in the light theme; textColor at 0.45 is the shared
    // border for the env pill and every popup this chrome opens.
    readonly property color chromeBorder: Qt.rgba(
        Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
        Kirigami.Theme.textColor.b, 0.45)
}
