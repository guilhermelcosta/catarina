import QtQuick
import QtQuick.Dialogs
import "../Strings.js" as Strings

// FolderDialog das configurações: aplica a pasta escolhida no campo da tela (injetado).
FolderDialog {
    id: folderPicker
    property var dirField

    title: Strings.t.chooseCollectionsFolder
    onAccepted: dirField.text = selectedFolder.toString().replace("file://", "")
}
