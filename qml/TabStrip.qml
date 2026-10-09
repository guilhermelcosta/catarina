import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "Strings.js" as Strings

// Barra de abas (flickable) com pin/fechar/drag. `app` = janela; `tabsModel` injetado;
// a row é exposta p/ a janela calcular o ponto de inserção do drag.
Rectangle {
    id: tabStripRoot
    property var app
    property var tabsModel
    readonly property alias row: tabRow
    Layout.fillWidth: true
    implicitHeight: Kirigami.Units.gridUnit * 2
    color: Kirigami.Theme.alternateBackgroundColor
    visible: tabsModel.count > 0
    Flickable {
        id: tabStrip
        anchors.fill: parent
        contentWidth: tabRow.width
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        Row {
            id: tabRow
            height: tabStrip.height
            Repeater {
                model: tabsModel
                delegate: Item {
                    id: tabItem
                    height: tabRow.height
                    width: tabContent.implicitWidth + 74
                    property bool isTabDelegate: true
                    opacity: (app.dragging && app.tabDragIndex === index) ? 0.4 : 1
                    HoverHandler { id: tabHover }
                    Rectangle {
                        anchors.fill: parent
                        color: index === app.currentTab ? Kirigami.Theme.backgroundColor : "transparent"
                        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 2; visible: index === app.currentTab; color: Kirigami.Theme.highlightColor }
                    }
                    // ponto de inserção (à esquerda desta aba)
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 2; color: Kirigami.Theme.highlightColor
                        visible: app.dragging && app.tabDragIndex >= 0 && app.tabDropIndex === index
                    }
                    // ponto de inserção no fim (após a última aba)
                    Rectangle {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 2; color: Kirigami.Theme.highlightColor
                        visible: app.dragging && app.tabDragIndex >= 0
                                 && app.tabDropIndex === tabsModel.count && index === tabsModel.count - 1
                    }
                    RowLayout {
                        id: tabContent
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        spacing: 6
                        MethodBadge {
                            visible: !model.isCollection && !model.isEnvironment && !model.isSettings
                            method: model.method
                            color: app.methodColor(model.method)
                            pixelSize: 8
                            badgeHeight: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Kirigami.Icon {
                            visible: model.isCollection || model.isEnvironment || model.isSettings
                            source: model.isSettings ? "configure"
                                  : (model.isEnvironment ? "vcs-branch"
                                  : (model.relPath.indexOf("/") < 0 ? "folder-documents" : "folder"))
                            implicitWidth: 14; implicitHeight: 14
                            color: Kirigami.Theme.textColor
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label { text: model.name; font.bold: index === app.currentTab; font.italic: model.preview === true; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                        Kirigami.Icon {
                            visible: !!(model.dirty === true
                                     || (model.isCollection === true && index === app.currentTab && (app.collectionVarsDirty || app.collectionHeadersDirty || app.collectionAuthDirty))
                                     || (model.isEnvironment === true && index === app.currentTab && app.envTabDirty))
                            source: "media-record-symbolic"
                            color: Kirigami.Theme.highlightColor
                            implicitWidth: 8; implicitHeight: 8
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        preventStealing: true
                        property real pressX: 0
                        property real pressY: 0
                        onPressed: function (m) { app.justDragged = false; pressX = m.x; pressY = m.y; }
                        onPositionChanged: function (m) {
                            if (!pressed || !(m.buttons & Qt.LeftButton)) return;
                            if (!app.dragging) {
                                if (Math.abs(m.x - pressX) + Math.abs(m.y - pressY) < 8) return;
                                app.dragging = true;
                                app.tabDragIndex = index;
                                app.dragFrom = model.relPath;
                                app.dragLabel = model.name;
                                app.dragMethod = model.method;
                                app.dragIsCollection = model.isCollection === true;
                            }
                            var gp = tabMouse.mapToItem(mainPage, m.x, m.y);
                            app.ghostX = gp.x;
                            app.ghostY = gp.y;
                            var lp = tabMouse.mapToItem(tabRow, m.x, m.y);
                            app.tabDropIndex = app.tabIndexAt(lp.x);
                        }
                        onReleased: {
                            if (!app.dragging) return;
                            app.justDragged = true;
                            var from = app.tabDragIndex;
                            var to = app.tabDropIndex;
                            app.dragging = false;
                            app.tabDragIndex = -1;
                            app.tabDropIndex = -1;
                            if (from >= 0 && to >= 0 && from !== to)
                                app.moveTab(from, to);
                        }
                        onCanceled: { app.dragging = false; app.tabDragIndex = -1; app.tabDropIndex = -1; }
                        onClicked: function (mouse) {
                            if (app.justDragged) { app.justDragged = false; return; }
                            if (mouse.button === Qt.MiddleButton) app.closeTab(index);
                            else app.switchTab(index);
                        }
                    }
                    Kirigami.Icon {
                        id: pinBtn
                        anchors.right: parent.right
                        anchors.rightMargin: model.pinned === true ? 6 : 26
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 20
                        implicitHeight: 20
                        source: "pin"
                        // hover azul (como o × fica vermelho); fixada já aparece azul
                        color: (pinHover.hovered || model.pinned === true) ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                        opacity: (pinHover.hovered || model.pinned === true) ? 1.0 : 0.6
                        visible: !model.isCollection && !model.isEnvironment && !model.isSettings
                                 && (tabHover.hovered || model.pinned === true)
                        HoverHandler { id: pinHover }
                        TapHandler { onTapped: app.pinTab(index) }
                        // ponytail: NÃO usar ToolTip.visible:hovered aqui — o popup
                        // do tooltip rouba o clique (pino e × deixam de responder)
                    }
                    Label {
                        id: closeBtn
                        visible: model.pinned !== true
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        padding: 3
                        text: "×"
                        font.pixelSize: 16
                        color: closeHover.hovered ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        opacity: closeHover.hovered ? 1.0 : 0.6
                        HoverHandler { id: closeHover }
                        TapHandler { onTapped: app.closeTab(index) }
                        // idem pino: tooltip aqui rouba o clique do ×
                    }
                }
            }
        }
    }
}
