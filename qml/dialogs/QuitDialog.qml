import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: quitDialog
    property var app

    title: Strings.t.quitTitle; modal: true; anchors.centerIn: parent; width: 400
    header: DialogHeader { dialogTitle: quitDialog.title }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Strings.t.unsavedRequests }
        DialogActions {
            Button { id: quitCancel; text: Strings.t.cancel; KeyNavigation.right: quitDiscard; onClicked: quitDialog.close() }
            Button { id: quitDiscard; text: Strings.t.discardAndQuit; KeyNavigation.left: quitCancel; KeyNavigation.right: quitSave; onClicked: { app.persistSession(); app.forceQuit = true; quitDialog.close(); Qt.quit(); } }
            Button { id: quitSave; text: Strings.t.saveAndQuit; Accessible.defaultButton: true; KeyNavigation.left: quitDiscard; onClicked: { app.saveAllTabs(); app.persistSession(); app.forceQuit = true; quitDialog.close(); Qt.quit(); } }
        }
    }
}
