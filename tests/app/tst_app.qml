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

    // ---- edição: dirty / despin / reverter / salvar ----
    function test_editar_marca_dirty_e_reverter() {
        backend.saveRequest("t/e", baseReq());
        win.appController.openRequest("t/e");
        compare(win.appController.tabsModel.get(0).dirty, false);
        win.appController.requestEditor.url = "http://mudou";
        win.appController.markDirty();
        compare(win.appController.tabsModel.get(0).dirty, true);
        compare(win.appController.currentDirty, true);
        win.appController.revertCurrent();
        compare(win.appController.tabsModel.get(0).dirty, false);
        compare(win.appController.collectRequest().url, "http://exemplo/x");
    }

    function test_edicao_desfixa_preview() {
        backend.saveRequest("t/pv", baseReq());
        win.appController.openRequest("t/pv");
        compare(win.appController.tabsModel.get(0).preview, true);
        win.appController.requestEditor.url = "http://x2";
        win.appController.markDirty();
        compare(win.appController.tabsModel.get(0).preview, false);   // editar fixa a aba
    }

    function test_save_persiste_e_limpa_dirty() {
        backend.saveRequest("t/sv", baseReq());
        win.appController.openRequest("t/sv");
        win.appController.requestEditor.url = "http://salvo";
        win.appController.markDirty();
        win.appController.saveCurrent();
        compare(backend.loadRequest("t/sv").url, "http://salvo");
        compare(win.appController.tabsModel.get(0).dirty, false);
    }

    // digitação no campo de URL dispara textEdited → markDirty (mesmo caminho do teclado)
    function test_edicao_dispara_dirty() {
        backend.saveRequest("t/kb", baseReq());
        win.appController.openRequest("t/kb");
        compare(win.appController.tabsModel.get(0).dirty, false);
        var f = win.appController.requestEditor.urlInput;
        verify(f, "campo de URL exposto");
        f.text = "http://digitado";
        f.textEdited();
        compare(win.appController.tabsModel.get(0).dirty, true);
    }

    // ---- reordenar / mover ----
    function test_move_tab_reordena() {
        backend.saveRequest("t/1", baseReq("GET"));
        backend.saveRequest("t/2", baseReq("POST"));
        win.appController.openRequest("t/1");
        win.appController.pinTab(0);
        win.appController.openRequest("t/2");
        compare(win.appController.tabsModel.get(0).relPath, "t/1");
        compare(win.appController.tabsModel.get(1).relPath, "t/2");
        win.appController.moveTab(0, 2);   // move t/1 para o fim
        compare(win.appController.tabsModel.get(0).relPath, "t/2");
        compare(win.appController.tabsModel.get(1).relPath, "t/1");
    }

    function test_tab_index_at_insercao() {
        backend.saveRequest("t/idx", baseReq());
        win.appController.openRequest("t/idx");
        wait(50);
        compare(win.appController.tabIndexAt(-1), 0);       // antes do primeiro
        compare(win.appController.tabIndexAt(100000), 1);   // depois do último
    }

    // ---- exclusão respeita settings.confirmDelete ----
    function test_delete_respeita_confirmacao() {
        backend.saveRequest("t/del", baseReq());
        win.appController.selectedPath = "t/del";
        settings.confirmDelete = true;
        win.appController.askDelete();
        compare(backend.loadRequest("t/del").method, "GET");   // diálogo aberto, nada apagado
        settings.confirmDelete = false;
        win.appController.askDelete();
        compare(backend.loadRequest("t/del").method, undefined);   // apagado
        settings.confirmDelete = true;   // restaura o padrão
    }

    // ---- import de cURL abre a request importada ----
    function test_import_curl() {
        win.appController.importCurl("curl -X POST https://exemplo/api -H 'X-Test: 1' -d '{\"a\":1}'");
        compare(win.appController.tabsModel.count, 1);
        compare(win.appController.collectRequest().method, "POST");
        verify(win.appController.collectRequest().headers.length >= 1);
    }
}
