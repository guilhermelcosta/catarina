import QtQuick
import QtQuick.Controls
import QtTest
import org.kde.kirigami as Kirigami
import "../../qml"

// Comportamento de tela: instancia o Main real (com backend/settings injetados
// pelo tst_app.cpp) e exercita o AppController — abas, preview/pin, sessão,
// aplicar/coletar request, alvo de criação, abas singleton de ambiente/coleção.
TestCase {
    id: root
    name: "AppBehavior"
    when: windowShown

    Component { id: appComponent; Main {} }
    property var win: null

    function init() {
        if (win) { win.destroy(); win = null; }
        win = appComponent.createObject(null);
        verify(win, "não consegui criar o Main");
        win.visible = true;
    }
    function cleanupTestCase() {
        if (win) { win.destroy(); win = null; }
    }

    function baseReq(method) {
        return { method: method !== undefined ? method : "GET", url: "http://exemplo/x",
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

    function test_preview_tab_e_pin() {
        backend.saveRequest("t/a", baseReq("GET"));
        backend.saveRequest("t/b", baseReq("POST"));
        win.appController.openRequest("t/a");
        compare(win.appController.tabsModel.count, 1);
        // a segunda request reutiliza a aba preview (transiente)
        win.appController.openRequest("t/b");
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.tabsModel.get(0).relPath, "t/b");
        // fixando, a próxima abre uma nova aba
        win.appController.pinTab(0);
        win.appController.openRequest("t/a");
        compare(win.appController.tabsModel.count, 2);
    }

    function test_switch_aplica_editor() {
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
        compare(win.appController.tabsModel.count, n);   // não duplica
        compare(win.appController.showingEnv, true);
    }

    function test_collection_tab() {
        backend.createFolder("colA");
        win.appController.openCollection("colA");
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.showingCollection, true);
        compare(win.appController.collectionPath, "colA");
    }

    function test_session_restore_pins_e_ambiente() {
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
}
