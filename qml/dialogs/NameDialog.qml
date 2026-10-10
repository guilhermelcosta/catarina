import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: nameDialog
    property var app

    property string base: ""        // pasta onde criar ("" = raiz)
    property bool asCollection: false
    title: asCollection ? Strings.t.newCollectionTitle : Strings.t.newFolderTitle
    anchors.centerIn: parent; modal: true; width: 340
    header: DialogHeader { dialogTitle: nameDialog.title }
    // rodapé explícito (em vez de standardButtons) para as setas navegarem entre os botões
    function accept() {
        var n = nameField.text.trim();
        if (n.length === 0) { nameField.forceActiveFocus(); return; }
        backend.createFolder((base.length > 0 ? base + "/" : "") + n);
        app.reloadTree(); nameField.text = "";
        close();
    }
    onOpened: nameField.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        TextField {
            id: nameField; Layout.fillWidth: true
            placeholderText: nameDialog.asCollection ? Strings.t.collectionNamePlaceholder : Strings.t.folderNamePlaceholder
            KeyNavigation.down: nameOk; onAccepted: nameDialog.accept()
        }
        DialogActions {
            Button { id: nameCancel; text: Strings.t.cancel; KeyNavigation.right: nameOk; KeyNavigation.up: nameField; onClicked: nameDialog.close() }
            Button { id: nameOk; text: Strings.t.create; Accessible.defaultButton: true; KeyNavigation.left: nameCancel; KeyNavigation.up: nameField; onClicked: nameDialog.accept() }
        }
    }
}
