import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Tabela simples de cabeçalhos HTTP (nome/valor) para a resposta.
// As células são selecionáveis (copiar com o mouse) e há "Copiar tudo" no cabeçalho.
// A altura da linha acompanha o maior texto (nome ou valor) — evita sobreposição.
Item {
    id: table
    property var headers: []            // [{ name, value }]
    signal copyRequested(string text)
    readonly property real nameWidth: Math.max(80, width * 0.33)
    readonly property int copyColWidth: 36   // espaço à direita reservado ao botão copiar
    // altura natural (cabeçalho + linhas) — permite usar embutido sem altura explícita
    implicitHeight: 29 + view.contentHeight

    function allHeadersText() {
        var out = [];
        for (var i = 0; i < headers.length; i++)
            out.push(headers[i].name + ": " + headers[i].value);
        return out.join("\n");
    }

    Column {
        anchors.fill: parent
        spacing: 0
        // cabeçalho das colunas
        Rectangle {
            width: parent.width
            height: 28
            color: "transparent"
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: table.copyColWidth
                anchors.leftMargin: Kirigami.Units.smallSpacing
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                Text { width: table.nameWidth; anchors.verticalCenter: parent.verticalCenter; text: Strings.t.name; font.bold: true; opacity: 0.65; color: Kirigami.Theme.textColor }
                Rectangle { width: 1; height: parent.height; color: Kirigami.Theme.disabledTextColor; opacity: 0.3 }
                Text { width: parent.width - table.nameWidth - 6; anchors.verticalCenter: parent.verticalCenter; leftPadding: Kirigami.Units.smallSpacing; text: Strings.t.value; font.bold: true; opacity: 0.65; color: Kirigami.Theme.textColor }
            }
            ToolButton {
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                icon.name: "edit-copy"
                enabled: table.headers.length > 0
                onClicked: table.copyRequested(table.allHeadersText())
                ToolTip.text: Strings.t.copyAllHeaders; ToolTip.visible: hovered
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
                id: row
                width: view.width
                height: Math.max(30, Math.max(nameEdit.contentHeight, valueEdit.contentHeight) + Kirigami.Units.smallSpacing * 2)
                color: index % 2 === 0 ? "transparent" : Qt.rgba(0.5, 0.5, 0.5, 0.06)
                TextEdit {
                    id: nameEdit
                    x: Kirigami.Units.smallSpacing
                    width: table.nameWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.family: "monospace"
                    font.bold: true
                    color: Kirigami.Theme.textColor
                    selectionColor: Kirigami.Theme.highlightColor
                    selectedTextColor: Kirigami.Theme.highlightedTextColor
                }
                Rectangle {
                    x: Kirigami.Units.smallSpacing + table.nameWidth
                    width: 1; height: parent.height
                    color: Kirigami.Theme.disabledTextColor; opacity: 0.3
                }
                TextEdit {
                    id: valueEdit
                    x: Kirigami.Units.smallSpacing * 2 + table.nameWidth
                    width: parent.width - table.nameWidth - Kirigami.Units.smallSpacing * 3 - table.copyColWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.value
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.family: "monospace"
                    color: Kirigami.Theme.textColor
                    selectionColor: Kirigami.Theme.highlightColor
                    selectedTextColor: Kirigami.Theme.highlightedTextColor
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
        message: Strings.t.noHeadersEmpty
        visible: table.headers.length === 0
    }
}
