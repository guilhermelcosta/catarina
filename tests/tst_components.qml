import QtQuick
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

    ListModel { id: kvModel }
    HeaderTable { id: ht }
    JsonTree { id: tree }
    KvTable { id: kv; model: kvModel }

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
}
