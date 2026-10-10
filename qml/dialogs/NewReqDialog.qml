import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: newReqDialog
    property var app

    title: Strings.t.newRequestTitle; modal: true; anchors.centerIn: parent; width: 460
    header: DialogHeader { dialogTitle: newReqDialog.title }
    property string target: ""
    function openIn(folder) { target = folder; nrName.text = ""; nrUrl.text = ""; nrMethod.currentIndex = 0; open(); nrName.forceActiveFocus(); }
    function openPrefilled(folder, method, url) {
        target = folder;
        var base = url.split("?")[0].split("/").filter(function (s) { return s.length > 0; }).pop();
        nrName.text = base !== undefined && base.length > 0 ? base : "request";
        nrUrl.text = url;
        var i = nrMethod.find(method);
        nrMethod.currentIndex = i >= 0 ? i : 0;
        open();
        nrName.forceActiveFocus();
    }
    function errorText() {
        var n = nrName.text.trim();
        if (n.length === 0) return "";
        if (n.indexOf("/") >= 0) return Strings.t.nameCannotContainSlash;
        var newRel = (target.length > 0 ? target + "/" : "") + n;
        if (backend.isCollection(newRel) || backend.loadRequest(newRel).method !== undefined)
            return Strings.t.itemExists;
        return "";
    }
    function create() {
        if (errorText().length > 0) return;
        var n = nrName.text.trim();
        if (n.length === 0) { nrName.forceActiveFocus(); return; }
        var path = (target.length > 0 ? target + "/" : "") + n;
        var data = { method: nrMethod.currentText, url: nrUrl.text, params: [], headers: [], fields: [], body: "", bodyType: "none", auth: { type: "none" }, vars: [] };
        if (backend.saveRequest(path, data)) { app.reloadTree(); app.openRequest(path); close(); }
    }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.nameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        TextField { id: nrName; Layout.fillWidth: true; placeholderText: Strings.t.requestNamePlaceholder; KeyNavigation.down: nrUrl; onAccepted: newReqDialog.create() }
        Label { text: Strings.t.urlLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            ComboBox { id: nrMethod; model: ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS"]; implicitWidth: 110 }
            TextField { id: nrUrl; Layout.fillWidth: true; placeholderText: Strings.t.urlPlaceholder; KeyNavigation.down: nrCancel }
        }
        Label {
            text: newReqDialog.errorText(); color: Kirigami.Theme.negativeTextColor
            visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Label { text: Strings.willBeCreatedIn(newReqDialog.target.length > 0 ? newReqDialog.target : Strings.rootFolder()); opacity: 0.6 }
        DialogActions {
            Button { id: nrCancel; text: Strings.t.cancel; KeyNavigation.right: nrCreate; KeyNavigation.up: nrUrl; onClicked: newReqDialog.close() }
            Button { id: nrCreate; text: Strings.t.create; Accessible.defaultButton: true; enabled: newReqDialog.errorText().length === 0; KeyNavigation.left: nrCancel; KeyNavigation.up: nrUrl; onClicked: newReqDialog.create() }
        }
    }
}
