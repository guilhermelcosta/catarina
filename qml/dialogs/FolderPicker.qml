import QtQuick
import QtQuick.Dialogs
import "../Strings.js" as Strings

// Settings FolderDialog: applies the chosen folder to the screen's field (injected).
FolderDialog {
    id: folderPicker
    property var dirField

    title: Strings.t.chooseCollectionsFolder
    onAccepted: dirField.text = selectedFolder.toString().replace("file://", "")
}
