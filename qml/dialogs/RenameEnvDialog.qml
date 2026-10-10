import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: renameEnvDialog
    property var app
    property var envScreen

    title: Strings.t.renameEnvTitle; modal: true; anchors.centerIn: parent; width: 380
    header: DialogHeader { dialogTitle: renameEnvDialog.title }
    property string oldName: ""
    function errorText() {
        var n = envRenameField.text.trim();
        if (n.length === 0 || n === oldName) return "";
        for (var i = 0; i < app.envList.length; i++)
            if (app.envList[i].name === n) return Strings.t.environmentExists;
        return "";
    }
    function apply() {
        if (errorText().length > 0) return;
        var n = envRenameField.text.trim();
        if (n.length === 0 || n === oldName) { close(); return; }
        envScreen.renameTo(oldName, n);
        close();
    }
    onAboutToShow: envRenameField.text = oldName
    onOpened: { envRenameField.forceActiveFocus(); envRenameField.selectAll(); }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.newEnvNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        TextField { id: envRenameField; Layout.fillWidth: true; placeholderText: Strings.t.newEnvironmentShort; KeyNavigation.down: envRenameCancel; onAccepted: renameEnvDialog.apply() }
        Label {
            text: renameEnvDialog.errorText(); color: Kirigami.Theme.negativeTextColor
            visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        DialogActions {
            Button { id: envRenameCancel; text: Strings.t.cancel; KeyNavigation.right: envRenameApply; KeyNavigation.up: envRenameField; onClicked: renameEnvDialog.close() }
            Button { id: envRenameApply; text: Strings.t.rename; Accessible.defaultButton: true; enabled: renameEnvDialog.errorText().length === 0; KeyNavigation.left: envRenameCancel; KeyNavigation.up: envRenameField; onClicked: renameEnvDialog.apply() }
        }
    }
}
