import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Tabela de pares chave/valor com checkbox de ativação (params, headers, vars).
// O campo de valor aceita {{variavel}}: destaca, sugere e mostra o valor no hover.
ColumnLayout {
    id: table
    property var model
    property string keyPlaceholder: "chave"
    property bool secretColumn: false
    property var resolved: []
    property string collection: ""
    signal addRequested()
    signal edited()

    readonly property bool empty: model === undefined || model === null || model.count === 0

    spacing: Kirigami.Units.smallSpacing

    ListView {
        id: view
        visible: !table.empty
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        clip: true
        model: table.model
        delegate: RowLayout {
            width: view.width
            CheckBox {
                checked: model.enabled
                onToggled: { model.enabled = checked; table.edited(); }
            }
            TextField {
                Layout.fillWidth: true
                text: model.name
                placeholderText: table.keyPlaceholder
                onTextEdited: { model.name = text; table.edited(); }
            }
            // valor mascarado quando é segredo (TextField tem echoMode)
            TextField {
                visible: table.secretColumn && model.secret
                Layout.fillWidth: true
                text: model.value
                placeholderText: "segredo (no cofre)"
                echoMode: TextInput.Password
                onTextEdited: { model.value = text; table.edited(); }
            }
            // valor normal com destaque de {{variavel}}
            TextArea {
                id: valArea
                visible: !(table.secretColumn && model.secret)
                Layout.fillWidth: true
                text: model.value
                placeholderText: "valor"
                wrapMode: TextEdit.NoWrap
                selectByMouse: true
                implicitHeight: Kirigami.Units.gridUnit * 1.7
                topPadding: 3; bottomPadding: 3; leftPadding: 6; rightPadding: 6
                onTextEdited: { model.value = text; table.edited(); }
                Keys.onPressed: function (e) { if (valCompleter.handleKey(e)) e.accepted = true; }
                Component.onCompleted: varSupport.attach(valArea.textDocument, "#c678dd", true, false)
                VarCompleter {
                    id: valCompleter
                    anchors.fill: parent
                    target: valArea
                    resolved: table.resolved
                    collection: table.collection
                }
            }
            CheckBox {
                visible: table.secretColumn
                text: "segredo"
                checked: model.secret === true
                onToggled: { model.secret = checked; table.edited(); }
            }
            ToolButton {
                icon.name: "list-remove"
                onClicked: { table.model.remove(index); table.edited(); }
                ToolTip.text: "Remover linha"
                ToolTip.visible: hovered
            }
        }
    }

    Item {
        visible: table.empty
        Layout.fillWidth: true
        Layout.fillHeight: true
        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.alignment: Qt.AlignHCenter; text: "Nada aqui ainda."; opacity: 0.5 }
            ToolButton {
                Layout.alignment: Qt.AlignHCenter
                icon.name: "list-add"
                text: "Adicionar"
                display: AbstractButton.TextBesideIcon
                highlighted: true
                onClicked: { table.addRequested(); table.edited(); }
            }
        }
    }

    ToolButton {
        visible: !table.empty
        icon.name: "list-add"
        text: "Adicionar"
        display: AbstractButton.TextBesideIcon
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        onClicked: { table.addRequested(); table.edited(); }
    }
}
