.pragma library

// Pure logic for {{variable}} autocomplete/hover, with no UI dependency —
// hence testable in isolation (tests/tst_components.qml). The visual part
// (position, popup) lives in VarCompleter.qml.

// names that start with `partial`, enabled, ignoring the token being typed
function matchingNames(resolved, partial) {
    var out = [];
    for (var i = 0; i < resolved.length; i++) {
        var n = resolved[i].name;
        if (resolved[i].enabled === false || n.length === 0) continue;
        if (n.indexOf("{") >= 0 || n.indexOf("}") >= 0) continue;   // ignore "{{"
        if (n.indexOf(partial) === 0) out.push(n);
    }
    out.sort();
    return out;
}

// {{...}} token that contains position `pos` in the text
function tokenAt(text, pos) {
    var re = /\{\{\s*([^{}]+?)\s*\}\}/g;
    var m;
    while ((m = re.exec(text)) !== null)
        if (pos >= m.index && pos <= m.index + m[0].length)
            return { name: m[1], start: m.index };
    return null;
}

// item resolved by name (or null)
function valueOf(resolved, name) {
    for (var i = 0; i < resolved.length; i++)
        if (resolved[i].name === name) return resolved[i];
    return null;
}
