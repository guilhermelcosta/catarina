import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// "Move to" popover, anchored to the selected tree row.
Popup {
    id: moveDialog
    property var app
    property var treeModel
    property var treeView

    parent: Overlay.overlay
    modal: false
    padding: Kirigami.Units.smallSpacing
    width: 320
    height: Math.min(360, 64 + moveModel.count * 34)
    property string item: ""
    ListModel { id: moveModel }
    function openFor(relPath) {
        item = relPath;
        moveModel.clear();
        moveModel.append({ label: Strings.t.rootTop, path: "" });
        var t = backend.collectionTree();
        for (var i = 0; i < t.length; i++) {
            var e = t[i];
            if (!e.isFolder) continue;
            if (e.relPath === item || e.relPath.indexOf(item + "/") === 0) continue;  // don't move into itself
            moveModel.append({ label: e.relPath, path: e.relPath });
        }
        // anchors to the selected tree row
        var idx = -1;
        for (var k = 0; k < treeModel.count; k++)
            if (treeModel.get(k).relPath === relPath) { idx = k; break; }
        var it = idx >= 0 ? treeView.itemAtIndex(idx) : null;
        if (it) {
            var p = it.mapToItem(null, it.width, 0);
            x = Math.max(0, Math.min(p.x + 8, (parent ? parent.width : 800) - width));
            y = p.y;
        }
        open();
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing
        Label {
            text: Strings.moveTo(moveDialog.item.split("/").pop())
            font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            model: moveModel
            delegate: ItemDelegate {
                width: ListView.view.width
                text: model.label
                onClicked: {
                    var base = moveDialog.item.split("/").pop();
                    app.moveEntry(moveDialog.item, model.path);
                    app.selectedPath = model.path.length > 0 ? model.path + "/" + base : base;
                    app.selectedIsFolder = false;
                    moveDialog.close();
                }
            }
        }
    }
}
