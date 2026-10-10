import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Confirmar exclusão (genérico; respeita settings.confirmDelete).
Dialog {
    id: deleteDialog
    title: Strings.t.deleteTitle; modal: true; anchors.centerIn: parent; width: 400
    header: DialogHeader { dialogTitle: deleteDialog.title }
    property string message: ""
    property var callback: null
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: deleteDialog.message }
        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.7; text: Strings.t.cannotBeUndone }
        DialogActions {
            Button { id: deleteCancel; text: Strings.t.cancel; KeyNavigation.right: deleteConfirm; onClicked: deleteDialog.close() }
            Button {
                id: deleteConfirm
                text: Strings.t.delete; Accessible.defaultButton: true
                KeyNavigation.left: deleteCancel
                onClicked: { var f = deleteDialog.callback; deleteDialog.close(); if (f) f(); }
            }
        }
    }
}
