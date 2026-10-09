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
    property string errorText: ""      // mensagem mostrada no popup de hover (ex.: nome repetido)
    property var tabHandler: null      // function(dir): navegação Tab entre células (KvTable); null = nativo

    wrapMode: TextEdit.NoWrap
    selectByMouse: true
    activeFocusOnTab: true
    implicitHeight: Kirigami.Units.gridUnit * 1.7
    topPadding: 3; bottomPadding: 3; leftPadding: 6; rightPadding: 6
    // nome repetido: texto em vermelho e negrito (como o destaque de {{variavel}})
    color: root.errorText.length > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    font.bold: root.errorText.length > 0

    function updateErrorPopup() {
        if (root.hovered && root.errorText.length > 0) errPop.open();
        else errPop.close();
    }
    onHoveredChanged: updateErrorPopup()

    // popup escuro com o motivo (mesmo estilo do hover de {{variavel}})
    Popup {
        id: errPop
        parent: root
        padding: 6
        closePolicy: Popup.NoAutoClose
        x: 0
        y: root.height + 4
        width: errLabel.implicitWidth + 14
        height: errLabel.implicitHeight + 14
        Label { id: errLabel; font.family: "monospace"; text: root.errorText }
    }

    Keys.onPressed: function (e) {
        if (completer.handleKey(e)) { e.accepted = true; return; }
        // Tab/Shift+Tab: quando a tabela fornece um tabHandler, navega célula a célula;
        // fora da tabela deixa passar (navegação nativa de foco)
        if ((e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) && root.tabHandler) {
            root.tabHandler(e.key === Qt.Key_Backtab ? -1 : 1);
            e.accepted = true;
        }
    }
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
