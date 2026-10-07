import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Campo de texto de uma linha com suporte a {{variavel}} embutido: destaca,
// sugere (autocomplete) e mostra o valor no hover. Centraliza o que antes era
// repetido em cada campo (varSupport.attach + VarCompleter + Keys.onPressed).
// É um TextArea (não TextField) porque o highlight precisa de QQuickTextDocument,
// que só TextArea/TextEdit expõem.
TextArea {
    id: root
    property var resolved: []          // [{name, value, secret, source, enabled}]
    property string collection: ""     // para explicar variáveis fora de escopo

    wrapMode: TextEdit.NoWrap
    selectByMouse: true
    implicitHeight: Kirigami.Units.gridUnit * 1.7
    topPadding: 3; bottomPadding: 3; leftPadding: 6; rightPadding: 6

    Keys.onPressed: function (e) { if (completer.handleKey(e)) e.accepted = true; }
    Component.onCompleted: varSupport.attach(root.textDocument, "#c678dd", true, false)

    VarCompleter {
        id: completer
        objectName: "varCompleter"
        anchors.fill: parent
        target: root
        resolved: root.resolved
        collection: root.collection
    }
}
