import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: historyDialog
    property var app
    property var newReqDialog

    title: Strings.t.historyTitle; anchors.centerIn: parent; modal: true; width: 640; height: 460
    header: DialogHeader { dialogTitle: historyDialog.title }
    ListModel { id: historyModel }
    function openAndLoad() {
        historyModel.clear();
        var h = backend.history();
        for (var i = 0; i < h.length; i++) historyModel.append(h[i]);
        open();
    }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.historyHint; opacity: 0.6; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            model: historyModel
            delegate: ItemDelegate {
                width: ListView.view.width
                onClicked: { historyDialog.close(); newReqDialog.openPrefilled(app.targetFolder(), model.method, model.url); }
                contentItem: RowLayout {
                    spacing: 6
                    MethodBadge {
                        method: model.method
                        color: app.methodColor(model.method)
                    }
                    Label { Layout.fillWidth: true; text: model.url; elide: Text.ElideMiddle }
                    Label { text: model.status; opacity: 0.7 }
                }
            }
        }
        Label { visible: historyModel.count === 0; text: Strings.t.historyEmpty; opacity: 0.5 }
        DialogActions {
            Button { id: historyClear; text: Strings.t.clear; KeyNavigation.right: historyClose; onClicked: app.confirmDelete(Strings.clearHistoryConfirm(), function () { backend.clearHistory(); historyDialog.openAndLoad(); }) }
            Button { id: historyClose; text: Strings.t.close; KeyNavigation.left: historyClear; onClicked: historyDialog.close() }
        }
    }
}
