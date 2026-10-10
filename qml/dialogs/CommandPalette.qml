import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Paleta de comandos (Ctrl+K).
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
    width: 480
    height: 380
    modal: true
    focus: true
    padding: Kirigami.Units.smallSpacing
    property var allActions: []
    property var filtered: []

    function openPalette() {
        allActions = [
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.newRequest, run: function () { newReqDialog.openIn(app.targetFolder()); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.newFolder, run: function () { app.openNewFolder(); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.newCollection, run: function () { app.openNewCollection(); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.importCurl, run: function () { curlImportDialog.openFresh(); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.history, run: function () { historyDialog.openAndLoad(); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.settingsEllipsis, run: function () { app.openSettingsTab(); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.manageEnvVariables, run: function () { app.openEnvTab(app.activeEnv); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.createEnvironment, run: function () { createEnvDialog.open(); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.closeTab, run: function () { app.closeTab(app.currentTab); } },
            { group: Strings.t.paletteGroupGlobal, label: Strings.t.reopenTab, run: function () { app.reopenClosed(); } },
            { group: Strings.t.paletteGroupContext, label: Strings.t.saveRequest, run: function () { app.saveCurrent(); } },
            { group: Strings.t.paletteGroupContext, label: Strings.t.sendRequest, run: function () { app.doSend(); } },
            { group: Strings.t.paletteGroupContext, label: Strings.t.exportCode, run: function () { curlExportDialog.refresh(); curlExportDialog.open(); } },
            { group: Strings.t.paletteGroupContext, label: Strings.t.moveSelected, run: function () { if (app.selectedPath.length > 0) moveDialog.openFor(app.selectedPath); } },
            { group: Strings.t.paletteGroupContext, label: Strings.t.renameSelected, run: function () { if (app.selectedPath.length > 0) renameDialog.openFor(app.selectedPath); } },
            { group: Strings.t.paletteGroupContext, label: Strings.t.duplicateSelected, run: function () { app.duplicateSelected(); } }
        ];
        paletteField.text = "";
        applyFilter("");
        open();
        paletteField.forceActiveFocus();
    }
    function applyFilter(q) {
        q = q.toLowerCase();
        var out = [];
        for (var i = 0; i < allActions.length; i++)
            if (q.length === 0 || allActions[i].label.toLowerCase().indexOf(q) >= 0)
                out.push(allActions[i]);
        filtered = out;
        paletteList.currentIndex = out.length > 0 ? 0 : -1;
    }
    function trigger() {
        if (paletteList.currentIndex >= 0 && paletteList.currentIndex < filtered.length) {
            var a = filtered[paletteList.currentIndex];
            cmdPalette.close();
            a.run();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.commandPalette; font.bold: true }
        TextField {
            id: paletteField
            Layout.fillWidth: true
            placeholderText: Strings.t.commandPlaceholder
            onTextChanged: cmdPalette.applyFilter(text)
            onAccepted: cmdPalette.trigger()
            Keys.onDownPressed: paletteList.currentIndex = Math.min(paletteList.currentIndex + 1, cmdPalette.filtered.length - 1)
            Keys.onUpPressed: paletteList.currentIndex = Math.max(paletteList.currentIndex - 1, 0)
        }
        ListView {
            id: paletteList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: cmdPalette.filtered
            section.property: "group"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                width: paletteList.width
                implicitHeight: 28
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: section
                    font.bold: true
                    font.pixelSize: 11
                    opacity: 0.55
                }
            }
            onCurrentIndexChanged: { if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain); }
            delegate: ItemDelegate {
                width: ListView.view.width
                text: modelData.label
                highlighted: index === paletteList.currentIndex
                onClicked: { paletteList.currentIndex = index; cmdPalette.trigger(); }
            }
        }
    }
}
