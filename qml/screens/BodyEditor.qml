import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Aba "Corpo": tipo, form-urlencoded/multipart (fields) e editor JSON com autocomplete.
ColumnLayout {
    property var app
    property var fieldsModel
    property var fileDialog
    property alias body: bodyArea.text
    readonly property string bodyType: bodyTypeBox.currentValue
    function setBodyType(v) { var i = bodyTypeBox.indexOfValue(v); bodyTypeBox.currentIndex = i >= 0 ? i : 0; }
    // O StackLayout limita o filho atual pela altura máxima que
    // calcula (newSize.expandedTo(min).boundedTo(max)) e, num
    // ColumnLayout aninhado com ScrollView, esse máximo sai
    // pequeno — o corpo do payload ficava "espremido" ao trocar
    // de aba. Liberar o máximo resolve. Ver DESIGN.md.
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
            // auto-fecha pares e indenta no Enter (estilo Bruno)
            Keys.onPressed: function (event) {
                if (bodyCompleter.handleKey(event)) { event.accepted = true; return; }
                var pos = bodyArea.cursorPosition;
                var unit = "  ";
                if (event.key === Qt.Key_BraceLeft) {
                    event.accepted = true;
                    bodyArea.insert(pos, "{}");
                    bodyArea.cursorPosition = pos + 1;
                    app.markDirty();
                    // insert() programático não emite textEdited; sem
                    // isto o popup de {{var}} só abre ao digitar o 1º caractere
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
                        bodyArea.insert(pos, "\n" + indent + unit + "\n" + indent);   // expande em bloco
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
                        event.accepted = true;   // linha só com espaços: dedenta ao fechar
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
    // com maximumHeight liberado, o ColumnLayout ocupa a altura
    // inteira do StackLayout; sem filho que preencha, o Qt
    // redistribui o espaço e o cabeçalho "estica". Este filler
    // (só em "nenhum") âncora o topo, como na Autenticação.
    Item {
        Layout.fillHeight: true
        visible: bodyTypeBox.currentValue === "none"
    }
}
