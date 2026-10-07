import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Visão da rede: o que foi enviado (request) e como foi a conexão.
// O Qt não expõe DNS/TLS por fase; mostramos o que ele fornece.
Item {
    id: net
    property var meta: ({})      // vindo do Backend::responseMeta
    property var formatter: null  // expõe fmtSize (root do Main.qml)

    ScrollView {
        anchors.fill: parent
        clip: true
        ColumnLayout {
            width: net.width
            spacing: Kirigami.Units.smallSpacing

            // ---- linha de topo: método url status tempo ----
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                implicitHeight: 32
                color: Kirigami.Theme.alternateBackgroundColor
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing
                    Label {
                        text: net.meta.method !== undefined ? net.meta.method : ""
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: net.meta.url !== undefined ? net.meta.url : ""
                        elide: Text.ElideMiddle
                        font.family: "monospace"
                        opacity: 0.85
                    }
                    Label {
                        visible: net.meta.elapsedMs !== undefined
                        text: (net.meta.elapsedMs !== undefined ? net.meta.elapsedMs : 0) + " ms"
                        opacity: 0.7
                    }
                }
            }

            // ---- conexão ----
            Label { text: "Conexão"; font.bold: true; Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.topMargin: Kirigami.Units.smallSpacing }
            GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Label { text: "Host"; opacity: 0.7 }
                Label { text: net.meta.host !== undefined ? net.meta.host : "—"; font.family: "monospace" }
                Label { text: "Porta"; opacity: 0.7 }
                Label { text: net.meta.port !== undefined ? String(net.meta.port) : "—"; font.family: "monospace" }
                Label { text: "Protocolo"; opacity: 0.7 }
                Label {
                    text: net.meta.encrypted === true ? (net.meta.http2 === true ? "HTTPS · HTTP/2" : "HTTPS · HTTP/1.1")
                                                      : (net.meta.http2 === true ? "HTTP · HTTP/2" : "HTTP · HTTP/1.1")
                    font.family: "monospace"
                }
                Label { text: "Criptografado"; opacity: 0.7 }
                Label { text: net.meta.encrypted === true ? "Sim (TLS)" : "Não"; font.family: "monospace" }
                Label { text: "Tamanho"; opacity: 0.7 }
                Label { text: net.meta.sizeBytes !== undefined ? net.formatter.fmtSize(net.meta.sizeBytes) : "—"; font.family: "monospace" }
            }

            Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

            // ---- request headers ----
            Label { text: "Requisição enviada"; font.bold: true; Layout.leftMargin: Kirigami.Units.smallSpacing }
            Repeater {
                model: net.meta.requestHeaders
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing
                    Label { Layout.preferredWidth: 180; text: modelData.name; font.family: "monospace"; font.bold: true; elide: Text.ElideRight }
                    Label { Layout.fillWidth: true; text: modelData.value; font.family: "monospace"; wrapMode: Text.Wrap }
                }
            }
            Label {
                visible: !net.meta.requestHeaders || net.meta.requestHeaders.length === 0
                text: "sem cabeçalhos"; opacity: 0.5; Layout.leftMargin: Kirigami.Units.smallSpacing
            }

            // ---- request body ----
            Label {
                visible: net.meta.requestBody !== undefined && net.meta.requestBody.length > 0
                text: "Corpo enviado"; font.bold: true; Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.topMargin: Kirigami.Units.smallSpacing
            }
            TextArea {
                visible: net.meta.requestBody !== undefined && net.meta.requestBody.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.preferredHeight: Math.min(200, contentHeight + 10)
                readOnly: true
                text: net.meta.requestBody !== undefined ? net.meta.requestBody : ""
                font.family: "monospace"
                wrapMode: TextEdit.Wrap
                background: Rectangle { color: Kirigami.Theme.alternateBackgroundColor; radius: 3 }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: net.meta.method === undefined
        text: "Envie uma requisição para ver os dados de rede."
        opacity: 0.5
    }
}
