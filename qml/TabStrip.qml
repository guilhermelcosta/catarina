import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "Strings.js" as Strings

// Tab bar (flickable) with pin/close/drag. `app` = window; `tabsModel` injected;
// the row is exposed so the window can compute the drag insertion point.
Rectangle {
    id: tabStripRoot
    property var app
    property var tabsModel
    readonly property alias row: tabRow
    readonly property alias flickable: tabStrip
    // Bounded tab width (docs/DESIGN.md §5) and the control gutter: left margin
    // plus room for the pin/close controls, kept at today's effective value.
    readonly property int tabMinWidth: 90
    readonly property int tabMaxWidth: 200
    readonly property int tabGutter: 74
    Layout.fillWidth: true
    implicitHeight: Kirigami.Units.gridUnit * 2
    color: Kirigami.Theme.alternateBackgroundColor
    visible: tabsModel.count > 0

    // Scroll the tab at delegate index `i` into view (mouse click, shortcut or
    // newly opened tab all funnel through app.currentTab).
    function ensureVisible(i) {
        if (i < 0) return;
        var n = 0;
        for (var c = 0; c < tabRow.children.length; c++) {
            var it = tabRow.children[c];
            if (!it.isTabDelegate) continue;
            if (n === i) {
                if (it.x < tabStrip.contentX) tabStrip.contentX = it.x;
                else if (it.x + it.width > tabStrip.contentX + tabStrip.width)
                    tabStrip.contentX = it.x + it.width - tabStrip.width;
                return;
            }
            ++n;
        }
    }

    // Shared tooltip, owned by the strip and placed below the clickable band so
    // it can never swallow a tab/pin/close click (docs/DESIGN.md §1).
    function showTabTip(it) {
        if (!it || !it.labelTruncated) { tabTip.close(); return; }
        tabTip.text = it.tabName;
        var tw = tabTip.implicitWidth;
        var visX = it.x - tabStrip.contentX;
        tabTip.x = Math.max(0, Math.min(tabStripRoot.width - tw, visX + (it.width - tw) / 2));
        tabTip.y = it.height + 2;
        tabTip.open();
    }

    function hideTabTip() { tabTip.close(); }

    // right-click context menu: anchored under the tab
    function openTabContext(i, item) {
        if (i < 0 || i >= tabsModel.count) return;
        tabCtxMenu.tabIndex = i;
        var p = item.mapToItem(tabStripRoot, item.width / 2, item.height);
        tabCtxMenu.x = Math.max(0, Math.min(tabStripRoot.width - tabCtxMenu.implicitWidth, p.x));
        tabCtxMenu.y = p.y;
        tabCtxMenu.open();
    }
    function isUtilityTab(i) {
        if (i < 0 || i >= tabsModel.count) return false;
        var t = tabsModel.get(i);
        return t.isCollection === true || t.isEnvironment === true || t.isSettings === true;
    }

    ToolTip {
        id: tabTip
        objectName: "tabTip"
        timeout: 0
        delay: 0
    }

    Connections {
        target: app
        function onCurrentTabChanged() {
            if (app && !app.dragging) scrollTimer.restart();
        }
    }

    // one frame later: a tab appended by the change is laid out by then, and
    // Qt.callLater is not enough (it runs before the Repeater's delegate exists)
    Timer {
        id: scrollTimer
        interval: 16
        onTriggered: tabStripRoot.ensureVisible(app ? app.currentTab : -1)
    }

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
                    width: Math.max(tabMinWidth, Math.min(tabMaxWidth, tabContent.implicitWidth + tabGutter))
                    property bool isTabDelegate: true
                    property bool labelTruncated: tabLabel.truncated
                    property string tabName: model.name
                    activeFocusOnTab: true
                    opacity: (app.dragging && app.tabDragIndex === index) ? 0.4 : 1
                    HoverHandler {
                        id: tabHover
                        onHoveredChanged: {
                            if (hovered) {
                                tipTimer.start();
                            } else {
                                tipTimer.stop();
                                tabStripRoot.hideTabTip();
                            }
                        }
                    }
                    Timer {
                        id: tipTimer
                        interval: 700
                        onTriggered: tabStripRoot.showTabTip(tabItem)
                    }
                    Rectangle {
                        id: tabSurface
                        objectName: "tabSurface"
                        anchors.fill: parent
                        radius: app.theme.radiusControl
                        color: index === app.currentTab ? Kirigami.Theme.backgroundColor
                             : "transparent"
                        Rectangle {
                            id: tabUnderline
                            objectName: "tabUnderline"
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 2
                            visible: index === app.currentTab
                            color: Kirigami.Theme.highlightColor
                        }
                    }
                    // hover tint fades; the active surface is a swap, not a tint,
                    // and never brightens when hovered (docs/DESIGN.md §2)
                    Rectangle {
                        objectName: "tabHoverTint"
                        anchors.fill: parent
                        radius: tabSurface.radius
                        color: (tabHover.hovered && index !== app.currentTab)
                               ? app.theme.hoverTint : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: app.theme.hoverDurationMs; easing.type: Easing.InOutQuad }
                        }
                    }
                    // keyboard focus ring: the tab strips the platform chrome
                    Rectangle {
                        objectName: "tabFocusRing"
                        anchors.fill: parent
                        radius: tabSurface.radius
                        color: "transparent"
                        border.width: app.theme.focusRingWidth
                        border.color: Kirigami.Theme.highlightColor
                        visible: tabItem.activeFocus
                    }
                    // insertion point (to the left of this tab)
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 2; color: Kirigami.Theme.highlightColor
                        visible: app.dragging && app.tabDragIndex >= 0 && app.tabDropIndex === index
                    }
                    // insertion point at the end (after the last tab)
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
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        // clears the pin (unpinned) and close hit areas
                        anchors.rightMargin: 56
                        spacing: 6
                        MethodBadge {
                            visible: !model.isCollection && !model.isEnvironment && !model.isSettings
                            method: model.method
                            color: app.methodColor(model.method)
                            pixelSize: app.theme.fontSizeMeta
                            badgeHeight: 16
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Kirigami.Icon {
                            objectName: "tabStripTypeIcon"
                            visible: model.isCollection || model.isEnvironment || model.isSettings
                            readonly property var identity: model.isCollection
                                ? app.identityFor(model.relPath) : ({ icon: "", color: "" })
                            source: model.isSettings ? "configure"
                                  : (model.isEnvironment ? "vcs-branch"
                                  : (identity.icon.length > 0
                                     ? app.collectionIcon(identity.icon)
                                     : (model.relPath.indexOf("/") < 0 ? "folder-documents" : "folder")))
                            implicitWidth: 14; implicitHeight: 14
                            color: model.isEnvironment
                                   ? (app.activeEnvColor().length > 0 ? app.activeEnvColor()
                                                                     : Kirigami.Theme.textColor)
                                   : (identity.color.length > 0 ? identity.color : Kirigami.Theme.textColor)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            id: tabLabel
                            objectName: "tabLabel"
                            text: model.name
                            font.bold: index === app.currentTab
                            font.italic: model.preview === true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
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
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
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
                            else if (mouse.button === Qt.RightButton) tabStripRoot.openTabContext(index, tabItem);
                            else app.switchTab(index);
                        }
                    }
                    Item {
                        id: pinBtn
                        objectName: "tabPin"
                        anchors.right: parent.right
                        anchors.rightMargin: model.pinned === true ? 6 : 30
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        visible: !model.isCollection && !model.isEnvironment && !model.isSettings
                                 && (tabHover.hovered || model.pinned === true)
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            implicitWidth: 20
                            implicitHeight: 20
                            source: "pin"
                            // blue on hover (like the × turns red); pinned already appears blue
                            color: (pinHover.hovered || model.pinned === true) ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                        }
                        HoverHandler { id: pinHover }
                        TapHandler { onTapped: app.pinTab(index) }
                        // ponytail: do NOT use ToolTip.visible:hovered here — the tooltip
                        // popup steals the click (pin and × stop responding)
                    }
                    // 24x24 hit area; the × glyph is the visible part
                    Item {
                        id: closeBtn
                        objectName: "tabClose"
                        visible: !model.isCollection && !model.isEnvironment && !model.isSettings
                                 && model.pinned !== true
                                 && (tabHover.hovered || index === app.currentTab)
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        HoverHandler { id: closeHover }
                        TapHandler { onTapped: app.closeTab(index) }
                        Label {
                            anchors.centerIn: parent
                            text: "×"
                            font.pixelSize: app.theme.fontSizeScreenTitle
                            color: closeHover.hovered ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        }
                        // same as pin: tooltip here steals the × click
                    }
                }
            }
        }
    }

    // Context menu (right-click on a tab). Hidden tab types (settings,
    // environment, collection) only get Close.
    Menu {
        id: tabCtxMenu
        objectName: "tabCtxMenu"
        property int tabIndex: -1
        readonly property bool utility: tabStripRoot.isUtilityTab(tabIndex)
        MenuItem {
            objectName: "tabCtxPin"
            visible: !tabCtxMenu.utility
            text: (tabCtxMenu.tabIndex >= 0 && tabCtxMenu.tabIndex < tabsModel.count
                   && tabsModel.get(tabCtxMenu.tabIndex).pinned === true)
                  ? Strings.t.unpinTab : Strings.t.pinTab
            onTriggered: app.pinTab(tabCtxMenu.tabIndex)
        }
        MenuItem {
            objectName: "tabCtxClose"
            text: Strings.t.closeTab
            onTriggered: app.closeTab(tabCtxMenu.tabIndex)
        }
        MenuSeparator { visible: !tabCtxMenu.utility }
        MenuItem {
            objectName: "tabCtxCloseOthers"
            visible: !tabCtxMenu.utility
            text: Strings.t.closeOthers
            onTriggered: app.closeOtherTabs(tabCtxMenu.tabIndex)
        }
        MenuItem {
            objectName: "tabCtxCloseAll"
            visible: !tabCtxMenu.utility
            text: Strings.t.closeAll
            onTriggered: app.closeAllTabs()
        }
    }
}
