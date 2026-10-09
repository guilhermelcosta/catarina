import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Editor do request: método/URL/params/headers/body/auth/vars. `app` = janela;
// modelos e FileDialog injetados; o editor de auth exposto p/ a janela.
ColumnLayout {
    id: editor
    property var app
    property var paramsModel
    property var headersModel
    property var fieldsModel
    property var requestVarsModel
    property var fileDialog
    property alias authEditor: requestAuthEditor
    readonly property string method: methodBox.currentText
    readonly property string bodyType: bodyEditor.bodyType
    property alias url: urlField.text
    property alias body: bodyEditor.body
    function setMethod(m) { var i = methodBox.find(m); methodBox.currentIndex = i >= 0 ? i : 0; }
    function setBodyType(v) { bodyEditor.setBodyType(v); }
    SplitView.fillWidth: true
    SplitView.minimumWidth: 380
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        ComboBox {
            id: methodBox
            model: ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS"]
            implicitWidth: 120
            onActivated: app.markDirty()
            contentItem: Text {
                leftPadding: 10
                text: methodBox.displayText
                color: app.methodColor(methodBox.currentText)
                font.bold: true
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 2

            VarField {
                id: urlField
                anchors.fill: parent
                placeholderText: Strings.t.urlExample
                font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize
                topPadding: 5; bottomPadding: 5; leftPadding: 8; rightPadding: 8
                resolved: app.resolvedVars
                collection: app.currentCollection
                onTextEdited: app.markDirty()
                onAccepted: app.doSend()
            }

            // Preview da query anexada pelos params ativos (o que o buildUrl
            // junta à URL). Só visual, não interfere na edição. Se a URL
            // digitada transborda o campo, esconde (o fim some no scroll).
            TextMetrics {
                id: urlTextMetrics
                font: urlField.font
                text: urlField.text
            }
            Rectangle {
                id: urlQueryGhost
                // destaque legível nos dois temas: mistura o accent com a cor
                // de texto (clareia no escuro, escurece no claro)
                readonly property color accent: Kirigami.ColorUtils.linearInterpolation(
                    Kirigami.Theme.highlightColor, Kirigami.Theme.textColor, 0.8)
                readonly property real startX: urlField.leftPadding + urlTextMetrics.advanceWidth
                enabled: false
                visible: app.querySuffix().length > 0 && urlField.text.length > 0
                         && startX <= urlField.width - urlField.rightPadding
                x: startX
                y: urlField.topPadding
                height: queryGhostText.implicitHeight
                width: Math.min(queryGhostText.implicitWidth + 8,
                                urlField.width - x - urlField.rightPadding)
                radius: 3
                color: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
                Text {
                    id: queryGhostText
                    anchors.fill: parent
                    anchors.leftMargin: 4; anchors.rightMargin: 4
                    verticalAlignment: Text.AlignVCenter
                    text: app.querySuffix()
                    color: urlQueryGhost.accent
                    font: urlField.font
                    elide: Text.ElideRight
                }
            }
        }
        Button {
            icon.name: app.sending ? "process-stop" : "document-send"
            text: app.sending ? Strings.t.cancel : Strings.t.send
            highlighted: !app.sending
            onClicked: app.sending ? backend.cancel() : app.doSend()
        }
        ToolButton {
            icon.name: "edit-undo"
            enabled: app.currentDirty
            onClicked: app.revertCurrent()
            ToolTip.text: Strings.t.discardTooltip; ToolTip.visible: hovered
        }
        ToolButton {
            icon.name: "document-save"
            enabled: app.currentDirty && app.requestVarsWarning.length === 0
            onClicked: app.saveCurrent()
            ToolTip.text: Strings.t.saveTooltip; ToolTip.visible: hovered
        }
    }

    RowLayout {
        visible: app.missingText.length > 0
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon {
            source: "dialog-warning"
            color: Kirigami.Theme.negativeTextColor
            implicitWidth: 16; implicitHeight: 16
        }
        Label {
            text: app.missingText
            color: Kirigami.Theme.negativeTextColor
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    TabBar {
        id: reqTabBar
        Layout.fillWidth: true
        TabButton { text: Strings.t.parameters }
        TabButton { text: Strings.t.headers }
        TabButton { text: Strings.t.body }
        TabButton { text: Strings.t.authentication }
        TabButton { text: Strings.t.variables }
    }

    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: reqTabBar.currentIndex

        KvTable { model: paramsModel; keyPlaceholder: Strings.t.parameter; resolved: app.resolvedVars; collection: app.currentCollection; onAddRequested: paramsModel.append({ name: "", value: "", enabled: true }); onEdited: { app.markDirty(); app.paramsRevision++; } }
        KvTable { model: headersModel; keyPlaceholder: Strings.t.header; resolved: app.resolvedVars; collection: app.currentCollection; onAddRequested: headersModel.append({ name: "", value: "", enabled: true }); onEdited: app.markDirty() }

        BodyEditor { id: bodyEditor; app: editor.app; fieldsModel: fieldsModel; fileDialog: fileDialog }

        AuthEditor {
            id: requestAuthEditor
            resolvedVars: app.resolvedVars
            collection: app.currentCollection
            allowInherit: true
            onEdited: app.markDirty()
        }

        // variáveis editáveis (topo) + efetivas (embaixo), com divisor
        // arrastável — no máximo metade da altura da aba.
        ReqVarsEditor { id: reqVars; app: editor.app; requestVarsModel: requestVarsModel }
    }
}
