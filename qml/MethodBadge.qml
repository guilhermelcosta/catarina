import QtQuick
import QtQuick.Layouts

// HTTP method badge (colored abbreviation). The color comes from the caller
// (`root.methodColor`) because it depends on the theme; the background is the same color at 18%.
Item {
    id: badge
    property string method: ""
    property color color: "transparent"
    property int pixelSize: 9
    property int badgeHeight: 16
    implicitWidth: label.implicitWidth + 8
    implicitHeight: badgeHeight

    Rectangle {
        anchors.fill: parent
        radius: 3
        color: Qt.rgba(badge.color.r, badge.color.g, badge.color.b, 0.18)
        Text {
            id: label
            anchors.centerIn: parent
            text: badge.method
            color: badge.color
            font.pixelSize: badge.pixelSize
            font.bold: true
        }
    }
}
