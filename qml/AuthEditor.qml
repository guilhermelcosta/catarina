import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Shared authentication editor: the request's Authentication tab
// (with allowInherit, which inherits the collection's auth) and the collection's Authentication tab.
// Usage: load(auth) → fills; value() → current map; edited() when the user changes.
ColumnLayout {
    id: root
    property var resolvedVars: []      // [{name, value, ...}] for the {{var}} autocomplete
    property string collection: ""     // scope of the variables
    property bool allowInherit: false  // shows the "inherit" option (inherits from the collection)
    signal edited()

    function load(a) {
        a = a !== undefined && a !== null ? a : {};
        var type = a.type !== undefined ? a.type : "none";
        if (!root.allowInherit && type === "inherit")
            type = "none";
        var idx = authTypeBox.indexOfValue(type);
        authTypeBox.currentIndex = idx >= 0 ? idx : 0;
        bearerToken.text = a.token !== undefined ? a.token : "";
        basicUser.text = a.user !== undefined ? a.user : "";
        basicPass.text = a.pass !== undefined ? a.pass : "";
        apiKeyName.text = a.key !== undefined ? a.key : "";
        apiKeyValue.text = a.value !== undefined ? a.value : "";
    }
    function value() {
        return { type: authTypeBox.currentValue, token: bearerToken.text,
                 user: basicUser.text, pass: basicPass.text,
                 key: apiKeyName.text, value: apiKeyValue.text };
    }
    function clear() {
        authTypeBox.currentIndex = 0;
        bearerToken.text = basicUser.text = basicPass.text = apiKeyName.text = apiKeyValue.text = "";
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        Label { text: Strings.t.type + ":" }
        ComboBox {
            id: authTypeBox
            textRole: "text"; valueRole: "value"
            model: {
                var m = [{ text: Strings.t.authNoneOption, value: "none" }];
                if (root.allowInherit)
                    m.push({ text: Strings.t.authInherit, value: "inherit" });
                m.push({ text: Strings.t.authBearer, value: "bearer" });
                m.push({ text: Strings.t.authBasic, value: "basic" });
                m.push({ text: Strings.t.authApiKey, value: "apikey" });
                return m;
            }
            implicitWidth: 200
            onActivated: root.edited()
        }
    }
    VarField {
        id: bearerToken
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        visible: authTypeBox.currentValue === "bearer"
        placeholderText: Strings.t.token
        resolved: root.resolvedVars
        collection: root.collection
        onTextEdited: root.edited()
    }
    RowLayout {
        visible: authTypeBox.currentValue === "basic"
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        VarField { id: basicUser; Layout.fillWidth: true; placeholderText: Strings.t.user; resolved: root.resolvedVars; collection: root.collection; onTextEdited: root.edited() }
        TextField { id: basicPass; Layout.fillWidth: true; placeholderText: Strings.t.password; echoMode: TextInput.Password; onTextEdited: root.edited() }
    }
    RowLayout {
        visible: authTypeBox.currentValue === "apikey"
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        VarField { id: apiKeyName; Layout.fillWidth: true; placeholderText: Strings.t.headerName; resolved: root.resolvedVars; collection: root.collection; onTextEdited: root.edited() }
        VarField { id: apiKeyValue; Layout.fillWidth: true; placeholderText: Strings.t.value; resolved: root.resolvedVars; collection: root.collection; onTextEdited: root.edited() }
    }
    Label { visible: authTypeBox.currentValue === "none"; text: Strings.t.authNone; opacity: 0.7; Layout.leftMargin: Kirigami.Units.smallSpacing }
    Label {
        visible: root.allowInherit && authTypeBox.currentValue === "inherit"
        text: Strings.t.authInheritHint
        opacity: 0.7; wrapMode: Text.WordWrap; Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
    }
    Item { Layout.fillHeight: true }
}
