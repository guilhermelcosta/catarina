import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Rodapé padrão de ações de um diálogo. Os `Button` declarados como filhos ficam
// alinhados à direita, com o MESMO espaçamento e o mesmo respiro até a borda
// inferior em todos os modais. Use sempre este componente no fim do conteúdo:
//
//   DialogActions {
//       Button { text: ...; onClicked: ... }
//       Button { text: ...; Accessible.defaultButton: true; onClicked: ... }
//   }
//
// O `Item` abaixo empurra os botões para a direita (fica antes dos filhos do chamador).
RowLayout {
    id: actions
    Layout.fillWidth: true
    Layout.bottomMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing
    Item { Layout.fillWidth: true }
}
