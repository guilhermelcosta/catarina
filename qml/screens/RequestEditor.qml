import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Request editor: method/URL/params/headers/body/auth/vars. `app` = window;
// models and FileDialog injected; the auth editor exposed to the window.
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
    readonly property alias urlInput: urlField
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
                topPadding: 5; bottomPadding: 5; horizontalPadding: 8
                resolved: app.resolvedVars
                collection: app.currentCollection
                onTextEdited: app.markDirty()
                onAccepted: app.doSend()
            }

            // Preview of the query appended by the active params (what buildUrl
            // joins to the URL). Visual only, doesn't interfere with editing. If the URL
            // typed overflows the field, it hides (the end disappears in the scroll).
            TextMetrics {
                id: urlTextMetrics
                font: urlField.font
                text: urlField.text
            }
            Rectangle {
                id: urlQueryGhost
                // readable highlight in both themes: blends the accent with the text
                // color (lightens on dark, darkens on light)
                readonly property color accent: Kirigami.ColorUtils.linearInterpolation(
                    Kirigami.Theme.highlightColor, Kirigami.Theme.textColor, 0.8)
                readonly property real startX: urlField.leftPadding + urlTextMetrics.advanceWidth
                enabled: false
                visible: app.querySuffix().length > 0 && urlField.text.length > 0
                         && urlField.scroll === 0
                         && startX <= urlField.width - urlField.rightPadding
                x: startX
                y: urlField.topPadding
                height: queryGhostText.implicitHeight
                width: Math.min(queryGhostText.implicitWidth + 8,
                                urlField.width - x - urlField.rightPadding)
                radius: 3
                color: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
                // the width is clamped to the field, but a Text with a width
                // smaller than its margins goes negative and Qt paints it at
                // full implicit width; clip keeps it inside the field
                clip: true
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

        // NB: qualify with `editor.` — `fieldsModel`/`fileDialog` are properties
        // of this component; without the prefix QML would resolve to the property
        // itself (still undefined) instead of the parent's.
        BodyEditor { id: bodyEditor; objectName: "bodyEditor"; app: editor.app; fieldsModel: editor.fieldsModel; fileDialog: editor.fileDialog }

        AuthEditor {
            id: requestAuthEditor
            resolvedVars: app.resolvedVars
            collection: app.currentCollection
            allowInherit: true
            onEdited: app.markDirty()
        }

        // editable variables (top) + effective ones (bottom), with a draggable
        // divider — at most half the tab height.
        ReqVarsEditor { id: reqVars; objectName: "reqVarsEditor"; app: editor.app; requestVarsModel: editor.requestVarsModel }
    }
}
