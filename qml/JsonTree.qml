import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Árvore JSON colapsável para o corpo da resposta.
Item {
    id: treeRoot
    property string text: ""
    property var root: undefined
    property var expanded: ({})

    ListModel { id: nodes }

    function typeOf(v) {
        if (v === null) return "null";
        if (Array.isArray(v)) return "array";
        return typeof v;   // object | string | number | boolean
    }
    function previewOf(v, t) {
        if (t === "array") return "[" + v.length + "]";
        if (t === "object") {
            var n = 0;
            for (var k in v) n++;
            return "{" + n + "}";
        }
        if (t === "string") return "\"" + v + "\"";
        return String(v);
    }
    function colorOf(t) {
        var dark = Kirigami.Theme.backgroundColor.hsvValue < 0.5;
        if (t === "string") return dark ? "#98c379" : "#2e7d32";
        if (t === "number") return dark ? "#d19a66" : "#b26a00";
        if (t === "boolean" || t === "null") return dark ? "#d19a66" : "#b26a00";
        return Kirigami.Theme.textColor;
    }
    function addRow(key, value, depth, path) {
        var t = typeOf(value);
        var expandable = (t === "object" || t === "array");
        // padrão: os 2 primeiros níveis vêm abertos; clique guarda estado explícito
        var isOpen = (expanded[path] === undefined) ? (depth < 2) : (expanded[path] === true);
        nodes.append({ key: key, preview: previewOf(value, t), vtype: t, depth: depth,
                       expandable: expandable, open: isOpen, path: path });
        if (expandable && isOpen) {
            if (t === "array") {
                for (var i = 0; i < value.length; i++)
                    addRow("[" + i + "]", value[i], depth + 1, path + "[" + i + "]");
            } else {
                for (var k in value)
                    addRow(k, value[k], depth + 1, path + "." + k);
            }
        }
    }
    function rebuild() {
        nodes.clear();
        if (root === undefined) return;
        var t = typeOf(root);
        if (t === "object" || t === "array") {
            if (t === "array")
                for (var i = 0; i < root.length; i++) addRow("[" + i + "]", root[i], 0, "$[" + i + "]");
            else
                for (var k in root) addRow(k, root[k], 0, "$." + k);
        } else {
            nodes.append({ key: "", preview: previewOf(root, t), vtype: t, depth: 0, expandable: false, open: false, path: "$" });
        }
    }
    function load(t) {
        expanded = ({});
        try { root = JSON.parse(t); } catch (e) { root = undefined; }
        rebuild();
    }
    function toggle(path) {
        var currently = isOpenAt(path);
        expanded[path] = !currently;   // grava estado explícito
        expanded = expanded;           // notifica
        rebuild();
    }
    // descobre se está aberto agora (explícito ou padrão)
    function isOpenAt(path) {
        for (var i = 0; i < nodes.count; i++)
            if (nodes.get(i).path === path) return nodes.get(i).open;
        return false;
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        ListView {
            id: view
            model: nodes
            delegate: Row {
                width: view.width
                height: 22
                spacing: 4
                Item { width: model.depth * 14; height: 1 }
                ToolButton {
                    visible: model.expandable
                    width: 16; height: 16
                    y: 3
                    icon.name: model.open ? "arrow-down" : "arrow-right"
                    onClicked: treeRoot.toggle(model.path)
                }
                Item { visible: !model.expandable; width: 16; height: 1 }
                Label {
                    id: keyLabel
                    y: 2
                    text: model.key
                    font.bold: true
                    color: Kirigami.Theme.textColor
                }
                Label { y: 2; text: ":"; opacity: 0.5 }
                Label {
                    y: 2
                    width: Math.max(50, view.width - (model.depth * 14 + 70))
                    text: model.preview
                    color: treeRoot.colorOf(model.vtype)
                    elide: Text.ElideRight
                    font.family: "monospace"
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
        message: treeRoot.text.length === 0 ? Strings.t.noResponse : Strings.t.invalidJson
        visible: nodes.count === 0
    }
}
