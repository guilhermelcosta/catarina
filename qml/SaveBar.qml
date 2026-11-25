import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Standard header of an editable section: title on the left; on the right the
// "unsaved changes" indicator + Revert (icon, secondary) + Save.
// `showRename` adds a pencil next to the title (e.g. rename environment).
RowLayout {
    id: bar
    property string title: ""
    property bool dirty: false
    property bool showDiscard: false
    property bool showRename: false
    property bool canRename: true
    property bool canSave: true
    property string saveTooltip: Strings.t.saveTooltip
    property string discardTooltip: Strings.t.discardTooltip
    property string renameTooltip: Strings.t.renameTooltip
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
        Label { text: Strings.t.unsavedMarker; color: Kirigami.Theme.neutralTextColor }
    }
    ToolButton {
        visible: bar.showDiscard
        icon.name: "edit-undo"
        enabled: bar.dirty
        onClicked: bar.discard()
        ToolTip.text: bar.discardTooltip; ToolTip.visible: hovered
    }
    Button {
        icon.name: "document-save"; text: Strings.t.save
        highlighted: true
        enabled: bar.dirty && bar.canSave
        onClicked: bar.save()
        ToolTip.text: bar.saveTooltip; ToolTip.visible: hovered
    }
}
