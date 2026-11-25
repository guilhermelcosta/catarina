import QtQuick
import QtQuick.Controls
import QtTest
import org.kde.kirigami as Kirigami
import "../../qml"
import "../../qml/Strings.js" as Strings

// Screen behavior: instantiates the real Main (with backend/settings injected
// by tst_app.cpp) and exercises AppController — tabs, preview/pin, session,
// apply/collect request, creation target, environment/collection singleton tabs.
TestCase {
    id: root
    name: "AppBehavior"
    when: windowShown

    Component { id: appComponent; Main {} }
    property var win: null
    property int treeResets: 0
    // a full rebuild clears the ListModel: count drops to 0 before refilling
    Connections {
        target: root.win ? root.win.appController.treeModel : null
        function onCountChanged() { if (target.count === 0) root.treeResets++; }
    }

    function init() {
        if (win) { win.destroy(); win = null; }
        win = appComponent.createObject(null);
        verify(win, "could not create Main");
        win.visible = true;
    }
    function cleanupTestCase() {
        if (win) { win.destroy(); win = null; }
    }

    function tabDelegate(controller, i) {
        var n = 0;
        for (var c = 0; c < controller.tabStrip.row.children.length; c++) {
            var it = controller.tabStrip.row.children[c];
            if (!it.isTabDelegate) continue;
            if (n === i) return it;
            ++n;
        }
        return null;
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

    // selection paint comes from app.theme (Theme.qml), not a literal or the
    // Breeze full-saturation highlight
    function test_sidebar_selection_uses_theme_tokens() {
        backend.saveRequest("tint/a", baseReq());
        backend.saveRequest("tint/b", baseReq());
        win.appController.reloadTree();
        wait(100);

        var theme = win.appController.theme;
        verify(theme, "theme is wired into the controller");

        var tree = win.appController.treeModel;
        var selIdx = -1, otherIdx = -1;
        for (var i = 0; i < tree.count; i++) {
            if (tree.get(i).relPath === "tint/a") selIdx = i;
            else if (tree.get(i).relPath === "tint/b") otherIdx = i;
        }
        verify(selIdx >= 0 && otherIdx >= 0, "both rows are in the tree");

        win.appController.selectedPath = "tint/a";
        wait(50);
        var selected = win.appController.sidebar.view.itemAtIndex(selIdx);
        verify(selected, "selected delegate is visible");
        verify(Qt.colorEqual(selected.background.color, theme.selectionTint),
               "selected row paints the theme selection tint");

        var plain = win.appController.sidebar.view.itemAtIndex(otherIdx);
        verify(plain, "unselected delegate is visible");
        compare(plain.background.color.a, 0, "unselected, unhovered row is transparent");
    }

    // ---- keyboard navigation in the collections tree ----
    function test_sidebar_keyboard_navigation() {
        backend.saveRequest("kb/a", baseReq("GET"));
        backend.saveRequest("kb/b", baseReq("POST"));
        win.appController.reloadTree();
        wait(100);

        var model = win.appController.treeModel;
        var idx = -1;
        for (var i = 0; i < model.count; i++)
            if (model.get(i).relPath === "kb") { idx = i; break; }
        verify(idx >= 0, "folder in the tree");

        var view = win.appController.sidebar.view;
        win.appController.toggleCollapse("kb");   // start collapsed
        win.appController.selectedPath = "kb";
        win.appController.selectedIsFolder = true;
        view.currentIndex = idx;
        view.forceActiveFocus();
        verify(view.activeFocus, "tree has focus");

        keyClick(Qt.Key_Right);   // expand
        verify(!win.appController.collapsedFolders["kb"], "Right expands the folder");
        keyClick(Qt.Key_Down);    // first child
        compare(win.appController.selectedPath, "kb/a");
        keyClick(Qt.Key_Return);  // open
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.tabsModel.get(0).relPath, "kb/a");
        keyClick(Qt.Key_Up);      // back to the folder
        compare(win.appController.selectedPath, "kb");
        keyClick(Qt.Key_Left);    // collapse
        compare(win.appController.collapsedFolders["kb"], true);
    }

    // navigation must not reset the tree model (no full rebuild)
    function test_navigation_does_not_rebuild_the_tree() {
        backend.saveRequest("t/nav-a", baseReq());
        backend.saveRequest("t/nav-b", baseReq());
        win.appController.openRequest("t/nav-a");
        win.appController.pinTab(0);
        win.appController.openRequest("t/nav-b");
        win.appController.reloadTree();
        wait(100);

        var before = root.treeResets;
        verify(before > 0, "the tree was rebuilt at least once before navigating");
        win.appController.switchTab(0);
        wait(100);
        compare(root.treeResets, before, "switching tabs must not rebuild the tree");

        win.appController.closeTab(0);
        wait(100);
        compare(root.treeResets, before, "closing a tab must not rebuild the tree");
    }

    // response views must never interpret server data as rich text
    function test_response_views_render_plain_text() {
        var body = findChild(win, "responseBodyArea");
        verify(body !== null, "response body text area");
        compare(body.textFormat, TextEdit.PlainText);
        var cookies = findChild(win, "responseCookiesArea");
        verify(cookies !== null, "cookies text area");
        compare(cookies.textFormat, TextEdit.PlainText);
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

    // creating an environment whose name exists must not overwrite its variables
    function test_create_environment_refuses_an_existing_name() {
        compare(win.appController.createEnvironment("qa-guard"), true);
        compare(win.appController.environmentExists("qa-guard"), true);
        backend.saveEnvironment("qa-guard", [{ name: "token", value: "abc", enabled: true }]);
        win.appController.reloadEnvs();
        compare(win.appController.createEnvironment("qa-guard"), false);
        var vars = backend.environmentVariables("qa-guard");
        compare(vars.length, 1);
        compare(vars[0].name, "token");
    }

    function test_environment_empty_state() {
        win.appController.openEnvTab("");
        win.appController.envList = [];
        wait(50);
        var empty = findChild(win, "envEmptyState");
        verify(empty !== null, "empty state exists");
        verify(empty.visible, "visible when there is no environment");
    }

    // a selected row is a tinted surface, not the Breeze solid highlight, so its
    // label must keep the normal text role or it disappears into the tint
    function test_selected_rows_keep_normal_text_colour() {
        win.appController.openEnvTab("");
        win.appController.envList = [{ name: "tint-a" }, { name: "tint-b" }];
        wait(50);
        win.appController.envScreen.editing = "tint-b";
        wait(50);

        var envList = findChild(win, "envList");
        verify(envList !== null, "environment list exists");
        var envRow = envList.itemAtIndex(1);
        var envPlain = envList.itemAtIndex(0);
        verify(envRow !== null, "selected environment row is realised");
        verify(envPlain !== null, "unselected environment row is realised");
        compare(envRow.highlighted, true, "the edited environment is the selected row");
        verify(Qt.colorEqual(envRow.contentItem.color, envPlain.contentItem.color),
               "selected environment label keeps the normal text colour");

        var palette = findChild(win, "commandPalette");
        verify(palette !== null, "command palette exists");
        palette.openPalette();
        wait(50);
        var paletteList = findChild(palette, "paletteList");
        verify(paletteList !== null, "palette list exists");
        var paletteRow = paletteList.itemAtIndex(0);
        var palettePlain = paletteList.itemAtIndex(1);
        verify(paletteRow !== null, "keyboard-current palette row is realised");
        verify(palettePlain !== null, "unselected palette row is realised");
        compare(paletteRow.highlighted, true, "index 0 is the keyboard-current row");
        var rowLabel = findChild(paletteRow, "paletteRowLabel");
        var plainLabel = findChild(palettePlain, "paletteRowLabel");
        verify(rowLabel !== null && plainLabel !== null, "palette rows render a label");
        verify(Qt.colorEqual(rowLabel.color, plainLabel.color),
               "keyboard-current palette row keeps the normal text colour");
        palette.close();
    }

    function test_sidebar_empty_state() {
        win.appController.treeModel.clear();
        wait(50);
        var empty = findChild(win, "sidebarEmptyState");
        verify(empty !== null, "empty state exists");
        verify(empty.visible, "visible when the tree has no rows");
    }

    function test_response_pane_default_fits_tabs() {
        verify(win.appController.responsePane.expandedWidth >= 420,
               "default width must fit the five tab labels");
    }

    // Request bar (spec 004-request-bar): Save and Discard moved to icon-only
    // buttons outside the container, and the dirty label is gone — the tab dot
    // carries that state now.
    function test_request_save_is_icon_only_and_dirty_label_is_gone() {
        backend.saveRequest("t/dirty", baseReq());
        win.appController.openRequest("t/dirty");
        wait(50);

        var save = findChild(win, "requestSaveButton");
        verify(save !== null, "save button");
        compare(save.display, AbstractButton.IconOnly, "save renders icon-only");
        var revert = findChild(win, "requestRevertButton");
        verify(revert !== null, "revert button");
        compare(revert.display, AbstractButton.IconOnly, "revert renders icon-only");
        compare(findChild(win, "requestDirtyLabel"), null, "the dirty label is removed");

        win.appController.currentDirty = false;
        wait(20);
        compare(save.enabled, false, "clean request: save disabled");
        compare(revert.enabled, false, "clean request: discard disabled");

        win.appController.currentDirty = true;
        wait(20);
        compare(save.enabled, true, "dirty request: save enabled");
        compare(revert.enabled, true, "dirty request: discard enabled");

        win.appController.requestVarsWarning = "duplicate variable";
        wait(20);
        compare(save.enabled, false, "variable warning blocks save");
        compare(revert.enabled, true, "variable warning leaves discard enabled");

        win.appController.requestVarsWarning = "";
        win.appController.currentDirty = false;
    }

    // Criterion 5 / ui.md C3: exactly one primary action at rest, and it is Send.
    function test_request_row_one_primary_action() {
        backend.saveRequest("t/primary", baseReq());
        win.appController.openRequest("t/primary");
        wait(50);

        var bar = findChild(win, "requestBar");
        verify(bar !== null, "request bar exists");
        var send = findChild(win, "requestSendButton");
        verify(send !== null, "send button exists");
        compare(send.highlighted, true, "send is highlighted at rest");

        var names = ["requestRevertButton", "requestSaveButton"];
        for (var i = 0; i < names.length; i++) {
            var button = findChild(win, names[i]);
            verify(button !== null, names[i] + " exists");
            compare(button.highlighted, false, names[i] + " is never highlighted");
        }

        // no other action inside the bar paints a highlight; an action is a
        // button that carries text (the style's internal panels have none)
        var highlighted = [];
        var pending = [bar];
        while (pending.length > 0) {
            var item = pending.pop();
            if (item.highlighted === true && typeof item.text === "string")
                highlighted.push(item.objectName);
            for (var c = 0; c < item.children.length; c++) pending.push(item.children[c]);
        }
        compare(highlighted.length, 1, "exactly one highlighted action inside the request bar");
        compare(highlighted[0], "requestSendButton", "and it is Send");
    }

    // UI review row 1: the chevron belongs to the label. The style's own
    // indicator slot is not laid out once the background is stripped, so the
    // segment must carry no indicator and the chevron must sit inside it.
    function test_request_method_chevron_belongs_to_the_label() {
        backend.saveRequest("t/method", baseReq());
        win.appController.openRequest("t/method");
        wait(50);

        var box = findChild(win, "requestMethodBox");
        verify(box !== null, "method segment exists");
        compare(box.indicator, null, "no detached indicator");

        var chevron = findChild(win, "requestMethodChevron");
        verify(chevron !== null, "chevron exists");
        compare(chevron.visible, box.width >= 72, "the chevron gives way below 72 px");

        var topLeft = chevron.mapToItem(box, 0, 0);
        verify(topLeft.x >= 0, "chevron starts inside the segment: " + topLeft.x);
        verify(topLeft.x + chevron.width <= box.width,
               "chevron ends inside the segment: " + (topLeft.x + chevron.width));
        var centreY = topLeft.y + chevron.height / 2;
        verify(Math.abs(centreY - box.height / 2) <= box.height / 4,
               "chevron is vertically centred, not in a corner: " + centreY);
    }

    // Criterion 4: the URL keeps its floor while the row is squeezed; the icon
    // buttons keep their fixed width (design §2.2 space budget).
    function test_request_bar_url_width() {
        backend.saveRequest("t/width", baseReq());
        win.appController.openRequest("t/width");
        wait(50);

        var editor = win.appController.requestEditor;
        verify(editor !== null, "request editor");
        var send = findChild(win, "requestSendButton");
        var save = findChild(win, "requestSaveButton");
        var revert = findChild(win, "requestRevertButton");
        verify(send !== null && save !== null && revert !== null, "request row controls exist");

        verify(editor.urlInput.width >= 240,
               "URL is at least 240 px at the default window: " + editor.urlInput.width);
        var sendWidth = send.width, saveWidth = save.width, revertWidth = revert.width;

        var restoredWidth = win.width;
        // one pixel above the stacking threshold: horizontal, editor forced to
        // its minimum by a wide response pane
        win.width = win.minimumWidth + 1;
        wait(100);
        win.appController.responsePane.splitWidth = 900;
        wait(120);
        compare(editor.width, editor.SplitView.minimumWidth, "editor squeezed to its minimum");
        verify(editor.urlInput.width >= 220,
               "URL keeps its 220 px floor at the editor minimum: " + editor.urlInput.width);
        compare(send.width, sendWidth, "send keeps its fixed width");
        compare(save.width, saveWidth, "save keeps its fixed width");
        compare(revert.width, revertWidth, "discard keeps its fixed width");

        var savePos = save.mapToItem(editor, 0, 0);
        var revertPos = revert.mapToItem(editor, 0, 0);
        verify(savePos.x + save.width <= editor.width + 0.5,
               "save stays inside the editor at its minimum: " + (savePos.x + save.width));
        verify(revertPos.x + revert.width <= editor.width + 0.5,
               "discard stays inside the editor at its minimum: " + (revertPos.x + revert.width));

        var bar = findChild(win, "requestBar");
        var method = findChild(win, "requestMethodBox");
        var barPos = bar.mapToItem(editor, 0, 0);
        var sendPos = send.mapToItem(editor, 0, 0);
        verify(sendPos.x + send.width <= barPos.x + bar.width + 0.5,
               "send stays inside the request bar: " + (sendPos.x + send.width));
        verify(revertPos.x >= barPos.x + bar.width,
               "discard starts after the bar: " + revertPos.x);
        verify(method.width >= 56,
               "the method keeps its 56 px floor: " + method.width);

        win.appController.responsePane.splitWidth = 430;
        win.width = restoredWidth;
        wait(100);
    }

    function test_sidebar_error_state() {
        win.appController.storageError = "Can't read /x. Check the folder permissions.";
        win.appController.treeModel.clear();
        wait(20);
        var empty = findChild(win, "sidebarEmptyState");
        verify(empty !== null && empty.visible, "empty state visible");
        verify(empty.message.indexOf("/x") >= 0, "message names the unreadable path");
        compare(empty.actionText, "", "no create action when the folder cannot be read");
        win.appController.storageError = "";
        win.appController.reloadTree();
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

    // tab delegates in model order (the Repeater's non-delegate children skipped)
    function tabDelegates() {
        var out = [];
        var kids = win.appController.tabStrip.row.children;
        for (var i = 0; i < kids.length; i++)
            if (kids[i].isTabDelegate) out.push(kids[i]);
        return out;
    }

    function test_tab_close_visibility() {
        backend.saveRequest("close/a", baseReq());
        backend.saveRequest("close/b", baseReq());
        backend.saveRequest("close/c", baseReq());
        win.appController.openRequest("close/a");
        win.appController.pinTab(0);
        win.appController.openRequest("close/b");
        win.appController.pinTab(1);
        win.appController.openRequest("close/c");
        compare(win.appController.currentTab, 2);
        wait(100);

        var tabs = tabDelegates();
        compare(tabs.length, 3);
        verify(findChild(tabs[2], "tabClose").visible, "active tab shows the close control");
        verify(!findChild(tabs[0], "tabClose").visible, "inactive tab hides the close control");
        verify(!findChild(tabs[1], "tabClose").visible, "inactive tab hides the close control");

        win.appController.pinTab(2);
        wait(50);
        tabs = tabDelegates();
        verify(!findChild(tabs[2], "tabClose").visible, "a pinned tab never shows close");
        verify(findChild(tabs[2], "tabPin").visible, "the pinned tab shows the pin");
    }

    // M2: an inactive, unpinned tab hides close. The older test pinned both
    // inactive tabs, so an implementation that shows × on every unpinned tab
    // would still pass.
    function test_tab_close_hidden_on_inactive_unpinned() {
        backend.saveRequest("idle/a", baseReq());
        backend.saveRequest("idle/b", baseReq());
        backend.saveRequest("idle/c", baseReq());
        win.appController.openRequest("idle/a");
        win.appController.pinTab(0);
        win.appController.openRequest("idle/b");
        win.appController.tabsModel.setProperty(1, "preview", false);
        win.appController.openRequest("idle/c");
        compare(win.appController.currentTab, 2);
        wait(100);

        var tabs = tabDelegates();
        compare(tabs.length, 3);
        verify(findChild(tabs[2], "tabClose").visible,
               "the active tab shows the close control");
        verify(!findChild(tabs[1], "tabClose").visible,
               "an inactive unpinned tab hides the close control");
    }

    function test_tab_width_bounds() {
        var longName = "long" + "o".repeat(160);
        backend.saveRequest(longName, baseReq());
        backend.saveRequest("w", baseReq());
        win.appController.openRequest(longName);
        win.appController.pinTab(0);
        win.appController.openRequest("w");
        wait(150);

        var tabs = tabDelegates();
        compare(tabs.length, 2);
        verify(tabs[0].width <= 200, "long name clamps at tabMaxWidth");
        verify(tabs[1].width >= 90, "short name floors at tabMinWidth");
        verify(tabs[0].labelTruncated, "the clamped label is elided");
        verify(!tabs[1].labelTruncated, "a short label is not elided");
    }

    function test_tab_tooltip_full_name() {
        var longName = "tip" + "p".repeat(160);
        backend.saveRequest(longName, baseReq());
        backend.saveRequest("s", baseReq());
        win.appController.openRequest(longName);
        win.appController.pinTab(0);
        win.appController.openRequest("s");
        wait(150);

        var strip = win.appController.tabStrip;
        var tip = findChild(strip, "tabTip");
        verify(tip !== null, "the strip owns one shared tooltip");
        var tabs = tabDelegates();
        strip.showTabTip(tabs[0]);
        verify(tip.visible, "a truncated tab opens the tooltip");
        compare(tip.text, longName, "the tooltip shows the full, unelided name");
        verify(tip.y >= tabs[0].height, "the tooltip sits below the tab band");

        strip.hideTabTip();
        verify(!tip.visible, "unhover closes the tooltip");
        strip.showTabTip(tabs[1]);
        verify(!tip.visible, "a short tab has no tooltip");
    }

    function test_tab_scroll_into_view() {
        for (var i = 0; i < 16; i++) {
            backend.saveRequest("scroll/n" + i, baseReq());
            win.appController.openRequest("scroll/n" + i);
            win.appController.pinTab(win.appController.tabsModel.count - 1);
        }
        wait(200);
        var strip = win.appController.tabStrip;
        var flick = strip.flickable;
        verify(flick.contentWidth > flick.width, "tabs overflow the strip");

        win.appController.switchTab(15);
        wait(100);
        var tabs = tabDelegates();
        verify(tabs[15].x >= flick.contentX, "active tab left edge is in view");
        verify(tabs[15].x + tabs[15].width <= flick.contentX + flick.width + 1,
               "active tab right edge is in view");

        win.appController.switchTab(0);
        wait(100);
        compare(flick.contentX, 0, "switching back to the first tab scrolls to the start");
    }

    function test_tab_active_surface_uses_theme() {
        backend.saveRequest("surface/a", baseReq());
        backend.saveRequest("surface/b", baseReq());
        win.appController.openRequest("surface/a");
        win.appController.pinTab(0);
        win.appController.openRequest("surface/b");
        wait(250);

        var theme = win.appController.theme;
        var tabs = tabDelegates();
        var active = findChild(tabs[1], "tabSurface");
        var inactive = findChild(tabs[0], "tabSurface");
        verify(Qt.colorEqual(active.color, win.Kirigami.Theme.backgroundColor),
               "the active tab paints the raised surface: " + active.color
               + " vs " + win.Kirigami.Theme.backgroundColor);
        compare(active.radius, theme.radiusControl);
        var underline = findChild(active, "tabUnderline");
        compare(underline.height, 2);
        verify(underline.visible, "the active tab has the accent underline");
        compare(inactive.color.a, 0, "an inactive tab is transparent");
        verify(!findChild(inactive, "tabUnderline").visible, "an inactive tab has no underline");
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

    function test_import_curl_with_name() {
        compare(win.appController.importCurl("curl https://example/named", "Named import"), true);
        compare(backend.loadRequest("Named import").url, "https://example/named");
        compare(win.appController.tabsModel.get(0).relPath, "Named import");
        // an existing name and a slash are refused, and do not overwrite or create
        compare(win.appController.importCurl("curl https://example/other", "Named import"), false);
        compare(win.appController.importCurl("curl https://example/other", "bad/name"), false);
        compare(backend.loadRequest("Named import").url, "https://example/named");
    }

    // the name describes the result, so it reads above the command it names
    function test_curl_import_name_is_above_the_command() {
        win.appController.curlImportDialog.openFresh();
        wait(50);
        var name = findChild(win, "curlNameField");
        var command = findChild(win, "curlCommandArea");
        var nameError = findChild(win, "curlNameError");
        verify(name !== null && command !== null && nameError !== null, "fields exist");
        verify(name.mapToItem(null, 0, 0).y < command.mapToItem(null, 0, 0).y,
               "name field sits above the command area");
        // make the error visible to check where it lands
        name.text = "bad/name";
        wait(20);
        verify(nameError.visible, "slash error is shown");
        verify(nameError.mapToItem(null, 0, 0).y > name.mapToItem(null, 0, 0).y,
               "name error sits below the name field");
        verify(nameError.mapToItem(null, 0, 0).y < command.mapToItem(null, 0, 0).y,
               "name error sits above the command area");
        name.text = "";
        verify(!nameError.visible, "error clears with an empty name");
        verify(command.activeFocus, "focus starts in the command area for Ctrl+V");
        keyClick(Qt.Key_Backtab);
        compare(name.activeFocus, true, "Shift+Tab reaches the name field");
        command.forceActiveFocus();

        // an empty command keeps Import disabled; typing clears the old hint
        var importBtn = findChild(win, "curlImportButton");
        verify(importBtn !== null, "import button exists");
        verify(!importBtn.enabled, "Import is disabled with an empty command");
        win.appController.curlImportDialog.hint = "Provide a URL";
        command.text = "curl https://example/x";
        compare(win.appController.curlImportDialog.hint, "", "typing clears the old hint");
        verify(importBtn.enabled, "Import enables with a command and a valid name");
        var cancel = findChild(win, "curlCancelButton");
        command.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        compare(command.text, "curl https://example/x", "Tab must not insert a tab into the command");
        verify(cancel.activeFocus, "Tab reaches the dialog actions");
        win.appController.curlImportDialog.close();
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
        verify(label.text.indexOf("Unresolved variables in the request") >= 0, "concise message");
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

    // ---- P0 closeout: sidebar filter and response header ----
    function seedResponse(rec) {
        var c = win.appController;
        backend.saveRequest("p0/req", baseReq());
        c.openRequest("p0/req");
        c.responses["p0/req"] = rec;
        c.responsePane.restoreResponse("p0/req");
    }

    function test_sidebar_filter_field_and_filtering() {
        backend.saveRequest("flt/alpha", baseReq("GET"));
        backend.saveRequest("flt/beta", baseReq("POST"));
        win.appController.reloadTree();
        wait(100);

        var field = findChild(win, "sidebarFilterField");
        verify(field !== null, "filter field exists");
        verify(field.visible, "visible when the tree has rows");

        field.forceActiveFocus();
        field.text = "alpha";
        wait(50);
        compare(win.appController.treeFilter, "alpha");

        var tree = win.appController.treeModel, alpha = -1, beta = -1;
        for (var i = 0; i < tree.count; i++) {
            if (tree.get(i).relPath === "flt/alpha") alpha = i;
            else if (tree.get(i).relPath === "flt/beta") beta = i;
        }
        verify(alpha >= 0 && beta >= 0, "both requests are in the model");
        compare(tree.get(alpha).hidden, false, "the match stays visible");
        compare(tree.get(beta).hidden, true, "the non-match hides");
    }

    function test_sidebar_filter_empty_state_and_escape() {
        backend.saveRequest("flt/a2", baseReq());
        win.appController.reloadTree();
        wait(100);

        var field = findChild(win, "sidebarFilterField");
        var empty = findChild(win, "sidebarFilterEmpty");
        verify(field && empty, "filter field and no-match placeholder exist");

        field.text = "zzz-no-such-request";
        wait(50);
        verify(empty.visible, "No matches is shown when nothing matches");

        field.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        wait(50);
        compare(field.text, "", "Escape clears the field");
        compare(win.appController.treeFilter, "", "Escape clears the filter");
        verify(!empty.visible, "the placeholder leaves with the filter");
        verify(win.appController.sidebar.view.activeFocus, "focus returns to the tree");
    }

    function test_sidebar_filter_selection_survives() {
        backend.saveRequest("flt/keep", baseReq());
        backend.saveRequest("flt/hide", baseReq());
        win.appController.reloadTree();
        wait(100);

        var c = win.appController;
        c.selectedPath = "flt/keep";
        var view = c.sidebar.view;
        var idx = -1;
        for (var i = 0; i < c.treeModel.count; i++)
            if (c.treeModel.get(i).relPath === "flt/keep") idx = i;
        view.currentIndex = idx;

        var field = findChild(win, "sidebarFilterField");
        field.text = "hide";
        wait(80);
        compare(c.selectedPath, "flt/keep", "the selection itself is kept");
        compare(view.currentIndex, -1, "no highlighted row while filtered out");

        field.text = "";
        wait(80);
        compare(view.currentIndex, idx, "the row is highlighted again on clear");
    }

    function test_ctrl_f_routes_by_focus() {
        backend.saveRequest("flt/focus", baseReq());
        win.appController.reloadTree();
        wait(100);

        var c = win.appController;
        var field = findChild(win, "sidebarFilterField");
        c.sidebar.view.forceActiveFocus();
        wait(20);
        keyClick(Qt.Key_F, Qt.ControlModifier);
        wait(20);
        verify(field.activeFocus, "Ctrl+F in the sidebar focuses the filter");

        c.responsePane.clearResponse();
        c.responses["p0/req"] = { status: 200, statusText: "OK", time: "1 ms", size: "1 B",
                                  headers: [], cookies: "", body: "hello" };
        c.responsePane.restoreResponse("p0/req");
        var body = findChild(win, "responseBodyArea");
        body.forceActiveFocus();
        wait(20);
        keyClick(Qt.Key_F, Qt.ControlModifier);
        wait(20);
        verify(c.responsePane.findVisible, "Ctrl+F with a displayed body opens the body find");
        c.responsePane.closeFind();
    }

    function test_sidebar_header_has_add_and_overflow_only() {
        backend.saveRequest("flt/hdr", baseReq());
        win.appController.reloadTree();
        win.appController.selectedPath = "flt/hdr";
        wait(50);

        var add = findChild(win, "sidebarAddButton");
        var overflow = findChild(win, "sidebarOverflowButton");
        verify(add !== null, "primary add button");
        verify(overflow !== null, "overflow button");
        compare(overflow.enabled, true, "overflow enabled with a selection");

        var header = add.parent;
        var buttons = [], trashes = 0;
        for (var i = 0; i < header.children.length; i++) {
            var ch = header.children[i];
            if (ch.icon === undefined || !ch.visible) continue;
            buttons.push(ch);
            if (ch.icon.name === "edit-delete") trashes++;
        }
        compare(buttons.length, 2, "exactly two actions in the header");
        compare(trashes, 0, "the permanent trash icon is gone");

        var menu = win.appController.sidebar.overflowMenu;
        verify(menu, "overflow menu injected");
        var actions = 0;
        for (var m = 0; m < menu.count; m++) {
            var it = menu.itemAt(m);
            if (it && it.text !== undefined && it.text.length > 0) actions++;
        }
        compare(actions, 4, "delete, rename, collapse all, reveal");
        compare(menu.itemAt(3).text, Strings.t.collapseAll);
    }

    function test_tree_rows_use_plain_method_text() {
        backend.saveRequest("flt/method", baseReq("PUT"));
        win.appController.reloadTree();
        wait(100);

        var c = win.appController, idx = -1;
        for (var i = 0; i < c.treeModel.count; i++)
            if (c.treeModel.get(i).relPath === "flt/method") idx = i;
        verify(idx >= 0, "request row in the tree");
        c.sidebar.view.positionViewAtIndex(idx, ListView.Contain);
        wait(50);
        var del = c.sidebar.view.itemAtIndex(idx);
        verify(del, "delegate visible");

        var label = findChild(del, "treeMethodLabel");
        verify(label !== null, "plain method label replaces the badge");
        compare(label.text, "PUT");
        compare(label.font.pixelSize, 11);
        compare(label.color, c.methodColor("PUT"));
    }

    function test_response_header_one_row() {
        seedResponse({ status: 200, statusText: "OK", time: "12 ms", size: "3 B",
                       headers: [{ name: "A", value: "1" }], cookies: "", body: '{"a":1}' });
        wait(50);

        var status = findChild(win, "statusLabel");
        var meta = findChild(win, "responseMetaLabel");
        var dot = findChild(win, "responseStatusDot");
        verify(status && meta && dot, "status, meta and dot exist");
        compare(status.text, "200 OK");
        compare(meta.text, "· 12 ms · 3 B");
        verify(dot.visible, "dot visible for a status code");

        verify(findChild(win, "responseFormatSelector") !== null, "format selector");
        verify(findChild(win, "responseWrapToggle") !== null, "wrap toggle");
        verify(findChild(win, "responseCopyButton") !== null, "copy action");
        verify(findChild(win, "responseFindButton") !== null, "find action");
        verify(findChild(win, "responseOverflowButton") !== null, "overflow action");

        var row = findChild(win, "responseHeaderRow");
        verify(row !== null, "header row");
        verify(row.height <= Kirigami.Units.gridUnit * 3,
               "the header stays one row at the default size, got " + row.height);
        verify(meta.width >= Math.min(meta.implicitWidth, 220) - 1,
               "the merged meta keeps its space, width " + meta.width
               + " of " + meta.implicitWidth + " in a " + row.width + " px row");
        compare(status.lineCount, 1, "the status stays on one line instead of wrapping");
        var overflow = findChild(win, "responseOverflowButton");
        var right = row.x + overflow.x + overflow.width;
        verify(right <= win.appController.responsePane.width + 1,
               "every header control fits at 1280x800, right edge " + right
               + " > pane " + win.appController.responsePane.width);
    }

    function test_response_header_overflow_fits_at_min_width() {
        seedResponse({ status: 200, statusText: "OK", time: "12 ms", size: "3 B",
                       headers: [{ name: "A", value: "1" }], cookies: "", body: '{"a":1}' });
        var pane = win.appController.responsePane;
        pane.splitWidth = 230;
        wait(300);
        verify(pane.width <= 231, "pane is at the 230 px minimum, got " + pane.width);

        var row = findChild(win, "responseHeaderRow");
        var overflow = findChild(win, "responseOverflowButton");
        verify(row && overflow, "header row and overflow exist");
        verify(overflow.visible, "the overflow is always visible");
        var right = row.x + overflow.x + overflow.width;
        verify(right <= pane.width + 1,
               "the overflow stays inside the pane, right edge " + right
               + " > pane " + pane.width);
    }

    function test_response_format_and_wrap_do_not_mutate() {
        var stored = '{"a":1}';
        seedResponse({ status: 200, statusText: "OK", time: "1 ms", size: "7 B",
                       headers: [], cookies: "", body: stored });
        wait(50);

        var c = win.appController;
        var body = findChild(win, "responseBodyArea");
        var selector = findChild(win, "responseFormatSelector");
        var wrap = findChild(win, "responseWrapToggle");

        compare(body.text, '{\n  "a": 1\n}', "JSON pretty-prints");
        compare(c.responses["p0/req"].body, stored, "the stored body is untouched");

        selector.currentIndex = 3;   // Raw
        wait(20);
        compare(body.text, stored, "Raw shows the untouched body");
        compare(c.responses["p0/req"].body, stored, "switching format never mutates the record");

        wrap.checked = false;
        wait(20);
        compare(body.wrapMode, TextEdit.NoWrap, "wrap off disables wrapping");
        wrap.checked = true;
        wait(20);
        compare(body.wrapMode, TextEdit.Wrap, "wrap on restores wrapping");
    }

    function test_response_tab_counts() {
        seedResponse({ status: 200, statusText: "OK", time: "1 ms", size: "1 B",
                       headers: [{ name: "A", value: "1" }, { name: "B", value: "2" }],
                       cookies: "a=1\nb=2", body: "x" });
        wait(50);

        var tabs = findChild(win, "responseTabBar");
        verify(tabs, "response tab bar");
        compare(tabs.itemAt(2).text, "Headers 2");
        compare(tabs.itemAt(3).text, "Cookies 2");

        win.appController.responsePane.clearResponse();
        wait(50);
        compare(tabs.itemAt(2).text, "Headers", "plain label without a response");
        compare(tabs.itemAt(3).text, "Cookies", "plain label without a response");
    }

    function test_response_line_reference_and_find_counter() {
        seedResponse({ status: 200, statusText: "OK", time: "1 ms", size: "9 B",
                       headers: [], cookies: "", body: "abc\ndef" });
        wait(50);

        var body = findChild(win, "responseBodyArea");
        var lineRef = findChild(win, "responseLineRef");
        verify(lineRef !== null, "Ln, Col indicator");
        verify(lineRef.visible, "visible on the Body tab with a body");
        body.cursorPosition = 5;
        wait(20);
        compare(lineRef.text, "Ln 2, Col 2");

        win.appController.responsePane.openFind();
        wait(20);
        var findField = findChild(win, "responseFindField");
        verify(findField !== null, "find field");
        findField.text = "def";
        wait(300);
        var counter = findChild(win, "responseFindCounter");
        verify(counter !== null, "find counter");
        verify(counter.visible, "counter shows with a match");
        compare(counter.text, "1/1");
        win.appController.responsePane.closeFind();
    }

    // ---- P1 cohesion: chrome, palette and type scale ----

    // every Text/Label currently visible in `item`, as { name, size }
    function collectFontSizes(item, out) {
        if (!item) return out;
        if (item.font !== undefined && typeof item.text === "string"
                && item.visible && item.width > 0 && item.height > 0) {
            var ps = item.font.pixelSize;
            if (ps > 0) out.push({ name: String(item.objectName), size: ps });
        }
        var kids = item.children;
        if (kids === undefined) return out;
        for (var i = 0; i < kids.length; i++) collectFontSizes(kids[i], out);
        return out;
    }
    function collectTexts(item, out) {
        if (!item) return out;
        if (typeof item.text === "string" && item.text.length > 0) out.push(item.text);
        var kids = item.children;
        if (kids === undefined) return out;
        for (var i = 0; i < kids.length; i++) collectTexts(kids[i], out);
        return out;
    }

    // criterion 3: one 40 px row, breadcrumb left, toggles + one overflow right
    function test_top_bar_is_one_row_with_overflow() {
        backend.saveRequest("chrome/r", baseReq());
        win.appController.openRequest("chrome/r");
        wait(50);

        var bar = findChild(win, "topBar");
        verify(bar !== null, "topBar exists");
        compare(bar.height, win.appController.theme.topBarHeight, "top bar is one 40 px row");

        var crumb = findChild(win, "topBarBreadcrumb");
        verify(crumb !== null, "breadcrumb label exists");
        compare(crumb.text, "chrome", "breadcrumb names the collection");
        var crumbReq = findChild(win, "topBarBreadcrumbRequest");
        verify(crumbReq !== null && crumbReq.visible, "breadcrumb shows the open request");
        compare(crumbReq.text, "r");

        var pill = findChild(win, "envPill");
        var overflow = findChild(win, "topBarOverflow");
        verify(pill !== null && overflow !== null, "pill and overflow exist");
       verify(crumb.mapToItem(bar, 0, 0).x < pill.mapToItem(bar, 0, 0).x,
               "context on the left, controls on the right");
        verify(findChild(win, "topBarSidebarToggle") !== null, "collections toggle");
        verify(findChild(win, "topBarResponseToggle") !== null, "response toggle");

        var menu = findChild(win, "topBarOverflowMenu");
        verify(menu !== null, "overflow menu exists");
        compare(menu.itemAt(0).text, Strings.t.history, "History in the overflow");
        compare(menu.itemAt(1).text, Strings.t.settings, "Settings in the overflow");

        var texts = collectTexts(bar, []);
        verify(texts.indexOf(Strings.t.appName) < 0, "no logo/wordmark in the top bar");
    }

    // criterion 4: outlined pill, chevron, popup anchored to it, live label
    function test_env_pill_is_outlined_and_anchored() {
        var pill = findChild(win, "envPill");
        verify(pill !== null, "env pill exists");
        compare(pill.background.border.width, 1, "outlined, not filled");
        verify(Qt.colorEqual(pill.background.border.color,
                             win.appController.theme.chromeBorder), "border uses the shared chrome value");
        var chevron = findChild(win, "envPillChevron");
        verify(chevron !== null, "pill draws a chevron");

        var popup = findChild(win, "envPopup");
        verify(popup !== null, "environment popup exists");
        compare(popup.parent, pill, "popup anchors to the pill, not a fixed x/y");
        pill.clicked();
        wait(30);
        verify(popup.visible, "the pill opens the popup");
        verify(popup.y >= pill.height, "popup opens below the pill");
        popup.close();
        wait(20);

        backend.saveEnvironment("pillenv", []);
        win.appController.reloadEnvs();
        win.appController.activateEnv("pillenv");
        wait(50);
        compare(pill.text, "pillenv", "activating an environment updates the pill");
    }

    // criterion 5: 28 px footer, live readouts, zoom, theme toggle, Ctrl+/ hint
    function test_status_bar_readouts_and_controls() {
        var bar = findChild(win, "statusBar");
        verify(bar !== null, "statusBar exists");
        compare(bar.height, win.appController.theme.controlToolbar, "status bar is 28 px");

        var storage = findChild(win, "statusBarStorage");
        verify(storage !== null, "storage readout exists");
        compare(storage.text, Strings.t.storageLabel + " " + Strings.t.storageFile,
                "the test runs on the file backend");

        var timeout = findChild(win, "statusBarTimeout");
        verify(timeout !== null, "timeout readout exists");
        settings.timeoutSec = 30;
        wait(20);
        compare(timeout.text, "Timeout: 30 s");
        settings.timeoutSec = 45;
        wait(20);
        compare(timeout.text, "Timeout: 45 s", "timeout follows settings live");
        settings.timeoutSec = 0;
        wait(20);
        compare(timeout.text, "Timeout: no limit");
        settings.timeoutSec = 30;

        var zoomOut = findChild(win, "statusBarZoomOut");
        var zoomValue = findChild(win, "statusBarZoomValue");
        var zoomIn = findChild(win, "statusBarZoomIn");
        verify(zoomOut && zoomValue && zoomIn, "zoom controls exist");
        settings.editorFontSize = 0;
        wait(20);
        compare(zoomValue.text, String(settings.editorFontSizeResolved), "shows the resolved editor size");
        var before = settings.editorFontSizeResolved;
        zoomIn.clicked();
        wait(20);
        compare(settings.editorFontSize, before + 1, "zoom in steps the editor font by one");
        compare(zoomValue.text, String(before + 1));
        zoomValue.clicked();
        wait(20);
        compare(settings.editorFontSize, 0, "clicking the value resets to the unset default");

        var themeToggle = findChild(win, "statusBarThemeToggle");
        verify(themeToggle === null || !themeToggle.visible,
               "the forced-theme toggle is absent while the app follows the system");

        var hint = findChild(win, "statusBarShortcutsHint");
        verify(hint !== null, "Ctrl+/ hint exists");
        compare(hint.text, Strings.t.shortcutsHintText);
    }

    // criterion 6: 520 px, icons, shortcut column, recents and fuzzy highlight
    function test_command_palette_rows_recents_and_fuzzy() {
        var palette = findChild(win, "commandPalette");
        verify(palette !== null, "command palette exists");
        palette.openPalette();
        wait(50);
        compare(palette.width, 520, "palette is 520 px wide");

        var list = findChild(palette, "paletteList");
        var sendIdx = -1;
        for (var i = 0; i < palette.filtered.length; i++)
            if (palette.filtered[i].label === Strings.t.sendRequest) sendIdx = i;
        verify(sendIdx >= 0, "Send request is in the palette");
        var row = list.itemAtIndex(sendIdx);
        verify(row !== null, "row is realised");
        var icon = findChild(row, "paletteRowIcon");
        verify(icon !== null && icon.visible, "row carries an icon");
        var label = findChild(row, "paletteRowLabel");
        var shortcut = findChild(row, "paletteRowShortcut");
        verify(label && shortcut, "label and shortcut column exist");
        verify(shortcut.visible && shortcut.text.length > 0, "Send shows its shortcut");
        verify(shortcut.mapToItem(row, 0, 0).x > label.mapToItem(row, 0, 0).x,
               "shortcut sits right of the label");
        verify(shortcut.mapToItem(row, 0, 0).x + shortcut.width <= row.width + 1,
               "shortcut stays inside the row");

        palette.applyFilter("snd");
        wait(20);
        var fuzzyIdx = -1;
        for (var j = 0; j < palette.filtered.length; j++)
            if (palette.filtered[j].label === Strings.t.sendRequest) fuzzyIdx = j;
        verify(fuzzyIdx >= 0, "fuzzy subsequence finds Send request");
        verify(palette.filtered[fuzzyIdx].ranges.length > 0, "matched ranges are recorded");
        verify(palette.highlightText(palette.filtered[fuzzyIdx].label,
                                     palette.filtered[fuzzyIdx].ranges).indexOf("<b>") >= 0,
               "matched characters render highlighted");

        // run a safe action, then reopen: it is the Recent group on top
        palette.applyFilter("");
        var reopenIdx = -1;
        for (var k = 0; k < palette.filtered.length; k++)
            if (palette.filtered[k].label === Strings.t.reopenTab) reopenIdx = k;
        verify(reopenIdx >= 0, "Reopen closed tab is in the palette");
        list.currentIndex = reopenIdx;
        palette.trigger();
        wait(20);
        palette.openPalette();
        wait(50);
        compare(palette.filtered[0].group, Strings.t.paletteGroupRecent,
                "recents group appears above the categories");
        compare(palette.filtered[0].label, Strings.t.reopenTab);
        compare(palette.paletteRecents.length, 1, "recents are bounded and in-session");
        palette.close();
    }

    // criterion 7: every visible literal lives on the type scale
    function test_type_scale_walk() {
        settings.uiScale = 1.0;
        settings.density = "comfortable";
        var theme = win.appController.theme;
        compare(theme.fontSizeMeta, 11);
        compare(theme.fontSizeSecondary, 12);
        compare(theme.fontSizeBase, 13);
        compare(theme.fontSizeEmphasis, 14);
        compare(theme.fontSizeScreenTitle, 16);
        compare(theme.fontSizeCollectionTitle, 20);

        backend.saveRequest("scale/r", baseReq());
        win.appController.openRequest("scale/r");
        wait(80);
        var palette = findChild(win, "commandPalette");
        palette.openPalette();
        wait(50);

        var sizes = collectFontSizes(win, []);
        var allowed = { "11": true, "12": true, "13": true, "14": true, "16": true, "20": true };
        // declared exceptions: the editor-font content surfaces (content, not chrome)
        var exempt = { "requestUrlField": true, "bodyEditorArea": true, "responseBodyArea": true };
        for (var i = 0; i < sizes.length; i++) {
            if (exempt[sizes[i].name]) continue;
            verify(allowed[sizes[i].size] === true,
                   "off-scale font size " + sizes[i].size + " px on '" + sizes[i].name + "'");
        }
        palette.close();
    }

    // criterion 9: counts ride in the section labels, never on Body/Authentication
    function test_request_section_tab_counts() {
        backend.saveRequest("sect/r", baseReq());
        win.appController.openRequest("sect/r");
        wait(50);

        var bar = findChild(win, "requestTabBar");
        verify(bar !== null, "request section tab bar exists");
        compare(bar.itemAt(0).text, Strings.t.parameters, "empty params: plain label");
        compare(bar.itemAt(1).text, Strings.t.headers, "empty headers: plain label");
        compare(bar.itemAt(4).text, Strings.t.variables, "empty vars: plain label");
        compare(bar.itemAt(2).text, Strings.t.body, "Body never carries a count");
        compare(bar.itemAt(3).text, Strings.t.authentication, "Authentication never carries a count");

        win.appController.paramsModel.append({ name: "q", value: "1", enabled: true });
        win.appController.headersModel.append({ name: "h", value: "1", enabled: true });
        win.appController.requestVarsModel.append({ name: "v", value: "1", enabled: true });
        wait(30);
        compare(bar.itemAt(0).text, Strings.t.parameters + " 1");
        compare(bar.itemAt(1).text, Strings.t.headers + " 1");
        compare(bar.itemAt(4).text, Strings.t.variables + " 1");
    }

    // ---- criteria 3, 4, 14: settings shell, cards and search ----
    function test_settings_two_panes_cards_and_no_apply() {
        win.appController.openSettingsTab();
        wait(80);

        var nav = findChild(win, "settingsNav");
        verify(nav !== null, "settingsNav exists");
        compare(nav.width, 190, "category nav is 190 px");
        compare(nav.count, 7, "seven categories");
        compare(nav.itemAtIndex(0).text, Strings.t.appearance, "Appearance first");
        compare(nav.itemAtIndex(1).text, Strings.t.editor);
        compare(nav.itemAtIndex(6).text, Strings.t.about);

        verify(findChild(win, "settingsForm") !== null, "settingsForm preserved");
        verify(findChild(win, "settingsCard.appearance") !== null, "Appearance card exists");
        verify(findChild(win, "settingsRow.density") !== null, "density row exists");
        compare(findChild(win, "settingsCard.appearance").visible, true,
                "Appearance is active on open");

        var texts = collectTexts(win, []);
        verify(texts.indexOf("Apply") < 0, "no Apply-labelled control anywhere");
        compare(Strings.t.apply, undefined, "Strings.t.apply is gone");

        // the selected rail row is a theme tint with an icon and plain weight,
        // not ItemDelegate's filled accent block or a bold label
        var selected = nav.itemAtIndex(0);
        compare(selected.highlighted, false, "the rail row does not use the filled highlight");
        verify(Qt.colorEqual(selected.background.color, win.appController.theme.selectionTint),
               "selection uses the theme selectionTint");
        var navContent = selected.contentItem;
        verify(navContent.children.length >= 2, "the rail row has an icon column and a label");
        verify(navContent.children[0].source !== undefined && navContent.children[0].source.length > 0,
               "the rail row carries a Breeze icon");
        var navLabel = navContent.children[navContent.children.length - 1];
        compare(navLabel.font.bold, false, "the selected label keeps the plain weight");

        var card = findChild(win, "settingsCard.appearance");
        var subtitle = findChild(win, "settingsSubtitle");
        verify(subtitle !== null, "the subtitle exists");
        verify(subtitle.mapToItem(card.parent, 0, 0).y < card.mapToItem(card.parent, 0, 0).y,
               "the subtitle sits above the cards, not under their bottom edge");

        nav.itemAtIndex(1).clicked();
        wait(30);
        compare(findChild(win, "settingsCard.editor").visible, true, "nav switches category");
        compare(findChild(win, "settingsCard.appearance").visible, false);
    }

    function test_settings_search_filters_and_routes_ctrl_f() {
        win.appController.openSettingsTab();
        wait(80);
        var nav = findChild(win, "settingsNav");
        var search = findChild(win, "settingsSearch");
        verify(search !== null, "settingsSearch exists");
        nav.itemAtIndex(0).clicked();
        wait(30);

        search.text = "density";
        wait(30);
        compare(findChild(win, "settingsRow.density").visible, true, "matching row stays");
        compare(findChild(win, "settingsRow.uiScale").visible, false, "non-matching row hides");
        compare(findChild(win, "settingsEmptyState").visible, false);

        // a category with matches does not take the pane while another is
        // selected: the rail selection and the visible card must agree
        search.text = "wrap";
        wait(30);
        compare(findChild(win, "settingsCard.appearance").visible, false,
                "the selected category's card hides when it has no match");
        compare(findChild(win, "settingsCard.editor").visible, false,
                "a non-selected matching card stays hidden");
        compare(findChild(win, "settingsEmptyState").visible, true,
                "the pane shows the empty state instead of a disagreeing card");
        compare(nav.itemAtIndex(5).visible, false, "a rail entry with no match hides");
        compare(nav.itemAtIndex(1).visible, true, "a rail entry with a match stays");

        search.text = "zzzz-no-setting";
        wait(30);
        compare(findChild(win, "settingsRow.density").visible, false);
        compare(findChild(win, "settingsEmptyState").visible, true, "no match shows the empty state");

        search.text = "";
        wait(30);
        compare(findChild(win, "settingsEmptyState").visible, false);
        compare(findChild(win, "settingsRow.density").visible, true, "clearing restores the card");

        nav.itemAtIndex(2).clicked();   // move focus away from the search
        wait(20);
        keyClick(Qt.Key_F, Qt.ControlModifier);
        wait(30);
        verify(search.activeFocus, "Ctrl+F in settings focuses the settings search");
        search.text = "";
    }

    // ---- criteria 5, 6, 7: appearance + editor rows wired ----
    function test_settings_appearance_and_editor_rows() {
        win.appController.openSettingsTab();
        wait(80);
        var nav = findChild(win, "settingsNav");
        nav.itemAtIndex(0).clicked();
        wait(30);

        var theme = win.appController.theme;
        var scale = findChild(win, "settingsUiScale");
        verify(scale !== null, "UI scale control exists");
        compare(scale.value, 100, "scale starts at 1.00");
        settings.uiScale = 1.2;
        wait(30);
        compare(theme.fontSizeBase, Math.round(13 * 1.2), "type scale follows uiScale");
        compare(theme.controlToolbar, Math.round(28 * 1.2), "control size follows uiScale");
        settings.uiScale = 1.0;
        wait(20);

        settings.density = "compact";
        wait(30);
        compare(theme.densityFactor, 0.85);
        compare(theme.controlToolbar, Math.round(28 * 0.85), "compact shrink the controls");
        compare(theme.settingsRowHeight, 44, "compact settings rows");
        settings.density = "comfortable";
        wait(20);
        compare(theme.settingsRowHeight, 48);

        nav.itemAtIndex(1).clicked();
        wait(30);
        var size = findChild(win, "settingsEditorFontSize");
        verify(size !== null, "editor size control exists");
        settings.editorFontSize = 18;
        wait(30);
        compare(size.value, 18, "the size control writes editorFontSize");
        var preview = findChild(win, "editorFontPreview");
        verify(preview !== null, "live preview exists");
        compare(preview.font.pointSize, 18, "preview uses the resolved editor size");

        var family = findChild(win, "settingsEditorFontFamily");
        verify(family !== null, "font family control exists");
        compare(family.model[0], Strings.t.editorFontDefault, "default monospace is the first entry");
        settings.editorFontSize = 0;
    }

    function test_settings_storage_row_takes_the_width_it_needs() {
        win.appController.openSettingsTab();
        wait(80);
        var nav = findChild(win, "settingsNav");
        nav.itemAtIndex(5).clicked();
        wait(60);

        var storage = findChild(win, "settingsRow.storage");
        verify(storage !== null, "the Storage row exists");
        compare(storage.wideControl, true, "Storage is the one wide row");
        verify(storage.resolvedControlWidth >= 380,
               "the Storage control keeps at least 380 px (got " + storage.resolvedControlWidth + ")");
        var field = findChild(win, "storageDirField");
        verify(field !== null, "the path field exists");
        verify(field.width > 200, "the path field outgrows the standard column");

        nav.itemAtIndex(0).clicked();
        wait(40);
        var standard = findChild(win, "settingsRow.density");
        compare(standard.wideControl, false);
        compare(standard.resolvedControlWidth, 200, "standard rows keep the 200 px column");
    }

    function test_editor_content_surfaces_use_resolved_font() {
        settings.editorFontSize = 17;
        settings.editorFontFamily = "";
        settings.editorLineNumbers = true;
        settings.editorWrap = false;
        var req = baseReq();
        req.bodyType = "json";
        req.body = "{\n  \"a\": 1\n}";
        backend.saveRequest("font/r", req);
        win.appController.openRequest("font/r");
        wait(120);

        var url = findChild(win, "requestUrlField");
        var body = findChild(win, "bodyEditorArea");
        var resp = findChild(win, "responseBodyArea");
        verify(url && body && resp, "content surfaces exist");
        compare(url.font.pointSize, 17);
        compare(body.font.pointSize, 17);
        compare(resp.font.pointSize, 17);
        compare(url.font.family, settings.editorFontResolved);
        compare(body.font.family, settings.editorFontResolved);
        compare(resp.font.family, settings.editorFontResolved);
        compare(body.wrapMode, TextEdit.NoWrap, "wrap follows settings.editorWrap");

        var gutter = findChild(win, "bodyLineGutter");
        verify(gutter !== null, "line-number gutter exists");
        var sectionBar = findChild(win, "requestTabBar");
        verify(sectionBar !== null, "request section bar exists");
        sectionBar.currentIndex = 2;   // Body tab: the gutter lives under it
        wait(60);
        compare(settings.editorLineNumbers, true, "line-number setting is on before the check");
        compare(gutter.visible, true, "gutter follows settings.editorLineNumbers");
        settings.editorLineNumbers = false;
        wait(30);
        compare(gutter.visible, false, "gutter hides when the setting is off");

        settings.editorWrap = true;
        settings.editorLineNumbers = false;
        settings.editorFontSize = 0;
    }

    // criterion 8: pane widths persist, restore clamped
    function test_layout_panes_persist_and_restore_clamped() {
        backend.saveRequest("panes/r", baseReq());
        win.appController.openRequest("panes/r");
        wait(150);
        var c = win.appController;
        var inner = c.innerSplit;
        compare(inner.orientation, Qt.Horizontal, "the default window is horizontal");

        settings.sidebarWidth = 0;
        settings.splitPosition = 0;
        c.paneSidebarWidth = 0;
        c.paneSplitPosition = 0;
        settings.sidebarWidth = 270;
        settings.splitPosition = 0.3;
        c.restorePanes();
        wait(220);
        verify(Math.abs(c.sidebar.width - 270) <= 2,
               "the saved sidebar width applies (got " + c.sidebar.width + ")");
        var frac = c.responsePane.width / inner.width;
        verify(Math.abs(frac - 0.3) <= 0.04,
               "the saved split fraction applies (got " + frac + ")");

        c.persistPanes();
        wait(30);
        verify(Math.abs(settings.sidebarWidth - 270) <= 2, "persist writes the sidebar width");
        verify(Math.abs(settings.splitPosition - 0.3) <= 0.04, "persist writes the split fraction");

        // out-of-range values clamp to the window and the SplitView minimums
        settings.sidebarWidth = 10;
        settings.splitPosition = 0.95;
        c.paneSidebarWidth = 0;
        c.paneSplitPosition = 0;
        c.restorePanes();
        wait(220);
        verify(c.sidebar.width >= 189,
               "a too-small sidebar clamps to 190 (got " + c.sidebar.width + ")");
        verify(c.responsePane.width >= 229,
               "a too-wide response clamps to the 230 px minimum (got " + c.responsePane.width + ")");
        verify(c.responsePane.width / inner.width <= 0.81, "the fraction clamps to 0.8");

        settings.sidebarWidth = 0;
        settings.splitPosition = 0;
        c.paneSidebarWidth = 0;
        c.paneSplitPosition = 0;
        c.sidebar.expandedWidth = 250;
        c.sidebar.splitWidth = 250;
        c.responsePane.expandedWidth = 430;
        c.responsePane.splitWidth = 430;
        wait(120);
    }

    // criterion 8 regression: startup restores only once the window has a
    // width, so the pre-layout split cannot collapse the saved values to the
    // minimums (the old code did, and then persisted 190 on close)
    function test_layout_restore_waits_for_the_first_layout() {
        if (win) { win.destroy(); win = null; }
        settings.sidebarWidth = 420;
        settings.splitPosition = 0.35;
        backend.saveRequest("panes/startup", baseReq());
        var w = appComponent.createObject(null);
        verify(w, "could not create Main");
        win = w;
        w.visible = true;
        w.appController.openRequest("panes/startup");
        wait(400);
        compare(w.appController.panesRestored, true,
                "restore runs once the window has a width");
        verify(Math.abs(w.appController.sidebar.width - 420) <= 2,
               "the saved sidebar width survives the first layout (got "
               + w.appController.sidebar.width + ")");
        var inner = w.appController.innerSplit;
        verify(inner.width > 0, "the request editor is laid out");
        verify(Math.abs(w.appController.responsePane.width / inner.width - 0.35) <= 0.05,
               "the saved split fraction survives the first layout (got "
               + (w.appController.responsePane.width / inner.width) + ")");

        settings.sidebarWidth = 0;
        settings.splitPosition = 0;
        w.appController.paneSidebarWidth = 0;
        w.appController.paneSplitPosition = 0;
        w.appController.sidebar.expandedWidth = 250;
        w.appController.sidebar.splitWidth = 250;
        w.appController.responsePane.expandedWidth = 430;
        w.appController.responsePane.splitWidth = 430;
        wait(120);
    }

    // criterion 8 regression: the window floor squeezes the panes; that live
    // width is not a user choice and must not replace the saved value (on
    // widening or on close)
    function test_layout_squeeze_does_not_overwrite_saved_widths() {
        backend.saveRequest("squeeze/r", baseReq());
        win.appController.openRequest("squeeze/r");
        wait(150);
        var c = win.appController;
        var inner = c.innerSplit;
        var resp = c.responsePane;
        var restoredWidth = win.width;
        compare(inner.orientation, Qt.Horizontal, "the default window is horizontal");

        settings.sidebarWidth = 420;
        settings.splitPosition = 0.6;
        c.paneSidebarWidth = 0;
        c.paneSplitPosition = 0;
        c.restorePanes();
        wait(220);
        var wideSidebar = c.sidebar.width;
        var wideFraction = resp.width / inner.width;
        verify(wideSidebar > 380, "the saved sidebar applies at the wide window (got "
               + wideSidebar + ")");

        // the window floor squeezes the live sidebar without the user dragging
        c.sidebar.expandedWidth = 190;
        c.sidebar.splitWidth = 190;
        wait(120);
        verify(c.sidebar.width < wideSidebar - 20,
               "the live sidebar is squeezed (got " + c.sidebar.width + ")");

        win.width = 1000;
        wait(300);
        compare(inner.orientation, Qt.Vertical, "the panes stack at the floor");

        // closing at the floor must keep the saved values, not the squeeze
        c.persistPanes();
        wait(30);
        verify(Math.abs(settings.sidebarWidth - 420) <= 1,
               "the squeezed width is not persisted (got " + settings.sidebarWidth + ")");
        verify(Math.abs(settings.splitPosition - 0.6) <= 0.01,
               "the saved split survives the stacked layout (got " + settings.splitPosition + ")");

        win.width = restoredWidth;
        wait(300);
        compare(inner.orientation, Qt.Horizontal, "widening restores the horizontal split");
        verify(Math.abs(c.sidebar.width - wideSidebar) <= 2,
               "the saved sidebar width returns (got " + c.sidebar.width + ")");
        verify(Math.abs(resp.width / inner.width - wideFraction) <= 0.05,
               "the saved split fraction returns (got " + (resp.width / inner.width) + ")");

        settings.sidebarWidth = 0;
        settings.splitPosition = 0;
        c.paneSidebarWidth = 0;
        c.paneSplitPosition = 0;
        c.sidebar.expandedWidth = 250;
        c.sidebar.splitWidth = 250;
        c.responsePane.expandedWidth = 430;
        c.responsePane.splitWidth = 430;
        wait(120);
    }

    // criterion 9: vertical stack at <= 1000 px, horizontal above
    function test_layout_stacks_vertically_at_the_window_floor() {
        backend.saveRequest("stack/r", baseReq());
        win.appController.openRequest("stack/r");
        wait(150);
        var c = win.appController;
        var inner = c.innerSplit;
        var resp = c.responsePane;
        var restoredWidth = win.width;
        compare(inner.orientation, Qt.Horizontal, "wide windows keep the horizontal split");
        var horizontalFraction = resp.width / inner.width;

        win.width = 1000;
        wait(300);
        compare(inner.orientation, Qt.Vertical, "the panes stack at 1000 px");
        verify(Math.abs(resp.height - inner.height * 0.4) <= inner.height * 0.08,
               "the stacked response is ~40 % of the height (got " + resp.height
               + " of " + inner.height + ")");

        win.width = restoredWidth;
        wait(300);
        compare(inner.orientation, Qt.Horizontal, "widening restores the horizontal split");
        var back = resp.width / inner.width;
        verify(Math.abs(back - horizontalFraction) <= 0.05,
               "the horizontal widths reapply (got " + back + ", expected " + horizontalFraction + ")");
    }

    // criterion 10: Ctrl+Shift+A opens tab search; matches navigate
    function test_tab_search_opens_and_navigates() {
        var req = baseReq();
        req.url = "http://example/needle";
        req.params = [{ name: "q", value: "needle", enabled: true }];
        req.body = "first needle second needle";
        backend.saveRequest("find/r", req);
        win.appController.openRequest("find/r");
        wait(150);

        var c = win.appController;
        compare(c.shortcutSeq("tabSearch"), "Ctrl+Shift+A", "the shipped default");
        keyClick(Qt.Key_A, Qt.ControlModifier | Qt.ShiftModifier);
        wait(120);
        var search = findChild(win, "tabSearch");
        var field = findChild(win, "tabSearchField");
        verify(search !== null && field !== null, "the tab-search popup exists");
        verify(search.visible, "Ctrl+Shift+A opens tab search");

        // empty query: the prompt, not "no matches", and no result list
        compare(search.hasQuery, false, "the popup opens with an empty query");
        var hint = findChild(search, "tabSearchEmptyHint");
        var list = findChild(search, "tabSearchList");
        var empty = findChild(search, "tabSearchEmpty");
        verify(hint !== null && hint.visible, "the empty-query prompt is shown");
        verify(list !== null && !list.visible, "the result list is hidden while empty");
        verify(empty !== null && !empty.visible, "no match state is not shown before typing");

        field.text = "needle";
        wait(100);
        verify(search.matchCount >= 4,
               "URL, params and two body hits match (got " + search.matchCount + ")");
        compare(search.matches[0].surface, "url", "the URL match comes first");
        compare(search.hasQuery, true, "typing starts the search");
        verify(list.visible, "the result list appears with matches");
        compare(list.count, search.matchCount, "the list shows every match");
        verify(list.itemAtIndex(0) !== null, "the first match row exists");
        var surfaceTag = findChild(list.itemAtIndex(0), "tabSearchSurface");
        verify(surfaceTag !== null, "each row has a surface tag");
        compare(surfaceTag.text, "URL", "the first row names the URL surface");

        field.text = "zzz";
        wait(80);
        verify(empty.visible, "the no-match state appears");
        compare(empty.text, Strings.notFound("zzz"), "the no-match copy carries the query");

        field.text = "needle";
        wait(80);
        field.forceActiveFocus();
        keyClick(Qt.Key_Down);
        wait(40);
        compare(search.currentIndex, 1, "Down advances the selection");
        compare(search.matches[1].surface, "params");

        search.activate(search.matches[search.matchCount - 1]);
        wait(150);
        compare(search.visible, false, "activation closes the popup");
        var bar = findChild(win, "requestTabBar");
        compare(bar.currentIndex, 2, "a body match switches to the Body tab");
        var body = findChild(win, "bodyEditorArea");
        verify(body.selectedText === "needle", "the body match is selected");

        // no request open: no-op, never opens over another tab type
        c.openSettingsTab();
        wait(100);
        c.requestEditor.openTabSearch();
        wait(80);
        verify(!search.visible, "tab search does not open outside a request tab");
    }

    // criterion 11: tab context menu closes others / all
    function test_tab_context_menu_close_others_and_all() {
        backend.saveRequest("ctx/a", baseReq());
        backend.saveRequest("ctx/b", baseReq());
        backend.saveRequest("ctx/c", baseReq());
        var c = win.appController;
        c.openRequest("ctx/a");
        c.pinTab(c.currentTab);
        c.openRequest("ctx/b");
        c.pinTab(c.currentTab);
        c.openRequest("ctx/c");
        c.pinTab(c.currentTab);
        wait(150);
        compare(c.tabsModel.count, 3);

        var menu = findChild(c.tabStrip, "tabCtxMenu");
        verify(menu !== null, "the tab context menu exists");
        verify(findChild(menu, "tabCtxCloseOthers") !== null, "Close others is offered");
        verify(findChild(menu, "tabCtxCloseAll") !== null, "Close all is offered");
        verify(findChild(menu, "tabCtxClose") !== null, "Close is offered");

        c.closeOtherTabs(1);
        wait(120);
        compare(c.tabsModel.count, 1, "Close others keeps one tab");
        compare(c.tabsModel.get(0).relPath, "ctx/b", "it keeps the requested tab");

        c.closeAllTabs();
        wait(120);
        compare(c.tabsModel.count, 0, "Close all reaches the empty state");
        compare(c.currentTab, -1);
    }

    // criterion 11: dirty bulk close uses one count-based confirmation
    function test_tab_bulk_close_dirty_confirmation() {
        backend.saveRequest("dirty/a", baseReq());
        backend.saveRequest("dirty/b", baseReq());
        backend.saveRequest("dirty/c", baseReq());
        var c = win.appController;
        c.openRequest("dirty/a");
        c.pinTab(c.currentTab);
        c.openRequest("dirty/b");
        c.pinTab(c.currentTab);
        c.openRequest("dirty/c");
        c.pinTab(c.currentTab);
        wait(120);
        c.markDirty();
        wait(30);

        var previous = settings.confirmDelete;
        settings.confirmDelete = true;
        c.closeAllTabs();
        wait(120);
        var dialog = findChild(win, "deleteDialog");
        verify(dialog !== null && dialog.visible, "dirty bulk close asks once");
        compare(dialog.message, Strings.closeAllConfirm(1), "the message carries the dirty count");
        var confirm = findChild(dialog, "deleteConfirm");
        verify(confirm !== null, "the confirmation button exists");
        confirm.clicked();
        wait(120);
        compare(c.tabsModel.count, 0, "confirming closes every tab");
        compare(c.currentTab, -1);
        settings.confirmDelete = previous;
    }

    // criterion 12: Ctrl+/ opens the shortcuts overlay with keycap chips; Esc closes
    function test_shortcuts_overlay_and_focus() {
        win.appController.openSettingsTab();
        wait(80);
        var page = findChild(win, "settingsPage");
        verify(page !== null, "the settings screen is reachable");

        keyClick(Qt.Key_Slash, Qt.ControlModifier);
        wait(100);
        var overlay = findChild(win, "shortcutsOverlay");
        verify(overlay !== null, "the shortcuts overlay exists");
        verify(overlay.visible, "Ctrl+/ opens the shortcuts overlay");

        var label = findChild(overlay.contentItem, "shortcutOverlayLabel");
        verify(label !== null, "rows carry a label");
        compare(label.text, Strings.t.shortcutSend, "the first row is the first shortcut");
        var keycap = findChild(overlay.contentItem, "keycap");
        verify(keycap !== null, "a keycap chip exists");
        compare(keycap.label, "Ctrl", "the sequence is split into keycaps");

        keyClick(Qt.Key_Escape);
        wait(80);
        verify(!overlay.visible, "Esc closes the overlay");

        // focusShortcuts still retargets the settings category (contract kept)
        page.focusShortcuts();
        wait(60);
        compare(findChild(win, "settingsCard.shortcuts").visible, true,
                "focusShortcuts selects the Shortcuts card");
    }

    // criterion 13: duplicate capture flags both rows and only the newer wins;
    // reset clears the conflict
    function test_shortcut_duplicate_flag_and_reset() {
        var c = win.appController;
        settings.resetShortcut("newRequest");
        settings.resetShortcut("save");

        settings.setShortcut("newRequest", "Ctrl+Shift+K");
        settings.setShortcut("save", "Ctrl+Shift+K");
        wait(80);

        var conflicts = c.shortcutConflicts();
        compare(conflicts.newRequest, true, "both rows are flagged");
        compare(conflicts.save, true);
        compare(c.shortcutSeq("save"), "Ctrl+Shift+K", "the newer capture holds the key");
        compare(c.shortcutSeq("newRequest"), "Ctrl+T", "the older steps aside to its default");

        win.appController.openSettingsTab();
        wait(80);
        findChild(win, "settingsPage").settingsCategory = 4;
        wait(80);
        var repeater = findChild(win, "shortcutRowsRepeater");
        verify(repeater !== null && repeater.count === c.shortcutDefs.length,
               "one row per shortcut");
        var newRow = repeater.itemAt(1);
        var saveRow = repeater.itemAt(3);
        verify(newRow !== null && saveRow !== null, "shortcut rows exist");
        compare(newRow.conflict, true, "the duplicate row is flagged");
        compare(saveRow.conflict, true);
        var rowLabel = findChild(newRow, "settingsRowLabel");
        verify(rowLabel.font.bold, "the flagged label is bold");
        verify(Qt.colorEqual(rowLabel.color, Kirigami.Theme.negativeTextColor),
               "the flagged label is red");

        settings.resetShortcut("save");
        wait(40);
        compare(c.shortcutConflicts().newRequest, undefined, "reset clears the conflict");
        compare(saveRow.conflict, false);

        settings.resetShortcut("newRequest");
        wait(20);
    }

    // criterion 16: environment colour and collection identity render on every
    // surface (pill, popup, env list, tab strip, sidebar, palette)
    function test_identity_renders_across_surfaces() {
        var c = win.appController;
        backend.saveEnvironment("ident-env", []);
        backend.setEnvironmentColor("ident-env", "#1565c0");
        c.reloadEnvs();
        c.activateEnv("ident-env");
        wait(80);

        var pillDot = findChild(win, "envPillDot");
        verify(pillDot !== null && pillDot.visible, "the env pill carries a colour dot");
        verify(Qt.colorEqual(pillDot.color, "#1565c0"), "the pill dot is the env colour");

        c.openEnvTab("ident-env");
        wait(120);
        var list = findChild(win, "envList");
        var idx = -1;
        for (var i = 0; i < list.count; i++)
            if (list.model[i].name === "ident-env") idx = i;
        verify(idx >= 0, "the environment is listed");
        var listDot = findChild(list.itemAtIndex(idx), "envListDot");
        verify(listDot !== null && listDot.visible, "the env list row carries the dot");
        verify(Qt.colorEqual(listDot.color, "#1565c0"));

        // environment tab: the branch icon is tinted
        var envTabIdx = -1;
        for (var t = 0; t < c.tabsModel.count; t++)
            if (c.tabsModel.get(t).isEnvironment === true) envTabIdx = t;
        verify(envTabIdx >= 0, "the environment tab is open");
        var tabIcon = findChild(tabDelegate(c, envTabIdx), "tabStripTypeIcon");
        verify(tabIcon !== null, "the tab icon exists");
        verify(Qt.colorEqual(tabIcon.color, "#1565c0"), "the environment tab is tinted");

        // palette: env rows use the additive iconColor field
        var palette = findChild(win, "commandPalette");
        palette.openPalette();
        wait(60);
        var envRow = -1;
        for (var p = 0; p < palette.filtered.length; p++)
            if (palette.filtered[p].id === "envVars") envRow = p;
        verify(envRow >= 0, "the palette has the environment row");
        compare(palette.filtered[envRow].iconColor, "#1565c0",
                "palette env rows carry the colour");
        palette.close();

        // collection identity: sidebar depth-0 icon + colour, and the tab strip
        backend.deleteEntry("ident-col");
        backend.createFolder("ident-col");
        backend.setCollectionIdentity("ident-col", "folder-code", "#00838f");
        c.reloadTree();
        wait(100);
        var treeIdx = -1;
        for (var r = 0; r < c.treeModel.count; r++)
            if (c.treeModel.get(r).relPath === "ident-col") treeIdx = r;
        verify(treeIdx >= 0, "the collection is in the tree");
        compare(c.treeModel.get(treeIdx).icon, "folder-code");
        compare(c.treeModel.get(treeIdx).color, "#00838f");
        var treeIcon = findChild(c.sidebar.view.itemAtIndex(treeIdx), "treeRowIcon");
        verify(treeIcon !== null, "the tree row icon exists");
        compare(treeIcon.source, "folder-code");
        verify(Qt.colorEqual(treeIcon.color, "#00838f"), "the tree row is tinted");

        c.openCollection("ident-col");
        wait(100);
        var colTabIdx = c.currentTab;
        var colIcon = findChild(tabDelegate(c, colTabIdx), "tabStripTypeIcon");
        verify(colIcon !== null, "the collection tab icon exists");
        compare(colIcon.source, "folder-code");
        verify(Qt.colorEqual(colIcon.color, "#00838f"), "the collection tab is tinted");

        // round-trip and defaults are unchanged when unset
        verify(backend.setCollectionIdentity("ident-col", "", ""), "identity clears");
        backend.deleteEntry("ident-col");
        backend.setEnvironmentColor("ident-env", "");
        backend.deleteEnvironment("ident-env");
        c.reloadEnvs();
        c.closeTab(c.currentTab);
    }

    // criterion 5: a custom accent retints the selection roles
}
