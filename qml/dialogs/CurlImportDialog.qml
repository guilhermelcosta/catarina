import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

Dialog {
    id: curlImportDialog
    property var app

    title: Strings.t.importCurlTitle; anchors.centerIn: parent; modal: true; width: 560; height: 320
    header: DialogHeader { dialogTitle: curlImportDialog.title }
    property string hint: ""
    // called from outside: clears the content before opening (the internal TextArea isn't accessible outside)
    function openFresh() { hint = ""; curlImportArea.text = ""; open(); }
    onOpened: curlImportArea.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.importCurlLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            TextArea { id: curlImportArea; font.family: "monospace"; wrapMode: TextEdit.Wrap; placeholderText: Strings.t.importCurlPlaceholder }
        }
        Label { text: curlImportDialog.hint; color: Kirigami.Theme.negativeTextColor; visible: text.length > 0 }
        DialogActions {
            Button { id: curlCancel; text: Strings.t.cancel; KeyNavigation.right: curlImportBtn; KeyNavigation.up: curlImportArea; onClicked: curlImportDialog.close() }
            Button { id: curlImportBtn; text: Strings.t.import; Accessible.defaultButton: true; KeyNavigation.left: curlCancel; KeyNavigation.up: curlImportArea; onClicked: app.importCurl(curlImportArea.text) }
        }
    }
}
