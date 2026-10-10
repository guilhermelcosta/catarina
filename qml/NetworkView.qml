import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Util.js" as Util
import "Strings.js" as Strings

// Network view: what was sent (request) and how the connection went.
// Qt doesn't expose DNS/TLS per phase; we show what it provides.
Item {
    id: net
    property var meta: ({})      // coming from Backend::responseMeta

    ScrollView {
        anchors.fill: parent
        clip: true
        ColumnLayout {
            width: net.width
            spacing: Kirigami.Units.smallSpacing

            // ---- top row: method url status time ----
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

            // ---- connection ----
            Label { text: Strings.t.connection; font.bold: true; Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.topMargin: Kirigami.Units.smallSpacing }
            GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Label { text: Strings.t.host; opacity: 0.7 }
                Label { text: net.meta.host !== undefined ? net.meta.host : "—"; font.family: "monospace" }
                Label { text: Strings.t.port; opacity: 0.7 }
                Label { text: net.meta.port !== undefined ? String(net.meta.port) : "—"; font.family: "monospace" }
                Label { text: Strings.t.protocol; opacity: 0.7 }
                Label {
                    text: net.meta.encrypted === true ? (net.meta.http2 === true ? "HTTPS · HTTP/2" : "HTTPS · HTTP/1.1")
                                                      : (net.meta.http2 === true ? "HTTP · HTTP/2" : "HTTP · HTTP/1.1")
                    font.family: "monospace"
                }
                Label { text: Strings.t.encrypted; opacity: 0.7 }
                Label { text: net.meta.encrypted === true ? Strings.t.yesTls : Strings.t.no; font.family: "monospace" }
                Label { text: Strings.t.size; opacity: 0.7 }
                Label { text: net.meta.sizeBytes !== undefined ? Util.fmtSize(net.meta.sizeBytes) : "—"; font.family: "monospace" }
            }

            Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

            // ---- request headers ----
            Label { text: Strings.t.requestSent; font.bold: true; Layout.leftMargin: Kirigami.Units.smallSpacing }
            HeaderTable {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                visible: net.meta.requestHeaders !== undefined && net.meta.requestHeaders.length > 0
                headers: net.meta.requestHeaders !== undefined ? net.meta.requestHeaders : []
                onCopyRequested: function (text) { varSupport.copyText(text) }
            }
            Label {
                visible: !net.meta.requestHeaders || net.meta.requestHeaders.length === 0
                text: Strings.t.noHeaders; opacity: 0.5; Layout.leftMargin: Kirigami.Units.smallSpacing
            }

            // ---- request body ----
            Label {
                visible: net.meta.requestBody !== undefined && net.meta.requestBody.length > 0
                text: Strings.t.bodySent; font.bold: true; Layout.leftMargin: Kirigami.Units.smallSpacing
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

    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
        message: Strings.t.networkEmpty
        visible: net.meta.method === undefined
    }
}
