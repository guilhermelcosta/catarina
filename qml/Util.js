.pragma library

// Pure domain logic, independent of the UI: cURL parsing/generation and
// formatting. Kept out of Main.qml on purpose — only code with no screen-state
// dependency goes here, so it can be reused and tested in isolation.

function q(s) { return "'" + s.replace(/'/g, "'\\''") + "'"; }

// HTML-escape a plain label for a Text.RichText row (palette highlight).
function escapeHtml(s) {
    return String(s === undefined || s === null ? "" : s)
        .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

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

// Fuzzy command-palette match: case-insensitive subsequence. Returns null when
// the label does not contain the query, else { score, ranges } where ranges is
// a list of [start, length] runs to highlight. An empty query matches with no
// ranges. Scores: consecutive runs and word starts are worth more, so better
// matches sort first; the caller keeps the original order on ties.
function fuzzyMatch(query, label) {
    label = String(label === undefined || label === null ? "" : label);
    query = String(query === undefined || query === null ? "" : query);
    if (query.length === 0)
        return { score: 0, ranges: [] };
    var l = label.toLowerCase(), q = query.toLowerCase();
    var positions = [], from = 0;
    for (var i = 0; i < q.length; i++) {
        var at = l.indexOf(q.charAt(i), from);
        if (at < 0) return null;
        positions.push(at);
        from = at + 1;
    }
    var score = 0, ranges = [];
    for (var p = 0; p < positions.length; p++) {
        var pos = positions[p];
        var prev = p > 0 ? positions[p - 1] : -1;
        if (prev >= 0 && pos === prev + 1) score += 3;                 // consecutive run
        if (pos === 0 || /\W/.test(label.charAt(pos - 1))) score += 2; // word start
        ranges.push([pos, 1]);
    }
    // merge adjacent single-character runs into one highlight span
    var merged = [];
    for (var r = 0; r < ranges.length; r++) {
        var last = merged[merged.length - 1];
        if (last && last[0] + last[1] === ranges[r][0]) last[1] += ranges[r][1];
        else merged.push(ranges[r]);
    }
    return { score: score, ranges: merged };
}

// Sidebar filter: rows = [{ relPath, name }]. Returns a map relPath → true for
// every tree hit: the row itself matches (name or path, case-insensitive) or a
// descendant matches, so ancestors of a hit are never hidden. An empty filter
// returns an empty map (the caller treats that as "no filter").
function filterRows(rows, filter) {
    var out = {}, hits = [], f = (filter || "").toLowerCase();
    if (f.length === 0 || !rows) return out;
    for (var i = 0; i < rows.length; i++) {
        var r = rows[i];
        if (!r) continue;
        var path = r.relPath || "", name = r.name || "";
        if (path.toLowerCase().indexOf(f) >= 0 || name.toLowerCase().indexOf(f) >= 0) {
            hits.push(path);
            out[path] = true;
        }
    }
    for (var h = 0; h < hits.length; h++) {
        var p = hits[h];
        var slash = p.lastIndexOf("/");
        while (slash > 0) {
            p = p.substring(0, slash);
            out[p] = true;
            slash = p.lastIndexOf("/");
        }
    }
    return out;
}

// Pretty JSON, or null when the text does not parse.
function prettyJson(text) {
    try {
        return JSON.stringify(JSON.parse(text), null, 2);
    } catch (e) {
        return null;
    }
}

// Body rendering for the format selector. Never throws; non-JSON formats keep
// the stored text untouched.
function formatBody(format, body) {
    if (body === undefined || body === null) return "";
    if (format === "json") {
        var pretty = prettyJson(body);
        return pretty === null ? body : pretty;
    }
    return body;
}

// Counts for the response tab labels: 0 when there is nothing to count.
function headerCount(headers) {
    if (!Array.isArray(headers)) return 0;
    return headers.length;
}

function cookieCount(cookies) {
    if (typeof cookies !== "string" || cookies.length === 0) return 0;
    var lines = cookies.split(/\r?\n/), n = 0;
    for (var i = 0; i < lines.length; i++)
        if (lines[i].trim().length > 0) n++;
    return n;
}

// Tab search over the open request: case-insensitive substring hits over the
// URL, the table rows (name + value) and the body. Returns
// [{ surface, index, label, snippet, start, end }]: `index` is the row index
// for table surfaces (-1 otherwise), `start`/`end` are offsets in the source
// text (used to select a body range) and `snippet` is the text shown in the
// result list. An empty query matches nothing.
function tabSearchMatches(request, query) {
    var out = [];
    var q = String(query === undefined || query === null ? "" : query).toLowerCase();
    if (!request || q.length === 0) return out;

    function snippetAround(text, at, len) {
        var pad = 28;
        var from = Math.max(0, at - pad);
        var to = Math.min(text.length, at + len + pad);
        return (from > 0 ? "…" : "") + text.substring(from, to) + (to < text.length ? "…" : "");
    }
    function addHit(surface, index, label, text, at) {
        out.push({ surface: surface, index: index, label: String(label || ""),
                   snippet: snippetAround(text, at, q.length), start: at, end: at + q.length });
    }
    function scanRow(surface, index, row) {
        var name = String(row && row.name !== undefined ? row.name : "");
        var value = String(row && row.value !== undefined ? row.value : "");
        var text = name.length > 0 ? name + ": " + value : value;
        var at = text.toLowerCase().indexOf(q);
        if (at >= 0) addHit(surface, index, name.length > 0 ? name : value, text, at);
    }

    var url = String(request.url !== undefined && request.url !== null ? request.url : "");
    var urlAt = url.toLowerCase().indexOf(q);
    if (urlAt >= 0) addHit("url", -1, "URL", url, urlAt);

    var surfaces = [
        { id: "params", rows: request.params },
        { id: "headers", rows: request.headers },
        { id: "fields", rows: request.fields },
        { id: "vars", rows: request.vars }
    ];
    for (var s = 0; s < surfaces.length; s++) {
        var rows = surfaces[s].rows || [];
        for (var i = 0; i < rows.length; i++) scanRow(surfaces[s].id, i, rows[i]);
    }

    var body = String(request.body !== undefined && request.body !== null ? request.body : "");
    var lower = body.toLowerCase(), from = 0, at = lower.indexOf(q, from);
    while (at >= 0) {
        addHit("body", -1, "Body", body, at);
        from = at + q.length;
        at = lower.indexOf(q, from);
    }
    return out;
}

// Relative luminance (WCAG) of a colour: "#rrggbb" string or a Qt color
// object ({r,g,b} in 0..1). Returns 0..1; invalid input returns 0.
function luminance(c) {
    var r = 0, g = 0, b = 0;
    if (typeof c === "string") {
        var m = /^#([0-9a-fA-F]{6})$/.exec(c);
        if (!m) return 0;
        var n = parseInt(m[1], 16);
        r = ((n >> 16) & 255) / 255;
        g = ((n >> 8) & 255) / 255;
        b = (n & 255) / 255;
    } else if (c && c.r !== undefined) {
        r = c.r; g = c.g; b = c.b;
    } else {
        return 0;
    }
    function linear(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

// 1-based line/column for a cursor position, used by the response line reference.
function lnCol(position, text) {
    text = text || "";
    if (position < 0) position = 0;
    if (position > text.length) position = text.length;
    var line = 1, col = 1;
    for (var i = 0; i < position; i++) {
        if (text.charAt(i) === "\n") { line++; col = 1; }
        else col++;
    }
    return { line: line, col: col };
}
