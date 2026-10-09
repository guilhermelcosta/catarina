import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: renameDialog
    property var app

    title: Strings.t.renameTitle; modal: true; anchors.centerIn: parent; width: 360
    header: DialogHeader { dialogTitle: renameDialog.title }
    property string relPath: ""
    // erro ao vivo (conforme digita); nome vazio não mostra nada
    function errorText() {
        var n = renameField.text.trim();
        if (n.length === 0) return "";
        if (n.indexOf("/") >= 0) return Strings.t.nameCannotContainSlash;
        var parent = relPath.split("/").slice(0, -1).join("/");
        var newRel = parent.length > 0 ? parent + "/" + n : n;
        if (newRel !== relPath && (backend.isCollection(newRel) || backend.loadRequest(newRel).method !== undefined))
            return Strings.t.itemExists;
        return "";
    }
    function openFor(p) {
        relPath = p;
        renameField.text = p.split("/").pop();
        open();
        renameField.forceActiveFocus();
        renameField.selectAll();
    }
    function apply() {
        if (errorText().length > 0) return;
        var n = renameField.text.trim();
        if (n.length === 0) return;
        var parent = relPath.split("/").slice(0, -1).join("/");
        var newRel = parent.length > 0 ? parent + "/" + n : n;
        if (backend.renameEntry(relPath, n)) {
            app.remapTabs(relPath, newRel);
            if (app.selectedPath === relPath) app.selectedPath = newRel;
            app.reloadTree();
            close();
        } else {
            app.notify(Strings.t.renameFailed);
        }
    }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.newNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        TextField { id: renameField; Layout.fillWidth: true; KeyNavigation.down: renameCancel; onAccepted: renameDialog.apply() }
        Label {
            text: renameDialog.errorText(); color: Kirigami.Theme.negativeTextColor
            visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        DialogActions {
            Button { id: renameCancel; text: Strings.t.cancel; KeyNavigation.right: renameApply; KeyNavigation.up: renameField; onClicked: renameDialog.close() }
            Button { id: renameApply; text: Strings.t.rename; Accessible.defaultButton: true; enabled: renameDialog.errorText().length === 0; KeyNavigation.left: renameCancel; KeyNavigation.up: renameField; onClicked: renameDialog.apply() }
        }
    }
}
