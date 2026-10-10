import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Split grab area (SplitView.handle), with a generous drag zone.
Rectangle {
    // Generous grab area (a 1px line is nearly impossible to hit with the mouse).
    // The transparent square is the drag zone; the thin line is just the visual.
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
