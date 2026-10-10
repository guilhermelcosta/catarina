import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Standard action footer of a dialog. The `Button`s declared as children are
// aligned to the right, with the SAME spacing and the same breathing room to the
// bottom edge across all modals. Always use this component at the end of the content:
//
//   DialogActions {
//       Button { text: ...; onClicked: ... }
//       Button { text: ...; Accessible.defaultButton: true; onClicked: ... }
//   }
//
// The `Item` below pushes the buttons to the right (it comes before the caller's children).
RowLayout {
    id: actions
    Layout.fillWidth: true
    Layout.bottomMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing
    Item { Layout.fillWidth: true }

    // Qt's `Button` responds to Space, but not to Enter/Return. Since the key isn't
    // consumed by the focused button, it bubbles up to here; we click the focused item.
    // A text field consumes Return on its own (onAccepted), so it isn't affected.
    Keys.onReturnPressed: function (event) {
        var item = Window.activeFocusItem;
        if (item && typeof item.click === "function") {
            item.click();
            event.accepted = true;
        }
    }
}
