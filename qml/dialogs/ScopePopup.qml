import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Variable scope (global or specific collections) — anchored popover.
Popup {
    id: scopePopup
    property var app
    property var envVarsModel
    property var envScreen

    parent: Overlay.overlay
    modal: false
    padding: Kirigami.Units.smallSpacing
    width: 300
    property int rowIndex: -1
    property bool global: true
    ListModel { id: scopeCollectionsModel }
    function openFor(index, gx, gy) {
        rowIndex = index;
        var row = envVarsModel.get(index);
        global = row === undefined || row.scope !== "collections";
        var sel = (row && row.collections.length > 0) ? row.collections.split(",") : [];
        scopeCollectionsModel.clear();
        var names = app.collectionNames();
        for (var i = 0; i < names.length; i++)
            scopeCollectionsModel.append({ name: names[i], on: sel.indexOf(names[i]) >= 0 });
        x = Math.max(0, Math.min(gx, (parent ? parent.width : 800) - width));
        y = gy;
        open();
    }
    // applies live (no OK/Cancel)
    function applyScope() {
        if (rowIndex < 0) return;
        if (global) {
            envVarsModel.setProperty(rowIndex, "scope", "all");
            envVarsModel.setProperty(rowIndex, "collections", "");
        } else {
            var sel = [];
            for (var i = 0; i < scopeCollectionsModel.count; i++)
                if (scopeCollectionsModel.get(i).on) sel.push(scopeCollectionsModel.get(i).name);
            envVarsModel.setProperty(rowIndex, "scope", "collections");
            envVarsModel.setProperty(rowIndex, "collections", sel.join(","));
        }
        envScreen.recomputeDirty();
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.scopeOfVariable; font.bold: true; Layout.fillWidth: true }
        TabBar {
            id: scopeMode
            Layout.fillWidth: true
            currentIndex: scopePopup.global ? 0 : 1
            TabButton { text: Strings.t.globalTab; onClicked: { scopePopup.global = true; scopePopup.applyScope(); } }
            TabButton { text: Strings.t.collectionsTab; onClicked: { scopePopup.global = false; scopePopup.applyScope(); } }
        }
        Rectangle {
            visible: !scopePopup.global
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(240, Math.max(60, scopeCollectionsModel.count * 34 + 8))
            border.width: 1
            border.color: Kirigami.Theme.disabledTextColor
            radius: 4
            color: "transparent"
            ListView {
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: scopeCollectionsModel
                delegate: CheckDelegate {
                    width: ListView.view.width
                    text: model.name
                    checked: model.on
                    onToggled: { model.on = checked; scopePopup.applyScope(); }
                }
            }
            Label {
                anchors.centerIn: parent
                visible: scopeCollectionsModel.count === 0
                text: Strings.t.noCollectionsYet
                opacity: 0.6
            }
        }
    }
}
