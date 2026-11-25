import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings
import "../Util.js" as Util

// Command palette (Ctrl+K). Rows are { group, label, run } plus additive
// icon/shortcut/ranges; matching is the pure Util.fuzzyMatch.
Popup {
    id: cmdPalette
    property var app
    property var newReqDialog
    property var curlImportDialog
    property var historyDialog
    property var createEnvDialog
    property var moveDialog
    property var renameDialog
    property var curlExportDialog

    anchors.centerIn: parent
    width: 520
    height: 380
    modal: true
    focus: true
    padding: Kirigami.Units.smallSpacing
    property var allActions: []
    property var filtered: []
    // recent command ids, most recent first, bounded 5, in-session only
    property var paletteRecents: []

    background: Rectangle {
        radius: app.theme.radiusPanel
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: app.theme.chromeBorder
    }

    function buildActions() {
        allActions = [
            { id: "newRequest", icon: "document-new", shortcut: app.shortcutSeq("newRequest"), group: Strings.t.paletteGroupGlobal, label: Strings.t.newRequest, run: function () { newReqDialog.openIn(app.targetFolder()); } },
            { id: "newFolder", icon: "folder-new", shortcut: "", group: Strings.t.paletteGroupGlobal, label: Strings.t.newFolder, run: function () { app.openNewFolder(); } },
            { id: "newCollection", icon: "folder-documents", shortcut: "", group: Strings.t.paletteGroupGlobal, label: Strings.t.newCollection, run: function () { app.openNewCollection(); } },
            { id: "importCurl", icon: "document-import", shortcut: "", group: Strings.t.paletteGroupGlobal, label: Strings.t.importCurl, run: function () { curlImportDialog.openFresh(); } },
            { id: "history", icon: "view-history", shortcut: "", group: Strings.t.paletteGroupGlobal, label: Strings.t.history, run: function () { historyDialog.openAndLoad(); } },
            { id: "settings", icon: "configure", shortcut: "", group: Strings.t.paletteGroupGlobal, label: Strings.t.settingsEllipsis, run: function () { app.openSettingsTab(); } },
            { id: "envVars", icon: "vcs-branch", iconColor: app.activeEnvColor(), shortcut: "", group: Strings.t.paletteGroupGlobal, label: Strings.t.manageEnvVariables, run: function () { app.openEnvTab(app.activeEnv); } },
            { id: "createEnv", icon: "list-add", iconColor: app.activeEnvColor(), shortcut: "", group: Strings.t.paletteGroupGlobal, label: Strings.t.createEnvironment, run: function () { createEnvDialog.open(); } },
            { id: "closeTab", icon: "window-close", shortcut: app.shortcutSeq("closeTab"), group: Strings.t.paletteGroupGlobal, label: Strings.t.closeTab, run: function () { app.closeTab(app.currentTab); } },
            { id: "tabSearch", icon: "edit-find", shortcut: app.shortcutSeq("tabSearch"), group: Strings.t.paletteGroupContext, label: Strings.t.tabSearch, run: function () { app.requestEditor.openTabSearch(); } },
            { id: "reopenTab", icon: "view-refresh", shortcut: app.shortcutSeq("reopenTab"), group: Strings.t.paletteGroupGlobal, label: Strings.t.reopenTab, run: function () { app.reopenClosed(); } },
            { id: "saveRequest", icon: "document-save", shortcut: app.shortcutSeq("save"), group: Strings.t.paletteGroupContext, label: Strings.t.saveRequest, run: function () { app.saveCurrent(); } },
            { id: "sendRequest", icon: "document-send", shortcut: app.shortcutSeq("send"), group: Strings.t.paletteGroupContext, label: Strings.t.sendRequest, run: function () { app.doSend(); } },
            { id: "exportCode", icon: "document-export", shortcut: "", group: Strings.t.paletteGroupContext, label: Strings.t.exportCode, run: function () { curlExportDialog.refresh(); curlExportDialog.open(); } },
            { id: "moveSelected", icon: "edit-move", shortcut: "", group: Strings.t.paletteGroupContext, label: Strings.t.moveSelected, run: function () { if (app.selectedPath.length > 0) moveDialog.openFor(app.selectedPath); } },
            { id: "renameSelected", icon: "edit-rename", shortcut: "", group: Strings.t.paletteGroupContext, label: Strings.t.renameSelected, run: function () { if (app.selectedPath.length > 0) renameDialog.openFor(app.selectedPath); } },
            { id: "duplicateSelected", icon: "edit-duplicate", shortcut: "", group: Strings.t.paletteGroupContext, label: Strings.t.duplicateSelected, run: function () { app.duplicateSelected(); } }
        ];
    }

    function openPalette() {
        buildActions();
        paletteField.text = "";
        applyFilter("");
        open();
        paletteField.forceActiveFocus();
    }

    function actionById(id) {
        for (var i = 0; i < allActions.length; i++)
            if (allActions[i].id === id) return allActions[i];
        return null;
    }
    // recents first (no query), then the categories in their original order
    function recentRows() {
        var out = [];
        for (var i = 0; i < paletteRecents.length; i++) {
            var a = actionById(paletteRecents[i]);
            if (a === null) continue;
            out.push({ id: a.id, icon: a.icon, iconColor: a.iconColor || "",
                       shortcut: a.shortcut,
                       group: Strings.t.paletteGroupRecent, label: a.label,
                       run: a.run, ranges: null, score: 0 });
        }
        return out;
    }
    function applyFilter(q) {
        var out = [];
        if (q.length === 0) {
            out = recentRows();
            for (var i = 0; i < allActions.length; i++) {
                var a = allActions[i];
                out.push({ id: a.id, icon: a.icon, iconColor: a.iconColor || "",
                           shortcut: a.shortcut,
                           group: a.group, label: a.label, run: a.run,
                           ranges: null, score: 0 });
            }
        } else {
            var scored = [];
            for (var j = 0; j < allActions.length; j++) {
                var act = allActions[j];
                var m = Util.fuzzyMatch(q, act.label);
                if (m === null) continue;
                scored.push({ id: act.id, icon: act.icon, iconColor: act.iconColor || "",
                              shortcut: act.shortcut,
                              group: act.group, label: act.label, run: act.run,
                              ranges: m.ranges, score: m.score, order: j });
            }
            // better score first; ties keep the action's original order
            scored.sort(function (a, b) {
                return b.score !== a.score ? b.score - a.score : a.order - b.order;
            });
            out = scored;
        }
        filtered = out;
        paletteList.currentIndex = out.length > 0 ? 0 : -1;
    }
    function remember(row) {
        if (!row || !row.id) return;
        var ids = [row.id];
        for (var i = 0; i < paletteRecents.length && ids.length < 5; i++)
            if (paletteRecents[i] !== row.id) ids.push(paletteRecents[i]);
        paletteRecents = ids;
    }
    function trigger() {
        if (paletteList.currentIndex >= 0 && paletteList.currentIndex < filtered.length) {
            var a = filtered[paletteList.currentIndex];
            remember(a);
            cmdPalette.close();
            a.run();
        }
    }
    // rich-text row: HTML-escaped label with the matched runs in the live accent
    function highlightText(label, ranges) {
        if (!ranges || ranges.length === 0)
            return Util.escapeHtml(label);
        var out = "", pos = 0;
        for (var i = 0; i < ranges.length; i++) {
            var start = ranges[i][0], len = ranges[i][1];
            out += Util.escapeHtml(label.substring(pos, start));
            out += "<b><span style=\"color:" + Kirigami.Theme.highlightColor + "\">"
                   + Util.escapeHtml(label.substr(start, len)) + "</span></b>";
            pos = start + len;
        }
        out += Util.escapeHtml(label.substring(pos));
        return out;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing
        TextField {
            id: paletteField
            objectName: "paletteField"
            Layout.fillWidth: true
            placeholderText: Strings.t.commandPlaceholder
            onTextChanged: cmdPalette.applyFilter(text)
            onAccepted: cmdPalette.trigger()
            Keys.onDownPressed: paletteList.currentIndex = Math.min(paletteList.currentIndex + 1, cmdPalette.filtered.length - 1)
            Keys.onUpPressed: paletteList.currentIndex = Math.max(paletteList.currentIndex - 1, 0)
        }
        ListView {
            id: paletteList
            objectName: "paletteList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: cmdPalette.filtered
            section.property: "group"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                width: paletteList.width
                implicitHeight: 24
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: section
                    font.bold: true
                    font.pixelSize: app.theme.fontSizeMeta
                    opacity: app.theme.textInformational
                }
            }
            onCurrentIndexChanged: { if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain); }
            delegate: ItemDelegate {
                id: paletteRow
                width: ListView.view.width
                highlighted: index === paletteList.currentIndex
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        objectName: "paletteRowIcon"
                        visible: modelData.icon !== undefined && modelData.icon.length > 0
                        source: modelData.icon !== undefined ? modelData.icon : ""
                        implicitWidth: app.theme.iconSize
                        implicitHeight: app.theme.iconSize
                        color: (modelData.iconColor !== undefined
                                && modelData.iconColor.length > 0)
                               ? modelData.iconColor : Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Label {
                        objectName: "paletteRowLabel"
                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        text: cmdPalette.highlightText(modelData.label, modelData.ranges)
                        color: Kirigami.Theme.textColor
                        font.pixelSize: app.theme.fontSizeBase
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    Label {
                        objectName: "paletteRowShortcut"
                        visible: modelData.shortcut !== undefined && modelData.shortcut.length > 0
                        text: modelData.shortcut !== undefined ? modelData.shortcut : ""
                        font.pixelSize: app.theme.fontSizeMeta
                        font.features: ({ "tnum": 1 })
                        color: Kirigami.Theme.textColor
                        opacity: app.theme.textInformational
                    }
                }
                background: Rectangle {
                    color: paletteRow.highlighted ? app.theme.selectionTint
                         : paletteRow.hovered ? app.theme.hoverTint
                         : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: app.theme.hoverDurationMs; easing.type: Easing.InOutQuad }
                    }
                }
                onClicked: { paletteList.currentIndex = index; cmdPalette.trigger(); }
            }
            Label {
                anchors.centerIn: parent
                z: 1
                visible: paletteList.count === 0
                text: Strings.t.noCommandMatches
                opacity: app.theme.textInformational
            }
        }
    }
}
