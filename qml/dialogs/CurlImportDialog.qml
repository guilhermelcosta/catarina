import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: curlImportDialog
    property var app

    title: Strings.t.importCurlTitle; anchors.centerIn: parent; modal: true; width: 560; height: 420
    header: DialogHeader { dialogTitle: curlImportDialog.title }
    property string hint: ""
    property string nameHint: ""
    function nameError() {
        var n = curlName.text.trim();
        if (n.length === 0) return "";
        if (n.indexOf("/") >= 0) return Strings.t.nameCannotContainSlash;
        var folder = app.targetFolder();
        var rel = (folder.length > 0 ? folder + "/" : "") + n;
        if (backend.isCollection(rel) || backend.loadRequest(rel).method !== undefined)
            return Strings.t.itemExists;
        return "";
    }
    // called from outside: clears the content before opening (the internal fields aren't accessible outside)
    function openFresh() {
        hint = ""; nameHint = ""; curlName.text = ""; curlImportArea.text = "";
        open();
    }
    onOpened: curlImportArea.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.nameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        TextField {
            id: curlName
            objectName: "curlNameField"
            Layout.fillWidth: true
            placeholderText: Strings.t.importCurlNamePlaceholder
            KeyNavigation.down: curlImportArea
            onTextChanged: curlImportDialog.nameHint = ""
            onAccepted: if (curlImportDialog.nameError().length === 0 && curlImportArea.text.trim().length > 0)
                            app.importCurl(curlImportArea.text, text)
        }
        Label {
            objectName: "curlNameError"
            text: curlImportDialog.nameHint.length > 0 ? curlImportDialog.nameHint : curlImportDialog.nameError()
            color: Kirigami.Theme.negativeTextColor
            visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Label { text: Strings.t.importCurlLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            TextArea {
                id: curlImportArea
                objectName: "curlCommandArea"
                font.family: "monospace"; wrapMode: TextEdit.Wrap
                placeholderText: Strings.t.importCurlPlaceholder
                // QML TextArea inserts a tab by default; Tab must walk the form instead
                Keys.onTabPressed: function (event) { event.accepted = true; curlCancel.forceActiveFocus(); }
                Keys.onBacktabPressed: function (event) { event.accepted = true; curlName.forceActiveFocus(); }
                KeyNavigation.up: curlName
                KeyNavigation.down: curlCancel
                onTextChanged: curlImportDialog.hint = ""
            }
        }
        Label { text: curlImportDialog.hint; color: Kirigami.Theme.negativeTextColor; visible: text.length > 0 }
        Label {
            text: Strings.willBeCreatedIn(app.targetFolder().length > 0 ? app.targetFolder() : Strings.rootFolder())
            opacity: 0.75
            Layout.fillWidth: true
            elide: Text.ElideMiddle
        }
        DialogActions {
            Button { id: curlCancel; objectName: "curlCancelButton"; text: Strings.t.cancel; KeyNavigation.right: curlImportBtn; KeyNavigation.up: curlImportArea; onClicked: curlImportDialog.close() }
            Button {
                id: curlImportBtn; text: Strings.t.import; Accessible.defaultButton: true
                objectName: "curlImportButton"
                enabled: curlImportDialog.nameError().length === 0 && curlImportArea.text.trim().length > 0
                KeyNavigation.left: curlCancel; KeyNavigation.up: curlImportArea
                onClicked: app.importCurl(curlImportArea.text, curlName.text)
            }
        }
    }
}
