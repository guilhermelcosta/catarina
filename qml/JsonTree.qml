import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

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
        if (t === "string") return Kirigami.Theme.positiveTextColor;
        if (t === "number" || t === "boolean") return Kirigami.Theme.neutralTextColor;
        if (t === "null") return Kirigami.Theme.disabledTextColor;
        return Kirigami.Theme.textColor;
    }
    function addRow(key, value, depth, path) {
        var t = typeOf(value);
        var expandable = (t === "object" || t === "array");
        var isOpen = expanded[path] === true;
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
        expanded[path] = !(expanded[path] === true);
        expanded = expanded;   // notifica
        rebuild();
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        ListView {
            id: view
            model: nodes
            delegate: RowLayout {
                width: view.width
                spacing: 4
                Item { Layout.preferredWidth: model.depth * 14; Layout.preferredHeight: 1 }
                ToolButton {
                    visible: model.expandable
                    implicitWidth: 16; implicitHeight: 16
                    icon.name: model.open ? "arrow-down" : "arrow-right"
                    onClicked: treeRoot.toggle(model.path)
                }
                Label { visible: !model.expandable; Layout.preferredWidth: 16; text: " " }
                Label { text: model.key; font.bold: true; color: Kirigami.Theme.textColor }
                Label { text: ":"; opacity: 0.5 }
                Label {
                    Layout.fillWidth: true
                    text: model.preview
                    color: treeRoot.colorOf(model.vtype)
                    elide: Text.ElideRight
                    font.family: "monospace"
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: nodes.count === 0
        text: treeRoot.text.length === 0 ? "Sem resposta." : "Resposta não é JSON válido."
        opacity: 0.5
    }
}
