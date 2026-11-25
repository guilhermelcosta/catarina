import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// "Body" tab: type, form-urlencoded/multipart (fields) and JSON editor with autocomplete.
ColumnLayout {
    property var app
    property var fieldsModel
    property var fileDialog
    property alias body: bodyArea.text
    readonly property string bodyType: bodyTypeBox.currentValue
    function setBodyType(v) { var i = bodyTypeBox.indexOfValue(v); bodyTypeBox.currentIndex = i >= 0 ? i : 0; }
    // StackLayout constrains the current child by the maximum height it
    // computes (newSize.expandedTo(min).boundedTo(max)) and, in a
    // ColumnLayout nested with a ScrollView, that maximum comes out
    // small — the payload body got "squeezed" when switching
    // tabs. Lifting the maximum fixes it. See DESIGN.md.
    Layout.maximumHeight: Number.POSITIVE_INFINITY
    spacing: Kirigami.Units.smallSpacing
    RowLayout {
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.type + ":" }
        ComboBox {
            id: bodyTypeBox
            textRole: "text"; valueRole: "value"
            model: [
                { text: Strings.t.bodyNone, value: "none" },
                { text: "JSON", value: "json" },
                { text: Strings.t.bodyText, value: "text" },
                { text: "form-urlencoded", value: "urlencoded" },
                { text: "multipart/form-data", value: "multipart" }
            ]
            implicitWidth: 170
            onActivated: app.markDirty()
        }
        Item { Layout.fillWidth: true }
        Button {
            visible: bodyTypeBox.currentValue === "json"
            icon.name: "tools-wizard"; text: Strings.t.formatButton
            display: AbstractButton.TextBesideIcon
            onClicked: app.formatBody()
            ToolTip.text: Strings.t.formatJson; ToolTip.visible: hovered
        }
    }
    Label {
        visible: bodyTypeBox.currentValue === "none"
        text: Strings.t.noBody
        opacity: 0.7
        Layout.leftMargin: Kirigami.Units.smallSpacing
    }
    KvTable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: bodyTypeBox.currentValue === "multipart" || bodyTypeBox.currentValue === "urlencoded"
        model: fieldsModel
        keyPlaceholder: Strings.t.field
        allowFiles: bodyTypeBox.currentValue === "multipart"
        onAddRequested: fieldsModel.append({ name: "", value: "", type: "text", fileName: "", enabled: true })
        onEdited: app.markDirty()
        onPickFile: function (index) { fileDialog.targetIndex = index; fileDialog.open(); }
    }
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: bodyTypeBox.currentValue !== "none" && bodyTypeBox.currentValue !== "multipart" && bodyTypeBox.currentValue !== "urlencoded"
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        TextArea {
            id: bodyArea
            placeholderText: Strings.t.jsonExample
            font.family: "monospace"
            font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize
            wrapMode: TextEdit.Wrap
            onTextEdited: app.markDirty()
            Component.onCompleted:
                varSupport.attach(bodyArea.textDocument, "#c678dd", true, true,
                    app.jsonStringColor, app.jsonNumberColor, app.jsonKeywordColor,
                    app.jsonKeyColor)
            VarCompleter {
                id: bodyCompleter
                anchors.fill: parent
                target: bodyArea
                resolved: app.resolvedVars
                collection: app.currentCollection
            }
            // auto-closes pairs and indents on Enter (Bruno style)
            Keys.onPressed: function (event) {
                if (bodyCompleter.handleKey(event)) { event.accepted = true; return; }
                var pos = bodyArea.cursorPosition;
                var unit = "  ";
                if (event.key === Qt.Key_BraceLeft) {
                    event.accepted = true;
                    bodyArea.insert(pos, "{}");
                    bodyArea.cursorPosition = pos + 1;
                    app.markDirty();
                    // programmatic insert() doesn't emit textEdited; without
                    // this the {{var}} popup only opens when typing the 1st character
                    bodyCompleter.updateCompleter();
                } else if (event.key === Qt.Key_BracketLeft) {
                    event.accepted = true;
                    bodyArea.insert(pos, "[]");
                    bodyArea.cursorPosition = pos + 1;
                    app.markDirty();
                } else if (event.key === Qt.Key_QuoteDbl) {
                    event.accepted = true;
                    if (bodyArea.selectedText.length > 0) {
                        bodyArea.insert(pos, "\"" + bodyArea.selectedText + "\"");
                    } else {
                        bodyArea.insert(pos, "\"\"");
                        bodyArea.cursorPosition = pos + 1;
                    }
                    app.markDirty();
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    event.accepted = true;
                    var t = bodyArea.text;
                    var ls = t.lastIndexOf("\n", pos - 1) + 1;
                    var indent = (t.substring(ls, pos).match(/^[ \t]*/) || [""])[0];
                    var before = pos > 0 ? t.charAt(pos - 1) : "";
                    var after = pos < t.length ? t.charAt(pos) : "";
                    if ((before === "{" && after === "}") || (before === "[" && after === "]")) {
                        bodyArea.insert(pos, "\n" + indent + unit + "\n" + indent);   // expands as a block
                        bodyArea.cursorPosition = pos + 1 + indent.length + unit.length;
                    } else if (before === "{" || before === "[") {
                        bodyArea.insert(pos, "\n" + indent + unit);
                        bodyArea.cursorPosition = pos + 1 + indent.length + unit.length;
                    } else {
                        bodyArea.insert(pos, "\n" + indent);
                        bodyArea.cursorPosition = pos + 1 + indent.length;
                    }
                    app.markDirty();
                } else if (event.key === Qt.Key_BraceRight) {
                    var t2 = bodyArea.text;
                    var ls2 = t2.lastIndexOf("\n", pos - 1) + 1;
                    var prefix = t2.substring(ls2, pos);
                    if (/^[ \t]+$/.test(prefix) && prefix.length >= unit.length) {
                        event.accepted = true;   // line with only spaces: dedents on close
                        var kept = prefix.substring(0, prefix.length - unit.length);
                        bodyArea.remove(ls2, pos);
                        bodyArea.insert(ls2, kept + "}");
                        bodyArea.cursorPosition = ls2 + kept.length + 1;
                        app.markDirty();
                    }
                }
            }
        }
    }
    // with maximumHeight lifted, the ColumnLayout takes the full
    // height of the StackLayout; with no child to fill it, Qt
    // redistributes the space and the header "stretches". This filler
    // (only on "none") anchors the top, as in Authentication.
    Item {
        Layout.fillHeight: true
        visible: bodyTypeBox.currentValue === "none"
    }
}
