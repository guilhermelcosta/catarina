.pragma library

// Lógica de domínio pura, independente da UI: parsing/geração de cURL,
// base64 e formatação. Mantido fora do Main.qml de propósito — aqui só entra
// código sem dependência de estado da tela, então dá pra reusar e testar isolado.

// ponytail: Qt.btoa(string) codifica UTF-8 (bom p/ Basic auth), mas está
// deprecado no Qt 6.11+; migrar para o overload de byte-array quando avisar.
function b64(s) { return Qt.btoa(s); }

function q(s) { return "'" + s.replace(/'/g, "'\\''") + "'"; }

function fmtSize(n) {
    if (n < 1024) return n + " B";
    if (n < 1048576) return (n / 1024).toFixed(1) + " KB";
    return (n / 1048576).toFixed(1) + " MB";
}

function tokenizeCurl(s) {
    s = s.replace(/\\\r?\n/g, " ");
    var tokens = [], cur = "", quote = null;
    for (var i = 0; i < s.length; i++) {
        var c = s[i];
        if (quote) { if (c === quote) quote = null; else cur += c; }
        else if (c === "'" || c === '"') quote = c;
        else if (/\s/.test(c)) { if (cur.length) { tokens.push(cur); cur = ""; } }
        else cur += c;
    }
    if (cur.length) tokens.push(cur);
    return tokens;
}

function parseCurl(text) {
    var t = tokenizeCurl(text);
    var r = { method: "", url: "", headers: [], body: "", auth: { type: "none" } };
    for (var i = 0; i < t.length; i++) {
        var a = t[i];
        if (a === "curl") continue;
        if (a === "-X" || a === "--request") r.method = t[++i];
        else if (a === "-H" || a === "--header") {
            var h = t[++i], p = h.indexOf(":");
            if (p > 0) r.headers.push({ name: h.slice(0, p).trim(), value: h.slice(p + 1).trim(), enabled: true });
        } else if (a === "-d" || a === "--data" || a === "--data-raw" || a === "--data-binary" || a === "--data-urlencode") r.body = t[++i];
        else if (a === "-u" || a === "--user") { var up = t[++i].split(":"); r.auth = { type: "basic", user: up[0] || "", pass: up[1] || "" }; }
        else if (a === "--url") r.url = t[++i];
        else if (a === "-I" || a === "--head") r.method = "HEAD";
        else if (a.charAt(0) === "-") { /* ignora flags desconhecidas */ }
        else if (r.url === "") r.url = a;
    }
    if (r.method === "") r.method = r.body.length > 0 ? "POST" : "GET";
    var ct = "";
    for (var j = 0; j < r.headers.length; j++)
        if (r.headers[j].name.toLowerCase() === "content-type") ct = r.headers[j].value.toLowerCase();
    r.bodyType = r.body.length === 0 ? "none" : (ct.indexOf("json") >= 0 ? "json" : "text");
    return r;
}

// gera um comando cURL a partir de um objeto { method, url, headers[], body }
function exportCode(p) {
    var hs = p.headers;
    var s = "curl -X " + p.method + " " + q(p.url);
    for (var a = 0; a < hs.length; a++) s += " \\\n  -H " + q(hs[a].name + ": " + hs[a].value);
    if (p.body.length > 0) s += " \\\n  -d " + q(p.body);
    return s;
}

// Fixação de abas (modelo do VS Code): fixada = permanente; desfixar devolve a
// aba ao estado "preview" (transiente, a próxima request abre sobre ela) e garante
// que só exista um preview. Recebe o estado atual [{pinned, preview}] e o índice
// clicado; devolve só as mudanças [{index, pinned, preview}] a aplicar.
function tabPin(tabs, i) {
    if (i < 0 || i >= tabs.length)
        return [];
    var nowPinned = !(tabs[i].pinned === true);
    var changes = [{ index: i, pinned: nowPinned, preview: !nowPinned }];
    if (!nowPinned) {
        for (var j = 0; j < tabs.length; j++)
            if (j !== i && tabs[j].preview === true)
                changes.push({ index: j, pinned: tabs[j].pinned === true, preview: false });
    }
    return changes;
}

// Reordenação de abas: dado o ponto de inserção "to" (0..count), devolve o
// índice de destino para ListModel.move() e o novo índice da aba ativa.
// Devolve null quando não há mudança.
function tabMove(count, from, to, current) {
    if (from < 0 || from >= count)
        return null;
    if (to < 0) to = 0;
    if (to > count) to = count;
    var dest = to > from ? to - 1 : to;   // após a remoção o índice desloca
    if (dest === from)
        return null;
    if (current === from)
        current = dest;
    else if (from < current && current <= dest)
        --current;
    else if (dest <= current && current < from)
        ++current;
    return { dest: dest, current: current };
}

// Sessão persistida: só abas fixadas sobrevivem ao restart (as demais são
// transientes). Recebe os tabs [{ relPath, pinned }] e o índice ativo; devolve
// a lista de paths a salvar e o índice ativo remapeado (0 se a ativa sumiu).
function sessionPaths(tabs, current) {
    var paths = [], idx = 0;
    for (var i = 0; i < tabs.length; i++) {
        if (tabs[i].pinned !== true) continue;
        if (i === current) idx = paths.length;
        paths.push(tabs[i].relPath);
    }
    return { paths: paths, current: idx };
}
