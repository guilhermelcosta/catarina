import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: nameDialog
    property var app

    property string base: ""        // folder where to create ("" = root)
    property bool asCollection: false
    title: asCollection ? Strings.t.newCollectionTitle : Strings.t.newFolderTitle
    anchors.centerIn: parent; modal: true; width: 340
    header: DialogHeader { dialogTitle: nameDialog.title }
    property string failure: ""
    function errorText() {
        var n = nameField.text.trim();
        if (n.length === 0) return "";
        if (n.indexOf("/") >= 0) return Strings.t.nameCannotContainSlash;
        var rel = (base.length > 0 ? base + "/" : "") + n;
        if (backend.isCollection(rel) || backend.loadRequest(rel).method !== undefined)
            return Strings.t.itemExists;
        return "";
    }
    // explicit footer (instead of standardButtons) so the arrow keys navigate between the buttons
    function accept() {
        var n = nameField.text.trim();
        if (n.length === 0) { nameField.forceActiveFocus(); return; }
        if (errorText().length > 0) return;
        var rel = (base.length > 0 ? base + "/" : "") + n;
        if (!backend.createFolder(rel)) { failure = Strings.saveFailed(n); return; }
        failure = "";
        app.reloadTree();
        nameField.text = "";
        close();
    }
    onOpened: { nameField.text = ""; failure = ""; nameField.forceActiveFocus() }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        TextField {
            id: nameField; Layout.fillWidth: true
            objectName: "nameField"
            placeholderText: nameDialog.asCollection ? Strings.t.collectionNamePlaceholder : Strings.t.folderNamePlaceholder
            KeyNavigation.down: nameOk; onAccepted: nameDialog.accept()
        }
        Label {
            text: nameDialog.failure.length > 0 ? nameDialog.failure : nameDialog.errorText()
            color: Kirigami.Theme.negativeTextColor
            visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        DialogActions {
            Button { id: nameCancel; text: Strings.t.cancel; KeyNavigation.right: nameOk; KeyNavigation.up: nameField; onClicked: nameDialog.close() }
            Button { id: nameOk; text: Strings.t.create; Accessible.defaultButton: true
                     enabled: nameDialog.errorText().length === 0
                     KeyNavigation.left: nameCancel; KeyNavigation.up: nameField; onClicked: nameDialog.accept() }
        }
    }
}
