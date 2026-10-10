import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings
import "../Util.js" as Util

Dialog {
    id: curlExportDialog
    property var app

    title: Strings.t.exportTitle; anchors.centerIn: parent; modal: true; width: 640; height: 400
    header: DialogHeader { dialogTitle: curlExportDialog.title }
    function refresh() { curlExportArea.text = Util.exportCode(backend.resolvedRequestParts(app.collectRequest(), app.currentCollection)); }
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { text: "cURL"; Layout.bottomMargin: Kirigami.Units.smallSpacing }
            Item { Layout.fillWidth: true }
            Button {
                icon.name: "edit-copy"; text: Strings.t.copy
                display: AbstractButton.TextBesideIcon
                onClicked: { varSupport.copyText(curlExportArea.text); app.notify(Strings.t.codeCopied); }
            }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            TextArea { id: curlExportArea; readOnly: true; selectByMouse: true; font.family: "monospace"; wrapMode: TextEdit.NoWrap }
        }
        DialogActions {
            Button { text: Strings.t.close; onClicked: curlExportDialog.close() }
        }
    }
}
