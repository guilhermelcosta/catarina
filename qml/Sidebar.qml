import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "Strings.js" as Strings

// Sidebar de coleções (árvore + ações). `app` = janela; treeModel/menus injetados;
// a lista é exposta p/ o popup de mover ancorar na linha.
ColumnLayout {
    id: sidebar
    property var app
    property var treeModel
    property var addMenu
    property var ctxMenu
    readonly property alias view: treeView
    visible: app.sidebarVisible
    SplitView.preferredWidth: 250
    SplitView.minimumWidth: 190
    spacing: 0
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        Kirigami.Icon { source: "folder-documents"; implicitWidth: 16; implicitHeight: 16 }
        Label { text: Strings.t.collections; font.bold: true }
        Item { Layout.fillWidth: true }
        ToolButton { icon.name: "list-add"; onClicked: addMenu.open(); ToolTip.text: Strings.t.add; ToolTip.visible: hovered }
        ToolButton {
            icon.name: "edit-delete"
            enabled: app.selectedPath.length > 0
            onClicked: app.askDelete()
            ToolTip.text: Strings.t.deleteSelected; ToolTip.visible: hovered
        }
    }
    Kirigami.Separator { Layout.fillWidth: true }
    ListView {
        id: treeView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: treeModel
        delegate: ItemDelegate {
            id: treeItem
            width: ListView.view.width
            highlighted: model.relPath === app.selectedPath
            property int itemDepth: model.depth || 0

            // guias de indentação (estilo VS Code): uma linha vertical por nível de
            // ancestral, alinhada ao centro do triângulo daquele nível (recuo = 12px)
            Row {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                Repeater {
                    objectName: "indentRepeater"
                    model: treeItem.itemDepth
                    delegate: Item {
                        width: 12
                        height: treeItem.height
                        Rectangle {
                            x: 9
                            width: 1
                            height: parent.height
                            color: Kirigami.Theme.textColor
                            opacity: 0.15
                        }
                    }
                }
            }

            contentItem: RowLayout {
                spacing: 4
                Item { Layout.preferredWidth: (model.depth || 0) * 12 + 16; Layout.preferredHeight: 1 }
                Kirigami.Icon { visible: model.isFolder; source: (model.depth || 0) === 0 ? "folder-documents" : "folder"; implicitWidth: 16; implicitHeight: 16; color: Kirigami.Theme.textColor }
                MethodBadge {
                    visible: !model.isFolder
                    method: model.method
                    color: app.methodColor(model.method)
                }
                Label { Layout.fillWidth: true; text: model.name; elide: Text.ElideRight }
            }

            // clique (esquerdo/direito) + arrasto manual (com ghost)
            MouseArea {
                id: mainMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                property real pressX: 0
                property real pressY: 0
                onPressed: function (m) { app.justDragged = false; pressX = m.x; pressY = m.y; }
                onPositionChanged: function (m) {
                    if (!pressed) return;
                    if (!app.dragging) {
                        if (Math.abs(m.x - pressX) + Math.abs(m.y - pressY) < 8) return;
                        app.dragging = true;
                        app.dragFrom = model.relPath;
                        app.dragLabel = model.name;
                        app.dragMethod = model.isFolder ? "" : model.method;
                        app.dragIsCollection = model.isFolder && (model.depth || 0) === 0;
                    }
                    var gp = mainMouse.mapToItem(mainPage, m.x, m.y);
                    app.ghostX = gp.x;
                    app.ghostY = gp.y;
                    var lp = mainMouse.mapToItem(treeView, m.x, m.y);
                    var idx = treeView.indexAt(lp.x, lp.y);
                    if (idx >= 0 && idx < treeModel.count) {
                        var e = treeModel.get(idx);
                        app.dropTarget = (e.relPath === app.dragFrom) ? "" : e.relPath;
                        app.dropIsFolder = e.isFolder;
                    } else {
                        app.dropTarget = "";
                    }
                }
                onReleased: {
                    if (!app.dragging)
                        return;
                    app.justDragged = true;
                    var from = app.dragFrom;
                    var to = "";
                    if (app.dropTarget.length > 0 && app.dropTarget !== from)
                        to = app.dropIsFolder ? app.dropTarget : app.parentOf(app.dropTarget);
                    // limpa o ghost ANTES de mover (o move recria a lista e mata este delegate)
                    app.dragging = false;
                    app.dropTarget = "";
                    if (to.length > 0 && to !== from)
                        app.moveEntry(from, to);
                }
                onCanceled: { app.dragging = false; app.dropTarget = ""; }
                onClicked: function (m) {
                    if (app.justDragged) { app.justDragged = false; return; }
                    // clique no triângulo = colapsar/expandir
                    var triX = (model.depth || 0) * 12 + 3;
                    if (m.button === Qt.LeftButton && model.isFolder && model.hasChildren
                            && m.x >= triX - 2 && m.x <= triX + 18) {
                        app.toggleCollapse(model.relPath);
                        return;
                    }
                    app.selectedPath = model.relPath;
                    app.selectedIsFolder = model.isFolder;
                    if (m.button === Qt.RightButton) {
                        ctxMenu.popup(mainMouse, m.x, m.y);
                    } else if (model.isFolder) {
                        app.openCollection(model.relPath);
                    } else {
                        app.openRequest(model.relPath);
                    }
                }
            }

            // destaque do alvo de drop
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Kirigami.Theme.highlightColor
                border.width: 2
                visible: app.dropTarget === model.relPath
            }

            // triângulo de colapsar (só visual; o clique é tratado na MouseArea)
            Kirigami.Icon {
                visible: model.isFolder && model.hasChildren
                anchors.left: parent.left
                anchors.leftMargin: (model.depth || 0) * 12 + 3
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 12
                implicitHeight: 12
                source: model.collapsed ? "arrow-right" : "arrow-down"
                color: Kirigami.Theme.textColor
                opacity: 0.75
            }

            // ação rápida (⋯): aparece no hover / item selecionado
            ToolButton {
                id: itemMenuBtn
                anchors.right: parent.right
                anchors.rightMargin: Kirigami.Units.smallSpacing
                anchors.verticalCenter: parent.verticalCenter
                visible: treeItem.hovered || model.relPath === app.selectedPath
                icon.name: "overflow-menu"
                onClicked: {
                    app.selectedPath = model.relPath;
                    app.selectedIsFolder = model.isFolder;
                    ctxMenu.popup(itemMenuBtn);
                }
                ToolTip.text: Strings.t.moreActions; ToolTip.visible: hovered
            }
        }
    }
}
