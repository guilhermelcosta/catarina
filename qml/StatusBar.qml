import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "Strings.js" as Strings

// 28 px footer: readouts on the left (storage medium, timeout), controls on the
// right (zoom, theme toggle, Ctrl+/ shortcut hint). Text only, no coloured
// console, no border-top: the window edge is the divider. docs/DESIGN.md §2 "Chrome".
Item {
    id: statusBar
    objectName: "statusBar"
    property var app
    signal shortcutsRequested()
    implicitHeight: app.theme.controlToolbar
    Layout.fillWidth: true

    readonly property int effectiveFontSize: settings.editorFontSizeResolved

    function stepZoom(delta) {
        var cur = effectiveFontSize;
        settings.editorFontSize = Math.max(6, Math.min(28, cur + delta));
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // ---- readouts: they elide before any control does ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Label {
                objectName: "statusBarStorage"
                elide: Text.ElideRight
                font.pixelSize: app.theme.fontSizeMeta
                opacity: app.theme.textInformational
                text: Strings.t.storageLabel + " "
                      + (backend.secretsBackend === "keyring" ? Strings.t.storageKeyring
                                                              : Strings.t.storageFile)
                ToolTip.text: backend.secretsBackend === "keyring"
                              ? Strings.t.storageKeyringTooltip : Strings.t.storageFileTooltip
                ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            Label {
                objectName: "statusBarTimeout"
                elide: Text.ElideRight
                font.pixelSize: app.theme.fontSizeMeta
                font.features: ({ "tnum": 1 })
                opacity: app.theme.textInformational
                text: Strings.timeoutLabel(settings.timeoutSec)
            }
        }

        // ---- zoom: the editor font size as a quick control ----
        ToolButton {
            objectName: "statusBarZoomOut"
            icon.name: "zoom-out"
            implicitWidth: app.theme.hitTarget
            implicitHeight: app.theme.controlToolbar
            enabled: settings.editorFontSizeResolved !== 6
            onClicked: statusBar.stepZoom(-1)
            ToolTip.text: Strings.t.zoomOutTooltip
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        ToolButton {
            objectName: "statusBarZoomValue"
            text: String(statusBar.effectiveFontSize)
            implicitHeight: app.theme.controlToolbar
            font.features: ({ "tnum": 1 })
            onClicked: settings.editorFontSize = 0
            ToolTip.text: Strings.t.zoomReset
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        ToolButton {
            objectName: "statusBarZoomIn"
            icon.name: "zoom-in"
            implicitWidth: app.theme.hitTarget
            implicitHeight: app.theme.controlToolbar
            enabled: settings.editorFontSizeResolved !== 28
            onClicked: statusBar.stepZoom(1)
            ToolTip.text: Strings.t.zoomInTooltip
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        // ---- forced theme is deferred to the native-control skin phase ----
        ToolButton {
            objectName: "statusBarThemeToggle"
            visible: false
            icon.name: "contrast"
            implicitWidth: app.theme.hitTarget
            implicitHeight: app.theme.controlToolbar
            onClicked: {
                // "system" picks the opposite of the scheme currently on screen
                backend.colorScheme = app.darkTheme ? "light" : "dark";
            }
            ToolTip.text: Strings.t.themeToggleTooltip
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        // ---- shortcuts hint: same destination as Ctrl+/ ----
        ToolButton {
            objectName: "statusBarShortcutsHint"
            text: Strings.t.shortcutsHintText
            font.pixelSize: app.theme.fontSizeMeta
            implicitHeight: app.theme.controlToolbar
            onClicked: statusBar.shortcutsRequested()
            ToolTip.text: Strings.t.shortcutsHintText
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }
}
