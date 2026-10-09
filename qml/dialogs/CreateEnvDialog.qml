import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Criar ambiente (só o nome).
Dialog {
    id: createEnvDialog
    property var app

    title: Strings.t.createEnvTitle; anchors.centerIn: parent; modal: true; width: 380
    header: DialogHeader { dialogTitle: createEnvDialog.title }
    function create() {
        var n = newEnvName.text.trim();
        if (n.length === 0) { newEnvName.forceActiveFocus(); return; }
        backend.saveEnvironment(n, []);
        app.activateEnv(n);
        createEnvDialog.close();
        app.openEnvTab(n);
    }
    onAboutToShow: newEnvName.text = ""
    onOpened: newEnvName.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.envNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        TextField { id: newEnvName; Layout.fillWidth: true; placeholderText: Strings.t.envNamePlaceholder; KeyNavigation.down: envCreateCancel; onAccepted: createEnvDialog.create() }
        DialogActions {
            Button { id: envCreateCancel; text: Strings.t.cancel; KeyNavigation.right: envCreateBtn; KeyNavigation.up: newEnvName; onClicked: createEnvDialog.close() }
            Button { id: envCreateBtn; text: Strings.t.create; Accessible.defaultButton: true; KeyNavigation.left: envCreateCancel; KeyNavigation.up: newEnvName; onClicked: createEnvDialog.create() }
        }
    }
}
