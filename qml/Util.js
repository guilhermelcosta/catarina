.pragma library

// Pure domain logic, independent of the UI: cURL parsing/generation and
// formatting. Kept out of Main.qml on purpose — only code with no screen-state
// dependency goes here, so it can be reused and tested in isolation.

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
        else if (a.charAt(0) === "-") { /* ignore unknown flags */ }
        else if (r.url === "") r.url = a;
    }
    if (r.method === "") r.method = r.body.length > 0 ? "POST" : "GET";
    var ct = "";
    for (var j = 0; j < r.headers.length; j++)
        if (r.headers[j].name.toLowerCase() === "content-type") ct = r.headers[j].value.toLowerCase();
    r.bodyType = r.body.length === 0 ? "none" : (ct.indexOf("json") >= 0 ? "json" : "text");
    return r;
}

// generates a cURL command from an object { method, url, headers[], body }
function exportCode(p) {
    var hs = p.headers;
    var s = "curl -X " + p.method + " " + q(p.url);
    for (var a = 0; a < hs.length; a++) s += " \\\n  -H " + q(hs[a].name + ": " + hs[a].value);
    if (p.body.length > 0) s += " \\\n  -d " + q(p.body);
    return s;
}

// Canonical JSON: sorts object keys recursively (arrays keep their order).
// Used to compare ("dirty") states ignoring key order — returning to the
// original value must compare equal, even if the object was rebuilt.
function stableStringify(v) {
    if (Array.isArray(v))
        return "[" + v.map(stableStringify).join(",") + "]";
    if (v !== null && typeof v === "object") {
        var keys = Object.keys(v).sort(), parts = [];
        for (var i = 0; i < keys.length; i++) {
            if (v[keys[i]] === undefined) continue;
            parts.push(JSON.stringify(keys[i]) + ":" + stableStringify(v[keys[i]]));
        }
        return "{" + parts.join(",") + "}";
    }
    return JSON.stringify(v);
}

// Tab pinning (VS Code model): pinned = permanent; unpinning returns the
// tab to the "preview" state (transient, the next request opens over it) and ensures
// only one preview exists. Takes the current state [{pinned, preview}] and the
// clicked index; returns only the changes [{index, pinned, preview}] to apply.
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

// Tab reordering: given the insertion point "to" (0..count), returns the
// destination index for ListModel.move() and the new index of the active tab.
// Returns null when there is no change.
function tabMove(count, from, to, current) {
    if (from < 0 || from >= count)
        return null;
    if (to < 0) to = 0;
    if (to > count) to = count;
    var dest = to > from ? to - 1 : to;   // after removal the index shifts
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

// Persisted session: only pinned tabs survive a restart (the rest are
// transient). Takes the tabs [{ relPath, pinned }] and the active index; returns
// the list of paths to save and the remapped active index (0 if the active one is gone).
function sessionPaths(tabs, current) {
    var paths = [], idx = 0;
    for (var i = 0; i < tabs.length; i++) {
        if (tabs[i].pinned !== true) continue;
        if (i === current) idx = paths.length;
        paths.push(tabs[i].relPath);
    }
    return { paths: paths, current: idx };
}
