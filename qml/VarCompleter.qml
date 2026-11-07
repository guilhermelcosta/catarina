import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Strings.js" as Strings
import "js/VarTokens.js" as VarTokens

// {{variable}} autocomplete (with keyboard) and popup with the value (hover).
// Must be a child of the target editor, with anchors.fill: parent.
Item {
    id: completer
    property var target: null          // target TextArea
    property var resolved: []          // [{name, value, secret, source}]
    property string collection: ""    // to explain variables out of scope

    function matchingNames() {
        return VarTokens.matchingNames(resolved, partial);
    }
    function tokenAt(pos) {
        return VarTokens.tokenAt(target.text, pos);
    }
    function valueOf(name) {
        return VarTokens.valueOf(resolved, name);
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
        if (target.text !== before + "{{" + name + "}}" + rest) {
            target.text = before + "{{" + name + "}}" + rest;
            target.cursorPosition = before.length + name.length + 4;
            // setting `text` programmatically does NOT emit textEdited; without this the
            // KvTable model (onTextEdited) keeps the old value (the "{{" being typed)
            if (target.textEdited !== undefined)
                target.textEdited();
        }
        pop.close();
    }
    // called by the target's Keys.onPressed; returns true if it consumed the key
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
            Label { text: Strings.t.variables; font.bold: true; opacity: 0.7; Layout.leftMargin: 4 }
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

    // ---------------- value on hover ----------------
    function updateHover(x, y) {
        if (!target) { hoverPop.close(); return; }
        if (target.text.indexOf("{{") < 0) { hoverPop.close(); return; }   // no variable: don't run regex/positionAt
        var pos = target.positionAt(x, y);
        if (pos < 0) { hoverPop.close(); return; }
        var tok = tokenAt(pos);
        if (!tok) { hoverPop.close(); return; }
        var v = valueOf(tok.name);
        if (v === null) {
            var n = backend.variableNoteFor(tok.name, collection);
            var note = Strings.variableNote(n.code, n.collections);
            hoverPop.mainText = tok.name + "  " + (note.length > 0 ? note : Strings.t.notDefined);
            hoverPop.scopeSource = "";
        } else {
            hoverPop.mainText = tok.name + " = " + (v.secret ? "••••••" : v.value)
                                + (v.enabled === false ? "  · " + Strings.t.disabled : "");
            hoverPop.scopeSource = v.source !== undefined ? v.source : "";
        }

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
        property string mainText: ""
        property string scopeSource: ""
        width: hoverRow.implicitWidth + 14
        height: hoverRow.implicitHeight + 14
        RowLayout {
            id: hoverRow
            anchors.fill: parent
            spacing: 8
            Label {
                id: hoverLabel
                font.family: "monospace"
                text: hoverPop.mainText
                Layout.alignment: Qt.AlignVCenter
            }
            // scope chip (color/icon per origin), instead of "(scope)"
            SourceChip {
                visible: hoverPop.scopeSource.length > 0
                Layout.alignment: Qt.AlignVCenter
                source: hoverPop.scopeSource
            }
        }
    }
}
