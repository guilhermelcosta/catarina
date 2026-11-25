import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings
import "../Util.js" as Util

// Keyboard shortcuts overlay (Ctrl+/). One row per shortcut: label + keycap
// chips. Esc and click-outside close. docs/DESIGN.md §5.
Popup {
    id: overlay
    property var app
    objectName: "shortcutsOverlay"
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: parent
    width: 460
    padding: Kirigami.Units.largeSpacing

    background: Rectangle {
        radius: app.theme.radiusPanel
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: app.theme.chromeBorder
    }

    function openOverlay() {
        open();
        forceActiveFocus();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Label {
            Layout.fillWidth: true
            text: Strings.t.shortcutsOverlayTitle
            font.bold: true
            font.pixelSize: app.theme.fontSizeScreenTitle
        }
        Kirigami.Separator { Layout.fillWidth: true }

        Repeater {
            model: app.shortcutDefs
            delegate: RowLayout {
                objectName: "shortcutOverlayRow"
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Label {
                    objectName: "shortcutOverlayLabel"
                    Layout.fillWidth: true
                    text: modelData.label
                    elide: Text.ElideRight
                    font.pixelSize: app.theme.fontSizeBase
                }
                Row {
                    spacing: 4
                    Repeater {
                        model: Util.keycaps(app.shortcutSeq(modelData.id))
                        delegate: Keycap {
                            tokens: app.theme
                            label: modelData
                        }
                    }
                }
            }
        }
    }
}
