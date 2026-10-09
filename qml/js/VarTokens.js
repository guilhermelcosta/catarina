.pragma library

// Lógica pura do autocomplete/hover de {{variavel}}, sem dependência de UI —
// por isso testável isolada (tests/tst_components.qml). A parte visual (posição,
// popup) fica no VarCompleter.qml.

// nomes que começam com `partial`, habilitados, ignorando o token em digitação
function matchingNames(resolved, partial) {
    var out = [];
    for (var i = 0; i < resolved.length; i++) {
        var n = resolved[i].name;
        if (resolved[i].enabled === false || n.length === 0) continue;
        if (n.indexOf("{") >= 0 || n.indexOf("}") >= 0) continue;   // ignora "{{"
        if (n.indexOf(partial) === 0) out.push(n);
    }
    out.sort();
    return out;
}

// token {{...}} que contém a posição `pos` no texto
function tokenAt(text, pos) {
    var re = /\{\{\s*([^{}]+?)\s*\}\}/g;
    var m;
    while ((m = re.exec(text)) !== null)
        if (pos >= m.index && pos <= m.index + m[0].length)
            return { name: m[1], start: m.index };
    return null;
}

// item resolvido pelo nome (ou null)
function valueOf(resolved, name) {
    for (var i = 0; i < resolved.length; i++)
        if (resolved[i].name === name) return resolved[i];
    return null;
}
