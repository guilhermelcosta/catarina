import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Área de agarrar de split (SplitView.handle), com zona de arraste generosa.
Rectangle {
    // Área de agarrar generosa (traço de 1px é quase impossível acertar com o mouse).
    // O quadrado transparente é a zona de arraste; a linha fina é só o visual.
    readonly property bool verticalBar: height > width
    implicitWidth: Kirigami.Units.smallSpacing * 2 + 1
    implicitHeight: Kirigami.Units.smallSpacing * 2 + 1
    color: "transparent"
    HoverHandler { cursorShape: parent.verticalBar ? Qt.SplitHCursor : Qt.SplitVCursor }
    Rectangle {
        anchors.centerIn: parent
        width: parent.verticalBar ? 1 : parent.width
        height: parent.verticalBar ? parent.height : 1
        color: Kirigami.Theme.disabledTextColor
        opacity: SplitHandle.pressed ? 1.0 : (SplitHandle.hovered ? 0.8 : 0.4)
    }
}
