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

    // Request bar: one border around method, URL and Send (docs/DESIGN.md §5,
    // pattern 9). The URL owns all the slack; the fixed minimums (160 px) keep
    // it at 220 px or more even at the 380 px editor minimum.
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Rectangle {
            id: requestBar
            objectName: "requestBar"
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 2
            color: Kirigami.Theme.alternateBackgroundColor
            radius: app.theme.radiusControl
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4; anchors.rightMargin: 4
                spacing: Kirigami.Units.smallSpacing
                ComboBox {
                    id: methodBox
                    objectName: "requestMethodBox"
                    model: ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS"]
                    Layout.preferredWidth: Math.max(56, Math.min(88,
                        parent.width - (220 + 24 + Kirigami.Units.smallSpacing * 2 + 3)))
                    Layout.minimumWidth: 56
                    Layout.fillHeight: true
                    implicitHeight: Kirigami.Units.gridUnit * 2
                    background: null
                    padding: 0
                    leftPadding: 0; rightPadding: 4
                    onActivated: app.markDirty()
                    // One label: the name and its chevron live in the content item.
                    // A separate `indicator` is not laid out once the style is
                    // stripped, so the arrow would float in a corner.
                    indicator: null
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Text {
                            id: methodLabel
                            Layout.leftMargin: methodBox.width < 72 ? 4 : 10
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: methodBox.displayText
                            color: app.methodColor(methodBox.currentText)
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        // The chevron is the first thing to give way: below 72 px
                        // the whole segment is the click target and the name keeps
                        // its room (ui.md C2).
                        Kirigami.Icon {
                            objectName: "requestMethodChevron"
                            visible: methodBox.width >= 72
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            Layout.alignment: Qt.AlignVCenter
                            source: "arrow-down"
                            color: Kirigami.Theme.textColor
                        }
                    }
                    ToolTip.text: Strings.t.methodTooltip
                    ToolTip.delay: 700
                    ToolTip.visible: hovered && !methodBox.popup.visible
                }
                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 220
                    Layout.fillHeight: true
                    implicitHeight: Kirigami.Units.gridUnit * 2

                    VarField {
                        id: urlField
                        anchors.fill: parent
                        background: null
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
                    id: requestSendButton
                    objectName: "requestSendButton"
                    display: AbstractButton.IconOnly
                    icon.name: app.sending ? "process-stop" : "document-send"
                    text: app.sending ? Strings.t.cancel : Strings.t.send
                    highlighted: !app.sending
                    Layout.preferredWidth: 24
                    Layout.minimumWidth: 24
                    // inset inside the container so the highlighted chrome does
                    // not double the container's border (ui-review round 1)
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2 - 6
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 3
                    onClicked: app.sending ? backend.cancel() : app.doSend()
                    // delayed native tooltip; no immediate hover popup, which
                    // would overlap the click target (DESIGN.md §1)
                    ToolTip.text: Strings.t.sendTooltip
                    ToolTip.delay: 700
                }
            }
            // The borderless field and segment lose Breeze's focus ring, so the
            // container draws it. Overlay only: the space budget must not move
            // (ui.md C1), hence no change to border.width or padding.
            Rectangle {
                anchors.fill: parent
                radius: requestBar.radius
                color: "transparent"
                border.width: 1
                border.color: Kirigami.Theme.highlightColor
                visible: methodBox.activeFocus || urlField.activeFocus || requestSendButton.activeFocus
            }
        }
        // Persistence is not part of composing a request: quiet icon-only
        // buttons outside the bar, Discard before Save.
        ToolButton {
            objectName: "requestRevertButton"
            icon.name: "edit-undo"
            text: Strings.t.discard
            display: AbstractButton.IconOnly
            implicitWidth: 24; implicitHeight: 24
            Layout.preferredWidth: 24; Layout.minimumWidth: 24
            Layout.alignment: Qt.AlignVCenter
            enabled: app.currentDirty
            onClicked: app.revertCurrent()
            ToolTip.text: Strings.t.discardTooltip; ToolTip.delay: 700
        }
        ToolButton {
            objectName: "requestSaveButton"
            icon.name: "document-save"
            text: Strings.t.save
            display: AbstractButton.IconOnly
            implicitWidth: 24; implicitHeight: 24
            Layout.preferredWidth: 24; Layout.minimumWidth: 24
            Layout.alignment: Qt.AlignVCenter
            enabled: app.currentDirty && app.requestVarsWarning.length === 0
            onClicked: app.saveCurrent()
            ToolTip.text: Strings.t.saveTooltip; ToolTip.delay: 700
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
