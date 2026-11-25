import QtQuick
import org.kde.kirigami as Kirigami
import "Util.js" as Util

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
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property real textInformational: 0.75   // empty-state, secondary, help
    readonly property real textTableHeader: 0.65     // bold table column header
    readonly property real textDecoration: 0.5       // separator glyphs, colons
    readonly property real textDisabledRow: 0.45
    readonly property real textDisabledVariable: 0.4

    // UI scale and density are inputs for the derived tokens, bound by Main.qml
    // to Settings; Theme stays settings-free so tests can drive it directly.
    property real uiScale: 1.0
    property string density: "comfortable"
    readonly property real densityFactor: density === "compact" ? 0.85 : 1.0

    // type scale (px), docs/DESIGN.md §2 "Tokens". The only text sizes in the
    // chrome; editor-font surfaces are the declared exception.
    readonly property int fontSizeMeta: Math.round(11 * uiScale)           // badges, section headers, hints
    readonly property int fontSizeSecondary: Math.round(12 * uiScale)      // secondary/help/status-bar text
    readonly property int fontSizeBase: Math.round(13 * uiScale)           // default UI text
    readonly property int fontSizeEmphasis: Math.round(14 * uiScale)       // emphasised rows/labels
    readonly property int fontSizeScreenTitle: Math.round(16 * uiScale)    // screen title
    readonly property int fontSizeCollectionTitle: Math.round(20 * uiScale)

    // control sizes (px)
    readonly property int controlToolbar: Math.round(28 * uiScale * densityFactor)      // toolbar button / status bar height
    readonly property int controlField: Math.round(32 * uiScale * densityFactor)        // inline field (request bar)
    readonly property int controlDialogButton: Math.round(36 * uiScale * densityFactor) // dialog button height
    readonly property int iconSize: 16
    readonly property int hitTarget: Math.max(24, Math.round(28 * uiScale * densityFactor))
    // settings rows: 44-52 px at scale 1.0
    readonly property int settingsRowHeight: Math.round((density === "compact" ? 44 : 48) * uiScale)

    // HTTP method colours (criterion 15): each entry clears 4.5:1 against both
    // backgroundColor and alternateBackgroundColor in its scheme (tst_components).
    readonly property var methodColorsLight: ({
        GET: "#2b702e", POST: "#9c4f00", PUT: "#1565c0", PATCH: "#8e24aa",
        DELETE: "#c62828", HEAD: "#795548", OPTIONS: "#4e6570"
    })
    readonly property var methodColorsDark: ({
        GET: "#9ccc65", POST: "#ffb74d", PUT: "#64b5f6", PATCH: "#ce93d8",
        DELETE: "#ef9a9a", HEAD: "#bcaaa4", OPTIONS: "#90a4ae"
    })
    readonly property var methodColors: Kirigami.Theme.backgroundColor.hsvValue < 0.5
                                         ? methodColorsDark : methodColorsLight
    // decorative hues for identity pickers (dots/icons, never text)
    readonly property var swatchColors: [
        "#c62828", "#ef6c00", "#f9a825", "#2e7d32",
        "#00838f", "#1565c0", "#6a1b9a", "#ad1457"
    ]

    // Forced colour scheme. Backend::applyColorScheme installs the resolved
    // scheme as the application palette and the Qt colour-scheme hint. The
    // Kirigami desktop style resolves its control roles from that palette
    // (inherit: false), so a content-theme override alone leaves light fields
    // inside a dark shell. Here the same roles are also written to the content
    // theme and the content item palette (which the style-painted surfaces read)
    // so every surface follows a forced light/dark consistently. `system`
    // restores the roles captured at startup.
    // assigned by Main.qml (a QtObject cannot own SystemPalette children)
    property var systemPalette
    property var systemDisabledPalette

    function applyScheme(window, scheme, accent) {
        accent = accent || "";
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
        } else {
            target.inherit = false;     // own the theme data for the whole tree
            target.backgroundColor = systemPalette.window;
            target.alternateBackgroundColor = Qt.darker(systemPalette.window, 1.05);
            target.textColor = systemPalette.text;
            target.disabledTextColor = systemDisabledPalette.windowText;
            target.highlightColor = systemPalette.highlight;
            target.highlightedTextColor = systemPalette.highlightedText;
            target.focusColor = systemPalette.highlight;
        }
        // The style-painted surfaces (fields, combos, spin boxes, buttons,
        // popups) resolve their QPalette from the window/item chain, not from
        // the Kirigami roles above. Push the same resolved palette into the
        // content item so a forced scheme cannot leave light controls inside a
        // dark shell. Bindings keep the item palette following `systemPalette`
        // when the desktop theme changes at runtime.
        const item = window.contentItem;
        if (item && item.palette) {
            const roles = ["window", "windowText", "base", "alternateBase",
                           "text", "button", "buttonText", "brightText",
                           "highlight", "highlightedText", "placeholderText",
                           "light", "midlight", "dark", "mid", "shadow"];
            for (let i = 0; i < roles.length; ++i) {
                const role = roles[i];
                item.palette[role] = Qt.binding(function () { return systemPalette[role]; });
            }
        }
        // Custom accent: override the three selection roles after the scheme.
        // The highlighted text follows the accent luminance, so a checked
        // control can never paint white on white.
        if (accent.length === 7 && accent.charAt(0) === "#") {
            target.highlightColor = accent;
            target.focusColor = accent;
            target.highlightedTextColor = Util.luminance(accent) > 0.5 ? "#1a1a1a" : "#ffffff";
        }
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
