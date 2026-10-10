import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Single-line text field with built-in {{variable}} support: highlights,
// suggests (autocomplete) and shows the value on hover. Centralizes what used
// to be repeated in each field (varSupport.attach + VarCompleter + Keys.onPressed).
// It's a TextArea (not TextField) because the highlight needs QQuickTextDocument,
// hence masked fields (echoMode, password/secret) have no highlight.
//
// TextArea does NOT scroll by itself, and moving the item would drag its background/
// border too. So we scroll the TEXT by offsetting the horizontal padding (`scroll`):
// the frame stays put, only the text shifts. See `ensureVisible`.
TextArea {
    id: root
    property var resolved: []          // [{name, value, secret, source, enabled}]
    property string collection: ""     // to explain variables out of scope
    property string errorText: ""      // message shown in the hover popup (e.g. repeated name)
    property var tabHandler: null      // function(dir): Tab navigation between cells (KvTable); null = native
    signal accepted()                  // Enter/Return (single-line cell): consumed, the caller decides

    // base horizontal padding; the text is drawn at (horizontalPadding - scroll)
    property real horizontalPadding: 6
    property real scroll: 0            // current horizontal offset of the text (>= 0)
    leftPadding: horizontalPadding - scroll
    rightPadding: horizontalPadding

    wrapMode: TextEdit.NoWrap
    selectByMouse: true
    activeFocusOnTab: true
    clip: true                         // hide the text that scrolls out of the field
    implicitHeight: Kirigami.Units.gridUnit * 1.7
    topPadding: 3; bottomPadding: 3
    // repeated name: text in red and bold (like the {{variable}} highlight)
    color: root.errorText.length > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    font.bold: root.errorText.length > 0

    // keeps the caret in view by shifting `scroll` (cursorRectangle is unaffected by the
    // item position, so this converges in one step)
    function ensureVisible() {
        var hp = horizontalPadding;
        var cx = cursorRectangle.x - (hp - scroll);       // caret x within the text (scroll-independent)
        var cw = cursorRectangle.width;
        var lo = cx + cw - width + 2 * hp;                // min scroll to show the caret's right edge
        var hi = cx;                                      // max scroll to show the caret's left edge
        var s = scroll;
        if (s > hi) s = hi;
        else if (s < lo) s = lo;
        if (s < 0) s = 0;
        if (s !== scroll) scroll = s;
    }
    onCursorRectangleChanged: ensureVisible()
    onWidthChanged: ensureVisible()

    function updateErrorPopup() {
        if (root.hovered && root.errorText.length > 0) errPop.open();
        else errPop.close();
    }
    onHoveredChanged: updateErrorPopup()

    // dark popup with the reason (same style as the {{variable}} hover)
    Popup {
        id: errPop
        parent: root
        padding: 6
        closePolicy: Popup.NoAutoClose
        x: 0
        y: root.height + 4
        width: errLabel.implicitWidth + 14
        height: errLabel.implicitHeight + 14
        Label { id: errLabel; font.family: "monospace"; text: root.errorText }
    }

    Keys.onPressed: function (e) {
        if (completer.handleKey(e)) { e.accepted = true; return; }
        // single-line field (TextArea because of the highlight): Enter can't
        // insert a line break in the middle of the text; emits accepted() for the caller
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { e.accepted = true; root.accepted(); return; }
        // Tab/Shift+Tab: when the table provides a tabHandler, navigates cell by cell;
        // outside the table it passes through (native focus navigation)
        if ((e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) && root.tabHandler) {
            root.tabHandler(e.key === Qt.Key_Backtab ? -1 : 1);
            e.accepted = true;
        }
    }
    Component.onCompleted: varSupport.attach(root.textDocument, "#c678dd", true, false)

    VarCompleter {
        id: completer
        objectName: "varCompleter"
        anchors.fill: parent
        target: root
        resolved: root.resolved
        collection: root.collection
    }
}
