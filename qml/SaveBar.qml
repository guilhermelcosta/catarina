import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Cabeçalho padronizado de uma seção editável: título à esquerda; à direita o
// indicador "alterações não salvas" + Reverter (ícone, secundário) + Salvar.
// `showRename` adiciona um lápis ao lado do título (ex.: renomear ambiente).
RowLayout {
    id: bar
    property string title: ""
    property bool dirty: false
    property bool showDiscard: false
    property bool showRename: false
    property bool canRename: true
    property bool canSave: true
    property string saveTooltip: "Salvar (Ctrl+S)"
    property string discardTooltip: "Descartar alterações não salvas"
    property string renameTooltip: "Renomear"
    signal save()
    signal discard()
    signal rename()

    spacing: Kirigami.Units.smallSpacing

    Label { text: bar.title; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1 }
    ToolButton {
        visible: bar.showRename
        icon.name: "edit-rename"
        enabled: bar.canRename
        onClicked: bar.rename()
        ToolTip.text: bar.renameTooltip; ToolTip.visible: hovered
    }
    Item { Layout.fillWidth: true }
    RowLayout {
        visible: bar.dirty
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon { source: "media-record-symbolic"; color: Kirigami.Theme.neutralTextColor; implicitWidth: 10; implicitHeight: 10; Layout.alignment: Qt.AlignVCenter }
        Label { text: "alterações não salvas"; color: Kirigami.Theme.neutralTextColor }
    }
    ToolButton {
        visible: bar.showDiscard
        icon.name: "edit-undo"
        enabled: bar.dirty
        onClicked: bar.discard()
        ToolTip.text: bar.discardTooltip; ToolTip.visible: hovered
    }
    Button {
        icon.name: "document-save"; text: "Salvar"
        highlighted: true
        enabled: bar.dirty && bar.canSave
        onClicked: bar.save()
        ToolTip.text: bar.saveTooltip; ToolTip.visible: hovered
    }
}
