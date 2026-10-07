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
