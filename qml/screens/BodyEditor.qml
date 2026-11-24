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
    Item {
        id: bodyContainer
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: bodyTypeBox.currentValue !== "none" && bodyTypeBox.currentValue !== "multipart" && bodyTypeBox.currentValue !== "urlencoded"
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing

      ScrollView {
        id: bodyScroll
        anchors.fill: parent
        clip: true
        TextArea {
            id: bodyArea
            objectName: "bodyEditorArea"
            placeholderText: Strings.t.jsonExample
            font.family: settings.editorFontResolved
            font.pointSize: settings.editorFontSizeResolved
            leftPadding: settings.editorLineNumbers ? 40 : 6
            wrapMode: settings.editorWrap ? TextEdit.Wrap : TextEdit.NoWrap
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
                var unit = " ".repeat(settings.editorIndent);
                if (event.key === Qt.Key_BraceLeft && settings.editorBrackets) {
                    event.accepted = true;
                    bodyArea.insert(pos, "{}");
                    bodyArea.cursorPosition = pos + 1;
                    app.markDirty();
                    // programmatic insert() doesn't emit textEdited; without
                    // this the {{var}} popup only opens when typing the 1st character
                    bodyCompleter.updateCompleter();
                } else if (event.key === Qt.Key_BracketLeft && settings.editorBrackets) {
                    event.accepted = true;
                    bodyArea.insert(pos, "[]");
                    bodyArea.cursorPosition = pos + 1;
                    app.markDirty();
                } else if (event.key === Qt.Key_QuoteDbl && settings.editorBrackets) {
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
                } else if (event.key === Qt.Key_BraceRight && settings.editorBrackets) {
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
      // line-number gutter: fixed 34 px column over the scrolled text, drawn
      // viewport-only (positionToRectangle over the visible lines)
      Rectangle {
        id: lineGutter
        objectName: "bodyLineGutter"
        visible: settings.editorLineNumbers
        width: 34
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Kirigami.Theme.alternateBackgroundColor
        property var lines: []

        function refresh() {
            if (!visible || !bodyArea)
                return;
            var flick = bodyScroll.contentItem;
            var top = flick.contentY;
            var bottom = top + bodyScroll.height;
            var text = bodyArea.text;
            var pos = bodyArea.positionAt(0, Math.max(0, top));
            if (pos < 0) pos = 0;
            var lineStart = text.lastIndexOf("\n", Math.max(0, pos - 1)) + 1;
            var number = 1;
            for (var i = 0; i < lineStart; i++)
                if (text.charAt(i) === "\n") number++;
            var out = [];
            while (lineStart <= text.length && out.length < 500) {
                var r = bodyArea.positionToRectangle(lineStart);
                if (r.y > bottom) break;
                if (r.y + r.height >= top) out.push({ y: r.y - top, n: number });
                var nl = text.indexOf("\n", lineStart);
                if (nl < 0) break;
                lineStart = nl + 1; number++;
            }
            lines = out;
        }

        Component.onCompleted: refresh()
        onVisibleChanged: refresh()
        onHeightChanged: refresh()
        Connections {
            target: bodyArea
            function onTextChanged() { lineGutter.refresh(); }
            function onWidthChanged() { lineGutter.refresh(); }
        }
        Connections {
            target: bodyScroll.contentItem
            function onContentYChanged() { lineGutter.refresh(); }
        }
        Connections {
            target: settings
            function onSettingsChanged() { lineGutter.refresh(); }
        }

        Repeater {
            model: lineGutter.lines
            delegate: Text {
                x: 0
                y: modelData.y
                width: lineGutter.width - 6
                horizontalAlignment: Text.AlignRight
                text: modelData.n
                color: Kirigami.Theme.textColor
                opacity: 0.5
                font.pixelSize: app.theme.fontSizeMeta
                font.features: ({ "tnum": 1 })
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
