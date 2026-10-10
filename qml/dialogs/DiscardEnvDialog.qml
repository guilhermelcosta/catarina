import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Discard environment changes (injects the environments screen to reload).
Dialog {
    id: discardEnvDialog
    property var envScreen

    title: Strings.t.discardChangesTitle; modal: true; anchors.centerIn: parent; width: 400
    header: DialogHeader { dialogTitle: discardEnvDialog.title }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Strings.t.discardEnvMessage }
        DialogActions {
            Button { id: discardEnvCancel; text: Strings.t.cancel; KeyNavigation.right: discardEnvConfirm; onClicked: discardEnvDialog.close() }
            Button {
                id: discardEnvConfirm
                text: Strings.t.discard; Accessible.defaultButton: true
                KeyNavigation.left: discardEnvCancel
                onClicked: {
                    discardEnvDialog.close();
                    envScreen.loadVars(envScreen.pendingEnv);
                }
            }
        }
    }
}
