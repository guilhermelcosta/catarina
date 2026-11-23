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
        Label { text: Strings.t.importCurlLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            TextArea {
                id: curlImportArea
                font.family: "monospace"; wrapMode: TextEdit.Wrap
                placeholderText: Strings.t.importCurlPlaceholder
                KeyNavigation.down: curlName
            }
        }
        Label { text: Strings.t.importCurlNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        TextField {
            id: curlName
            objectName: "curlNameField"
            Layout.fillWidth: true
            placeholderText: Strings.t.importCurlNamePlaceholder
            KeyNavigation.down: curlCancel
            KeyNavigation.up: curlImportArea
            onTextChanged: curlImportDialog.nameHint = ""
            onAccepted: if (curlImportDialog.nameError().length === 0) app.importCurl(curlImportArea.text, text)
        }
        Label {
            text: curlImportDialog.nameHint.length > 0 ? curlImportDialog.nameHint : curlImportDialog.nameError()
            color: Kirigami.Theme.negativeTextColor
            visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Label { text: curlImportDialog.hint; color: Kirigami.Theme.negativeTextColor; visible: text.length > 0 }
        DialogActions {
            Button { id: curlCancel; text: Strings.t.cancel; KeyNavigation.right: curlImportBtn; KeyNavigation.up: curlName; onClicked: curlImportDialog.close() }
            Button {
                id: curlImportBtn; text: Strings.t.import; Accessible.defaultButton: true
                enabled: curlImportDialog.nameError().length === 0
                KeyNavigation.left: curlCancel; KeyNavigation.up: curlName
                onClicked: app.importCurl(curlImportArea.text, curlName.text)
            }
        }
    }
}
