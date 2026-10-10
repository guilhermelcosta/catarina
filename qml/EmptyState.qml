import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Standard empty (placeholder) state of the app. Centered content:
// optional icon (fixed area), title, message, shortcut and optional action.
// Transparent background — inherits the panel background (app pattern).
// Use centered: `anchors.centerIn: parent` + `width: Math.min(parent.width - largeSpacing*2, 340)`.
ColumnLayout {
    id: root
    property string iconSource: ""
    property bool iconIsMask: false       // monochrome icon (follows the theme color)
    property string title: ""
    property string message: ""
    property string shortcut: ""          // e.g. "Ctrl+K"
    property string shortcutLabel: ""     // e.g. "opens the command palette"
    property string actionText: ""
    property string actionIcon: ""
    signal actionTriggered()

    spacing: Kirigami.Units.smallSpacing

    // icon area: reserves 72px when there is an icon; collapses when there isn't
    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: root.iconSource.length > 0 ? 72 : 0
        implicitHeight: root.iconSource.length > 0 ? 72 : 0
        Kirigami.Icon {
            anchors.centerIn: parent
            source: root.iconSource
            implicitWidth: 72; implicitHeight: 72
            isMask: root.iconIsMask
            color: Kirigami.Theme.textColor
            opacity: 0.35
            visible: root.iconSource.length > 0
        }
    }
    Label {
        Layout.alignment: Qt.AlignHCenter
        text: root.title
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
        visible: root.title.length > 0
    }
    Label {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        opacity: 0.6
        text: root.message
        visible: root.message.length > 0
    }
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.shortcut.length > 0
        spacing: Kirigami.Units.smallSpacing
        Rectangle {
            implicitWidth: keyLabel.implicitWidth + 12
            implicitHeight: keyLabel.implicitHeight + 6
            radius: 4
            color: Kirigami.Theme.alternateBackgroundColor
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor
            Label { id: keyLabel; anchors.centerIn: parent; text: root.shortcut; font.bold: true; font.pixelSize: 11 }
        }
        Label { text: root.shortcutLabel; opacity: 0.6 }
    }
    Button {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.actionText.length > 0
        highlighted: true
        icon.name: root.actionIcon
        text: root.actionText
        onClicked: root.actionTriggered()
    }
}
