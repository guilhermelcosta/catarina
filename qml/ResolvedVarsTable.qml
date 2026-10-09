import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Tabela somente-leitura das variáveis efetivas (Origem / Nome / Valor).
// Mesmo padrão de tabela do app: cabeçalho em negrito (opacidade 0.65),
// colunas com larguras explícitas e linhas desabilitadas esmaecidas.
// `vars`: [{ name, value, secret, source, enabled }]
ColumnLayout {
    id: root
    property var vars: []
    // só as que realmente resolvem (desabilitadas não aparecem nesta visualização);
    // ordena por origem (global → coleção → request) e, dentro dela, por nome
    readonly property var activeVars: {
        var list = vars ? vars.filter(function (v) { return v.enabled !== false; }) : [];
        list.sort(function (a, b) {
            var d = sourceRank(a.source) - sourceRank(b.source);
            return d !== 0 ? d : String(a.name).localeCompare(String(b.name));
        });
        return list;
    }
    readonly property int count: activeVars.length
    spacing: Kirigami.Units.smallSpacing

    // origem → rank de ordenação, cor e ícone (identidade visual por escopo)
    function sourceRank(s) {
        if (s === "global") return 0;
        if (s === "collection") return 1;
        if (s === "request") return 2;
        return 3;
    }
    function sourceColor(s) {
        if (s === "global") return Kirigami.Theme.positiveTextColor;
        if (s === "collection") return Kirigami.Theme.activeTextColor;
        return Kirigami.Theme.neutralTextColor;
    }
    function sourceIcon(s) {
        if (s === "global") return "globe";
        if (s === "collection") return "folder-documents";
        return "document-send";
    }

    readonly property int sourceColWidth: 84
    readonly property int nameColPreferred: 140
    readonly property int nameColMinimum: 80
    readonly property int valueColPreferred: 160
    readonly property int valueColMinimum: 80

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.origin; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                Layout.preferredWidth: root.sourceColWidth; Layout.minimumWidth: root.sourceColWidth; Layout.maximumWidth: root.sourceColWidth }
        Label { text: Strings.t.name; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                Layout.fillWidth: true; Layout.preferredWidth: root.nameColPreferred; Layout.minimumWidth: root.nameColMinimum }
        Label { text: Strings.t.value; font.bold: true; opacity: 0.65; elide: Text.ElideRight
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
                color: Qt.rgba(root.sourceColor(modelData.source).r,
                               root.sourceColor(modelData.source).g,
                               root.sourceColor(modelData.source).b, 0.15)
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 3
                    Kirigami.Icon {
                        source: root.sourceIcon(modelData.source)
                        color: root.sourceColor(modelData.source)
                        implicitWidth: 11; implicitHeight: 11
                    }
                    Text {
                        text: modelData.source !== undefined ? modelData.source : ""
                        font.pixelSize: 9
                        font.bold: true
                        color: root.sourceColor(modelData.source)
                    }
                }
            }
            Label { Layout.fillWidth: true; Layout.preferredWidth: root.nameColPreferred; Layout.minimumWidth: root.nameColMinimum
                    text: modelData.name; font.bold: true; elide: Text.ElideRight }
            Label { Layout.fillWidth: true; Layout.preferredWidth: root.valueColPreferred; Layout.minimumWidth: root.valueColMinimum
                    text: modelData.secret ? "••••••" : modelData.value; elide: Text.ElideRight; opacity: 0.9 }
        }
    }
}
