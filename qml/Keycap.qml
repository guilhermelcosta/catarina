import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// One keycap chip for a shortcut segment ("Ctrl", "Shift", "A").
// Shared by the shortcuts overlay and the settings rows. docs/DESIGN.md §5.
Rectangle {
    id: keycap
    objectName: "keycap"
    property var tokens
    property string label: ""
    implicitWidth: chipLabel.implicitWidth + Kirigami.Units.smallSpacing * 1.5
    implicitHeight: Math.max(tokens ? tokens.hitTarget : 24,
                             chipLabel.implicitHeight + Kirigami.Units.smallSpacing)
    radius: tokens ? tokens.radiusChip : 4
    color: Kirigami.Theme.backgroundColor
    border.width: 1
    border.color: tokens ? tokens.chromeBorder : Kirigami.Theme.disabledTextColor

    Label {
        id: chipLabel
        anchors.centerIn: parent
        text: keycap.label
        font.bold: true
        font.family: "monospace"
        font.pixelSize: keycap.tokens ? keycap.tokens.fontSizeMeta : 11
    }
}
