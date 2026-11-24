import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A settings category surface: title + optional icon over a column of
// SettingsRows. docs/DESIGN.md §5 "Settings screen".
Rectangle {
    id: card
    property var tokens          // Main's Theme, passed by the settings screen
    property string title: ""
    property string cardIcon: ""
    default property alias content: body.data

    color: Kirigami.Theme.alternateBackgroundColor
    radius: tokens ? tokens.radiusPanel : 8
    border.width: 1
    border.color: tokens ? tokens.chromeBorder : Kirigami.Theme.disabledTextColor
    implicitHeight: layout.implicitHeight + Kirigami.Units.largeSpacing * 2

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: card.cardIcon.length > 0
                source: card.cardIcon
                implicitWidth: 16
                implicitHeight: 16
                color: Kirigami.Theme.textColor
            }
            Label {
                text: card.title
                font.bold: true
                font.pixelSize: tokens ? tokens.fontSizeEmphasis : 14
            }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }
}
