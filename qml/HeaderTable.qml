import QtQuick
import org.kde.kirigami as Kirigami

// Tabela simples de cabeçalhos HTTP (nome/valor) para a resposta.
Item {
    id: table
    property var headers: []            // [{ name, value }]
    readonly property real nameWidth: Math.max(80, width * 0.33)

    Column {
        anchors.fill: parent
        spacing: 0
        // cabeçalho
        Rectangle {
            width: parent.width
            height: 28
            color: "transparent"
            Row {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.smallSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                Text { width: table.nameWidth; anchors.verticalCenter: parent.verticalCenter; text: "Nome"; font.bold: true; opacity: 0.65; color: Kirigami.Theme.textColor }
                Rectangle { width: 1; height: parent.height; color: Kirigami.Theme.disabledTextColor; opacity: 0.3 }
                Text { width: parent.width - table.nameWidth - 6; anchors.verticalCenter: parent.verticalCenter; leftPadding: Kirigami.Units.smallSpacing; text: "Valor"; font.bold: true; opacity: 0.65; color: Kirigami.Theme.textColor }
            }
        }
        Kirigami.Separator { width: parent.width }
        ListView {
            id: view
            objectName: "headerList"
            width: parent.width
            height: parent.height - 29
            clip: true
            model: table.headers
            delegate: Rectangle {
                width: view.width
                height: Math.max(30, nameLabel.paintedHeight + Kirigami.Units.smallSpacing * 2)
                color: index % 2 === 0 ? "transparent" : Qt.rgba(0.5, 0.5, 0.5, 0.06)
                Text {
                    id: nameLabel
                    x: Kirigami.Units.smallSpacing
                    width: table.nameWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    font.family: "monospace"
                    font.bold: true
                    color: Kirigami.Theme.textColor
                    wrapMode: Text.Wrap
                }
                Rectangle {
                    x: Kirigami.Units.smallSpacing + table.nameWidth
                    width: 1; height: parent.height
                    color: Kirigami.Theme.disabledTextColor; opacity: 0.3
                }
                Text {
                    x: Kirigami.Units.smallSpacing * 2 + table.nameWidth
                    width: parent.width - table.nameWidth - Kirigami.Units.smallSpacing * 3
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.value
                    font.family: "monospace"
                    color: Kirigami.Theme.textColor
                    wrapMode: Text.Wrap
                }
            }
        }
        Text {
            width: parent.width
            visible: table.headers.length === 0
            horizontalAlignment: Text.AlignHCenter
            topPadding: Kirigami.Units.largeSpacing
            text: "Sem cabeçalhos."
            opacity: 0.6
            color: Kirigami.Theme.textColor
        }
    }
}
