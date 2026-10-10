import QtQuick
import org.kde.kirigami as Kirigami

// Standard dialog header: bold title, with the SAME padding across all
// modals. Always use `header: DialogHeader { dialogTitle: <id>.title }` — don't create
// a Heading by hand (otherwise the title breathing room varies between dialogs).
Kirigami.Heading {
    property string dialogTitle: ""
    text: dialogTitle
    level: 2
    type: Kirigami.Heading.Type.Primary
    padding: Kirigami.Units.gridUnit
    bottomPadding: 0
    elide: Text.ElideRight
}
