import QtQuick
import QtQuick.Controls
import QtTest
import org.kde.kirigami as Kirigami
import "../../qml"

// Screen behavior: instantiates the real Main (with backend/settings injected
// by tst_app.cpp) and exercises AppController — tabs, preview/pin, session,
// apply/collect request, creation target, environment/collection singleton tabs.
TestCase {
    id: root
    name: "AppBehavior"
    when: windowShown

    Component { id: appComponent; Main {} }
    property var win: null

    function init() {
        if (win) { win.destroy(); win = null; }
        win = appComponent.createObject(null);
        verify(win, "could not create Main");
        win.visible = true;
    }
    function cleanupTestCase() {
        if (win) { win.destroy(); win = null; }
    }

    function baseReq(method) {
        return { method: method !== undefined ? method : "GET", url: "http://example/x",
                 params: [], headers: [], fields: [], body: "", bodyType: "none",
                 auth: { type: "none" }, vars: [] };
    }

    function test_open_and_close_tab() {
        backend.saveRequest("t/r1", baseReq());
        win.appController.openRequest("t/r1");
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.currentTab, 0);
        win.appController.closeTab(0);
        compare(win.appController.tabsModel.count, 0);
        compare(win.appController.currentTab, -1);
    }

    function test_preview_tab_and_pin() {
        backend.saveRequest("t/a", baseReq("GET"));
        backend.saveRequest("t/b", baseReq("POST"));
        win.appController.openRequest("t/a");
        compare(win.appController.tabsModel.count, 1);
        // the second request reuses the preview (transient) tab
        win.appController.openRequest("t/b");
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.tabsModel.get(0).relPath, "t/b");
        // pinning makes the next one open a new tab
        win.appController.pinTab(0);
        win.appController.openRequest("t/a");
        compare(win.appController.tabsModel.count, 2);
    }

    function test_switch_applies_editor() {
        backend.saveRequest("t/g", baseReq("GET"));
        backend.saveRequest("t/p", baseReq("POST"));
        win.appController.openRequest("t/g");
        win.appController.pinTab(0);
        win.appController.openRequest("t/p");
        compare(win.appController.currentTab, 1);
        win.appController.switchTab(0);
        compare(win.appController.collectRequest().method, "GET");
        win.appController.switchTab(1);
        compare(win.appController.collectRequest().method, "POST");
    }

    function test_apply_and_collect_roundtrip() {
        var r = baseReq("PUT");
        r.url = "https://h/p";
        r.bodyType = "json";
        r.body = "{\"x\":1}";
        r.params = [{ name: "q", value: "1", enabled: true }];
        r.vars = [{ name: "v", value: "2", enabled: true }];
        r.auth = { type: "bearer", token: "tok" };
        win.appController.applyRequest(r, "");
        var c = win.appController.collectRequest();
        compare(c.method, "PUT");
        compare(c.url, "https://h/p");
        compare(c.bodyType, "json");
        compare(c.body, "{\"x\":1}");
        compare(c.params.length, 1);
        compare(c.vars.length, 1);
        compare(c.auth.type, "bearer");
    }

    function test_target_folder() {
        win.appController.selectedPath = "col/sub/req";
        win.appController.selectedIsFolder = false;
        compare(win.appController.targetFolder(), "col/sub");
        win.appController.selectedIsFolder = true;
        compare(win.appController.targetFolder(), "col/sub/req");
        win.appController.selectedPath = "";
        compare(win.appController.targetFolder(), "");
    }

    function test_env_tab_singleton() {
        win.appController.openEnvTab("");
        var n = win.appController.tabsModel.count;
        win.appController.openEnvTab("");
        compare(win.appController.tabsModel.count, n);   // doesn't duplicate
        compare(win.appController.showingEnv, true);
    }

    function test_collection_tab() {
        backend.createFolder("colA");
        win.appController.openCollection("colA");
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.showingCollection, true);
        compare(win.appController.collectionPath, "colA");
    }

    function test_session_restore_pins_and_environment() {
        backend.saveRequest("t/s1", baseReq());
        win.appController.restoreSessionTabs(["t/s1", "__environment__"]);
        compare(win.appController.tabsModel.count, 2);
        compare(win.appController.tabsModel.get(0).pinned, true);
        compare(win.appController.tabsModel.get(0).relPath, "t/s1");
        compare(win.appController.tabsModel.get(1).isEnvironment, true);
    }

    function test_reopen_closed() {
        backend.saveRequest("t/rc", baseReq());
        win.appController.openRequest("t/rc");
        win.appController.pinTab(0);
        win.appController.closeTab(0);
        compare(win.appController.tabsModel.count, 0);
        win.appController.reopenClosed();
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.tabsModel.get(0).relPath, "t/rc");
    }

    // ---- editing: dirty / unpin / revert / save ----
    function test_edit_marks_dirty_and_reverts() {
        backend.saveRequest("t/e", baseReq());
        win.appController.openRequest("t/e");
        compare(win.appController.tabsModel.get(0).dirty, false);
        win.appController.requestEditor.url = "http://mudou";
        win.appController.markDirty();
        compare(win.appController.tabsModel.get(0).dirty, true);
        compare(win.appController.currentDirty, true);
        win.appController.revertCurrent();
        compare(win.appController.tabsModel.get(0).dirty, false);
        compare(win.appController.collectRequest().url, "http://example/x");
    }

    function test_edit_unpins_preview() {
        backend.saveRequest("t/pv", baseReq());
        win.appController.openRequest("t/pv");
        compare(win.appController.tabsModel.get(0).preview, true);
        win.appController.requestEditor.url = "http://x2";
        win.appController.markDirty();
        compare(win.appController.tabsModel.get(0).preview, false);   // editing pins the tab
    }

    function test_save_persists_and_clears_dirty() {
        backend.saveRequest("t/sv", baseReq());
        win.appController.openRequest("t/sv");
        win.appController.requestEditor.url = "http://salvo";
        win.appController.markDirty();
        win.appController.saveCurrent();
        compare(backend.loadRequest("t/sv").url, "http://salvo");
        compare(win.appController.tabsModel.get(0).dirty, false);
    }

    // typing in the URL field triggers textEdited → markDirty (same keyboard path)
    function test_edit_triggers_dirty() {
        backend.saveRequest("t/kb", baseReq());
        win.appController.openRequest("t/kb");
        compare(win.appController.tabsModel.get(0).dirty, false);
        var f = win.appController.requestEditor.urlInput;
        verify(f, "URL field exposed");
        f.text = "http://digitado";
        f.textEdited();
        compare(win.appController.tabsModel.get(0).dirty, true);
    }

    // ---- reorder / move ----
    function test_move_tab_reorders() {
        backend.saveRequest("t/1", baseReq("GET"));
        backend.saveRequest("t/2", baseReq("POST"));
        win.appController.openRequest("t/1");
        win.appController.pinTab(0);
        win.appController.openRequest("t/2");
        compare(win.appController.tabsModel.get(0).relPath, "t/1");
        compare(win.appController.tabsModel.get(1).relPath, "t/2");
        win.appController.moveTab(0, 2);   // move t/1 to the end
        compare(win.appController.tabsModel.get(0).relPath, "t/2");
        compare(win.appController.tabsModel.get(1).relPath, "t/1");
    }

    function test_tab_index_at_insertion() {
        backend.saveRequest("t/idx", baseReq());
        win.appController.openRequest("t/idx");
        wait(50);
        compare(win.appController.tabIndexAt(-1), 0);       // before the first
        compare(win.appController.tabIndexAt(100000), 1);   // after the last
    }

    // ---- deletion respects settings.confirmDelete ----
    function test_delete_respects_confirmation() {
        backend.saveRequest("t/del", baseReq());
        win.appController.selectedPath = "t/del";
        settings.confirmDelete = true;
        win.appController.askDelete();
        compare(backend.loadRequest("t/del").method, "GET");   // dialog open, nothing deleted
        settings.confirmDelete = false;
        win.appController.askDelete();
        compare(backend.loadRequest("t/del").method, undefined);   // deleted
        settings.confirmDelete = true;   // restores the default
    }

    // ---- cURL import opens the imported request ----
    function test_import_curl() {
        win.appController.importCurl("curl -X POST https://example/api -H 'X-Test: 1' -d '{\"a\":1}'");
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.collectRequest().method, "POST");
        verify(win.appController.collectRequest().headers.length >= 1);
    }

    // indent guides: one line per ancestor level (depth = number of guides)
    function test_indent_guides_by_depth() {
        backend.saveRequest("col/sub/r", baseReq());
        win.appController.reloadTree();
        wait(100);   // rebuildTree is coalesced via Qt.callLater

        var tree = win.appController.treeModel;
        var idx = -1;
        for (var i = 0; i < tree.count; i++)
            if (tree.get(i).relPath === "col/sub/r") { idx = i; break; }
        verify(idx >= 0, "request in the tree");

        var del = win.appController.sidebar.view.itemAtIndex(idx);
        verify(del, "delegate visible");
        compare(del.itemDepth, 2);   // col(0) > sub(1) > r(2)

        var rep = findChild(del, "indentRepeater");
        verify(rep, "indent repeater present");
        compare(rep.count, 2);       // one guide per ancestor level
    }

    // collapse/expand keeps every row in the model and only flips the "hidden"
    // role (the delegate animates its height to 0). Rebuilding/filtering the
    // model here would reset the ListView and kill the open/close animation.
    function test_collapse_keeps_rows_and_marks_hidden() {
        backend.saveRequest("collapsecol/sub/r", baseReq());
        win.appController.reloadTree();
        wait(100);

        var tree = win.appController.treeModel;
        var before = tree.count;
        win.appController.toggleCollapse("collapsecol");

        var hiddenCount = 0;
        for (var i = 0; i < tree.count; i++) {
            var e = tree.get(i);
            if (e.relPath === "collapsecol") compare(e.collapsed, true);
            else if (e.relPath.indexOf("collapsecol/") === 0) { compare(e.hidden, true); hiddenCount++; }
        }
        compare(tree.count, before, "rows are kept, not removed");
        compare(hiddenCount, 2, "sub + r marked hidden");

        win.appController.toggleCollapse("collapsecol");
        for (var j = 0; j < tree.count; j++)
            if (tree.get(j).relPath.indexOf("collapsecol/") === 0)
                compare(tree.get(j).hidden, false, "expanded again");
    }

    // toggling the side panels actually hides them (guards the imperative
    // splitWidth/preferredWidth handling; a broken binding would leave visible=true)
    function test_panels_toggle() {
        win.appController.sidebarVisible = false;
        wait(300);
        compare(win.appController.sidebar.visible, false);
        win.appController.sidebarVisible = true;
        wait(300);
        compare(win.appController.sidebar.visible, true);

        win.appController.responseVisible = false;
        wait(300);
        compare(win.appController.responsePane.visible, false);
    }

    // drag destination: folder target, parent of a request target, or root ("")
    // when dropped outside the rows (root=true)
    function test_drag_destination() {
        var c = win.appController;
        compare(c.dragDestination("col/req", "", false, true), "");              // dropped outside → root
        compare(c.dragDestination("req", "", false, true), "req");              // already at root → no-op
        compare(c.dragDestination("col/req", "col/sub", true, false), "col/sub");   // into a folder
        compare(c.dragDestination("col/req", "col/sub/other", false, false), "col/sub"); // parent of a request
        compare(c.dragDestination("col/req", "col/req", false, false), "col/req");  // onto itself → no-op
        compare(c.dragDestination("col/req", "", false, false), "col/req");     // no target → no move
    }

    // a request can be moved to the root (top level, sibling of the collections)
    function test_move_request_to_root() {
        backend.saveRequest("roothold/req", baseReq());
        win.appController.reloadTree();
        wait(100);
        win.appController.moveEntry("roothold/req", "");
        wait(100);
        var tree = win.appController.treeModel;
        var found = false;
        for (var i = 0; i < tree.count; i++)
            if (tree.get(i).relPath === "req" && !tree.get(i).isFolder) found = true;
        verify(found, "request now at the root");
    }

    // Main's FolderPicker must receive the settings screen's directory field
    // (regression: `dirField: dirField` pointed to an id from another file → null)
    function test_folder_picker_wired() {
        var fp = findChild(win, "folderPicker");
        verify(fp, "FolderPicker present in Main");
        verify(fp.dirField, "directory field wired to the FolderPicker");
        compare(fp.dirField.text, settings.storageDir);
    }

    // injected models actually reach the editor's children (QML scope regression:
    // `X: X` with a same-named property becomes self-reference and arrives undefined)
    function test_editor_models_wired() {
        backend.saveRequest("t/w", baseReq());
        win.appController.openRequest("t/w");
        wait(50);
        var ed = win.appController.requestEditor;
        var rve = findChild(ed, "reqVarsEditor");
        var be = findChild(ed, "bodyEditor");
        verify(rve, "variables tab present");
        verify(be, "body editor present");
        compare(rve.requestVarsModel, win.appController.requestVarsModel);   // === (mesmo objeto)
        compare(be.fieldsModel, win.appController.fieldsModel);
    }

    // dynamic variables are offered to autocomplete/hover (source "dynamic") for every request
    function test_dynamic_variables_offered() {
        backend.saveRequest("dyn/r", baseReq());
        win.appController.openRequest("dyn/r");
        var names = win.appController.resolvedVars.map(function (v) { return v.name; });
        verify(names.indexOf("$randomTimestamp") >= 0);
        verify(win.appController.resolvedVars.filter(function (v) { return v.name === "$randomTimestamp"; })[0].source === "dynamic");
    }

    // an unresolved {{ref}} inside the request's own variables is flagged (red highlight)
    function test_missing_ref_in_request_variable() {
        backend.saveRequest("dv/r", baseReq());
        win.appController.openRequest("dv/r");
        win.appController.requestVarsModel.append({ name: "{{gone}}", value: "v", enabled: true });
        win.appController.refreshResolved();
        verify(win.appController.missingVars.indexOf("gone") >= 0, "request variable reference flagged");
    }

    // ...and inside the collection's own variables
    function test_missing_ref_in_collection_variable() {
        backend.createFolder("colmiss");
        win.appController.openCollection("colmiss");
        win.appController.collectionVarsModel.append({ name: "{{gone2}}", value: "v", enabled: true });
        win.appController.refreshCollectionResolved();
        verify(win.appController.missingVars.indexOf("gone2") >= 0, "collection variable reference flagged");
    }

    // ...and inside the environment's own variables
    function test_missing_ref_in_environment_variable() {
        backend.saveEnvironment("misse", []);
        win.appController.openEnvTab("misse");
        win.appController.envScreen.varsModel.append({ name: "{{gone3}}", value: "v", enabled: true,
                                                       scope: "all", collections: "" });
        win.appController.envScreen.refreshResolved();
        verify(win.appController.missingVars.indexOf("gone3") >= 0, "environment variable reference flagged");
    }

    // a URL longer than the field scrolls the text (not the box) so the caret stays visible
    function test_long_url_scrolls_to_cursor() {
        backend.saveRequest("scroll/r", baseReq());
        win.appController.openRequest("scroll/r");
        wait(50);
        var f = win.appController.requestEditor.urlInput;
        f.text = "http://example.com/" + "a".repeat(300);
        wait(50);                                   // let the layout settle with the long text
        var x0 = f.mapToItem(null, 0, 0).x, w0 = f.width;
        f.forceActiveFocus();
        f.cursorPosition = f.text.length;
        wait(80);
        verify(f.scroll > 0, "URL text scrolled to the caret");
        verify(f.leftPadding < f.horizontalPadding, "text offset via padding");
        compare(f.mapToItem(null, 0, 0).x, x0, "the URL box didn't move on screen");
        compare(f.width, w0, "the URL box kept its width");
    }

    // the concise "unresolved" message no longer lists every variable
    function test_unresolved_status_is_concise() {
        var vars = [];
        for (var i = 0; i < 20; i++) vars.push("{{missing" + i + "}}");
        backend.send({ method: "GET", url: "http://127.0.0.1:1/" + vars.join(""),
                       params: [], headers: [], fields: [], body: "", bodyType: "none",
                       auth: { type: "none" }, vars: [] }, "");
        wait(80);
        var label = findChild(win, "statusLabel");
        verify(label, "status label present");
        verify(label.text.indexOf("unresolved variables in the request") >= 0, "concise message");
        verify(label.text.indexOf("missing0") < 0, "does not list the variable names");
    }

    // a long error status wraps instead of being clipped by the pane
    function test_long_error_status_wraps() {
        backend.send({ method: "POST", url: "http://127.0.0.1:1/up",
                       params: [], headers: [],
                       fields: [{ name: "f", value: "", type: "file",
                                  fileName: "/" + "a".repeat(300), enabled: true }],
                       body: "", bodyType: "multipart", auth: { type: "none" }, vars: [] }, "");
        wait(80);
        var label = findChild(win, "statusLabel");
        verify(label, "status label present");
        verify(label.text.indexOf("open the file") >= 0, "error shown");
        verify(label.lineCount > 1, "long error wraps to multiple lines");
    }
}
