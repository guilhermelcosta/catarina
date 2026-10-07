import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Tabela somente-leitura das variáveis efetivas (Origem / Nome / Valor).
// Mesmo padrão de tabela do app: cabeçalho em negrito (opacidade 0.65),
// colunas com larguras explícitas e linhas desabilitadas esmaecidas.
// `vars`: [{ name, value, secret, source, enabled }]
ColumnLayout {
    id: root
    property var vars: []
    // só as que realmente resolvem (desabilitadas não aparecem nesta visualização)
    readonly property var activeVars: vars ? vars.filter(function (v) { return v.enabled !== false; }) : []
    readonly property int count: activeVars.length
    spacing: Kirigami.Units.smallSpacing

    readonly property int sourceColWidth: 84
    readonly property int nameColPreferred: 140
    readonly property int nameColMinimum: 80
    readonly property int valueColPreferred: 160
    readonly property int valueColMinimum: 80

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Label { text: "Origem"; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                Layout.preferredWidth: root.sourceColWidth; Layout.minimumWidth: root.sourceColWidth; Layout.maximumWidth: root.sourceColWidth }
        Label { text: "Nome"; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                Layout.fillWidth: true; Layout.preferredWidth: root.nameColPreferred; Layout.minimumWidth: root.nameColMinimum }
        Label { text: "Valor"; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                Layout.fillWidth: true; Layout.preferredWidth: root.valueColPreferred; Layout.minimumWidth: root.valueColMinimum }
    }
    Kirigami.Separator { Layout.fillWidth: true }

    ListView {
        id: view
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.activeVars
        delegate: RowLayout {
            width: view.width
            spacing: Kirigami.Units.smallSpacing
            opacity: modelData.enabled === false ? 0.4 : 1
            Rectangle {
                Layout.preferredWidth: root.sourceColWidth; Layout.minimumWidth: root.sourceColWidth; Layout.maximumWidth: root.sourceColWidth
                implicitHeight: 16; radius: 3
                color: Kirigami.Theme.alternateBackgroundColor
                Text { anchors.centerIn: parent; text: modelData.source; font.pixelSize: 9; opacity: 0.8; color: Kirigami.Theme.textColor }
            }
            Label { Layout.fillWidth: true; Layout.preferredWidth: root.nameColPreferred; Layout.minimumWidth: root.nameColMinimum
                    text: modelData.name; font.bold: true; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; Layout.preferredWidth: root.valueColPreferred; Layout.minimumWidth: root.valueColMinimum
                    text: modelData.secret ? "••••••" : modelData.value; elide: Text.ElideRight; opacity: 0.9 }
        }
    }
}
