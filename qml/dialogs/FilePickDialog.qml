import QtQuick
import QtQuick.Dialogs
import "../Strings.js" as Strings

// Seleção de arquivo para um field multipart; grava o caminho no modelo injetado.
FileDialog {
    id: fileDialog
    property var fieldsModel
    property int targetIndex: -1
    title: Strings.t.chooseFileTitle
    onAccepted: {
        if (targetIndex >= 0 && targetIndex < fieldsModel.count)
            fieldsModel.setProperty(targetIndex, "fileName", selectedFile.toString().replace("file://", ""));
    }
}
