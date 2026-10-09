import QtQuick
import org.kde.kirigami as Kirigami

// Cabeçalho padrão de diálogo: título em negrito, com o MESMO padding em todos os
// modais. Use sempre `header: DialogHeader { dialogTitle: <id>.title }` — não crie
// um Heading à mão (senão o respiro do título varia entre diálogos).
Kirigami.Heading {
    property string dialogTitle: ""
    text: dialogTitle
    level: 2
    type: Kirigami.Heading.Type.Primary
    padding: Kirigami.Units.gridUnit
    bottomPadding: 0
    elide: Text.ElideRight
}
