import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Tabela unificada de pares chave/valor do app (params, headers, campos, vars de
// request/coleção/ambiente). O campo de valor aceita {{variavel}} (destaca, sugere e
// mostra no hover). Colunas opcionais: Tipo (arquivos), Escopo e Segredo.
//
// Layout responsivo: as colunas "Nome", "Valor" e "Escopo" são flexíveis
// (fillWidth com preferred/minimum explícitos), então encolhem em janelas estreitas.
// Cabeçalho e linhas usam exatamente os mesmos preferred/minimum → ficam alinhados.
//
// Raiz é um Item (implicit 0) com ColumnLayout interna, para o tamanho implícito não
// depender da largura (evita loop de polish do layout).
Item {
    id: table
    property var model
    property string keyPlaceholder: Strings.t.key
    property bool secretColumn: false
    property bool allowFiles: false
    property bool scopeColumn: false
    property var resolved: []
    property string collection: ""
    property var scopeText: null     // function(index) -> texto do chip de escopo
    property var scopeIcon: null     // function(index) -> nome do ícone do chip de escopo
    property var scopeColor: null    // function(index) -> cor do chip (por escopo); null = neutro
    property var scopeTooltip: null  // function(index) -> tooltip (ex.: nomes completos)
    property bool uniqueNames: false // destaca nomes repetidos na tabela (variáveis)
    property var rowFilter: null     // function(index) -> bool (mostra/esconde a linha)
    signal addRequested()
    signal edited()
    signal pickFile(int index)
    signal scopeRequested(int index, real gx, real gy)

    // bump a cada edição: força a reavaliação do destaque de nome repetido
    property int revision: 0
    onEdited: revision++

    // nome da linha colide (aparado) com o de outra linha da mesma tabela
    function isDuplicateName(index) {
        var r = table.model.get(index);
        var n = r && r.name !== undefined ? String(r.name).trim() : "";
        if (n.length === 0) return false;
        for (var i = 0; i < table.model.count; i++) {
            if (i === index) continue;
            var m = table.model.get(i);
            var o = m && m.name !== undefined ? String(m.name).trim() : "";
            if (o === n) return true;
        }
        return false;
    }

    // remoção de linha com confirmação, seguindo a config global (settings.confirmDelete)
    function tryRemove(i) {
        if (settings.confirmDelete) { confirmRemove.pendingIndex = i; confirmRemove.open(); }
        else { table.model.remove(i); table.edited(); }
    }

    // células editáveis (na ordem das colunas) de uma linha já instanciada.
    // Cada célula expõe kvCell = true só na sua face ativa (a coluna "valor" tem
    // três faces mutuamente exclusivas), então não dependemos de `visible` — que no
    // harness de teste lê a visibilidade efetiva (TestCase é invisível).
    function focusableCells(row) {
        var it = kvList.itemAtIndex(row);
        if (!it || it.shown === false) return [];   // linha filtrada fora não recebe foco
        var out = [];
        for (var i = 0; i < it.children.length; i++) {
            var c = it.children[i];
            if (c && c.kvCell === true && c.enabled !== false) out.push(c);
        }
        return out;
    }
    // Tab/Shift+Tab (dir = +1/-1): próxima coluna; no fim da linha, linha seguinte
    function moveFocus(dir) {
        for (var r = 0; r < table.model.count; r++) {
            var cells = table.focusableCells(r);
            var idx = -1;
            for (var c = 0; c < cells.length; c++)
                if (cells[c].activeFocus) { idx = c; break; }
            if (idx < 0) continue;
            var n = idx + dir;
            if (n >= 0 && n < cells.length) { cells[n].forceActiveFocus(); return; }
            var r2 = r + dir;
            if (r2 < 0 || r2 >= table.model.count) return;
            var cells2 = table.focusableCells(r2);
            var c2 = dir > 0 ? 0 : cells2.length - 1;
            if (c2 >= 0 && cells2[c2]) cells2[c2].forceActiveFocus();
            return;
        }
    }

    readonly property bool empty: model === undefined || model === null || model.count === 0

    readonly property int colSpacing: Kirigami.Units.smallSpacing
    // colunas de largura fixa (pequenas)
    readonly property int enabledColWidth: 48
    readonly property int typeColWidth: 90
    readonly property int secretColWidth: 64
    readonly property int removeColWidth: 40
    // colunas flexíveis
    readonly property int keyColPreferred: 150
    readonly property int keyColMinimum: 80
    readonly property int valueColPreferred: 180
    readonly property int valueColMinimum: 80
    readonly property int scopeColPreferred: 170
    readonly property int scopeColMinimum: 90
    readonly property string keyHeader: keyPlaceholder.length > 0
        ? keyPlaceholder.charAt(0).toUpperCase() + keyPlaceholder.slice(1) : Strings.t.key

    ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: table.colSpacing

        // cabeçalho das colunas — mesmos preferred/minimum das linhas
        RowLayout {
            id: header
            objectName: "kvHeader"
            visible: !table.empty
            Layout.fillWidth: true
            Layout.leftMargin: table.colSpacing
            Layout.rightMargin: table.colSpacing
            Layout.topMargin: table.colSpacing
            spacing: table.colSpacing
            Label { text: Strings.t.active; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.preferredWidth: table.enabledColWidth; Layout.minimumWidth: table.enabledColWidth; Layout.maximumWidth: table.enabledColWidth }
            Label { text: table.keyHeader; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.fillWidth: true; Layout.preferredWidth: table.keyColPreferred; Layout.minimumWidth: table.keyColMinimum }
            Label { text: Strings.t.value; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum }
            Label { visible: table.allowFiles; text: Strings.t.type; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.preferredWidth: table.typeColWidth; Layout.minimumWidth: table.typeColWidth; Layout.maximumWidth: table.typeColWidth }
            Label { visible: table.scopeColumn; text: Strings.t.scope; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.fillWidth: true; Layout.preferredWidth: table.scopeColPreferred; Layout.minimumWidth: table.scopeColMinimum }
            Label { visible: table.secretColumn; text: Strings.t.secret; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.preferredWidth: table.secretColWidth; Layout.minimumWidth: table.secretColWidth; Layout.maximumWidth: table.secretColWidth }
            Item { Layout.preferredWidth: table.removeColWidth; Layout.minimumWidth: table.removeColWidth; Layout.maximumWidth: table.removeColWidth }
        }
        Kirigami.Separator {
            visible: !table.empty
            Layout.fillWidth: true
            Layout.leftMargin: table.colSpacing
            Layout.rightMargin: table.colSpacing
        }

        ListView {
            id: kvList
            objectName: "kvList"
            visible: !table.empty
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: table.colSpacing
            Layout.rightMargin: table.colSpacing
            clip: true
            model: table.model
            delegate: RowLayout {
                width: kvList.width
                spacing: table.colSpacing
                // Tab/Shift+Tab de controles que não consomem a tecla (checkbox, combo, botões)
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                        table.moveFocus(e.key === Qt.Key_Backtab ? -1 : 1);
                        e.accepted = true;
                    }
                }
                readonly property bool shown: table.rowFilter === null || table.rowFilter(index)
                visible: shown
                height: shown ? implicitHeight : 0
                opacity: model.enabled === false ? 0.45 : 1   // linha desabilitada esmaecida
                CheckBox {
                    property bool kvCell: true
                    Layout.preferredWidth: table.enabledColWidth; Layout.minimumWidth: table.enabledColWidth; Layout.maximumWidth: table.enabledColWidth
                    checked: model.enabled
                    onToggled: { model.enabled = checked; table.edited(); }
                }
                VarField {
                    property bool kvCell: true
                    objectName: "kvKeyField"
                    Layout.fillWidth: true; Layout.preferredWidth: table.keyColPreferred; Layout.minimumWidth: table.keyColMinimum
                    text: model.name
                    placeholderText: table.keyPlaceholder
                    tabHandler: function (dir) { table.moveFocus(dir); }
                    resolved: table.resolved
                    collection: table.collection
                    errorText: (table.uniqueNames && table.revision >= 0 && table.isDuplicateName(index))
                               ? Strings.t.duplicateNameHint : ""
                    onTextEdited: { model.name = text; table.edited(); }
                }
                // arquivo (só no modo campos)
                Button {
                    property bool kvCell: table.allowFiles && model.type === "file"
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum
                    visible: table.allowFiles && model.type === "file"
                    text: model.fileName && model.fileName.length > 0
                          ? model.fileName.split("/").pop() : Strings.t.chooseFile
                    icon.name: "document-open"
                    onClicked: table.pickFile(index)
                }
                // valor mascarado quando é segredo (TextField tem echoMode)
                TextField {
                    property bool kvCell: !(table.allowFiles && model.type === "file") && table.secretColumn && model.secret
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum
                    visible: !(table.allowFiles && model.type === "file") && table.secretColumn && model.secret
                    text: model.value
                    placeholderText: Strings.t.secretInVault
                    echoMode: TextInput.Password
                    onTextEdited: { model.value = text; table.edited(); }
                    // Tab/Shift+Tab movem para a célula ao lado (mesma navegação do VarField)
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                            table.moveFocus(e.key === Qt.Key_Backtab ? -1 : 1);
                            e.accepted = true;
                        }
                    }
                }
                // valor normal com destaque de {{variavel}}
                VarField {
                    id: valArea
                    property bool kvCell: !(table.allowFiles && model.type === "file") && !(table.secretColumn && model.secret)
                    objectName: "kvValueField"
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum
                    visible: !(table.allowFiles && model.type === "file") && !(table.secretColumn && model.secret)
                    text: model.value
                    placeholderText: Strings.t.value
                    tabHandler: function (dir) { table.moveFocus(dir); }
                    resolved: table.resolved
                    collection: table.collection
                    onTextEdited: { model.value = text; table.edited(); }
                }
                ComboBox {
                    property bool kvCell: table.allowFiles
                    Layout.preferredWidth: table.typeColWidth; Layout.minimumWidth: table.typeColWidth; Layout.maximumWidth: table.typeColWidth
                    visible: table.allowFiles
                    model: ["text", "file"]
                    currentIndex: model.type === "file" ? 1 : 0
                    onActivated: {
                        kvList.model.setProperty(index, "type", currentText);
                        table.edited();
                    }
                }
                // escopo: chip compacto (Global / N coleções) que abre um popover
                Rectangle {
                    id: scopeChip
                    objectName: "scopeChip"
                    visible: table.scopeColumn
                    Layout.fillWidth: true; Layout.preferredWidth: table.scopeColPreferred; Layout.minimumWidth: table.scopeColMinimum
                    implicitHeight: scopeRow.implicitHeight + 8
                    radius: 4
                    readonly property color tint: table.scopeColor !== null ? table.scopeColor(index) : Kirigami.Theme.textColor
                    color: table.scopeColor !== null
                           ? Qt.rgba(tint.r, tint.g, tint.b, 0.15) : Kirigami.Theme.alternateBackgroundColor
                    border.width: 1
                    border.color: table.scopeColor !== null ? tint : Kirigami.Theme.disabledTextColor
                    RowLayout {
                        id: scopeRow
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 4
                        Kirigami.Icon {
                            visible: table.scopeIcon !== null
                            source: table.scopeIcon !== null ? table.scopeIcon(index) : ""
                            color: scopeChip.tint
                            implicitWidth: 14; implicitHeight: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            text: table.scopeText !== null ? table.scopeText(index) : ""
                            color: scopeChip.tint
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var g = mapToItem(null, width / 2, height);
                            table.scopeRequested(index, g.x, g.y);
                        }
                        ToolTip.text: table.scopeTooltip !== null ? table.scopeTooltip(index) : ""
                        ToolTip.visible: containsMouse
                    }
                }
                CheckBox {
                    property bool kvCell: table.secretColumn
                    Layout.preferredWidth: table.secretColWidth; Layout.minimumWidth: table.secretColWidth; Layout.maximumWidth: table.secretColWidth
                    visible: table.secretColumn
                    checked: model.secret === true
                    onToggled: { model.secret = checked; table.edited(); }
                }
                ToolButton {
                    property bool kvCell: true
                    Layout.preferredWidth: table.removeColWidth; Layout.minimumWidth: table.removeColWidth; Layout.maximumWidth: table.removeColWidth
                    icon.name: "list-remove"
                    onClicked: table.tryRemove(index)
                    ToolTip.text: Strings.t.removeRow
                    ToolTip.visible: hovered
                }
            }
        }

        Item {
            visible: table.empty
            Layout.fillWidth: true
            Layout.fillHeight: true
            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                title: Strings.t.nothingHere
                actionText: Strings.t.add
                actionIcon: "list-add"
                onActionTriggered: { table.addRequested(); table.edited(); }
            }
        }

        ToolButton {
            visible: !table.empty
            icon.name: "list-add"
            text: Strings.t.add
            display: AbstractButton.TextBesideIcon
            Layout.leftMargin: table.colSpacing
            Layout.bottomMargin: table.colSpacing
            onClicked: { table.addRequested(); table.edited(); }
        }
    }

    // cabeçalho padrão de diálogo: título em negrito (padrão dos modais do app)
    component DialogHeader: Kirigami.Heading {
        property string dialogTitle: ""
        text: dialogTitle
        level: 2
        type: Kirigami.Heading.Type.Primary
        padding: Kirigami.Units.gridUnit
        bottomPadding: 0
        elide: Text.ElideRight
    }

    // confirmação de remoção de linha (mesma config global de exclusão)
    Dialog {
        id: confirmRemove
        objectName: "confirmRemoveDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: Strings.t.remove
        header: DialogHeader { dialogTitle: confirmRemove.title }
        modal: true
        width: 380
        height: 175
        property int pendingIndex: -1
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Strings.t.removeRowQuestion }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                Button { text: Strings.t.cancel; onClicked: confirmRemove.close() }
                Button {
                    text: Strings.t.remove; Accessible.defaultButton: true
                    onClicked: {
                        if (confirmRemove.pendingIndex >= 0) {
                            table.model.remove(confirmRemove.pendingIndex);
                            table.edited();
                        }
                        confirmRemove.close();
                    }
                }
            }
        }
    }
}
