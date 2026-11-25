import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// One settings row: label + description on the left, control in a fixed
// 200 px column (× uiScale) on the right. The control is the default child.
// `rowSearch` carries the searchable text (label + description).
// `controlWidth` overrides the column width; `wideControl` lets the control
// take the row's remaining width with a 380 px floor (the Storage path).
// docs/DESIGN.md §5.
Item {
    id: row
    property var tokens
    property string label: ""
    property string description: ""
    // duplicate-shortcut language: red + bold label (same as KvTable's duplicate name)
    property bool conflict: false
    // -1 = the standard settingsControlWidth (200 × uiScale)
    property int controlWidth: -1
    property bool wideControl: false
    readonly property string rowSearch: (label + " " + description).toLowerCase()
    readonly property int standardControlWidth: tokens ? Math.round(200 * tokens.uiScale) : 200
    readonly property int minimumWideWidth: tokens ? Math.round(380 * tokens.uiScale) : 380
    // the actual column width, exposed for the layout tests
    readonly property int resolvedControlWidth: controlColumn.width
    default property alias content: controlColumn.data

    Layout.fillWidth: true
    implicitHeight: tokens ? tokens.settingsRowHeight : 48

    RowLayout {
        anchors.fill: parent
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: row.wideControl
                                 ? Math.max(0, row.width - row.minimumWideWidth - 12)
                                 : Number.POSITIVE_INFINITY
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Label {
                objectName: "settingsRowLabel"
                Layout.fillWidth: true
                text: row.label
                wrapMode: Text.WordWrap
                font.pixelSize: tokens ? tokens.fontSizeBase : 13
                font.bold: row.conflict
                color: row.conflict ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
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
            Layout.fillWidth: row.wideControl
            Layout.preferredWidth: row.wideControl
                                   ? row.minimumWideWidth
                                   : (row.controlWidth >= 0 ? row.controlWidth : row.standardControlWidth)
            Layout.minimumWidth: row.wideControl
                                 ? row.minimumWideWidth
                                 : (row.controlWidth >= 0 ? row.controlWidth : row.standardControlWidth)
            Layout.maximumWidth: row.wideControl
                                 ? Number.POSITIVE_INFINITY
                                 : (row.controlWidth >= 0 ? row.controlWidth : row.standardControlWidth)
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            spacing: 2
        }
    }
}
