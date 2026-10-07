import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import "../qml"
import "../qml/Util.js" as Util

// Testes dos componentes reutilizáveis e da lógica pura do JsonTree.
TestCase {
    id: root
    name: "Components"
    when: windowShown

    // stub do highlighter/clipboard que o KvTable usa no contexto real
    QtObject {
        id: varSupport
        function attach() {}
        function copyText(t) {}
        function clipboardText() { return ""; }
    }

    // stub de settings: o KvTable consulta settings.confirmDelete ao remover linha
    QtObject {
        id: settings
        property bool confirmDelete: false
    }

    // já com uma linha: a ListView precisa estar visível no layout inicial do teste
    ListModel {
        id: kvModel
        ListElement { name: "chave-x"; value: "valor-x"; enabled: true }
    }
    HeaderTable { id: ht }
    JsonTree { id: tree }
    VarCompleter { id: comp }
    TextArea { id: emitProbe; onTextEdited: root.probeCount++ }
    property int probeCount: 0

    // setar `text` programaticamente não emite textEdited (só o usuário emite). O
    // popup precisa emitir para o modelo do KvTable (onTextEdited) atualizar ao escolher.
    function test_varcompleter_choose_notifica_edicao() {
        root.probeCount = 0;
        emitProbe.text = "{{";
        comp.target = emitProbe;
        comp.tokenStart = 0;
        comp.partial = "";
        comp.choose("teste");
        compare(emitProbe.text, "{{teste}}");
        compare(root.probeCount, 1);
    }
    KvTable { id: kv; model: kvModel; width: 800; height: 400 }
    ResolvedVarsTable {
        id: rvt
        vars: [{ name: "a", value: "1", enabled: true }, { name: "b", value: "2", enabled: false }]
    }

    // a visualização de variáveis efetivas não mostra as desabilitadas
    function test_resolved_vars_filters_disabled() {
        compare(rvt.count, 1);
        compare(rvt.activeVars[0].name, "a");
    }

    // o popup não deve sugerir o próprio token em digitação ("{{") nem nomes com chaves
    function test_varcompleter_filters_braces() {
        comp.resolved = [
            { name: "teste", enabled: true },
            { name: "{{teste}}", enabled: true },
            { name: "{{", enabled: true },
            { name: "", enabled: true },
            { name: "off", enabled: false }
        ];
        comp.partial = "";
        var names = comp.matchingNames();
        compare(names.length, 1);
        compare(names[0], "teste");
    }

    // cabeçalho e linha precisam usar a MESMA largura por coluna (o bug era o fillWidth
    // com preferred implícito; agora usam preferred/minimum explícitos e iguais)
    function test_kvtable_columns_aligned() {
        var hdr = findChild(kv, "kvHeader");
        var lv = findChild(kv, "kvList");
        verify(hdr !== null, "kvHeader não encontrado");
        verify(lv !== null, "kvList não encontrado");
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate não criado");
        // header: [ativo, chave, valor, tipo, escopo, segredo, remover]
        // row:    [ativo, chave, arquivo, valor-segredo, valor, tipo, escopo, segredo, remover]
        compare(hdr.children[0].Layout.preferredWidth, row.children[0].Layout.preferredWidth);   // ativo
        compare(hdr.children[1].Layout.preferredWidth, row.children[1].Layout.preferredWidth);   // chave
        compare(hdr.children[1].Layout.minimumWidth, row.children[1].Layout.minimumWidth);
        compare(hdr.children[2].Layout.preferredWidth, row.children[4].Layout.preferredWidth);   // valor
        compare(hdr.children[2].Layout.minimumWidth, row.children[4].Layout.minimumWidth);
        compare(hdr.children[6].Layout.preferredWidth, row.children[8].Layout.preferredWidth);   // remover
        // as três "caras" da coluna valor compartilham a mesma largura
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
        compare(tree.isOpenAt("$.a"), true);   // depth 0 vem aberto por padrão
        tree.toggle("$.a");
        compare(tree.isOpenAt("$.a"), false);  // grava estado explícito
        tree.toggle("$.a");
        compare(tree.isOpenAt("$.a"), true);
    }

    function test_jsontree_invalid() {
        tree.load("não é json");
        wait(50);
        compare(tree.root, undefined);
    }

    function test_kvtable_rows() {
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

    // com confirmação ligada, tryRemove NÃO remove até confirmar
    function test_kvtable_remove_needs_confirm() {
        settings.confirmDelete = true;
        kvModel.clear();
        kvModel.append({ name: "x", value: "1", enabled: true });
        wait(50);
        kv.tryRemove(0);
        wait(50);
        compare(kvModel.count, 1);           // aguarda confirmação
        var dlg = findChild(kv, "confirmRemoveDialog");
        if (dlg) dlg.close();
        kvModel.clear();
    }

    // com confirmação desligada, tryRemove remove direto
    function test_kvtable_remove_direct() {
        settings.confirmDelete = false;
        kvModel.clear();
        kvModel.append({ name: "x", value: "1", enabled: true });
        wait(50);
        compare(kvModel.count, 1);
        kv.tryRemove(0);
        compare(kvModel.count, 0);
    }

    // ---- Util.js: domínio puro ----
    function test_util_b64() {
        compare(Util.b64("a"), "YQ==");
        compare(Util.b64("user:pass"), "dXNlcjpwYXNz");
        compare(Util.b64("aé"), "YcOp");   // UTF-8
    }

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

    // [A,B,C,D]: B(1) -> inserir antes de D(to=3) => [A,C,B,D]
    function test_util_tabMove() {
        var m = Util.tabMove(4, 1, 3, 1);
        compare(m.dest, 2);
        compare(m.current, 2);          // a própria aba movida segue ativa
        compare(Util.tabMove(4, 1, 3, 2).current, 1);   // C foi para a esquerda
        compare(Util.tabMove(4, 1, 3, 3).current, 3);   // D não se move
        compare(Util.tabMove(4, 1, 3, 0).current, 0);   // A não se move

        // [A,B,C,D]: D(3) -> inserir antes de B(to=1) => [A,D,B,C]
        compare(Util.tabMove(4, 3, 1, 3).dest, 1);
        compare(Util.tabMove(4, 3, 1, 1).current, 2);
        compare(Util.tabMove(4, 3, 1, 2).current, 3);

        // no-op: inserir logo depois de si mesmo
        compare(Util.tabMove(4, 1, 2, 0), null);
        // limites: inserir no fim
        compare(Util.tabMove(4, 0, 4, 0).dest, 3);
    }

    // fixar/desfixar (VS Code): desfixar devolve a aba ao preview e mantém só um
    function test_util_tabPin() {
        // fixar a aba preview -> deixa de ser preview
        var m = Util.tabPin([{ pinned: false, preview: true }, { pinned: false, preview: false }], 0);
        compare(m.length, 1);
        compare(m[0].index, 0);
        compare(m[0].pinned, true);
        compare(m[0].preview, false);

        // desfixar -> volta a preview
        m = Util.tabPin([{ pinned: true, preview: false }], 0);
        compare(m.length, 1);
        compare(m[0].pinned, false);
        compare(m[0].preview, true);

        // desfixar com outra preview aberta -> só uma preview sobra (a última)
        m = Util.tabPin([{ pinned: true, preview: false }, { pinned: false, preview: true }], 0);
        compare(m.length, 2);
        compare(m[0].preview, true);
        compare(m[1].index, 1);
        compare(m[1].preview, false);

        // fixar uma aba que não é preview -> não mexe na preview ativa
        m = Util.tabPin([{ pinned: false, preview: false }, { pinned: false, preview: true }], 0);
        compare(m.length, 1);
        compare(m[0].pinned, true);

        // índice inválido
        compare(Util.tabPin([], 0).length, 0);
    }

    // sessão persistida: só abas fixadas voltam ao reabrir o app
    function test_util_sessionPaths() {
        // fixada no meio, não-fixadas descartadas; ativa remapeada p/ a posição salva
        var s = Util.sessionPaths([
            { relPath: "a", pinned: true },
            { relPath: "b", pinned: false },
            { relPath: "c", pinned: true }
        ], 2);
        compare(s.paths.length, 2);
        compare(s.paths[0], "a");
        compare(s.paths[1], "c");
        compare(s.current, 1);

        // ativa era não-fixada → cai para 0
        s = Util.sessionPaths([{ relPath: "a", pinned: true }, { relPath: "b", pinned: false }], 1);
        compare(s.paths.length, 1);
        compare(s.current, 0);

        // nenhuma fixada → lista vazia
        s = Util.sessionPaths([{ relPath: "b", pinned: false }], 0);
        compare(s.paths.length, 0);
        compare(s.current, 0);
    }

    // ListModel + delegate: uma role criada por setProperty DEPOIS que o delegate já
    // existe não chega ao delegate (model.pinned fica undefined para sempre). Foi a
    // causa de a aba fixada voltar a mostrar o X depois de restaurar a sessão: o append
    // não declarava "pinned"/"preview". Por isso TODO append declara as duas roles.
    ListModel { id: roleModelTarde }
    ListModel { id: roleModelCedo }
    ListView {
        id: roleViewTarde
        width: 100; height: 60
        model: roleModelTarde
        delegate: Text { text: String(model.pinned) }
    }
    ListView {
        id: roleViewCedo
        width: 100; height: 60
        model: roleModelCedo
        delegate: Text { text: String(model.pinned) }
    }

    function test_listmodel_roles_declaradas() {
        roleModelTarde.append({ name: "a" });            // sem declarar "pinned"
        wait(30);
        roleModelTarde.setProperty(0, "pinned", true);   // role criada tarde
        wait(50);
        compare(roleViewTarde.itemAtIndex(0).text, "undefined");   // delegate não vê a role tardia

        roleModelCedo.append({ name: "b", pinned: false });        // role declarada no append
        wait(30);
        roleModelCedo.setProperty(0, "pinned", true);
        wait(50);
        compare(roleViewCedo.itemAtIndex(0).text, "true");         // delegate acompanha
    }
}
