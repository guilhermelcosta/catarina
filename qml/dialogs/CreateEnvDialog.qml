import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Create environment (name only).
Dialog {
    id: createEnvDialog
    property var app

    title: Strings.t.createEnvTitle; anchors.centerIn: parent; modal: true; width: 380
    header: DialogHeader { dialogTitle: createEnvDialog.title }
    function errorText() {
        var n = newEnvName.text.trim();
        if (n.length === 0) return "";
        if (app.environmentExists(n)) return Strings.t.environmentExists;
        return "";
    }
    function create() {
        var n = newEnvName.text.trim();
        if (n.length === 0) { newEnvName.forceActiveFocus(); return; }
        if (errorText().length > 0) return;
        if (app.createEnvironment(n)) createEnvDialog.close();
    }
    onAboutToShow: newEnvName.text = ""
    onOpened: newEnvName.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.envNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        TextField { id: newEnvName; Layout.fillWidth: true; placeholderText: Strings.t.envNamePlaceholder; KeyNavigation.down: envCreateCancel; onAccepted: createEnvDialog.create() }
        Label {
            text: createEnvDialog.errorText(); color: Kirigami.Theme.negativeTextColor
            visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        DialogActions {
            Button { id: envCreateCancel; text: Strings.t.cancel; KeyNavigation.right: envCreateBtn; KeyNavigation.up: newEnvName; onClicked: createEnvDialog.close() }
            Button { id: envCreateBtn; text: Strings.t.create; Accessible.defaultButton: true
                     enabled: createEnvDialog.errorText().length === 0
                     KeyNavigation.left: envCreateCancel; KeyNavigation.up: newEnvName; onClicked: createEnvDialog.create() }
        }
    }
}
