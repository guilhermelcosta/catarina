import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "Strings.js" as Strings

// Collections sidebar (tree + actions). `app` = window; treeModel/menus injected;
// the list is exposed so the move popup can anchor to the row.
Item {
    id: sidebar
    property var app
    property var treeModel
    property var addMenu
    property var ctxMenu
    property var overflowMenu
    readonly property alias view: treeView
    property real expandedWidth: 250
    // current width of the split item. It is applied imperatively (not via a
    // binding) because dragging the handle makes SplitView overwrite
    // preferredWidth, which would destroy a binding and break the animation.
    property real splitWidth: 250
    SplitView.preferredWidth: splitWidth
    onSplitWidthChanged: SplitView.preferredWidth = splitWidth
    visible: app.sidebarVisible || splitWidth > 0.5
    // min follows the animation so collapse/expand slides instead of clamping
    SplitView.minimumWidth: app.sidebarVisible ? Math.min(190, splitWidth) : 0
    SplitView.maximumWidth: 500
    NumberAnimation { id: splitAnim; target: sidebar; property: "splitWidth"; duration: 160; easing.type: Easing.InOutQuad }
    Connections {
        target: app
        function onSidebarVisibleChanged() {
            splitAnim.stop();
            if (app.sidebarVisible) {
                splitAnim.from = sidebar.splitWidth;
                splitAnim.to = sidebar.expandedWidth;
            } else {
                sidebar.expandedWidth = sidebar.width;   // remember the dragged size
                sidebar.splitWidth = sidebar.width;      // sync before collapsing
                splitAnim.from = sidebar.width;
                splitAnim.to = 0;
            }
            splitAnim.start();
        }
    }
    // ---- keyboard navigation ----
    function rowIndexAt(relPath) {
        for (var i = 0; i < treeModel.count; i++)
            if (treeModel.get(i).relPath === relPath) return i;
        return -1;
    }
    function entryAt(i) {
        return (i >= 0 && i < treeModel.count) ? treeModel.get(i) : null;
    }
    // first visible row from `from` in `step` direction (from may be -1)
    function nextVisible(from, step) {
        for (var i = from; i >= 0 && i < treeModel.count; i += step)
            if (!treeModel.get(i).hidden) return i;
        return -1;
    }
    function selectRow(i) {
        var e = entryAt(i);
        if (e === null) return;
        app.selectedPath = e.relPath;
        app.selectedIsFolder = e.isFolder;
        treeView.currentIndex = i;
        treeView.positionViewAtIndex(i, ListView.Contain);
    }
    function moveSelection(step) {
        var cur = rowIndexAt(app.selectedPath);
        // no selection yet: both directions start at the first visible row
        if (cur < 0) { selectRow(nextVisible(0, 1)); return; }
        var next = nextVisible(cur + step, step);
        if (next >= 0) selectRow(next);
    }
    function openSelected() {
        var e = entryAt(rowIndexAt(app.selectedPath));
        if (e === null) return;
        if (e.isFolder) app.openCollection(e.relPath);
        else app.openRequest(e.relPath);
    }
    function expandSelected() {
        var i = rowIndexAt(app.selectedPath);
        var e = entryAt(i);
        if (e === null) return;
        if (e.isFolder && e.hasChildren && e.collapsed) { app.toggleCollapse(e.relPath); return; }
        if (e.isFolder && e.hasChildren) {
            var child = nextVisible(i + 1, 1);
            if (child >= 0 && entryAt(child).depth > e.depth) selectRow(child);
            return;
        }
        openSelected();
    }
    function collapseSelected() {
        var i = rowIndexAt(app.selectedPath);
        var e = entryAt(i);
        if (e === null) return;
        if (e.isFolder && e.hasChildren && !e.collapsed) { app.toggleCollapse(e.relPath); return; }
        for (var p = i - 1; p >= 0; p--) {
            var parent = entryAt(p);
            if (!parent.hidden && parent.depth < e.depth) { selectRow(p); return; }
        }
    }
    // Ctrl+F route 1/3: focus the filter and select its text
    function focusFilter() {
        if (!app.sidebarVisible || width <= 0) return;
        if (!filterField.visible) return;
        filterField.forceActiveFocus();
        filterField.selectAll();
    }
    // a selected row that the filter hides leaves no highlighted row until the
    // filter clears; the selection itself stays in `app.selectedPath`
    function syncSelection() {
        var i = rowIndexAt(app.selectedPath);
        treeView.currentIndex = (i < 0 || entryAt(i).hidden) ? -1 : i;
    }
    readonly property bool filterNoMatch: {
        var rev = app.treeRevision;
        if (app.treeFilter.length === 0 || treeView.count === 0) return false;
        for (var i = 0; i < treeModel.count; i++)
            if (!treeModel.get(i).hidden) return false;
        return true;
    }

    // keep the view on the selection when another screen (a tab) changes it
    Connections {
        target: app
        function onSelectedPathChanged() {
            var i = rowIndexAt(app.selectedPath);
            if (i < 0) return;
            if (entryAt(i).hidden) { treeView.currentIndex = -1; return; }
            treeView.currentIndex = i;
            treeView.positionViewAtIndex(i, ListView.Contain);
        }
        function onTreeFilterChanged() { Qt.callLater(sidebar.syncSelection); }
    }
    // keep the content at full width and clip it: collapsing slides it out
    // instead of squeezing the labels/badges to zero
    clip: true
    ColumnLayout {
        width: splitAnim.running ? sidebar.expandedWidth : sidebar.width
        height: sidebar.height
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            Kirigami.Icon { source: "folder-documents"; implicitWidth: 16; implicitHeight: 16 }
            Label { text: Strings.t.collections; font.bold: true }
            Item { Layout.fillWidth: true }
            ToolButton { id: addButton; objectName: "sidebarAddButton"; icon.name: "list-add"; onClicked: addMenu.popup(addButton); ToolTip.text: Strings.t.add; ToolTip.delay: Kirigami.Units.toolTipDelay }
            ToolButton {
                id: sidebarOverflowButton
                objectName: "sidebarOverflowButton"
                icon.name: "overflow-menu"
                enabled: app.selectedPath.length > 0
                onClicked: overflowMenu.popup(sidebarOverflowButton)
                ToolTip.text: Strings.t.moreActions; ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
        Kirigami.Separator { Layout.fillWidth: true }
        TextField {
            id: filterField
            objectName: "sidebarFilterField"
            visible: treeView.count > 0
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            implicitHeight: Kirigami.Units.gridUnit * 1.7
            placeholderText: Strings.t.sidebarFilter
            onTextChanged: if (app.treeFilter !== text) app.treeFilter = text
            Keys.onEscapePressed: {
                text = "";
                app.treeFilter = "";
                treeView.forceActiveFocus();
            }
            ToolTip.text: Strings.t.sidebarFilterHint
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        Kirigami.Separator { Layout.fillWidth: true }
        Item {
            id: treeArea
            Layout.fillWidth: true
            Layout.fillHeight: true
        ListView {
            id: treeView
            objectName: "treeView"
            anchors.fill: parent
            clip: true
            model: treeModel
            visible: treeView.count > 0
            activeFocusOnTab: true
            Keys.onPressed: function (event) {
                switch (event.key) {
                case Qt.Key_Down: sidebar.moveSelection(1); event.accepted = true; break;
                case Qt.Key_Up: sidebar.moveSelection(-1); event.accepted = true; break;
                case Qt.Key_Right: sidebar.expandSelected(); event.accepted = true; break;
                case Qt.Key_Left: sidebar.collapseSelected(); event.accepted = true; break;
                case Qt.Key_Return:
                case Qt.Key_Enter: sidebar.openSelected(); event.accepted = true; break;
                case Qt.Key_Space:
                    var e = sidebar.entryAt(sidebar.rowIndexAt(app.selectedPath));
                    if (e !== null && e.isFolder && e.hasChildren) app.toggleCollapse(e.relPath);
                    event.accepted = true;
                    break;
                }
            }
            delegate: ItemDelegate {
                id: treeItem
                width: ListView.view.width
                // hidden descendants collapse to 0 height (animated) instead of
                // being removed from the model, so open/close slides smoothly
                height: model.hidden ? 0 : implicitHeight
                clip: true
                Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.InOutQuad } }
                highlighted: model.relPath === app.selectedPath
                property int itemDepth: model.depth || 0
                // selection/hover come from the theme tokens; one selection state
                // (`highlighted`), hover never brightens past it
                background: Rectangle {
                    color: treeItem.highlighted ? app.theme.selectionTint
                         : treeItem.hovered ? app.theme.hoverTint
                         : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: app.theme.hoverDurationMs; easing.type: Easing.InOutQuad }
                    }
                }

                // indent guides (VS Code style): one vertical line per ancestor level,
                // aligned to the center of that level's triangle (indent = 12px)
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
                    Label {
                        objectName: "treeMethodLabel"
                        visible: !model.isFolder
                        text: (model.method || "").toUpperCase()
                        color: app.methodColor(model.method)
                        font.pixelSize: app.theme.fontSizeMeta
                        font.bold: true
                        Layout.preferredWidth: 46
                        elide: Text.ElideRight
                    }
                    Label { Layout.fillWidth: true; text: model.name; elide: Text.ElideRight }
                }

                // click (left/right) + manual drag (with ghost)
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
                            app.dragIsFolder = model.isFolder;
                            app.dropRoot = false;
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
                            app.dropRoot = false;
                        } else {
                            // outside the rows: only a request can drop to the root
                            app.dropTarget = "";
                            app.dropRoot = !app.dragIsFolder;
                        }
                    }
                    onReleased: {
                        if (!app.dragging)
                            return;
                        app.justDragged = true;
                        var from = app.dragFrom;
                        var to = app.dragDestination(from, app.dropTarget, app.dropIsFolder,
                                                     app.dropRoot && !app.dragIsFolder);
                        // clears the ghost BEFORE moving (the move recreates the list and kills this delegate)
                        app.dragging = false;
                        app.dropTarget = "";
                        app.dropRoot = false;
                        if (to !== from)
                            app.moveEntry(from, to);
                    }
                    onCanceled: { app.dragging = false; app.dropTarget = ""; app.dropRoot = false; }
                    onClicked: function (m) {
                        if (app.justDragged) { app.justDragged = false; return; }
                        treeView.currentIndex = index;
                        treeView.forceActiveFocus();
                        // click on the triangle = collapse/expand
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

                // drop target highlight
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.color: Kirigami.Theme.highlightColor
                    border.width: 2
                    visible: app.dropTarget === model.relPath
                }

                // selection uses ItemDelegate.highlighted only: one state, one highlight
                // collapse triangle (visual only; the click is handled in the MouseArea)
                Kirigami.Icon {
                    visible: model.isFolder && model.hasChildren
                    anchors.left: parent.left
                    anchors.leftMargin: (model.depth || 0) * 12 + 3
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 12
                    implicitHeight: 12
                    source: model.collapsed ? "arrow-right" : "arrow-down"
                    // blue on hover (same effect as the tab pin icon)
                    color: collapseHover.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                    opacity: collapseHover.hovered ? 1.0 : 0.75
                    HoverHandler { id: collapseHover }
                }

                // quick action (⋯): appears on hover / selected item
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

        Item {
            anchors.fill: parent
            visible: treeView.count === 0
            EmptyState {
                objectName: "sidebarEmptyState"
                anchors.centerIn: parent
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                message: app.storageError.length > 0 ? app.storageError : Strings.t.noCollectionsYet
                actionText: app.storageError.length > 0 ? "" : Strings.t.newCollection
                actionIcon: "folder-new"
                onActionTriggered: app.openNewCollection()
            }
        }
        Item {
            anchors.fill: parent
            visible: sidebar.filterNoMatch
            EmptyState {
                objectName: "sidebarFilterEmpty"
                anchors.centerIn: parent
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                title: Strings.t.noFilterMatches
                message: Strings.t.noFilterMatchesMessage
                shortcut: "Esc"
                shortcutLabel: Strings.t.clearsFilter
            }
        }
        }
    }
}
