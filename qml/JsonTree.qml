import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Collapsible JSON tree for the response body.
Item {
    id: treeRoot
    property string text: ""
    property var root: undefined
    property var expanded: ({})
    // path -> parsed value, registered as rows are created. Lets a collapsed
    // subtree be re-inserted without walking the whole document again.
    property var values: ({})
    readonly property int rowCount: nodes.count

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
    function openOf(path, depth) {
        return (expanded[path] === undefined) ? (depth < 2) : (expanded[path] === true);
    }
    function addRow(key, value, depth, path) {
        var t = typeOf(value);
        var expandable = (t === "object" || t === "array");
        // default: the first 2 levels come open; clicking stores explicit state
        var isOpen = openOf(path, depth);
        values[path] = value;
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
        values = ({});
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
    function rowAt(i) { return nodes.get(i); }
    // appends the rows of `value`'s children starting at model index `at`;
    // returns the index after the inserted block
    function insertChildren(at, value, depth, path) {
        var t = typeOf(value);
        var childDepth = depth + 1;
        if (t === "array") {
            for (var i = 0; i < value.length; i++) {
                var ap = path + "[" + i + "]";
                at = insertRow(at, "[" + i + "]", value[i], childDepth, ap);
            }
        } else {
            for (var k in value) {
                var kp = path + "." + k;
                at = insertRow(at, k, value[k], childDepth, kp);
            }
        }
        return at;
    }
    function insertRow(at, key, value, depth, path) {
        var t = typeOf(value);
        var expandable = (t === "object" || t === "array");
        var isOpen = openOf(path, depth);
        values[path] = value;
        nodes.insert(at, { key: key, preview: previewOf(value, t), vtype: t, depth: depth,
                           expandable: expandable, open: isOpen, path: path });
        at++;
        if (expandable && isOpen)
            at = insertChildren(at, value, depth, path);
        return at;
    }
    // reads the clicked row's own state; `index` is the delegate index
    function toggle(path, index) {
        if (index === undefined || index < 0 || index >= nodes.count || nodes.get(index).path !== path) {
            index = -1;
            for (var i = 0; i < nodes.count; i++)
                if (nodes.get(i).path === path) { index = i; break; }
        }
        if (index < 0) return;
        var row = nodes.get(index);
        var open = row.open;
        expanded[path] = !open;
        if (open) {
            // remove only the visible descendants
            var depth = row.depth;
            var next = index + 1;
            while (next < nodes.count && nodes.get(next).depth > depth) {
                delete values[nodes.get(next).path];
                nodes.remove(next);
            }
        } else {
            insertChildren(index + 1, values[path], row.depth, path);
        }
        nodes.setProperty(index, "open", !open);
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
                    onClicked: treeRoot.toggle(model.path, index)
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
