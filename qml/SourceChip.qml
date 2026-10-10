import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Variable origin chip (global/collection/request): tinted background + icon + text,
// with color/icon per scope. Used by ResolvedVarsTable and VarCompleter.
Item {
    id: chip
    property string source: ""
    implicitWidth: row.implicitWidth + 10
    implicitHeight: row.implicitHeight + 6

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

    Rectangle {
        anchors.fill: parent
        radius: 3
        color: Qt.rgba(chip.sourceColor(chip.source).r,
                       chip.sourceColor(chip.source).g,
                       chip.sourceColor(chip.source).b, 0.15)
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 3
            Kirigami.Icon {
                source: chip.sourceIcon(chip.source)
                color: chip.sourceColor(chip.source)
                implicitWidth: 11; implicitHeight: 11
            }
            Text {
                text: chip.source
                font.pixelSize: 9
                font.bold: true
                color: chip.sourceColor(chip.source)
            }
        }
    }
}
