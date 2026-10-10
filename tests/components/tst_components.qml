import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../qml"
import "../../qml/Util.js" as Util
import "../../qml/js/VarTokens.js" as VarTokens

// Tests for the reusable components and the pure JsonTree logic.
TestCase {
    id: root
    name: "Components"
    when: windowShown

    // highlighter/clipboard stub that KvTable uses in the real context
    QtObject {
        id: varSupport
        function attach() {}
        function copyText(t) {}
    }

    // settings stub: KvTable checks settings.confirmDelete when removing a row
    QtObject {
        id: settings
        property bool confirmDelete: false
    }

    // already with one row: the ListView must be visible in the test's initial layout
    ListModel {
        id: kvModel
        ListElement { name: "key-x"; value: "value-x"; enabled: true }
    }
    HeaderTable { id: ht }
    JsonTree { id: tree }
    VarCompleter { id: comp }
    TextArea { id: emitProbe; onTextEdited: root.probeCount++ }
    property int probeCount: 0

    // setting `text` programmatically doesn't emit textEdited (only the user emits). The
    // popup must emit so the KvTable model (onTextEdited) updates when choosing.
    function test_varcompleter_choose_emits_edit() {
        root.probeCount = 0;
        emitProbe.text = "{{";
        comp.target = emitProbe;
        comp.tokenStart = 0;
        comp.partial = "";
        comp.choose("test");
        compare(emitProbe.text, "{{test}}");
        compare(root.probeCount, 1);
    }
    // standard dialog components (same spacing/padding in all modals)
    DialogActions {
        id: dialogActions
        Button { text: "A" }
        Button { text: "B" }
    }
    DialogHeader { id: dialogHeader; dialogTitle: "T" }

    // standard dialog body: it is the contentItem itself, so it sizes by content
    Dialog {
        id: testDialog
        contentItem: ColumnLayout {
            id: testDialogBody
            spacing: Kirigami.Units.smallSpacing
            Label { text: "msg" }
            DialogActions { Button { text: "Cancel" } Button { text: "OK" } }
        }
    }

    KvTable { id: kv; model: kvModel; width: 800; height: 400 }
    ResolvedVarsTable {
        id: rvt
        vars: [{ name: "a", value: "1", enabled: true }, { name: "b", value: "2", enabled: false }]
    }
    // KvTable branches exercised by tests (secret, file, row filter)
    ListModel {
        id: secretModel
        ListElement { name: "s"; value: "v"; enabled: true; secret: true; type: "text"; fileName: "" }
    }
    ListModel {
        id: fileModel
        ListElement { name: "f"; value: "caminho"; enabled: true; secret: false; type: "file"; fileName: "/tmp/a.txt" }
    }
    ListModel {
        id: filterModel
        ListElement { name: "f"; value: "1"; enabled: true }
    }
    KvTable { id: kvSecret; model: secretModel; secretColumn: true; width: 800; height: 300 }
    KvTable { id: kvFiles; model: fileModel; allowFiles: true; width: 800; height: 300 }
    KvTable { id: kvFilter; model: filterModel; width: 800; height: 200
              rowFilter: function (i) { return false; } }
    ListModel {
        id: scopeModel
        ListElement { name: "s"; value: "v"; enabled: true; secret: false; type: "text"; fileName: ""; scope: "collections"; collections: "" }
    }
    KvTable { id: kvScope; model: scopeModel; scopeColumn: true; width: 800; height: 300
              scopeText: function (i) { return "x" }
              scopeColor: function (i) { return "#ff0000" } }
    ListModel {
        id: dupModel
        ListElement { name: "dup"; value: "1"; enabled: true; secret: false; type: "text"; fileName: "" }
        ListElement { name: "dup"; value: "2"; enabled: true; secret: false; type: "text"; fileName: "" }
    }
    KvTable { id: kvDup; model: dupModel; uniqueNames: true; width: 800; height: 300 }
    VarField { id: vf; resolved: vfVars }
    property var vfVars: [{ name: "x", value: "1", enabled: true }]

    // the effective variables view doesn't show disabled ones
    function test_resolved_vars_filters_disabled() {
        compare(rvt.count, 1);
        compare(rvt.activeVars[0].name, "a");
    }

    // ...nor dynamic ones (they resolve, but aren't user variables)
    function test_resolved_vars_hides_dynamic() {
        rvt.vars = [
            { name: "a", value: "1", enabled: true },
            { name: "$randomUuid", value: "zzz", enabled: true, source: "dynamic" }
        ];
        compare(rvt.activeVars.map(function (v) { return v.name; }).join(","), "a");
        rvt.vars = [{ name: "a", value: "1", enabled: true }, { name: "b", value: "2", enabled: false }];
    }

    // sorts by source (global → collection → request) and, within it, by name
    function test_resolved_vars_order_by_source() {
        rvt.vars = [
            { name: "z", value: "1", source: "request", enabled: true },
            { name: "b", value: "2", source: "global", enabled: true },
            { name: "m", value: "4", source: "collection", enabled: true },
            { name: "c", value: "5", source: "request", enabled: true },
            { name: "off", value: "6", source: "global", enabled: false }
        ];
        compare(rvt.activeVars.map(function (v) { return v.name; }).join(","), "b,m,c,z");
        rvt.vars = [{ name: "a", value: "1", enabled: true }, { name: "b", value: "2", enabled: false }];
    }

    // standard dialog footer: constant spacing and padding, buttons on the right
    function test_dialog_actions_standard() {
        compare(dialogActions.spacing, Kirigami.Units.smallSpacing);
        compare(dialogActions.Layout.bottomMargin, Kirigami.Units.smallSpacing);
        compare(dialogActions.children.length, 3, "spacer + 2 buttons");
        verify(dialogActions.children[0].text === undefined, "first child is the spacer");
        compare(dialogActions.children[1].text, "A");
        compare(dialogActions.children[2].text, "B");
    }

    // standard dialog body: contentItem is the ColumnLayout and auto-sizes
    function test_dialog_content_autosizes() {
        compare(testDialogBody.spacing, Kirigami.Units.smallSpacing);
        verify(testDialog.implicitHeight > 0, "dialog sizes by content");
    }

    // standard dialog header
    function test_dialog_header_standard() {
        compare(dialogHeader.text, "T");
        compare(dialogHeader.type, Kirigami.Heading.Type.Primary);
        compare(dialogHeader.bottomPadding, 0);
    }

    // Enter on a focused footer button of the dialog triggers the click (Tab moves focus)
    function test_dialog_enter_clicks_focused_button() {
        var btnA = dialogActions.children[1];
        var btnB = dialogActions.children[2];
        var clicked = 0;
        btnB.clicked.connect(function () { clicked++; });
        btnB.forceActiveFocus();
        wait(20);
        compare(btnB.activeFocus, true, "focus on button B");
        keyClick(Qt.Key_Return);
        wait(20);
        compare(clicked, 1, "Enter clicks the focused button");
    }

    // the popup must not suggest the token being typed ("{{") nor names with braces
    function test_varcompleter_filters_braces() {
        comp.resolved = [
            { name: "test", enabled: true },
            { name: "{{test}}", enabled: true },
            { name: "{{", enabled: true },
            { name: "", enabled: true },
            { name: "off", enabled: false }
        ];
        comp.partial = "";
        var names = comp.matchingNames();
        compare(names.length, 1);
        compare(names[0], "test");
    }

    // header and row must use the SAME per-column width (the bug was fillWidth
    // with implicit preferred; now they use explicit, equal preferred/minimum)
    function test_kvtable_columns_aligned() {
        var hdr = findChild(kv, "kvHeader");
        var lv = findChild(kv, "kvList");
        verify(hdr !== null, "kvHeader not found");
        verify(lv !== null, "kvList not found");
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate not created");
        // header: [active, key, value, type, scope, secret, remove]
        // row:    [active, key, file, secret-value, value, type, scope, secret, remove]
        compare(hdr.children[0].Layout.preferredWidth, row.children[0].Layout.preferredWidth);   // active
        compare(hdr.children[1].Layout.preferredWidth, row.children[1].Layout.preferredWidth);   // key
        compare(hdr.children[1].Layout.minimumWidth, row.children[1].Layout.minimumWidth);
        compare(hdr.children[2].Layout.preferredWidth, row.children[4].Layout.preferredWidth);   // value
        compare(hdr.children[2].Layout.minimumWidth, row.children[4].Layout.minimumWidth);
        compare(hdr.children[6].Layout.preferredWidth, row.children[8].Layout.preferredWidth);   // remove
        // the three "faces" of the value column share the same width
        compare(row.children[2].Layout.preferredWidth, row.children[4].Layout.preferredWidth);
        compare(row.children[3].Layout.preferredWidth, row.children[4].Layout.preferredWidth);
    }

    function test_headertable_copy_text() {
        ht.headers = [{ name: "A", value: "1" }, { name: "B", value: "2" }];
        compare(ht.allHeadersText(), "A: 1\nB: 2");
        ht.headers = [];
    }

    function test_headertable_rows() {
        ht.headers = [{ name: "A", value: "1" }, { name: "B", value: "2" }];
        wait(50);
        var lv = findChild(ht, "headerList");
        verify(lv !== null);
        compare(lv.count, 2);

        ht.headers = [];
        wait(50);
        compare(lv.count, 0);
    }

    function test_jsontree_types() {
        compare(tree.typeOf(null), "null");
        compare(tree.typeOf([1, 2]), "array");
        compare(tree.typeOf({ a: 1 }), "object");
        compare(tree.typeOf("x"), "string");
        compare(tree.typeOf(3), "number");
        compare(tree.typeOf(true), "boolean");
    }

    function test_jsontree_preview() {
        compare(tree.previewOf([1, 2, 3], "array"), "[3]");
        compare(tree.previewOf({ a: 1, b: 2 }, "object"), "{2}");
        compare(tree.previewOf("abc", "string"), "\"abc\"");
        compare(tree.previewOf(7, "number"), "7");
    }

    function test_jsontree_toggle() {
        tree.load('{"a":{"b":1}}');
        wait(50);
        compare(tree.isOpenAt("$.a"), true);   // depth 0 is open by default
        tree.toggle("$.a");
        compare(tree.isOpenAt("$.a"), false);  // records explicit state
        tree.toggle("$.a");
        compare(tree.isOpenAt("$.a"), true);
    }

    function test_jsontree_invalid() {
        tree.load("not json");
        wait(50);
        compare(tree.root, undefined);
    }

    function test_kvtable_rows() {
        kvModel.clear();
        kvModel.append({ name: "a", value: "1", enabled: true });
        wait(50);
        var lv = findChild(kv, "kvList");
        verify(lv !== null);
        compare(lv.count, 1);

        kvModel.append({ name: "b", value: "2", enabled: true });
        wait(50);
        compare(lv.count, 2);

        kvModel.clear();
        wait(50);
        compare(lv.count, 0);
    }

    // with confirmation on, tryRemove does NOT remove until confirmed
    function test_kvtable_remove_needs_confirm() {
        settings.confirmDelete = true;
        kvModel.clear();
        kvModel.append({ name: "x", value: "1", enabled: true });
        wait(50);
        kv.tryRemove(0);
        wait(50);
        compare(kvModel.count, 1);           // waits for confirmation
        var dlg = findChild(kv, "confirmRemoveDialog");
        if (dlg) dlg.close();
        kvModel.clear();
    }

    // with confirmation off, tryRemove removes directly
    function test_kvtable_remove_direct() {
        settings.confirmDelete = false;
        kvModel.clear();
        kvModel.append({ name: "x", value: "1", enabled: true });
        wait(50);
        compare(kvModel.count, 1);
        kv.tryRemove(0);
        compare(kvModel.count, 0);
    }

    // Tab/Shift+Tab move focus between the table's editable cells
    function test_kvtable_tab_navigates_cells() {
        settings.confirmDelete = false;
        kvModel.clear();
        kvModel.append({ name: "a", value: "1", enabled: true });
        wait(50);
        var lv = findChild(kv, "kvList");
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate not created");
        var keyField = row.children[1];
        var valField = row.children[4];
        keyField.forceActiveFocus();
        wait(20);
        compare(keyField.activeFocus, true, "initial focus on the key field");
        keyClick(Qt.Key_Tab);
        wait(20);
        compare(valField.activeFocus, true, "Tab goes to the value field");
        keyClick(Qt.Key_Backtab);
        wait(20);
        compare(keyField.activeFocus, true, "Shift+Tab goes back to the key field");
        kvModel.clear();
    }

    // ---- Util.js: pure domain ----
    function test_util_fmtSize() {
        compare(Util.fmtSize(512), "512 B");
        compare(Util.fmtSize(2048), "2.0 KB");
        compare(Util.fmtSize(2 * 1048576), "2.0 MB");
    }

    function test_util_parseCurl() {
        var r = Util.parseCurl("curl -X POST 'https://x/y' -H 'Content-Type: application/json' -d '{\"a\":1}'");
        compare(r.method, "POST");
        compare(r.url, "https://x/y");
        compare(r.headers.length, 1);
        compare(r.bodyType, "json");
        compare(r.body, '{"a":1}');
    }

    function test_util_parseCurl_defaults() {
        var r = Util.parseCurl("curl https://x/y");
        compare(r.method, "GET");
        compare(r.bodyType, "none");
        compare(r.auth.type, "none");
    }

    function test_util_parseCurl_basicAuth() {
        var r = Util.parseCurl("curl -u user:pass https://x/y");
        compare(r.auth.type, "basic");
        compare(r.auth.user, "user");
        compare(r.auth.pass, "pass");
    }

    function test_util_exportCurl() {
        var s = Util.exportCode({ method: "GET", url: "https://x/y",
                                  headers: [{ name: "A", value: "1" }], body: "" });
        verify(s.indexOf("curl -X GET 'https://x/y'") === 0);
        verify(s.indexOf("-H 'A: 1'") >= 0);

        var withBody = Util.exportCode({ method: "POST", url: "https://x/y",
                                         headers: [], body: "oi" });
        verify(withBody.indexOf("-d 'oi'") >= 0);
    }

    function test_vartokens() {
        var rv = [{ name: "test", enabled: true }, { name: "off", enabled: false },
                  { name: "{{a}}", enabled: true }, { name: "", enabled: true }];
        compare(VarTokens.matchingNames(rv, ""), ["test"]);
        compare(VarTokens.matchingNames(rv, "te"), ["test"]);
        compare(VarTokens.matchingNames(rv, "z"), []);
        compare(VarTokens.tokenAt("x {{base}}/u", 5).name, "base");
        compare(VarTokens.tokenAt("x {{base}}/u", 1), null);
        compare(VarTokens.valueOf(rv, "test").name, "test");
        compare(VarTokens.valueOf(rv, "nope"), null);
    }

    // dynamic variables reach autocomplete/hover through the resolved list (source "dynamic"),
    // but only appear once the user types `$` (a plain `{{` shows just their own variables)
    function test_vartokens_dynamic() {
        var rv = [{ name: "$randomTimestamp", value: "1", enabled: true, source: "dynamic" },
                  { name: "token", value: "x", enabled: true, source: "collection" }];
        compare(VarTokens.matchingNames(rv, ""), ["token"]);
        compare(VarTokens.matchingNames(rv, "$"), ["$randomTimestamp"]);
        compare(VarTokens.matchingNames(rv, "$time"), []);
        compare(VarTokens.matchingNames(rv, "$randomT"), ["$randomTimestamp"]);
        compare(VarTokens.matchingNames(rv, "tok"), ["token"]);
        compare(VarTokens.valueOf(rv, "$randomTimestamp").value, "1");
    }

    // canonical JSON: ignores key order (it's what decides dirty on undo)
    function test_util_stableStringify() {
        compare(Util.stableStringify({ a: 1, b: 2 }), Util.stableStringify({ b: 2, a: 1 }));
        compare(Util.stableStringify({ a: { x: 1, y: 2 }, b: [1, 2] }),
                Util.stableStringify({ b: [1, 2], a: { y: 2, x: 1 } }));
        verify(Util.stableStringify({ a: 1 }) !== Util.stableStringify({ a: 2 }));
        verify(Util.stableStringify([1, 2]) !== Util.stableStringify([2, 1]));   // array order matters
        // change and return to the original => same snapshot (dirty clears)
        var base = Util.stableStringify({ url: "x", vars: [{ name: "a", value: "1" }] });
        var cur = Util.stableStringify({ vars: [{ value: "1", name: "a" }], url: "y" });
        verify(cur !== base);
        cur = Util.stableStringify({ vars: [{ name: "a", value: "1" }], url: "x" });
        compare(cur, base);
    }

    // [A,B,C,D]: B(1) -> insert before D(to=3) => [A,C,B,D]
    function test_util_tabMove() {
        var m = Util.tabMove(4, 1, 3, 1);
        compare(m.dest, 2);
        compare(m.current, 2);          // the moved tab itself stays active
        compare(Util.tabMove(4, 1, 3, 2).current, 1);   // C moved to the left
        compare(Util.tabMove(4, 1, 3, 3).current, 3);   // D doesn't move
        compare(Util.tabMove(4, 1, 3, 0).current, 0);   // A doesn't move

        // [A,B,C,D]: D(3) -> insert before B(to=1) => [A,D,B,C]
        compare(Util.tabMove(4, 3, 1, 3).dest, 1);
        compare(Util.tabMove(4, 3, 1, 1).current, 2);
        compare(Util.tabMove(4, 3, 1, 2).current, 3);

        // no-op: insert right after itself
        compare(Util.tabMove(4, 1, 2, 0), null);
        // bounds: insert at the end
        compare(Util.tabMove(4, 0, 4, 0).dest, 3);
    }

    // pin/unpin (VS Code): unpin returns the tab to preview and keeps only one
    function test_util_tabPin() {
        // pin the preview tab -> it stops being preview
        var m = Util.tabPin([{ pinned: false, preview: true }, { pinned: false, preview: false }], 0);
        compare(m.length, 1);
        compare(m[0].index, 0);
        compare(m[0].pinned, true);
        compare(m[0].preview, false);

        // unpin -> back to preview
        m = Util.tabPin([{ pinned: true, preview: false }], 0);
        compare(m.length, 1);
        compare(m[0].pinned, false);
        compare(m[0].preview, true);

        // unpin with another preview open -> only one preview remains (the last)
        m = Util.tabPin([{ pinned: true, preview: false }, { pinned: false, preview: true }], 0);
        compare(m.length, 2);
        compare(m[0].preview, true);
        compare(m[1].index, 1);
        compare(m[1].preview, false);

        // pin a tab that isn't preview -> doesn't touch the active preview
        m = Util.tabPin([{ pinned: false, preview: false }, { pinned: false, preview: true }], 0);
        compare(m.length, 1);
        compare(m[0].pinned, true);

        // invalid index
        compare(Util.tabPin([], 0).length, 0);
    }

    // persisted session: only pinned tabs return when reopening the app
    function test_util_sessionPaths() {
        // pinned in the middle, non-pinned discarded; active remapped to the saved position
        var s = Util.sessionPaths([
            { relPath: "a", pinned: true },
            { relPath: "b", pinned: false },
            { relPath: "c", pinned: true }
        ], 2);
        compare(s.paths.length, 2);
        compare(s.paths[0], "a");
        compare(s.paths[1], "c");
        compare(s.current, 1);

        // active was non-pinned → falls back to 0
        s = Util.sessionPaths([{ relPath: "a", pinned: true }, { relPath: "b", pinned: false }], 1);
        compare(s.paths.length, 1);
        compare(s.current, 0);

        // none pinned → empty list
        s = Util.sessionPaths([{ relPath: "b", pinned: false }], 0);
        compare(s.paths.length, 0);
        compare(s.current, 0);
    }

    // ListModel + delegate: a role created via setProperty AFTER the delegate already
    // exists doesn't reach the delegate (model.pinned stays undefined forever). It was the
    // cause of the pinned tab showing the X again after restoring the session: the append
    // didn't declare "pinned"/"preview". That's why EVERY append declares both roles.
    ListModel { id: roleModelLate }
    ListModel { id: roleModelEarly }
    ListView {
        id: roleViewLate
        width: 100; height: 60
        model: roleModelLate
        delegate: Text { text: String(model.pinned) }
    }
    ListView {
        id: roleViewEarly
        width: 100; height: 60
        model: roleModelEarly
        delegate: Text { text: String(model.pinned) }
    }

    function test_listmodel_roles_declared() {
        roleModelLate.append({ name: "a" });            // without declaring "pinned"
        wait(30);
        roleModelLate.setProperty(0, "pinned", true);   // role created late
        wait(50);
        compare(roleViewLate.itemAtIndex(0).text, "undefined");   // delegate doesn't see the late role

        roleModelEarly.append({ name: "b", pinned: false });        // role declared in the append
        wait(30);
        roleModelEarly.setProperty(0, "pinned", true);
        wait(50);
        compare(roleViewEarly.itemAtIndex(0).text, "true");         // delegate keeps up
    }

    // VarField embeds the VarCompleter and propagates `resolved` (the font.family bug
    // went unnoticed because there was no instantiation test)
    function test_varfield_wiring() {
        var c = findChild(vf, "varCompleter");
        verify(c !== null, "VarCompleter not attached to VarField");
        verify(c.target === vf, "completer target must be the VarField");
        compare(c.resolved.length, 1);
        compare(c.resolved[0].name, "x");
    }

    // single-line field: Enter doesn't insert a line break (it's a TextArea because of highlighting)
    function test_varfield_enter_does_not_break_line() {
        vf.text = "abc";
        vf.forceActiveFocus();
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Enter);
        compare(vf.text.indexOf("\n"), -1, "Enter doesn't break the line");
        compare(vf.text, "abc");
    }

    // Secret column: masked field (echoMode Password) + associated normal editor
    function test_kvtable_secret_column() {
        wait(50);
        var lv = findChild(kvSecret, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate not created");
        compare(row.children.length, 9, "number of delegate children");
        compare(row.children[3].echoMode, TextInput.Password, "masked field");
        compare(row.children[4].placeholderText, "Value", "normal editor");
        // height equal to the normal editor: the echoMode dots must not shift the row
        compare(row.children[3].implicitHeight, row.children[4].implicitHeight, "secret field height");
        // peek eye: toggles echoMode without unchecking secret
        var eye = findChild(row.children[3], "kvRevealButton");
        verify(eye !== null, "reveal eye not found");
        eye.clicked();
        compare(row.children[3].echoMode, TextInput.Normal, "revealed");
        compare(row.children[3].text, "v", "accessible value");
        eye.clicked();
        compare(row.children[3].echoMode, TextInput.Password, "masked again");
    }

    // fields mode: file button in place of the value editor
    function test_kvtable_file_column() {
        wait(50);
        var lv = findChild(kvFiles, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate not created");
        compare(row.children[2].icon.name, "document-open", "file button");
    }

    function test_kvtable_row_filter() {
        filterModel.clear();
        filterModel.append({ name: "f", value: "1", enabled: true });
        wait(50);
        var lv = findChild(kvFilter, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate not created");
        compare(row.shown, false, "filtered row");
        compare(row.height, 0, "zero height when filtered");
        filterModel.clear();
    }

    // scope chip uses the color from the scopeColor callback
    function test_kvtable_scope_color() {
        wait(50);
        var lv = findChild(kvScope, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate not created");
        var chip = findChild(row, "scopeChip");
        verify(chip !== null, "scopeChip not found");
        compare(String(chip.tint), "#ff0000");
    }

    // duplicate name (uniqueNames) marks the field with erroText; without uniqueNames, it doesn't
    function test_kvtable_duplicate_name_highlight() {
        wait(50);
        var lv = findChild(kvDup, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate not created");
        compare(row.children[1].errorText.length > 0, true, "duplicate name marks error");
        var lv2 = findChild(kvSecret, "kvList");
        compare(lv2.itemAtIndex(0).children[1].errorText.length === 0, true, "without uniqueNames it doesn't mark");
    }

    function test_util_q() {
        compare(Util.q("simples"), "'simples'");
        compare(Util.q("a'b"), "'a'\\''b'");   // escapes apostrophe for the shell
    }

    function test_util_tokenizeCurl() {
        compare(JSON.stringify(Util.tokenizeCurl("a 'b c' d")), '["a","b c","d"]');
        compare(JSON.stringify(Util.tokenizeCurl('x "y z"')), '["x","y z"]');
        compare(JSON.stringify(Util.tokenizeCurl("a \\\nb")), '["a","b"]');   // line continuation
    }

    function test_jsontree_empty() {
        compare(tree.previewOf([], "array"), "[0]");
        compare(tree.previewOf({}, "object"), "{0}");
        compare(tree.typeOf([]), "array");
        compare(tree.typeOf({}), "object");
    }

    function test_jsontree_deep() {
        tree.load('{"a":{"b":{"c":1}}}');
        wait(50);
        compare(tree.isOpenAt("$.a"), true);
        compare(tree.isOpenAt("$.a.b"), true);   // depth 1 still opens by default
    }
}
