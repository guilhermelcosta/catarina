import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One settings row: label + description on the left, control in a fixed
// 200 px column on the right. The control is the default child. `rowSearch`
// carries the searchable text (label + description). docs/DESIGN.md §5.
Item {
    id: row
    property var tokens
    property string label: ""
    property string description: ""
    readonly property string rowSearch: (label + " " + description).toLowerCase()
    default property alias content: controlColumn.data

    Layout.fillWidth: true
    implicitHeight: tokens ? tokens.settingsRowHeight : 48

    RowLayout {
        anchors.fill: parent
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Label {
                Layout.fillWidth: true
                text: row.label
                wrapMode: Text.WordWrap
                font.pixelSize: tokens ? tokens.fontSizeBase : 13
            }
            Label {
                Layout.fillWidth: true
                visible: row.description.length > 0
                text: row.description
                wrapMode: Text.WordWrap
                opacity: 0.75
                font.pixelSize: tokens ? tokens.fontSizeSecondary : 12
            }
        }

        ColumnLayout {
            id: controlColumn
            Layout.preferredWidth: 200
            Layout.maximumWidth: 200
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: 2
        }
    }
}
