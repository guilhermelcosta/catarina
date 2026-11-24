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
        verify(Qt.colorEqual(paletteRow.contentItem.color, palettePlain.contentItem.color),
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
        win.width = win.minimumWidth;
        wait(100);
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
        wait(100);

        var theme = win.appController.theme;
        var tabs = tabDelegates();
        var active = findChild(tabs[1], "tabSurface");
        var inactive = findChild(tabs[0], "tabSurface");
        verify(Qt.colorEqual(active.color, win.Kirigami.Theme.backgroundColor),
               "the active tab paints the raised surface");
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
        var del = c.sidebar.view.itemAtIndex(idx);
        verify(del, "delegate visible");

        var label = findChild(del, "treeMethodLabel");
        verify(label !== null, "plain method label replaces the badge");
        compare(label.text, "PUT");
        compare(label.font.pixelSize, 10);
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
        compare(lineRef.text, "2, 2");

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
}
