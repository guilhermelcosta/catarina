import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Unified key/value pair table for the app (params, headers, fields, request/
// collection/environment vars). The value field accepts {{variable}} (highlights, suggests,
// and shows on hover). Optional columns: Type (files), Scope and Secret.
//
// Responsive layout: the "Name", "Value" and "Scope" columns are flexible
// (fillWidth with explicit preferred/minimum), so they shrink in narrow windows.
// Header and rows use exactly the same preferred/minimum → they stay aligned.
//
// Root is an Item (implicit 0) with an inner ColumnLayout, so the implicit size
// doesn't depend on width (avoids a layout polish loop).
Item {
    id: table
    property var model
    property string keyPlaceholder: Strings.t.key
    property bool secretColumn: false
    property bool allowFiles: false
    property bool scopeColumn: false
    property var resolved: []
    property string collection: ""
    property var scopeText: null     // function(index) -> scope chip text
    property var scopeIcon: null     // function(index) -> scope chip icon name
    property var scopeColor: null    // function(index) -> chip color (per scope); null = neutral
    property var scopeTooltip: null  // function(index) -> tooltip (e.g. full names)
    property bool uniqueNames: false // highlights repeated names in the table (variables)
    property var rowFilter: null     // function(index) -> bool (shows/hides the row)
    signal addRequested()
    signal edited()
    signal pickFile(int index)
    signal scopeRequested(int index, real gx, real gy)

    // bump on every edit: forces re-evaluation of the repeated-name highlight
    property int revision: 0
    onEdited: revision++

    // row name collides (trimmed) with that of another row in the same table
    function isDuplicateName(index) {
        var r = table.model.get(index);
        var n = r && r.name !== undefined ? String(r.name).trim() : "";
        if (n.length === 0) return false;
        for (var i = 0; i < table.model.count; i++) {
            if (i === index) continue;
            var m = table.model.get(i);
            var o = m && m.name !== undefined ? String(m.name).trim() : "";
            if (o === n) return true;
        }
        return false;
    }

    // row removal with confirmation, following the global config (settings.confirmDelete)
    function tryRemove(i) {
        if (settings.confirmDelete) { confirmRemove.pendingIndex = i; confirmRemove.open(); }
        else { table.model.remove(i); table.edited(); }
    }

    // editable cells (in column order) of an already instantiated row.
    // Each cell exposes kvCell = true only on its active face (the "value" column has
    // three mutually exclusive faces), so we don't rely on `visible` — which in the
    // test harness reads effective visibility (TestCase is invisible).
    function focusableCells(row) {
        var it = kvList.itemAtIndex(row);
        if (!it || it.shown === false) return [];   // filtered-out row gets no focus
        var out = [];
        for (var i = 0; i < it.children.length; i++) {
            var c = it.children[i];
            if (c && c.kvCell === true && c.enabled !== false) out.push(c);
        }
        return out;
    }
    // Tab/Shift+Tab (dir = +1/-1): next column; at the end of the row, the next row
    function moveFocus(dir) {
        for (var r = 0; r < table.model.count; r++) {
            var cells = table.focusableCells(r);
            var idx = -1;
            for (var c = 0; c < cells.length; c++)
                if (cells[c].activeFocus) { idx = c; break; }
            if (idx < 0) continue;
            var n = idx + dir;
            if (n >= 0 && n < cells.length) { cells[n].forceActiveFocus(); return; }
            var r2 = r + dir;
            if (r2 < 0 || r2 >= table.model.count) return;
            var cells2 = table.focusableCells(r2);
            var c2 = dir > 0 ? 0 : cells2.length - 1;
            if (c2 >= 0 && cells2[c2]) cells2[c2].forceActiveFocus();
            return;
        }
    }

    readonly property bool empty: model === undefined || model === null || model.count === 0

    readonly property int colSpacing: Kirigami.Units.smallSpacing
    // fixed-width columns (small)
    readonly property int enabledColWidth: 48
    readonly property int typeColWidth: 90
    readonly property int secretColWidth: 64
    readonly property int removeColWidth: 40
    // flexible columns
    readonly property int keyColPreferred: 150
    readonly property int keyColMinimum: 80
    readonly property int valueColPreferred: 180
    readonly property int valueColMinimum: 80
    readonly property int scopeColPreferred: 170
    readonly property int scopeColMinimum: 90
    readonly property string keyHeader: keyPlaceholder.length > 0
        ? keyPlaceholder.charAt(0).toUpperCase() + keyPlaceholder.slice(1) : Strings.t.key

    ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: table.colSpacing

        // column header — same preferred/minimum as the rows
        RowLayout {
            id: header
            objectName: "kvHeader"
            visible: !table.empty
            Layout.fillWidth: true
            Layout.leftMargin: table.colSpacing
            Layout.rightMargin: table.colSpacing
            Layout.topMargin: table.colSpacing
            spacing: table.colSpacing
            Label { text: Strings.t.active; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.preferredWidth: table.enabledColWidth; Layout.minimumWidth: table.enabledColWidth; Layout.maximumWidth: table.enabledColWidth }
            Label { text: table.keyHeader; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.fillWidth: true; Layout.preferredWidth: table.keyColPreferred; Layout.minimumWidth: table.keyColMinimum }
            Label { text: Strings.t.value; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum }
            Label { visible: table.allowFiles; text: Strings.t.type; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.preferredWidth: table.typeColWidth; Layout.minimumWidth: table.typeColWidth; Layout.maximumWidth: table.typeColWidth }
            Label { visible: table.scopeColumn; text: Strings.t.scope; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.fillWidth: true; Layout.preferredWidth: table.scopeColPreferred; Layout.minimumWidth: table.scopeColMinimum }
            Label { visible: table.secretColumn; text: Strings.t.secret; font.bold: true; opacity: 0.65; elide: Text.ElideRight
                    Layout.preferredWidth: table.secretColWidth; Layout.minimumWidth: table.secretColWidth; Layout.maximumWidth: table.secretColWidth }
            Item { Layout.preferredWidth: table.removeColWidth; Layout.minimumWidth: table.removeColWidth; Layout.maximumWidth: table.removeColWidth }
        }
        Kirigami.Separator {
            visible: !table.empty
            Layout.fillWidth: true
            Layout.leftMargin: table.colSpacing
            Layout.rightMargin: table.colSpacing
        }

        ListView {
            id: kvList
            objectName: "kvList"
            visible: !table.empty
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: table.colSpacing
            Layout.rightMargin: table.colSpacing
            clip: true
            model: table.model
            delegate: RowLayout {
                width: kvList.width
                spacing: table.colSpacing
                // Tab/Shift+Tab from controls that don't consume the key (checkbox, combo, buttons)
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                        table.moveFocus(e.key === Qt.Key_Backtab ? -1 : 1);
                        e.accepted = true;
                    }
                }
                readonly property bool shown: table.rowFilter === null || table.rowFilter(index)
                visible: shown
                height: shown ? implicitHeight : 0
                opacity: model.enabled === false ? 0.45 : 1   // disabled row dimmed
                CheckBox {
                    property bool kvCell: true
                    Layout.preferredWidth: table.enabledColWidth; Layout.minimumWidth: table.enabledColWidth; Layout.maximumWidth: table.enabledColWidth
                    checked: model.enabled
                    onToggled: { model.enabled = checked; table.edited(); }
                }
                VarField {
                    property bool kvCell: true
                    objectName: "kvKeyField"
                    Layout.fillWidth: true; Layout.preferredWidth: table.keyColPreferred; Layout.minimumWidth: table.keyColMinimum
                    text: model.name
                    placeholderText: table.keyPlaceholder
                    tabHandler: function (dir) { table.moveFocus(dir); }
                    resolved: table.resolved
                    collection: table.collection
                    errorText: (table.uniqueNames && table.revision >= 0 && table.isDuplicateName(index))
                               ? Strings.t.duplicateNameHint : ""
                    onTextEdited: { if (model.name !== text) { model.name = text; table.edited(); } }
                }
                // file (fields mode only)
                Button {
                    property bool kvCell: table.allowFiles && model.type === "file"
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum
                    visible: table.allowFiles && model.type === "file"
                    text: model.fileName && model.fileName.length > 0
                          ? model.fileName.split("/").pop() : Strings.t.chooseFile
                    icon.name: "document-open"
                    onClicked: table.pickFile(index)
                }
                // value masked when it's a secret (TextField has echoMode) + eye to
                // peek at the value without unchecking "secret"
                TextField {
                    id: secretField
                    property bool kvCell: !(table.allowFiles && model.type === "file") && table.secretColumn && model.secret
                    property bool revealed: false
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum
                    visible: !(table.allowFiles && model.type === "file") && table.secretColumn && model.secret
                    text: model.value
                    placeholderText: Strings.t.secretInVault
                    echoMode: revealed ? TextInput.Normal : TextInput.Password
                    // same metric as VarField: without this the echoMode bullets
                    // change the row height depending on the font
                    implicitHeight: Kirigami.Units.gridUnit * 1.7
                    topPadding: 3; bottomPadding: 3; leftPadding: 6
                    rightPadding: revealButton.width + Kirigami.Units.smallSpacing
                    onTextEdited: { if (model.value !== text) { model.value = text; table.edited(); } }
                    // Tab/Shift+Tab move to the adjacent cell (same navigation as VarField)
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                            table.moveFocus(e.key === Qt.Key_Backtab ? -1 : 1);
                            e.accepted = true;
                        }
                    }
                    ToolButton {
                        id: revealButton
                        objectName: "kvRevealButton"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: Kirigami.Units.smallSpacing / 2
                        width: 24; height: 24
                        flat: true
                        icon.name: secretField.revealed ? "view-hidden" : "view-visible"
                        icon.width: 17; icon.height: 17
                        onClicked: secretField.revealed = !secretField.revealed
                        ToolTip.text: secretField.revealed ? Strings.t.hideSecret : Strings.t.showSecret
                        ToolTip.visible: hovered
                    }
                }
                // normal value with {{variable}} highlighting
                VarField {
                    id: valArea
                    property bool kvCell: !(table.allowFiles && model.type === "file") && !(table.secretColumn && model.secret)
                    objectName: "kvValueField"
                    Layout.fillWidth: true; Layout.preferredWidth: table.valueColPreferred; Layout.minimumWidth: table.valueColMinimum
                    visible: !(table.allowFiles && model.type === "file") && !(table.secretColumn && model.secret)
                    text: model.value
                    placeholderText: Strings.t.value
                    tabHandler: function (dir) { table.moveFocus(dir); }
                    resolved: table.resolved
                    collection: table.collection
                    onTextEdited: { if (model.value !== text) { model.value = text; table.edited(); } }
                }
                ComboBox {
                    property bool kvCell: table.allowFiles
                    Layout.preferredWidth: table.typeColWidth; Layout.minimumWidth: table.typeColWidth; Layout.maximumWidth: table.typeColWidth
                    visible: table.allowFiles
                    model: ["text", "file"]
                    currentIndex: model.type === "file" ? 1 : 0
                    onActivated: {
                        kvList.model.setProperty(index, "type", currentText);
                        table.edited();
                    }
                }
                // scope: compact chip (Global / N collections) that opens a popover
                Rectangle {
                    id: scopeChip
                    objectName: "scopeChip"
                    visible: table.scopeColumn
                    Layout.fillWidth: true; Layout.preferredWidth: table.scopeColPreferred; Layout.minimumWidth: table.scopeColMinimum
                    implicitHeight: scopeRow.implicitHeight + 8
                    radius: 4
                    readonly property color tint: table.scopeColor !== null ? table.scopeColor(index) : Kirigami.Theme.textColor
                    color: table.scopeColor !== null
                           ? Qt.rgba(tint.r, tint.g, tint.b, 0.15) : Kirigami.Theme.alternateBackgroundColor
                    border.width: 1
                    border.color: table.scopeColor !== null ? tint : Kirigami.Theme.disabledTextColor
                    RowLayout {
                        id: scopeRow
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 4
                        Kirigami.Icon {
                            visible: table.scopeIcon !== null
                            source: table.scopeIcon !== null ? table.scopeIcon(index) : ""
                            color: scopeChip.tint
                            implicitWidth: 14; implicitHeight: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            text: table.scopeText !== null ? table.scopeText(index) : ""
                            color: scopeChip.tint
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var g = mapToItem(null, width / 2, height);
                            table.scopeRequested(index, g.x, g.y);
                        }
                        ToolTip.text: table.scopeTooltip !== null ? table.scopeTooltip(index) : ""
                        ToolTip.visible: containsMouse
                    }
                }
                CheckBox {
                    property bool kvCell: table.secretColumn
                    Layout.preferredWidth: table.secretColWidth; Layout.minimumWidth: table.secretColWidth; Layout.maximumWidth: table.secretColWidth
                    visible: table.secretColumn
                    checked: model.secret === true
                    onToggled: { model.secret = checked; table.edited(); }
                }
                ToolButton {
                    property bool kvCell: true
                    Layout.preferredWidth: table.removeColWidth; Layout.minimumWidth: table.removeColWidth; Layout.maximumWidth: table.removeColWidth
                    icon.name: "list-remove"
                    onClicked: table.tryRemove(index)
                    ToolTip.text: Strings.t.removeRow
                    ToolTip.visible: hovered
                }
            }
        }

        Item {
            visible: table.empty
            Layout.fillWidth: true
            Layout.fillHeight: true
            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                title: Strings.t.nothingHere
                actionText: Strings.t.add
                actionIcon: "list-add"
                onActionTriggered: { table.addRequested(); table.edited(); }
            }
        }

        ToolButton {
            visible: !table.empty
            icon.name: "list-add"
            text: Strings.t.add
            display: AbstractButton.TextBesideIcon
            Layout.leftMargin: table.colSpacing
            Layout.bottomMargin: table.colSpacing
            onClicked: { table.addRequested(); table.edited(); }
        }
    }

    // row removal confirmation (same global delete config)
    Dialog {
        id: confirmRemove
        objectName: "confirmRemoveDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: Strings.t.remove
        header: DialogHeader { dialogTitle: confirmRemove.title }
        modal: true
        width: 380
        property int pendingIndex: -1
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Strings.t.removeRowQuestion }
            DialogActions {
                Button { text: Strings.t.cancel; onClicked: confirmRemove.close() }
                Button {
                    text: Strings.t.remove; Accessible.defaultButton: true
                    onClicked: {
                        if (confirmRemove.pendingIndex >= 0) {
                            table.model.remove(confirmRemove.pendingIndex);
                            table.edited();
                        }
                        confirmRemove.close();
                    }
                }
            }
        }
    }
}
