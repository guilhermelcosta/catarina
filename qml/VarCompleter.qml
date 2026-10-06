import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Autocomplete de {{variavel}} (com teclado) e popup com o valor (hover).
// Deve ser filho do editor alvo, com anchors.fill: parent.
Item {
    id: completer
    property var target: null          // TextArea alvo
    property var resolved: []          // [{name, value, secret, source}]
    property string collection: ""    // para explicar variáveis fora de escopo

    function matchingNames() {
        var out = [];
        for (var i = 0; i < resolved.length; i++)
            if (resolved[i].name.indexOf(partial) === 0)
                out.push(resolved[i].name);
        out.sort();
        return out;
    }
    function tokenAt(pos) {
        var t = target.text;
        var re = /\{\{\s*([^{}]+?)\s*\}\}/g;
        var m;
        while ((m = re.exec(t)) !== null)
            if (pos >= m.index && pos <= m.index + m[0].length)
                return { name: m[1], start: m.index };
        return null;
    }
    function valueOf(name) {
        for (var i = 0; i < resolved.length; i++)
            if (resolved[i].name === name)
                return resolved[i];
        return null;
    }

    // ---------------- autocomplete ----------------
    property int tokenStart: -1
    property string partial: ""
    property int current: -1

    function updateCompleter() {
        if (!target) return;
        var t = target.text;
        var pos = target.cursorPosition;
        var before = t.substring(0, pos);
        var open = before.lastIndexOf("{{");
        if (open < 0) { pop.close(); return; }
        var afterOpen = before.substring(open + 2);
        if (afterOpen.indexOf("}") >= 0 || afterOpen.indexOf("{") >= 0 || afterOpen.indexOf("\n") >= 0) {
            pop.close();
            return;
        }
        tokenStart = open;
        partial = afterOpen;
        if (matchingNames().length === 0) { pop.close(); return; }
        current = 0;

        var r = target.positionToRectangle(pos);
        pop.x = Math.max(0, Math.min(r.x, completer.width - pop.width));
        pop.y = r.y + r.height + 2;
        pop.open();
    }
    function choose(name) {
        if (!target) return;
        var t = target.text;
        var before = t.substring(0, tokenStart);
        var rest = t.substring(tokenStart + 2 + partial.length);
        if (rest.indexOf("}}") === 0) rest = rest.substring(2);
        target.text = before + "{{" + name + "}}" + rest;
        target.cursorPosition = before.length + name.length + 4;
        pop.close();
    }
    // chamado pelos Keys.onPressed do alvo; devolve true se consumiu a tecla
    function handleKey(event) {
        if (!pop.visible) return false;
        var m = matchingNames();
        if (event.key === Qt.Key_Down) { current = Math.min(current + 1, m.length - 1); return true; }
        if (event.key === Qt.Key_Up) { current = Math.max(current - 1, 0); return true; }
        if (event.key === Qt.Key_Escape) { pop.close(); return true; }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
            if (current >= 0 && current < m.length) { choose(m[current]); return true; }
        }
        return false;
    }

    Connections {
        target: completer.target
        function onTextEdited() { completer.updateCompleter(); }
    }

    Popup {
        id: pop
        parent: completer
        width: 300
        height: 30 + Math.min(completer.matchingNames().length * 30, 210)
        padding: 4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        ColumnLayout {
            anchors.fill: parent
            spacing: 2
            Label { text: "Variáveis"; font.bold: true; opacity: 0.7; Layout.leftMargin: 4 }
            ListView {
                id: compList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: completer.matchingNames()
                currentIndex: completer.current
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: ItemDelegate {
                    width: ListView.view.width
                    height: 30
                    text: modelData
                    highlighted: index === completer.current
                    onClicked: completer.choose(modelData)
                }
            }
        }
    }

    // ---------------- valor no hover ----------------
    function updateHover(x, y) {
        if (!target) { hoverPop.close(); return; }
        var pos = target.positionAt(x, y);
        if (pos < 0) { hoverPop.close(); return; }
        var tok = tokenAt(pos);
        if (!tok) { hoverPop.close(); return; }
        var v = valueOf(tok.name);
        if (v === null) {
            var note = backend.variableNoteFor(tok.name, collection);
            hoverLabel.text = tok.name + "  (" + (note.length > 0 ? note : "não definida") + ")";
        } else if (v.secret)
            hoverLabel.text = tok.name + " = ••••••   (" + v.source + ")";
        else
            hoverLabel.text = tok.name + " = " + v.value + "   (" + v.source + ")";

        var r = target.positionToRectangle(tok.start);
        hoverPop.x = Math.max(0, Math.min(r.x, completer.width - hoverPop.width));
        var above = r.y - hoverPop.height - 4;
        hoverPop.y = above < 0 ? r.y + r.height + 4 : above;
        hoverPop.open();
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        acceptedButtons: Qt.NoButton
        onPositionChanged: function (mouse) { completer.updateHover(mouse.x, mouse.y); }
        onExited: hoverPop.close()
    }

    Popup {
        id: hoverPop
        parent: completer
        padding: 6
        closePolicy: Popup.NoAutoClose
        width: hoverLabel.implicitWidth + 14
        height: hoverLabel.implicitHeight + 14
        Label { id: hoverLabel; font.family: "monospace"; text: "" }
    }
}
