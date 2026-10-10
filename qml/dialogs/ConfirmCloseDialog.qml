import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: confirmCloseDialog
    property var app
    property var tabsModel

    title: Strings.t.unsavedChangesTitle; modal: true; anchors.centerIn: parent; width: 400
    header: DialogHeader { dialogTitle: confirmCloseDialog.title }
    property int tabIndex: -1
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: {
                var i = confirmCloseDialog.tabIndex;
                if (i < 0 || i >= tabsModel.count) return Strings.t.unsavedChanges;
                var t = tabsModel.get(i);
                var kind = t.isCollection ? "collection" : (t.isEnvironment ? "environment" : "request");
                return Strings.unsavedItem(t.name, kind);
            }
        }
        DialogActions {
            Button { id: closeCancel; text: Strings.t.cancel; KeyNavigation.right: closeDiscard; onClicked: confirmCloseDialog.close() }
            Button { id: closeDiscard; text: Strings.t.discard; KeyNavigation.left: closeCancel; KeyNavigation.right: closeSave; onClicked: { app.doCloseTab(confirmCloseDialog.tabIndex, false); confirmCloseDialog.close(); } }
            Button { id: closeSave; text: Strings.t.save; Accessible.defaultButton: true; KeyNavigation.left: closeDiscard; onClicked: { app.doCloseTab(confirmCloseDialog.tabIndex, true); confirmCloseDialog.close(); } }
        }
    }
}
