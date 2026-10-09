import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
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
    // componentes padrão de diálogo (mesmo espaçamento/respiro em todos os modais)
    DialogActions {
        id: dialogActions
        Button { text: "A" }
        Button { text: "B" }
    }
    DialogHeader { id: dialogHeader; dialogTitle: "T" }

    // padrão de corpo de diálogo: é o próprio contentItem, então dimensiona pelo conteúdo
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
    // ramos do KvTable exercitados por testes (segredo, arquivo, filtro de linha)
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

    // a visualização de variáveis efetivas não mostra as desabilitadas
    function test_resolved_vars_filters_disabled() {
        compare(rvt.count, 1);
        compare(rvt.activeVars[0].name, "a");
    }

    // ordena por origem (global → collection → request) e, dentro dela, por nome
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

    // rodapé padrão de diálogo: espaçamento e respiro constantes, botões à direita
    function test_dialog_actions_standard() {
        compare(dialogActions.spacing, Kirigami.Units.smallSpacing);
        compare(dialogActions.Layout.bottomMargin, Kirigami.Units.smallSpacing);
        compare(dialogActions.children.length, 3, "espaçador + 2 botões");
        verify(dialogActions.children[0].text === undefined, "primeiro filho é o espaçador");
        compare(dialogActions.children[1].text, "A");
        compare(dialogActions.children[2].text, "B");
    }

    // corpo padrão de diálogo: contentItem é o ColumnLayout e auto-dimensiona
    function test_dialog_content_autosizes() {
        compare(testDialogBody.spacing, Kirigami.Units.smallSpacing);
        verify(testDialog.implicitHeight > 0, "diálogo dimensiona pelo conteúdo");
    }

    // cabeçalho padrão de diálogo
    function test_dialog_header_standard() {
        compare(dialogHeader.text, "T");
        compare(dialogHeader.type, Kirigami.Heading.Type.Primary);
        compare(dialogHeader.bottomPadding, 0);
    }

    // Enter sobre um botão focado do rodapé do diálogo dispara o clique (Tab move o foco)
    function test_dialog_enter_clicks_focused_button() {
        var btnA = dialogActions.children[1];
        var btnB = dialogActions.children[2];
        var clicked = 0;
        btnB.clicked.connect(function () { clicked++; });
        btnB.forceActiveFocus();
        wait(20);
        compare(btnB.activeFocus, true, "foco no botão B");
        keyClick(Qt.Key_Return);
        wait(20);
        compare(clicked, 1, "Enter clica o botão focado");
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

    // Tab/Shift+Tab movem o foco entre as células editáveis da tabela
    function test_kvtable_tab_navigates_cells() {
        settings.confirmDelete = false;
        kvModel.clear();
        kvModel.append({ name: "a", value: "1", enabled: true });
        wait(50);
        var lv = findChild(kv, "kvList");
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate não criado");
        var keyField = row.children[1];
        var valField = row.children[4];
        keyField.forceActiveFocus();
        wait(20);
        compare(keyField.activeFocus, true, "foco inicial no campo chave");
        keyClick(Qt.Key_Tab);
        wait(20);
        compare(valField.activeFocus, true, "Tab vai para o campo valor");
        keyClick(Qt.Key_Backtab);
        wait(20);
        compare(keyField.activeFocus, true, "Shift+Tab volta para o campo chave");
        kvModel.clear();
    }

    // ---- Util.js: domínio puro ----
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

    function test_util_querySuffix() {
        var p = [{ name: "a", value: "1", enabled: true }];
        compare(Util.querySuffix("https://x/y", p), "?a=1");
        compare(Util.querySuffix("https://x/y?z=0", p), "&a=1");
        compare(Util.querySuffix("https://x/y?", p), "a=1");          // '?' final: sem separador
        compare(Util.querySuffix("https://x/y", [{ name: "a", value: "", enabled: true }]), "?a=");
        // desabilitado / sem nome são ignorados
        compare(Util.querySuffix("https://x/y", [{ name: "a", value: "1", enabled: false }]), "");
        compare(Util.querySuffix("https://x/y", [{ name: "", value: "1", enabled: true }]), "");
        // vários params na ordem
        compare(Util.querySuffix("https://x/y", [
            { name: "a", value: "1", enabled: true },
            { name: "b", value: "2", enabled: true }]), "?a=1&b=2");
        compare(Util.querySuffix("https://x/y", []), "");
    }

    // JSON canônico: ignora a ordem das chaves (é o que decide o dirty ao desfazer)
    function test_util_stableStringify() {
        compare(Util.stableStringify({ a: 1, b: 2 }), Util.stableStringify({ b: 2, a: 1 }));
        compare(Util.stableStringify({ a: { x: 1, y: 2 }, b: [1, 2] }),
                Util.stableStringify({ b: [1, 2], a: { y: 2, x: 1 } }));
        verify(Util.stableStringify({ a: 1 }) !== Util.stableStringify({ a: 2 }));
        verify(Util.stableStringify([1, 2]) !== Util.stableStringify([2, 1]));   // array importa ordem
        // mudar e voltar ao original => mesmo snapshot (dirty some)
        var base = Util.stableStringify({ url: "x", vars: [{ name: "a", value: "1" }] });
        var cur = Util.stableStringify({ vars: [{ value: "1", name: "a" }], url: "y" });
        verify(cur !== base);
        cur = Util.stableStringify({ vars: [{ name: "a", value: "1" }], url: "x" });
        compare(cur, base);
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

    // VarField embute o VarCompleter e propaga `resolved` (o bug do font.family
    // passou batido por não haver teste de instanciação)
    function test_varfield_wiring() {
        var c = findChild(vf, "varCompleter");
        verify(c !== null, "VarCompleter não anexado ao VarField");
        verify(c.target === vf, "target do completer deve ser o VarField");
        compare(c.resolved.length, 1);
        compare(c.resolved[0].name, "x");
    }

    // campo de uma linha: Enter não insere quebra de linha (é TextArea por causa do highlight)
    function test_varfield_enter_nao_quebra_linha() {
        vf.text = "abc";
        vf.forceActiveFocus();
        keyClick(Qt.Key_Return);
        keyClick(Qt.Key_Enter);
        compare(vf.text.indexOf("\n"), -1, "Enter não quebra linha");
        compare(vf.text, "abc");
    }

    // coluna Segredo: campo mascarado (echoMode Password) + editor normal associado
    function test_kvtable_secret_column() {
        wait(50);
        var lv = findChild(kvSecret, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate não criado");
        compare(row.children.length, 9, "nº de filhos do delegate");
        compare(row.children[3].echoMode, TextInput.Password, "campo mascarado");
        compare(row.children[4].placeholderText, "Value", "editor normal");
        // altura igual ao editor normal: as bolinhas do echoMode não podem mexer na linha
        compare(row.children[3].implicitHeight, row.children[4].implicitHeight, "altura do campo secreto");
        // olho espiar: alterna o echoMode sem desmarcar segredo
        var eye = findChild(row.children[3], "kvRevealButton");
        verify(eye !== null, "olho de revelar não encontrado");
        eye.clicked();
        compare(row.children[3].echoMode, TextInput.Normal, "revelado");
        compare(row.children[3].text, "v", "valor acessível");
        eye.clicked();
        compare(row.children[3].echoMode, TextInput.Password, "mascarado de novo");
    }

    // modo campos: botão de arquivo no lugar do editor de valor
    function test_kvtable_file_column() {
        wait(50);
        var lv = findChild(kvFiles, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate não criado");
        compare(row.children[2].icon.name, "document-open", "botão de arquivo");
    }

    function test_kvtable_row_filter() {
        filterModel.clear();
        filterModel.append({ name: "f", value: "1", enabled: true });
        wait(50);
        var lv = findChild(kvFilter, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate não criado");
        compare(row.shown, false, "linha filtrada");
        compare(row.height, 0, "altura zero quando filtrada");
        filterModel.clear();
    }

    // chip de escopo usa a cor vinda do callback scopeColor
    function test_kvtable_scope_color() {
        wait(50);
        var lv = findChild(kvScope, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate não criado");
        var chip = findChild(row, "scopeChip");
        verify(chip !== null, "scopeChip não encontrado");
        compare(String(chip.tint), "#ff0000");
    }

    // nome repetido (uniqueNames) marca o campo com erroText; sem uniqueNames, não
    function test_kvtable_duplicate_name_highlight() {
        wait(50);
        var lv = findChild(kvDup, "kvList");
        verify(lv !== null);
        var row = lv.itemAtIndex(0);
        verify(row !== null, "delegate não criado");
        compare(row.children[1].errorText.length > 0, true, "nome repetido marca erro");
        var lv2 = findChild(kvSecret, "kvList");
        compare(lv2.itemAtIndex(0).children[1].errorText.length === 0, true, "sem uniqueNames não marca");
    }

    function test_util_q() {
        compare(Util.q("simples"), "'simples'");
        compare(Util.q("a'b"), "'a'\\''b'");   // escapa apóstrofo pro shell
    }

    function test_util_tokenizeCurl() {
        compare(JSON.stringify(Util.tokenizeCurl("a 'b c' d")), '["a","b c","d"]');
        compare(JSON.stringify(Util.tokenizeCurl('x "y z"')), '["x","y z"]');
        compare(JSON.stringify(Util.tokenizeCurl("a \\\nb")), '["a","b"]');   // continuação de linha
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
        compare(tree.isOpenAt("$.a.b"), true);   // depth 1 ainda abre por padrão
    }
}
