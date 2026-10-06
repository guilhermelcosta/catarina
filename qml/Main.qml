import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtWebEngine
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    width: 1280
    height: 800
    minimumWidth: 1000
    minimumHeight: 560

    // ---- árvore/coleções ----
    property string selectedPath: ""
    property bool selectedIsFolder: false
    property bool showingCollection: false
    property bool sidebarVisible: true
    property bool responseVisible: true
    property string collectionPath: ""
    property bool collectionIsSubfolder: false
    property string dropTarget: ""
    property bool dropIsFolder: false
    property bool dragging: false
    property bool justDragged: false
    property string dragFrom: ""
    property string dragLabel: ""
    property string dragMethod: ""
    property real ghostX: 0
    property real ghostY: 0
    property var collapsedFolders: ({})
    property var collectionRequests: []
    property int collectionFolders: 0
    property bool collectionVarsDirty: false
    property int collectionTab: 0
    property bool collectionHeadersDirty: false

    // ---- abas ----
    ListModel { id: tabsModel }
    property int currentTab: -1
    property var closedTabs: []
    property var responses: ({})       // relPath -> { status, statusText, time, size, headers, body }
    property bool sending: false
    property bool responseIsHtml: false
    property string responseHtml: ""

    // ---- ambientes ----
    property var envList: []
    property string activeEnv: ""
    property var resolvedVars: []
    property var collectionResolvedVars: []
    property string currentCollection: ""
    property string missingText: ""
    property string responseCookies: ""
    property bool currentDirty: false

    ListModel { id: paramsModel }
    ListModel { id: headersModel }
    ListModel { id: fieldsModel }
    ListModel { id: requestVarsModel }
    ListModel { id: collectionVarsModel }
    ListModel { id: collectionHeadersModel }
    ListModel { id: treeModel }

    title: "katarina" + (currentTab >= 0 && currentTab < tabsModel.count
                     ? " — " + tabsModel.get(currentTab).name : "")

    component SplitHandle: Rectangle {
        implicitWidth: 1
        implicitHeight: 1
        color: Kirigami.Theme.disabledTextColor
        opacity: 0.4
    }

    // ================= helpers =================
    function methodColor(m) {
        switch (m) {
        case "GET":    return Kirigami.Theme.positiveTextColor;
        case "POST":   return Kirigami.Theme.neutralTextColor;
        case "PUT":    return Kirigami.Theme.activeTextColor;
        case "PATCH":  return "#b180d7";
        case "DELETE": return Kirigami.Theme.negativeTextColor;
        default:       return Kirigami.Theme.textColor;
        }
    }
    function fmtSize(n) {
        if (n < 1024) return n + " B";
        if (n < 1048576) return (n / 1024).toFixed(1) + " KB";
        return (n / 1048576).toFixed(1) + " MB";
    }
    function parentOf(p) { var i = p.lastIndexOf("/"); return i < 0 ? "" : p.substring(0, i); }
    function collectionOf(p) { var i = p.indexOf("/"); return i < 0 ? p : p.substring(0, i); }
    function collectionNames() {
        var out = [];
        for (var i = 0; i < treeModel.count; i++) {
            var e = treeModel.get(i);
            if (e.isFolder && e.depth === 0) out.push(e.name);
        }
        return out;
    }
    function reloadTree() {
        treeModel.clear();
        var a = backend.collectionTree();
        var collapsed = Object.keys(root.collapsedFolders);
        for (var i = 0; i < a.length; i++) {
            var e = a[i];
            var hidden = false;
            for (var c = 0; c < collapsed.length; c++) {
                if (e.relPath !== collapsed[c] && e.relPath.indexOf(collapsed[c] + "/") === 0) {
                    hidden = true;
                    break;
                }
            }
            if (hidden)
                continue;
            var hasChildren = false;
            if (e.isFolder) {
                var prefix = e.relPath + "/";
                for (var j = 0; j < a.length; j++)
                    if (a[j].relPath.indexOf(prefix) === 0) { hasChildren = true; break; }
            }
            treeModel.append({ name: e.name, relPath: e.relPath, isFolder: e.isFolder,
                               method: e.method !== undefined ? e.method : "",
                               depth: e.depth !== undefined ? e.depth : 0,
                               hasChildren: hasChildren,
                               collapsed: root.collapsedFolders[e.relPath] === true });
        }
    }
    function toggleCollapse(relPath) {
        var c = Object.assign({}, root.collapsedFolders);
        if (c[relPath]) delete c[relPath]; else c[relPath] = true;
        root.collapsedFolders = c;
        reloadTree();
    }
    function remapTabs(from, to) {
        var prefix = from + "/";
        for (var i = 0; i < tabsModel.count; i++) {
            var rp = tabsModel.get(i).relPath;
            if (rp === from)
                tabsModel.setProperty(i, "relPath", to);
            else if (rp.indexOf(prefix) === 0)
                tabsModel.setProperty(i, "relPath", to + "/" + rp.substring(prefix.length));
        }
        if (collectionPath === from || collectionPath.indexOf(prefix) === 0)
            collectionPath = collectionPath === from ? to : to + "/" + collectionPath.substring(prefix.length);
    }
    function duplicateSelected() {
        if (selectedPath.length === 0) return;
        backend.duplicateEntry(selectedPath);
        reloadTree();
    }
    function reloadEnvs() {
        envList = backend.environments();
        activeEnv = backend.activeEnvironment;
    }
    function activateEnv(name) {
        if (name === undefined || name === null || name.length === 0)
            return;
        root.activeEnv = name;                 // otimista: o rótulo atualiza na hora
        backend.setActiveEnvironment(name);
        root.reloadEnvs();
        root.refreshResolved();                // re-resolve as variáveis do request aberto
    }
    function targetFolder() {
        if (selectedPath.length === 0) return "";
        return selectedIsFolder ? selectedPath : parentOf(selectedPath);
    }
    function modelToArray(model) {
        var out = [];
        for (var i = 0; i < model.count; i++) {
            var m = model.get(i);
            out.push({ name: m.name, value: m.value, enabled: m.enabled !== false,
                       secret: m.secret === true, secretId: m.secretId !== undefined ? m.secretId : "",
                       type: m.type !== undefined ? m.type : "text",
                       fileName: m.fileName !== undefined ? m.fileName : "" });
        }
        return out;
    }
    function currentAuth() {
        return { type: authTypeBox.currentValue, token: bearerToken.text,
                 user: basicUser.text, pass: basicPass.text,
                 key: apiKeyName.text, value: apiKeyValue.text };
    }
    function collectRequest() {
        return { method: methodBox.currentText, url: urlField.text,
                 params: modelToArray(paramsModel), headers: modelToArray(headersModel),
                 fields: modelToArray(fieldsModel),
                 body: bodyArea.text, bodyType: bodyTypeBox.currentValue,
                 auth: currentAuth(),
                 vars: modelToArray(requestVarsModel) };
    }
    function fillModels(list, model, withExtras) {
        model.clear();
        var a = list !== undefined ? list : [];
        for (var i = 0; i < a.length; i++) {
            var it = {
                name: a[i].name !== undefined ? a[i].name : "",
                value: a[i].value !== undefined ? a[i].value : "",
                enabled: a[i].enabled !== undefined ? a[i].enabled : true
            };
            if (withExtras) {
                it.secret = a[i].secret === true;
                it.secretId = a[i].secretId !== undefined ? a[i].secretId : "";
                it.type = a[i].type !== undefined ? a[i].type : "text";
                it.fileName = a[i].fileName !== undefined ? a[i].fileName : "";
            }
            model.append(it);
        }
    }

    function applyRequest(r, relPath) {
        var idx = methodBox.find(r.method !== undefined ? r.method : "GET");
        methodBox.currentIndex = idx >= 0 ? idx : 0;
        urlField.text = r.url !== undefined ? r.url : "";
        fillModels(r.params, paramsModel, false);
        fillModels(r.headers, headersModel, false);
        fillModels(r.fields, fieldsModel, true);
        fillModels(r.vars, requestVarsModel, true);
        bodyArea.text = r.body !== undefined ? r.body : "";
        var bt = bodyTypeBox.indexOfValue(r.bodyType !== undefined ? r.bodyType : "none");
        bodyTypeBox.currentIndex = bt >= 0 ? bt : 0;
        var auth = r.auth !== undefined ? r.auth : {};
        var at = authTypeBox.indexOfValue(auth.type !== undefined ? auth.type : "none");
        authTypeBox.currentIndex = at >= 0 ? at : 0;
        bearerToken.text = auth.token !== undefined ? auth.token : "";
        basicUser.text = auth.user !== undefined ? auth.user : "";
        basicPass.text = auth.pass !== undefined ? auth.pass : "";
        apiKeyName.text = auth.key !== undefined ? auth.key : "";
        apiKeyValue.text = auth.value !== undefined ? auth.value : "";
        restoreResponse(relPath);
        refreshResolved();
    }
    function clearEditor() {
        methodBox.currentIndex = 0;
        urlField.text = "";
        paramsModel.clear(); headersModel.clear(); fieldsModel.clear(); requestVarsModel.clear();
        bodyArea.text = "";
        bodyTypeBox.currentIndex = 0;
        authTypeBox.currentIndex = 0;
        bearerToken.text = basicUser.text = basicPass.text = apiKeyName.text = apiKeyValue.text = "";
        restoreResponse("");
    }
    function formatBody() {
        if (bodyArea.text.trim().length === 0) return;
        try {
            bodyArea.text = JSON.stringify(JSON.parse(bodyArea.text), null, 2);
            root.markDirty();
        } catch (e) {
            notify("JSON inválido");
        }
    }
    function refreshResolved() {
        if (currentTab < 0 || currentTab >= tabsModel.count) {
            resolvedVars = [];
            missingText = "";
            currentDirty = false;
            return;
        }
        const collection = collectionOf(tabsModel.get(currentTab).relPath);
        currentCollection = collection;
        const miss = backend.missingVariables(collectRequest(), collection);
        var notes = [];
        for (var i = 0; i < miss.length; i++) {
            const note = backend.variableNoteFor(miss[i], collection);
            notes.push(note.length > 0 ? miss[i] + " (" + note + ")" : miss[i]);
        }
        missingText = notes.length > 0 ? "Variáveis não resolvidas: " + notes.join(", ") : "";
        const res = backend.resolvedVariables(collection, modelToArray(requestVarsModel));
        res.sort(function (a, b) { return a.name.localeCompare(b.name); });
        resolvedVars = res;
        currentDirty = tabsModel.get(currentTab).dirty;
    }
    function findNext() {
        var q = searchField.text;
        if (q.length === 0) return;
        var body = responseBody.text;
        var idx = body.indexOf(q, responseBody.selectionEnd);
        if (idx < 0) idx = body.indexOf(q, 0);
        if (idx < 0) { notify("Não encontrado: " + q); return; }
        responseBody.select(idx, idx + q.length);
    }
    function loadHtmlPreview() {
        htmlPreview.loadHtml(root.responseHtml, "about:blank");
    }
    function setResponseBody(body) {
        responseBody.text = body;
        root.responseIsHtml = root.looksLikeHtml(body);
        if (root.responseIsHtml) {
            root.responseHtml = body;
            if (respTabBar.currentIndex === 4) htmlPreview.loadHtml(body, "about:blank");
        } else {
            root.responseHtml = "";
        }
    }
    function looksLikeHtml(body) {
        var t = body.trim().toLowerCase();
        if (t.length === 0) return false;
        return t.indexOf("<!doctype html") === 0 || t.indexOf("<html") === 0
            || t.indexOf("<head") === 0 || t.indexOf("<body") === 0
            || t.indexOf("<div") === 0 || t.indexOf("<meta") === 0
            || (t.indexOf("</") >= 0 && t.indexOf("<") === 0);
    }
    function restoreResponse(relPath) {
        var r = relPath.length > 0 ? responses[relPath] : undefined;
        if (r === undefined) {
            setResponseBody("");
            responseHeaders.text = "";
            responseCookies = "";
            jsonTree.load("");
            statusLabel.text = "";
            timeLabel.text = "";
            sizeLabel.text = "";
        } else {
            statusLabel.text = r.status + " " + r.statusText;
            timeLabel.text = r.time;
            sizeLabel.text = r.size;
            responseHeaders.text = r.headers;
            responseCookies = r.cookies !== undefined ? r.cookies : "";
            setResponseBody(r.body);
            jsonTree.load(r.body);
        }
    }

    // ================= abas =================
    function snapshotCurrent() {
        if (currentTab < 0 || currentTab >= tabsModel.count) return;
        tabsModel.setProperty(currentTab, "dataJson", JSON.stringify(collectRequest()));
        tabsModel.setProperty(currentTab, "method", methodBox.currentText);
    }
    function markDirty() {
        if (currentTab >= 0 && currentTab < tabsModel.count)
            tabsModel.setProperty(currentTab, "dirty", true);
        currentDirty = true;
        refreshResolved();
    }
    // expande as pastas acima de relPath e o seleciona na árvore
    function revealPath(relPath) {
        var c = Object.assign({}, root.collapsedFolders);
        var parts = relPath.split("/"), prefix = "";
        for (var i = 0; i < parts.length - 1; i++) {
            prefix = prefix.length === 0 ? parts[i] : prefix + "/" + parts[i];
            delete c[prefix];
        }
        root.collapsedFolders = c;
        root.selectedPath = relPath;
        root.selectedIsFolder = false;
        reloadTree();
    }
    function openRequest(relPath) {
        revealPath(relPath);           // seleciona na árvore e expande as pastas acima
        snapshotCurrent();
        for (var i = 0; i < tabsModel.count; i++) {
            if (tabsModel.get(i).relPath === relPath) { switchTab(i); return; }
        }
        var r = backend.loadRequest(relPath);
        if (r.method === undefined) return;
        tabsModel.append({ relPath: relPath, name: relPath.split("/").pop(),
                           method: r.method, dirty: false, dataJson: JSON.stringify(r) });
        currentTab = tabsModel.count - 1;
        applyRequest(r, relPath);
        showingCollection = false;
    }
    function switchTab(i) {
        if (i < 0 || i >= tabsModel.count || i === currentTab) return;
        revealPath(tabsModel.get(i).relPath);   // mantém a árvore em sincronia com a aba ativa
        snapshotCurrent();
        currentTab = i;
        var t = tabsModel.get(i);
        applyRequest(JSON.parse(t.dataJson), t.relPath);
        showingCollection = false;
    }
    function closeTab(i) {
        if (i < 0 || i >= tabsModel.count) return;
        if (tabsModel.get(i).dirty) { confirmCloseDialog.tabIndex = i; confirmCloseDialog.open(); return; }
        doCloseTab(i, false);
    }
    function doCloseTab(i, saveFirst) {
        var t = tabsModel.get(i);
        var relPath = t.relPath;
        if (saveFirst) {
            var dataJson = (i === currentTab) ? JSON.stringify(collectRequest()) : t.dataJson;
            backend.saveRequest(relPath, JSON.parse(dataJson));
        }
        closedTabs.push(relPath);
        tabsModel.remove(i);
        if (tabsModel.count === 0) { currentTab = -1; clearEditor(); reloadTree(); return; }
        if (i < currentTab) currentTab--;
        else if (i === currentTab) currentTab = Math.min(i, tabsModel.count - 1);
        var nt = tabsModel.get(currentTab);
        applyRequest(JSON.parse(nt.dataJson), nt.relPath);
        showingCollection = false;
        reloadTree();
    }
    function reopenClosed() {
        if (closedTabs.length === 0) return;
        openRequest(closedTabs.pop());
    }

    function openPath(relPath) {
        for (var i = 0; i < treeModel.count; i++) {
            var e = treeModel.get(i);
            if (e.relPath === relPath) {
                if (e.isFolder) openCollection(relPath); else openRequest(relPath);
                return;
            }
        }
        openCollection(relPath);
    }
    function openCollection(relPath) {
        reloadTree();
        collectionPath = relPath;
        // usa a árvore completa (não a visível): pastas colapsadas não escondem requests
        var all = backend.collectionTree();
        var reqs = [], folders = 0, prefix = relPath + "/";
        for (var i = 0; i < all.length; i++) {
            var e = all[i];
            if (e.relPath.indexOf(prefix) !== 0) continue;
            if (e.isFolder) folders++; else reqs.push(e);
        }
        collectionRequests = reqs;
        collectionFolders = folders;
        collectionIsSubfolder = relPath.indexOf("/") >= 0;
        collectionTab = 0;
        if (collectionIsSubfolder) {
            collectionVarsModel.clear();       // pasta não tem variáveis: elas pertencem à coleção
            collectionHeadersModel.clear();
        } else {
            fillModels(backend.collectionVariables(relPath), collectionVarsModel, true);
            fillModels(backend.collectionHeaders(relPath), collectionHeadersModel, false);
        }
        collectionResolvedVars = backend.resolvedVariables(collectionOf(relPath), []);
        collectionVarsDirty = false;
        collectionHeadersDirty = false;
        showingCollection = true;
    }
    function saveCollectionVars() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem variáveis
        backend.saveCollectionVariables(collectionPath, modelToArray(collectionVarsModel));
        collectionVarsDirty = false;
        notify("Variáveis da coleção salvas");
    }
    function saveCollectionHeaders() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem cabeçalhos
        backend.saveCollectionHeaders(collectionPath, modelToArray(collectionHeadersModel));
        collectionHeadersDirty = false;
        notify("Cabeçalhos da coleção salvos");
    }

    function saveCurrent() {
        if (currentTab < 0 || currentTab >= tabsModel.count) return;
        var t = tabsModel.get(currentTab);
        if (backend.saveRequest(t.relPath, collectRequest())) {
            tabsModel.setProperty(currentTab, "method", methodBox.currentText);
            tabsModel.setProperty(currentTab, "dirty", false);
            currentDirty = false;
            refreshResolved();
            reloadTree();
            notify("Salvo em ~/katarina-collections/" + t.relPath + ".json");
        }
    }
    function moveEntry(from, to) {
        if (!backend.moveEntry(from, to))
            return;
        var newRel = (to.length > 0 ? to + "/" : "") + from.split("/").pop();
        remapTabs(from, newRel);
        reloadTree();
        if (showingCollection)
            openCollection(collectionPath);
    }
    function notify(msg) { root.showPassiveNotification(msg); }
    function statusColor(t) {
        if (t.length === 0 || root.sending) return Kirigami.Theme.textColor;
        if (t === "Cancelado") return Kirigami.Theme.disabledTextColor;
        var code = parseInt(t);
        if (!isNaN(code)) {
            if (code >= 200 && code < 300) return Kirigami.Theme.positiveTextColor;
            if (code >= 300 && code < 400) return Kirigami.Theme.neutralTextColor;
            if (code >= 400) return Kirigami.Theme.negativeTextColor;
        }
        return Kirigami.Theme.negativeTextColor;   // "Erro: …"
    }
    function applyStorageDir(dir) {
        backend.setStorageDir(dir);
        settings.setStorageDir(dir);
        tabsModel.clear();
        currentTab = -1;
        clearEditor();
        showingCollection = false;
        reloadTree();
        reloadEnvs();
        notify("Coleções agora em " + dir);
    }
    function askDelete() {
        if (selectedPath.length === 0) return;
        if (!settings.confirmDelete) { deleteSelected(); return; }
        confirmDeleteDialog.target = selectedPath;
        confirmDeleteDialog.open();
    }
    function deleteSelected() {
        if (selectedPath.length === 0) return;
        backend.deleteEntry(selectedPath);
        for (var i = tabsModel.count - 1; i >= 0; i--) {
            var rp = tabsModel.get(i).relPath;
            if (rp === selectedPath || rp.indexOf(selectedPath + "/") === 0) {
                tabsModel.remove(i);
                if (i < currentTab) currentTab--;
            }
        }
        if (currentTab >= tabsModel.count) currentTab = tabsModel.count - 1;
        if (currentTab >= 0) { var nt = tabsModel.get(currentTab); applyRequest(JSON.parse(nt.dataJson), nt.relPath); }
        else clearEditor();
        if (showingCollection && (collectionPath === selectedPath || collectionPath.indexOf(selectedPath + "/") === 0))
            showingCollection = false;
        selectedPath = ""; selectedIsFolder = false;
        reloadTree();
    }

    function doSend() {
        if (sending || showingCollection || currentTab < 0) return;
        if (urlField.text.length === 0) { notify("Informe uma URL"); return; }
        if (settings.autoSaveOnSend && currentDirty) saveCurrent();
        var t = tabsModel.get(currentTab);
        responseBody.text = ""; responseHeaders.text = "";
        backend.send(collectRequest(), collectionOf(t.relPath));
    }
    function persistSession() {
        var paths = [];
        for (var i = 0; i < tabsModel.count; i++) paths.push(tabsModel.get(i).relPath);
        settings.saveSession(paths, currentTab);
    }

    function hasDirtyTabs() {
        for (var i = 0; i < tabsModel.count; i++) if (tabsModel.get(i).dirty) return true;
        return false;
    }
    function saveAllTabs() {
        for (var i = 0; i < tabsModel.count; i++) {
            var relPath = tabsModel.get(i).relPath;
            var dataJson = (i === currentTab) ? JSON.stringify(collectRequest()) : tabsModel.get(i).dataJson;
            backend.saveRequest(relPath, JSON.parse(dataJson));
            tabsModel.setProperty(i, "dirty", false);
        }
        currentDirty = false;
        reloadTree();
    }

    // ================= cURL =================
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
    function importCurl(text) {
        var r = parseCurl(text);
        if (r.url.length === 0) { curlImportDialog.hint = "Não achei uma URL no comando."; return; }
        var path = (targetFolder().length > 0 ? targetFolder() + "/" : "")
                   + "curl-import";
        var n = 1;
        while (backend.loadRequest(path).method !== undefined) { path = parentOf(path) + (parentOf(path).length ? "/" : "") + "curl-import-" + (++n); }
        var data = { method: r.method, url: r.url, params: [], headers: r.headers, fields: [],
                     body: r.body, bodyType: r.bodyType, auth: r.auth, vars: [] };
        if (backend.saveRequest(path, data)) {
            reloadTree();
            openRequest(path);
            curlImportDialog.close();
        }
    }
    function b64(s) {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        var str = unescape(encodeURIComponent(s)), out = "", i = 0;
        while (i < str.length) {
            var c1 = str.charCodeAt(i++);
            var c2 = i < str.length ? str.charCodeAt(i++) : NaN;
            var c3 = i < str.length ? str.charCodeAt(i++) : NaN;
            var e1 = c1 >> 2;
            var e2 = ((c1 & 3) << 4) | (isNaN(c2) ? 0 : c2 >> 4);
            var e3 = isNaN(c2) ? 64 : ((c2 & 15) << 2) | (isNaN(c3) ? 0 : c3 >> 6);
            var e4 = isNaN(c3) ? 64 : c3 & 63;
            out += chars.charAt(e1) + chars.charAt(e2)
                 + (e3 === 64 ? "=" : chars.charAt(e3)) + (e4 === 64 ? "=" : chars.charAt(e4));
        }
        return out;
    }
    function q(s) { return "'" + s.replace(/'/g, "'\\''") + "'"; }
    function dq(s) { return "\"" + s.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\""; }

    function requestParts() {
        var r = collectRequest();
        var headers = [];
        for (var i = 0; i < r.headers.length; i++)
            if (r.headers[i].enabled && r.headers[i].name.length > 0)
                headers.push({ name: r.headers[i].name, value: r.headers[i].value });
        var a = currentAuth();
        if (a.type === "bearer" && a.token.length > 0)
            headers.push({ name: "Authorization", value: "Bearer " + a.token });
        else if (a.type === "basic")
            headers.push({ name: "Authorization", value: "Basic " + b64(a.user + ":" + a.pass) });
        else if (a.type === "apikey" && a.key.length > 0)
            headers.push({ name: a.key, value: a.value });
        function hasCT() {
            for (var k = 0; k < headers.length; k++)
                if (headers[k].name.toLowerCase() === "content-type") return true;
            return false;
        }
        var body = r.body;
        if (r.bodyType === "urlencoded") {
            var parts = [];
            for (var j = 0; j < r.fields.length; j++) {
                var f = r.fields[j];
                if (f.enabled !== false && f.name.length > 0)
                    parts.push(encodeURIComponent(f.name) + "=" + encodeURIComponent(f.value));
            }
            body = parts.join("&");
            if (body.length > 0 && !hasCT()) headers.push({ name: "Content-Type", value: "application/x-www-form-urlencoded" });
        } else if (r.bodyType === "json" && r.body.length > 0 && !hasCT()) {
            headers.push({ name: "Content-Type", value: "application/json" });
        }
        var hasBody = (r.bodyType === "json" || r.bodyType === "text" || r.bodyType === "urlencoded") && body.length > 0;
        return { method: r.method, url: r.url, headers: headers, body: hasBody ? body : "" };
    }

    function exportCode(fmt) {
        var p = requestParts();
        var hs = [];
        for (var i = 0; i < p.headers.length; i++)
            hs.push({ n: p.headers[i].name, v: p.headers[i].value });

        if (fmt === "cURL") {
            var s = "curl -X " + p.method + " " + q(p.url);
            for (var a = 0; a < hs.length; a++) s += " \\\n  -H " + q(hs[a].n + ": " + hs[a].v);
            if (p.body.length > 0) s += " \\\n  -d " + q(p.body);
            return s;
        }
        if (fmt === "Python (requests)") {
            var hd = "{}";
            if (hs.length > 0) {
                var pp = [];
                for (var b = 0; b < hs.length; b++) pp.push(dq(hs[b].n) + ": " + dq(hs[b].v));
                hd = "{\n    " + pp.join(",\n    ") + "\n}";
            }
            var ln = "import requests\n\nresp = requests.request(" + dq(p.method) + ", " + dq(p.url) + ",\n    headers=" + hd;
            if (p.body.length > 0) ln += ",\n    data=" + dq(p.body);
            ln += ")\nprint(resp.status_code)\nprint(resp.text)";
            return ln;
        }
        if (fmt === "JavaScript (fetch)") {
            var hd2 = "{}";
            if (hs.length > 0) {
                var pp2 = [];
                for (var c = 0; c < hs.length; c++) pp2.push("      " + dq(hs[c].n) + ": " + dq(hs[c].v));
                hd2 = "{\n" + pp2.join(",\n") + "\n    }";
            }
            var s2 = "const resp = await fetch(" + dq(p.url) + ", {\n  method: " + dq(p.method) + ",\n  headers: " + hd2;
            if (p.body.length > 0) s2 += ",\n  body: " + dq(p.body);
            return s2 + "\n});\nconsole.log(await resp.text());";
        }
        if (fmt === "Go") {
            var s3 = "req, _ := http.NewRequest(" + dq(p.method) + ", " + dq(p.url);
            s3 += (p.body.length > 0 ? ", strings.NewReader(" + dq(p.body) + ")" : ", nil") + ")\n";
            for (var d = 0; d < hs.length; d++) s3 += "req.Header.Set(" + dq(hs[d].n) + ", " + dq(hs[d].v) + ")\n";
            return s3 + "resp, _ := http.DefaultClient.Do(req)\ndefer resp.Body.Close()\nbody, _ := io.ReadAll(resp.Body)\nfmt.Println(string(body))";
        }
        if (fmt === "PHP") {
            var s4 = "<?php\n$ch = curl_init(" + dq(p.url) + ");\n$headers = [\n";
            for (var e = 0; e < hs.length; e++) s4 += "    " + dq(hs[e].n + ": " + hs[e].v) + ",\n";
            s4 += "];\ncurl_setopt($ch, CURLOPT_CUSTOMREQUEST, " + dq(p.method) + ");\ncurl_setopt($ch, CURLOPT_HTTPHEADER, $headers);\n";
            if (p.body.length > 0) s4 += "curl_setopt($ch, CURLOPT_POSTFIELDS, " + dq(p.body) + ");\n";
            return s4 + "$resp = curl_exec($ch);\ncurl_close($ch);";
        }
        if (fmt === "Ruby") {
            var s5 = "require 'net/http'\nrequire 'uri'\n\nuri = URI(" + dq(p.url) + ")\n";
            s5 += "req = Net::HTTP::" + p.method.charAt(0) + p.method.slice(1).toLowerCase() + ".new(uri)\n";
            for (var f = 0; f < hs.length; f++) s5 += "req[" + dq(hs[f].n) + "] = " + dq(hs[f].v) + "\n";
            if (p.body.length > 0) s5 += "req.body = " + dq(p.body) + "\n";
            return s5 + "puts Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |h| h.request(req) }";
        }
        if (fmt === "HTTPie") {
            var s6 = "http " + p.method + " " + q(p.url);
            for (var g = 0; g < hs.length; g++)
                if (hs[g].n.toLowerCase() !== "content-type")
                    s6 += " " + q(hs[g].n + ":" + hs[g].v);
            return s6;
        }
        return "";
    }

    function copyRequest() {
        if (currentTab < 0) return;
        varSupport.copyText(JSON.stringify(collectRequest(), null, 2));
        notify("Request copiado");
    }
    function pasteRequest() {
        var o = null;
        try { o = JSON.parse(varSupport.clipboardText()); } catch (e) { o = null; }
        if (!o || o.url === undefined) { notify("A área de transferência não tem um request"); return; }
        var folder = targetFolder();
        var base = "request-colado";
        var path = (folder.length > 0 ? folder + "/" : "") + base;
        var n = 1;
        while (backend.loadRequest(path).method !== undefined)
            path = (folder.length > 0 ? folder + "/" : "") + base + "-" + (++n);
        if (backend.saveRequest(path, o)) { reloadTree(); openRequest(path); }
    }
    function copyTreeRequest(relPath) {
        var o = backend.loadRequest(relPath);
        if (o.method === undefined) return;
        varSupport.copyText(JSON.stringify(o, null, 2));
        notify("Request copiado");
    }

    // ================= ciclo de vida =================
    function hasCollection() {
        for (var i = 0; i < treeModel.count; i++) return true;
        return false;
    }
    Component.onCompleted: {
        reloadTree();
        reloadEnvs();
        // A Kirigami registra Alt+Left/Right (StandardKey Back/Forward) no pageStack,
        // o que dá atalho ambíguo e anula a nossa navegação entre abas. Desativamos.
        var pr = pageStack.data;
        for (var pi = 0; pi < pr.length; pi++)
            if (pr[pi] && pr[pi].sequences !== undefined) pr[pi].enabled = false;
        var saved = settings.openTabs;      // restaura as abas da sessão anterior
        for (var i = 0; i < saved.length; i++) openRequest(saved[i]);
        if (tabsModel.count > 0) {
            var idx = settings.openTabIndex;
            if (idx < 0 || idx >= tabsModel.count) idx = 0;
            switchTab(idx);
        } else if (treeModel.count > 0) {
            var e = treeModel.get(0);
            if (e.isFolder) openCollection(e.relPath); else openRequest(e.relPath);
        }
    }

    property var shortcutDefs: [
        { id: "send", label: "Enviar requisição", def: "Ctrl+Return" },
        { id: "newRequest", label: "Novo request", def: "Ctrl+T" },
        { id: "closeTab", label: "Fechar aba", def: "Ctrl+W" },
        { id: "save", label: "Salvar request", def: "Ctrl+S" },
        { id: "prevTab", label: "Aba anterior", def: "Alt+Left" },
        { id: "nextTab", label: "Próxima aba", def: "Alt+Right" },
        { id: "reopenTab", label: "Reabrir aba fechada", def: "Ctrl+Shift+T" },
        { id: "palette", label: "Paleta de comandos", def: "Ctrl+K" }
    ]
    function shortcutSeq(id) {
        var def = "";
        for (var i = 0; i < shortcutDefs.length; i++)
            if (shortcutDefs[i].id === id) def = shortcutDefs[i].def;
        var m = settings.shortcuts;
        return (m && m[id] !== undefined) ? m[id] : def;
    }
    property bool recordingShortcut: false
    function prevTab() { if (tabsModel.count > 1) switchTab((currentTab - 1 + tabsModel.count) % tabsModel.count); }
    function nextTab() { if (tabsModel.count > 1) switchTab((currentTab + 1) % tabsModel.count); }

    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("save"); onActivated: root.saveCurrent() }
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("send"); onActivated: root.doSend() }
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("closeTab"); onActivated: root.closeTab(root.currentTab) }
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("reopenTab"); onActivated: root.reopenClosed() }
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("newRequest"); onActivated: newReqDialog.openIn(root.targetFolder()) }
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("palette"); onActivated: cmdPalette.openPalette() }
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("prevTab"); onActivated: root.prevTab() }
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("nextTab"); onActivated: root.nextTab() }
    property bool forceQuit: false
    onClosing: function (close) {
        root.persistSession();
        if (!root.forceQuit && root.hasDirtyTabs()) { close.accepted = false; quitDialog.open(); }
    }

    pageStack.initialPage: Kirigami.Page {
        id: mainPage
        padding: 0
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---------- barra superior ----------
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon { source: "qrc:/icons/katarina.svg"; implicitWidth: 22; implicitHeight: 22 }
                Label { text: "katarina"; font.bold: true }
                Item { Layout.fillWidth: true }
                // grupo de painéis: esquerda (coleções) e direita (resposta)
                RowLayout {
                    spacing: 0
                    ToolButton {
                        checkable: true; checked: root.sidebarVisible
                        icon.name: root.sidebarVisible ? "view-left-close" : "view-left-new"
                        onToggled: root.sidebarVisible = checked
                        ToolTip.text: root.sidebarVisible ? "Ocultar painel de coleções" : "Mostrar painel de coleções"
                        ToolTip.visible: hovered
                    }
                    ToolButton {
                        checkable: true; checked: root.responseVisible
                        icon.name: root.responseVisible ? "view-right-close" : "view-right-new"
                        onToggled: root.responseVisible = checked
                        ToolTip.text: root.responseVisible ? "Ocultar painel de resposta" : "Mostrar painel de resposta"
                        ToolTip.visible: hovered
                    }
                }
                ToolButton {
                    icon.name: "view-history"; text: "Histórico"
                    display: AbstractButton.TextBesideIcon
                    onClicked: historyDialog.openAndLoad()
                }
                Button {
                    id: envButton
                    icon.name: "vcs-branch"
                    text: root.activeEnv.length > 0 ? root.activeEnv : "Sem ambiente"
                    onClicked: envPopup.open()
                }
                ToolButton {
                    icon.name: "configure"
                    onClicked: settingsDialog.open()
                    ToolTip.text: "Configurações"; ToolTip.visible: hovered
                }
                Popup {
                    id: envPopup
                    x: mainPage.width - width - 12
                    y: 46
                    width: 260
                    padding: Kirigami.Units.smallSpacing
                    onOpened: root.reloadEnvs()
                    ColumnLayout {
                        width: envPopup.availableWidth
                        spacing: Kirigami.Units.smallSpacing

                        Label {
                            visible: root.envList.length > 0
                            text: "Ambiente ativo"
                            font.bold: true
                            Layout.leftMargin: Kirigami.Units.smallSpacing
                        }
                        Repeater {
                            model: root.envList
                            delegate: ItemDelegate {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.bold: modelData.name === root.activeEnv
                                icon.name: modelData.name === root.activeEnv ? "checkmark" : ""
                                onClicked: {
                                    root.activateEnv(modelData.name);
                                    envPopup.close();
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.envList.length === 0
                            spacing: Kirigami.Units.smallSpacing
                            Label { text: "Pronto para começar?"; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                            Label {
                                text: "Crie um ambiente para ter variáveis como base_url e tokens."
                                wrapMode: Text.WordWrap; Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter; opacity: 0.75
                            }
                        }

                        Kirigami.Separator { Layout.fillWidth: true }
                        ItemDelegate {
                            Layout.fillWidth: true; text: "Criar ambiente…"; icon.name: "list-add"
                            onClicked: { envPopup.close(); createEnvDialog.open(); }
                        }
                        ItemDelegate {
                            Layout.fillWidth: true; text: "Gerenciar variáveis…"; icon.name: "configure"
                            visible: root.envList.length > 0
                            onClicked: { envPopup.close(); envScreen.openFor(root.activeEnv); }
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            SplitView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: Qt.Horizontal
                handle: SplitHandle {}

                // ================= SIDEBAR =================
                ColumnLayout {
                    visible: root.sidebarVisible
                    SplitView.preferredWidth: 250
                    SplitView.minimumWidth: 190
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        Kirigami.Icon { source: "vcs-repo"; implicitWidth: 16; implicitHeight: 16 }
                        Label { text: "Coleções"; font.bold: true }
                        Item { Layout.fillWidth: true }
                        ToolButton { icon.name: "list-add"; onClicked: addMenu.open(); ToolTip.text: "Adicionar"; ToolTip.visible: hovered }
                        ToolButton {
                            icon.name: "edit-delete"
                            enabled: root.selectedPath.length > 0
                            onClicked: root.askDelete()
                            ToolTip.text: "Excluir selecionado"; ToolTip.visible: hovered
                        }
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                    ListView {
                        id: treeView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: treeModel
                        delegate: ItemDelegate {
                            id: treeItem
                            width: ListView.view.width
                            highlighted: model.relPath === root.selectedPath

                            contentItem: RowLayout {
                                spacing: 4
                                Item { Layout.preferredWidth: (model.depth || 0) * 12 + 16; Layout.preferredHeight: 1 }
                                Kirigami.Icon { visible: model.isFolder; source: (model.depth || 0) === 0 ? "folder-documents" : "folder"; implicitWidth: 16; implicitHeight: 16; color: Kirigami.Theme.textColor }
                                Rectangle {
                                    visible: !model.isFolder
                                    implicitWidth: badge.implicitWidth + 8; implicitHeight: 16; radius: 3
                                    color: Qt.rgba(root.methodColor(model.method).r, root.methodColor(model.method).g, root.methodColor(model.method).b, 0.18)
                                    Text { id: badge; anchors.centerIn: parent; text: model.method; color: root.methodColor(model.method); font.pixelSize: 9; font.bold: true }
                                }
                                Label { Layout.fillWidth: true; text: model.name; elide: Text.ElideRight }
                            }

                            // clique (esquerdo/direito) + arrasto manual (com ghost)
                            MouseArea {
                                id: mainMouse
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                preventStealing: true
                                property real pressX: 0
                                property real pressY: 0
                                onPressed: function (m) { root.justDragged = false; pressX = m.x; pressY = m.y; }
                                onPositionChanged: function (m) {
                                    if (!pressed) return;
                                    if (!root.dragging) {
                                        if (Math.abs(m.x - pressX) + Math.abs(m.y - pressY) < 8) return;
                                        root.dragging = true;
                                        root.dragFrom = model.relPath;
                                        root.dragLabel = model.name;
                                        root.dragMethod = model.isFolder ? "" : model.method;
                                    }
                                    var gp = mainMouse.mapToItem(mainPage, m.x, m.y);
                                    root.ghostX = gp.x;
                                    root.ghostY = gp.y;
                                    var lp = mainMouse.mapToItem(treeView, m.x, m.y);
                                    var idx = treeView.indexAt(lp.x, lp.y);
                                    if (idx >= 0 && idx < treeModel.count) {
                                        var e = treeModel.get(idx);
                                        root.dropTarget = (e.relPath === root.dragFrom) ? "" : e.relPath;
                                        root.dropIsFolder = e.isFolder;
                                    } else {
                                        root.dropTarget = "";
                                    }
                                }
                                onReleased: {
                                    if (!root.dragging)
                                        return;
                                    root.justDragged = true;
                                    var from = root.dragFrom;
                                    var to = "";
                                    if (root.dropTarget.length > 0 && root.dropTarget !== from)
                                        to = root.dropIsFolder ? root.dropTarget : root.parentOf(root.dropTarget);
                                    // limpa o ghost ANTES de mover (o move recria a lista e mata este delegate)
                                    root.dragging = false;
                                    root.dropTarget = "";
                                    if (to.length > 0 && to !== from)
                                        root.moveEntry(from, to);
                                }
                                onCanceled: { root.dragging = false; root.dropTarget = ""; }
                                onClicked: function (m) {
                                    if (root.justDragged) { root.justDragged = false; return; }
                                    // clique no triângulo = colapsar/expandir
                                    var triX = (model.depth || 0) * 12 + 3;
                                    if (m.button === Qt.LeftButton && model.isFolder && model.hasChildren
                                            && m.x >= triX - 2 && m.x <= triX + 18) {
                                        root.toggleCollapse(model.relPath);
                                        return;
                                    }
                                    root.selectedPath = model.relPath;
                                    root.selectedIsFolder = model.isFolder;
                                    if (m.button === Qt.RightButton) {
                                        ctxMenu.popup();
                                    } else if (model.isFolder) {
                                        root.openCollection(model.relPath);
                                    } else {
                                        root.openRequest(model.relPath);
                                    }
                                }
                            }

                            // destaque do alvo de drop
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.color: Kirigami.Theme.highlightColor
                                border.width: 2
                                visible: root.dropTarget === model.relPath
                            }

                            // triângulo de colapsar (só visual; o clique é tratado na MouseArea)
                            Kirigami.Icon {
                                visible: model.isFolder && model.hasChildren
                                anchors.left: parent.left
                                anchors.leftMargin: (model.depth || 0) * 12 + 3
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 12
                                implicitHeight: 12
                                source: model.collapsed ? "arrow-right" : "arrow-down"
                                color: Kirigami.Theme.textColor
                                opacity: 0.75
                            }
                        }
                    }
                }

                // ================= ÁREA PRINCIPAL =================
                ColumnLayout {
                    SplitView.fillWidth: true
                    spacing: 0

                    // barra de abas
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 2
                        color: Kirigami.Theme.alternateBackgroundColor
                        visible: tabsModel.count > 0
                        Flickable {
                            id: tabStrip
                            anchors.fill: parent
                            contentWidth: tabRow.width
                            contentHeight: height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                            Row {
                                id: tabRow
                                height: tabStrip.height
                                Repeater {
                                    model: tabsModel
                                    delegate: Item {
                                        id: tabItem
                                        height: tabRow.height
                                        width: tabContent.implicitWidth + 52
                                        Rectangle {
                                            anchors.fill: parent
                                            color: index === root.currentTab ? Kirigami.Theme.backgroundColor : "transparent"
                                            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 2; visible: index === root.currentTab; color: Kirigami.Theme.highlightColor }
                                        }
                                        RowLayout {
                                            id: tabContent
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            spacing: 6
                                            Rectangle {
                                                implicitWidth: tabBadge.implicitWidth + 8; implicitHeight: 14; radius: 3
                                                color: Qt.rgba(root.methodColor(model.method).r, root.methodColor(model.method).g, root.methodColor(model.method).b, 0.18)
                                                Text { id: tabBadge; anchors.centerIn: parent; text: model.method; color: root.methodColor(model.method); font.pixelSize: 8; font.bold: true }
                                            }
                                            Label { text: model.name; font.bold: index === root.currentTab; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                                            Kirigami.Icon {
                                                visible: model.dirty
                                                source: "media-record-symbolic"
                                                color: Kirigami.Theme.highlightColor
                                                implicitWidth: 8; implicitHeight: 8
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            onClicked: function (mouse) {
                                                if (mouse.button === Qt.MiddleButton) root.closeTab(index);
                                                else root.switchTab(index);
                                            }
                                        }
                                        Label {
                                            id: closeBtn
                                            anchors.right: parent.right
                                            anchors.rightMargin: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            padding: 3
                                            text: "×"
                                            font.pixelSize: 16
                                            color: closeHover.hovered ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                            opacity: closeHover.hovered ? 1.0 : 0.6
                                            HoverHandler { id: closeHover }
                                            TapHandler { onTapped: root.closeTab(index) }
                                            ToolTip.text: "Fechar aba"
                                            ToolTip.visible: closeHover.hovered
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Kirigami.Separator { Layout.fillWidth: true; visible: tabsModel.count > 0 }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: root.showingCollection ? 1 : (root.currentTab >= 0 ? 0 : 2)

                        // ---- 0: editor + resposta ----
                        SplitView {
                            orientation: Qt.Horizontal
                            handle: SplitHandle {}

                            ColumnLayout {
                                SplitView.fillWidth: true
                                SplitView.minimumWidth: 380
                                spacing: Kirigami.Units.smallSpacing

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    ComboBox {
                                        id: methodBox
                                        model: ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS"]
                                        implicitWidth: 120
                                        onActivated: root.markDirty()
                                        contentItem: Text {
                                            leftPadding: 10
                                            text: methodBox.displayText
                                            color: root.methodColor(methodBox.currentText)
                                            font.bold: true
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                    }
                                    TextArea {
                                        id: urlField
                                        Layout.fillWidth: true
                                        placeholderText: "{{base_url}}/recurso"
                                        wrapMode: TextEdit.NoWrap
                                        selectByMouse: true
                                        font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize
                                        implicitHeight: Kirigami.Units.gridUnit * 2
                                        topPadding: 5; bottomPadding: 5; leftPadding: 8; rightPadding: 8
                                        onTextEdited: root.markDirty()
                                        Keys.onPressed: function (e) {
                                            // se o popup de variáveis está aberto, Enter insere a variável
                                            if (urlCompleter.handleKey(e)) { e.accepted = true; return; }
                                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { e.accepted = true; root.doSend(); }
                                        }
                                        Component.onCompleted: varSupport.attach(urlField.textDocument, "#c678dd", true)
                                        VarCompleter {
                                            id: urlCompleter
                                            anchors.fill: parent
                                            target: urlField
                                            resolved: root.resolvedVars
                                            collection: root.currentCollection
                                        }
                                    }
                                    Button {
                                        icon.name: root.sending ? "process-stop" : "document-send"
                                        text: root.sending ? "Cancelar" : "Enviar"
                                        highlighted: !root.sending
                                        onClicked: root.sending ? backend.cancel() : root.doSend()
                                    }
                                    ToolButton {
                                        icon.name: "document-save"
                                        enabled: root.currentDirty
                                        onClicked: root.saveCurrent()
                                        ToolTip.text: "Salvar (Ctrl+S)"; ToolTip.visible: hovered
                                    }
                                    ToolButton {
                                        icon.name: "overflow-menu"
                                        onClicked: reqMenu.popup()
                                        ToolTip.text: "Mais ações"; ToolTip.visible: hovered
                                    }
                                }

                                RowLayout {
                                    visible: root.missingText.length > 0
                                    Layout.leftMargin: Kirigami.Units.smallSpacing
                                    Layout.rightMargin: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    Kirigami.Icon {
                                        source: "dialog-warning"
                                        color: Kirigami.Theme.negativeTextColor
                                        implicitWidth: 16; implicitHeight: 16
                                    }
                                    Label {
                                        text: root.missingText
                                        color: Kirigami.Theme.negativeTextColor
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                TabBar {
                                    id: reqTabBar
                                    Layout.fillWidth: true
                                    TabButton { text: "Parâmetros" }
                                    TabButton { text: "Cabeçalhos" }
                                    TabButton { text: "Corpo" }
                                    TabButton { text: "Autenticação" }
                                    TabButton { text: "Variáveis" }
                                }

                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: reqTabBar.currentIndex

                                    KvTable { model: paramsModel; keyPlaceholder: "parâmetro"; resolved: root.resolvedVars; collection: root.currentCollection; onAddRequested: paramsModel.append({ name: "", value: "", enabled: true }); onEdited: root.markDirty() }
                                    KvTable { model: headersModel; keyPlaceholder: "Cabeçalho"; resolved: root.resolvedVars; collection: root.currentCollection; onAddRequested: headersModel.append({ name: "", value: "", enabled: true }); onEdited: root.markDirty() }

                                    ColumnLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        RowLayout {
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.topMargin: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing
                                            Label { text: "Tipo:" }
                                            ComboBox {
                                                id: bodyTypeBox
                                                textRole: "text"; valueRole: "value"
                                                model: [
                                                    { text: "nenhum", value: "none" },
                                                    { text: "JSON", value: "json" },
                                                    { text: "texto", value: "text" },
                                                    { text: "form-urlencoded", value: "urlencoded" },
                                                    { text: "multipart/form-data", value: "multipart" }
                                                ]
                                                implicitWidth: 170
                                                onActivated: root.markDirty()
                                            }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                visible: bodyTypeBox.currentValue === "json"
                                                icon.name: "tools-wizard"; text: "Formatar"
                                                display: AbstractButton.TextBesideIcon
                                                onClicked: root.formatBody()
                                                ToolTip.text: "Indentar o JSON"; ToolTip.visible: hovered
                                            }
                                        }
                                        Label {
                                            visible: bodyTypeBox.currentValue === "none"
                                            text: "Sem corpo."
                                            opacity: 0.7
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.topMargin: Kirigami.Units.smallSpacing
                                        }
                                        FormTable {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            visible: bodyTypeBox.currentValue === "multipart" || bodyTypeBox.currentValue === "urlencoded"
                                            model: fieldsModel
                                            allowFiles: bodyTypeBox.currentValue === "multipart"
                                            onAddRequested: fieldsModel.append({ name: "", value: "", type: "text", fileName: "", enabled: true })
                                            onEdited: root.markDirty()
                                            onPickFile: function (index) { fileDialog.targetIndex = index; fileDialog.open(); }
                                        }
                                        ScrollView {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            visible: bodyTypeBox.currentValue !== "none" && bodyTypeBox.currentValue !== "multipart" && bodyTypeBox.currentValue !== "urlencoded"
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
                                            Layout.bottomMargin: Kirigami.Units.smallSpacing
                                            TextArea {
                                                id: bodyArea
                                                placeholderText: '{ "chave": "valor" }'
                                                font.family: "monospace"
                                                font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize
                                                wrapMode: TextEdit.Wrap
                                                onTextEdited: root.markDirty()
                                                Component.onCompleted: {
                                                    var dark = Kirigami.Theme.backgroundColor.hsvValue < 0.5;
                                                    varSupport.attach(bodyArea.textDocument, "#c678dd", true, true,
                                                        dark ? "#98c379" : "#2e7d32",   // string
                                                        dark ? "#d19a66" : "#b26a00",   // número
                                                        dark ? "#d19a66" : "#b26a00");  // true/false/null
                                                }
                                                VarCompleter {
                                                    id: bodyCompleter
                                                    anchors.fill: parent
                                                    target: bodyArea
                                                    resolved: root.resolvedVars
                                                    collection: root.currentCollection
                                                }
                                                // auto-fecha pares e indenta no Enter (estilo Bruno)
                                                Keys.onPressed: function (event) {
                                                    if (bodyCompleter.handleKey(event)) { event.accepted = true; return; }
                                                    var pos = bodyArea.cursorPosition;
                                                    var unit = "  ";
                                                    if (event.key === Qt.Key_BraceLeft) {
                                                        event.accepted = true;
                                                        bodyArea.insert(pos, "{}");
                                                        bodyArea.cursorPosition = pos + 1;
                                                        root.markDirty();
                                                    } else if (event.key === Qt.Key_BracketLeft) {
                                                        event.accepted = true;
                                                        bodyArea.insert(pos, "[]");
                                                        bodyArea.cursorPosition = pos + 1;
                                                        root.markDirty();
                                                    } else if (event.key === Qt.Key_QuoteDbl) {
                                                        event.accepted = true;
                                                        if (bodyArea.selectedText.length > 0) {
                                                            bodyArea.insert(pos, "\"" + bodyArea.selectedText + "\"");
                                                        } else {
                                                            bodyArea.insert(pos, "\"\"");
                                                            bodyArea.cursorPosition = pos + 1;
                                                        }
                                                        root.markDirty();
                                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                        event.accepted = true;
                                                        var t = bodyArea.text;
                                                        var ls = t.lastIndexOf("\n", pos - 1) + 1;
                                                        var indent = (t.substring(ls, pos).match(/^[ \t]*/) || [""])[0];
                                                        var before = pos > 0 ? t.charAt(pos - 1) : "";
                                                        var after = pos < t.length ? t.charAt(pos) : "";
                                                        if ((before === "{" && after === "}") || (before === "[" && after === "]")) {
                                                            bodyArea.insert(pos, "\n" + indent + unit + "\n" + indent);   // expande em bloco
                                                            bodyArea.cursorPosition = pos + 1 + indent.length + unit.length;
                                                        } else if (before === "{" || before === "[") {
                                                            bodyArea.insert(pos, "\n" + indent + unit);
                                                            bodyArea.cursorPosition = pos + 1 + indent.length + unit.length;
                                                        } else {
                                                            bodyArea.insert(pos, "\n" + indent);
                                                            bodyArea.cursorPosition = pos + 1 + indent.length;
                                                        }
                                                        root.markDirty();
                                                    } else if (event.key === Qt.Key_BraceRight) {
                                                        var t2 = bodyArea.text;
                                                        var ls2 = t2.lastIndexOf("\n", pos - 1) + 1;
                                                        var prefix = t2.substring(ls2, pos);
                                                        if (/^[ \t]+$/.test(prefix) && prefix.length >= unit.length) {
                                                            event.accepted = true;   // linha só com espaços: dedenta ao fechar
                                                            var kept = prefix.substring(0, prefix.length - unit.length);
                                                            bodyArea.remove(ls2, pos);
                                                            bodyArea.insert(ls2, kept + "}");
                                                            bodyArea.cursorPosition = ls2 + kept.length + 1;
                                                            root.markDirty();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        Layout.margins: Kirigami.Units.smallSpacing
                                        RowLayout {
                                            spacing: Kirigami.Units.smallSpacing
                                            Label { text: "Tipo:" }
                                            ComboBox {
                                                id: authTypeBox
                                                textRole: "text"; valueRole: "value"
                                                model: [
                                                    { text: "nenhuma", value: "none" },
                                                    { text: "Bearer token", value: "bearer" },
                                                    { text: "Básico (usuário/senha)", value: "basic" },
                                                    { text: "Chave de API", value: "apikey" }
                                                ]
                                                implicitWidth: 200
                                                onActivated: root.markDirty()
                                            }
                                        }
                                        TextArea {
                                            id: bearerToken
                                            Layout.fillWidth: true
                                            visible: authTypeBox.currentValue === "bearer"
                                            placeholderText: "Token"
                                            wrapMode: TextEdit.NoWrap
                                            selectByMouse: true
                                            implicitHeight: Kirigami.Units.gridUnit * 1.7
                                            topPadding: 3; bottomPadding: 3; leftPadding: 6; rightPadding: 6
                                            onTextEdited: root.markDirty()
                                            Keys.onPressed: function (e) { if (bearerCompleter.handleKey(e)) e.accepted = true; }
                                            Component.onCompleted: varSupport.attach(bearerToken.textDocument, "#c678dd", true, false)
                                            VarCompleter { id: bearerCompleter; anchors.fill: parent; target: bearerToken; resolved: root.resolvedVars; collection: root.currentCollection }
                                        }
                                        RowLayout {
                                            visible: authTypeBox.currentValue === "basic"
                                            spacing: Kirigami.Units.smallSpacing
                                            TextField { id: basicUser; Layout.fillWidth: true; placeholderText: "Usuário"; onTextEdited: root.markDirty() }
                                            TextField { id: basicPass; Layout.fillWidth: true; placeholderText: "Senha"; echoMode: TextInput.Password; onTextEdited: root.markDirty() }
                                        }
                                        RowLayout {
                                            visible: authTypeBox.currentValue === "apikey"
                                            spacing: Kirigami.Units.smallSpacing
                                            TextField { id: apiKeyName; Layout.fillWidth: true; placeholderText: "Nome do cabeçalho"; onTextEdited: root.markDirty() }
                                            TextArea {
                                                id: apiKeyValue
                                                Layout.fillWidth: true
                                                placeholderText: "Valor"
                                                wrapMode: TextEdit.NoWrap
                                                selectByMouse: true
                                                implicitHeight: Kirigami.Units.gridUnit * 1.7
                                                topPadding: 3; bottomPadding: 3; leftPadding: 6; rightPadding: 6
                                                onTextEdited: root.markDirty()
                                                Keys.onPressed: function (e) { if (apiValueCompleter.handleKey(e)) e.accepted = true; }
                                                Component.onCompleted: varSupport.attach(apiKeyValue.textDocument, "#c678dd", true, false)
                                                VarCompleter { id: apiValueCompleter; anchors.fill: parent; target: apiKeyValue; resolved: root.resolvedVars; collection: root.currentCollection }
                                            }
                                        }
                                        Label { visible: authTypeBox.currentValue === "none"; text: "Sem autenticação."; opacity: 0.7 }
                                        Item { Layout.fillHeight: true }
                                    }

                                    ColumnLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        KvTable {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            model: requestVarsModel
                                            keyPlaceholder: "variável"
                                            secretColumn: true
                                            resolved: root.resolvedVars
                                            collection: root.currentCollection
                                            onAddRequested: requestVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "" })
                                            onEdited: root.markDirty()
                                        }
                                        Kirigami.Separator { Layout.fillWidth: true }
                                        Label {
                                            text: "Variáveis efetivas (request > coleção > global)"
                                            font.bold: true
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                        }
                                        ListView {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 150
                                            clip: true
                                            model: root.resolvedVars
                                            delegate: RowLayout {
                                                width: ListView.view.width
                                                spacing: Kirigami.Units.smallSpacing
                                                Rectangle {
                                                    implicitWidth: srcLabel.implicitWidth + 10
                                                    implicitHeight: 16
                                                    radius: 3
                                                    color: Kirigami.Theme.alternateBackgroundColor
                                                    Text { id: srcLabel; anchors.centerIn: parent; text: modelData.source; font.pixelSize: 9; opacity: 0.8 }
                                                }
                                                Label { text: modelData.name; font.bold: true }
                                                Label { text: "="; opacity: 0.5 }
                                                Label { Layout.fillWidth: true; text: modelData.secret ? "••••••" : modelData.value; elide: Text.ElideRight; opacity: 0.9 }
                                            }
                                        }
                                        Label {
                                            visible: root.resolvedVars.length === 0
                                            text: "Nenhuma variável definida (nem no request, nem na coleção, nem global)."
                                            opacity: 0.5
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: root.responseVisible
                                SplitView.preferredWidth: 330
                                SplitView.minimumWidth: 230
                                spacing: Kirigami.Units.smallSpacing

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    Rectangle {
                                        visible: statusLabel.text.length > 0
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: statusLabel.implicitWidth + 14
                                        implicitHeight: statusLabel.implicitHeight + 6
                                        radius: 4
                                        color: Qt.rgba(root.statusColor(statusLabel.text).r,
                                                       root.statusColor(statusLabel.text).g,
                                                       root.statusColor(statusLabel.text).b, 0.18)
                                        Label {
                                            id: statusLabel
                                            anchors.centerIn: parent
                                            font.bold: true
                                            elide: Text.ElideRight
                                            color: root.statusColor(text)
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label { id: timeLabel; visible: text.length > 0; opacity: 0.7 }
                                    Label { id: sizeLabel; visible: text.length > 0; opacity: 0.7 }
                                    ToolButton {
                                        visible: responseBody.text.length > 0
                                        icon.name: "edit-copy"; text: "Copiar"
                                        display: AbstractButton.TextBesideIcon
                                        onClicked: { responseBody.selectAll(); responseBody.copy(); responseBody.cursorPosition = 0; root.notify("Resposta copiada"); }
                                        ToolTip.text: "Copiar a resposta"; ToolTip.visible: hovered
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Kirigami.Units.smallSpacing
                                    Layout.rightMargin: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    visible: responseBody.text.length > 0
                                    TextField {
                                        id: searchField
                                        Layout.fillWidth: true
                                        placeholderText: "Buscar na resposta…"
                                        onAccepted: root.findNext()
                                    }
                                    ToolButton { icon.name: "edit-find"; onClicked: root.findNext(); ToolTip.text: "Próxima"; ToolTip.visible: hovered }
                                    ToolButton {
                                        icon.name: "checkbox"; checkable: true; checked: true
                                        onClicked: responseBody.wrapMode = checked ? TextEdit.Wrap : TextEdit.NoWrap
                                        ToolTip.text: "Quebrar linhas"; ToolTip.visible: hovered
                                    }
                                }

                                TabBar {
                                    id: respTabBar
                                    Layout.fillWidth: true
                                    TabButton { text: "Corpo" }
                                    TabButton { text: "Árvore" }
                                    TabButton { text: "Cabeçalhos" }
                                    TabButton { text: "Cookies" }
                                    TabButton {
                                        text: "Renderizar"
                                        visible: root.responseIsHtml
                                        onClicked: { respTabBar.currentIndex = 4; root.loadHtmlPreview(); }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    StackLayout {
                                        anchors.fill: parent
                                        currentIndex: respTabBar.currentIndex
                                        ScrollView {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing
                                            TextArea { id: responseBody; readOnly: true; font.family: "monospace"; font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize; wrapMode: TextEdit.Wrap }
                                        }
                                        JsonTree { id: jsonTree; Layout.fillWidth: true; Layout.fillHeight: true }
                                        ScrollView {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing
                                            TextArea { id: responseHeaders; readOnly: true; font.family: "monospace"; font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize; wrapMode: TextEdit.NoWrap }
                                        }
                                        ScrollView {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing
                                            TextArea { id: responseCookiesArea; readOnly: true; font.family: "monospace"; wrapMode: TextEdit.Wrap; text: root.responseCookies; placeholderText: "Sem cookies." }
                                        }
                                        WebEngineView {
                                            id: htmlPreview
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                        }
                                    }
                                    // estado vazio (ainda sem resposta)
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                                        spacing: Kirigami.Units.smallSpacing
                                        visible: responseBody.text.length === 0 && !root.sending
                                        Kirigami.Icon {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.bottomMargin: Kirigami.Units.smallSpacing
                                            source: "qrc:/icons/katarina.svg"
                                            implicitWidth: 72; implicitHeight: 72
                                            opacity: 0.22
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "Sem resposta ainda"
                                            font.bold: true
                                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            opacity: 0.65
                                            text: "Envie a requisição (Ctrl+Enter) para ver a resposta aqui."
                                        }
                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.topMargin: Kirigami.Units.largeSpacing
                                            spacing: Kirigami.Units.smallSpacing
                                            Rectangle {
                                                implicitWidth: keyText.implicitWidth + 12
                                                implicitHeight: keyText.implicitHeight + 6
                                                radius: 4
                                                color: Kirigami.Theme.alternateBackgroundColor
                                                border.width: 1
                                                border.color: Kirigami.Theme.disabledTextColor
                                                Label { id: keyText; anchors.centerIn: parent; text: "Ctrl+K"; font.bold: true; font.pixelSize: 11 }
                                            }
                                            Label { text: "abre a paleta de comandos"; opacity: 0.7 }
                                        }
                                    }
                                }
                            }
                        }

                        // ---- 1: tela da coleção ----
                        ColumnLayout {
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.margins: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.largeSpacing
                                Kirigami.Icon { source: root.collectionIsSubfolder ? "folder" : "folder-documents"; implicitWidth: 48; implicitHeight: 48; color: Kirigami.Theme.highlightColor }
                                ColumnLayout {
                                    spacing: 0
                                    Label { text: root.collectionPath.split("/").pop(); font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 6 }
                                    Label { text: root.collectionIsSubfolder ? "Pasta" : "Coleção"; opacity: 0.6 }
                                }
                                Item { Layout.fillWidth: true }
                                Button { icon.name: "document-new"; text: "Novo request…"; onClicked: newReqDialog.openIn(root.collectionPath) }
                            }
                            Kirigami.Separator { Layout.fillWidth: true }
                            TabBar {
                                id: collectionTabBar
                                visible: !root.collectionIsSubfolder
                                Layout.fillWidth: true
                                currentIndex: root.collectionTab
                                onCurrentIndexChanged: root.collectionTab = currentIndex
                                TabButton { text: "Visão geral" }
                                TabButton { text: "Cabeçalhos" }
                                TabButton { text: "Variáveis" }
                            }
                            StackLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndex: root.collectionIsSubfolder ? 0 : root.collectionTab
                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                ColumnLayout {
                                    width: parent.width
                                    spacing: Kirigami.Units.largeSpacing
                                    Layout.margins: Kirigami.Units.largeSpacing
                                    GridLayout {
                                        columns: 2
                                        columnSpacing: Kirigami.Units.largeSpacing
                                        rowSpacing: Kirigami.Units.smallSpacing
                                        Label { text: "Local"; font.bold: true }
                                        Label { text: "~/katarina-collections/" + root.collectionPath; opacity: 0.8 }
                                        Label { text: "Requests"; font.bold: true }
                                        Label { text: root.collectionRequests.length }
                                        Label { text: "Subpastas"; font.bold: true }
                                        Label { text: root.collectionFolders }
                                    }
                                    Kirigami.Separator { Layout.fillWidth: true }
                                    Label {
                                        visible: root.collectionIsSubfolder
                                        text: "Pasta é apenas organização. Cabeçalhos e variáveis ficam na coleção."
                                        opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                    Label {
                                        visible: !root.collectionIsSubfolder
                                        text: "Variáveis efetivas (coleção > ambiente)"
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                                    }
                                    ListView {
                                        visible: !root.collectionIsSubfolder && root.collectionResolvedVars.length > 0
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.min(200, root.collectionResolvedVars.length * 26)
                                        clip: true
                                        model: root.collectionResolvedVars
                                        delegate: RowLayout {
                                            width: ListView.view.width
                                            spacing: Kirigami.Units.smallSpacing
                                            Rectangle {
                                                implicitWidth: ovSrc.implicitWidth + 10
                                                implicitHeight: 16
                                                radius: 3
                                                color: Kirigami.Theme.alternateBackgroundColor
                                                Text { id: ovSrc; anchors.centerIn: parent; text: modelData.source; font.pixelSize: 9; opacity: 0.8 }
                                            }
                                            Label { text: modelData.name; font.bold: true }
                                            Label { text: "="; opacity: 0.5 }
                                            Label { Layout.fillWidth: true; text: modelData.secret ? "••••••" : modelData.value; elide: Text.ElideRight; opacity: 0.9 }
                                        }
                                    }
                                    Label {
                                        visible: !root.collectionIsSubfolder && root.collectionResolvedVars.length === 0
                                        text: "Nenhuma variável definida nesta coleção."
                                        opacity: 0.6
                                    }
                                    Kirigami.Separator { Layout.fillWidth: true }
                                    Label { text: root.collectionIsSubfolder ? "Requests nesta pasta" : "Requests nesta coleção"; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1 }
                                    Repeater {
                                        model: root.collectionRequests
                                        delegate: ItemDelegate {
                                            Layout.fillWidth: true
                                            onClicked: { root.revealPath(modelData.relPath); root.openRequest(modelData.relPath); }
                                            contentItem: RowLayout {
                                                spacing: 6
                                                Rectangle {
                                                    implicitWidth: rbadge.implicitWidth + 8; implicitHeight: 16; radius: 3
                                                    color: Qt.rgba(root.methodColor(modelData.method).r, root.methodColor(modelData.method).g, root.methodColor(modelData.method).b, 0.18)
                                                    Text { id: rbadge; anchors.centerIn: parent; text: modelData.method; color: root.methodColor(modelData.method); font.pixelSize: 9; font.bold: true }
                                                }
                                                Label { Layout.fillWidth: true; text: modelData.name }
                                            }
                                        }
                                    }
                                    Label { visible: root.collectionRequests.length === 0; text: root.collectionIsSubfolder ? "Nenhum request nesta pasta ainda." : "Nenhum request nesta coleção ainda."; opacity: 0.6 }
                                }
                            }

                            // 1) cabeçalhos
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.smallSpacing
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Cabeçalhos da coleção"; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1; Layout.fillWidth: true }
                                    RowLayout {
                                        visible: root.collectionHeadersDirty
                                        spacing: Kirigami.Units.smallSpacing
                                        Kirigami.Icon { source: "media-record-symbolic"; color: Kirigami.Theme.neutralTextColor; implicitWidth: 10; implicitHeight: 10; Layout.alignment: Qt.AlignVCenter }
                                        Label { text: "alterações não salvas"; color: Kirigami.Theme.neutralTextColor }
                                    }
                                    Button {
                                        icon.name: "document-save"; text: "Salvar"
                                        highlighted: true
                                        enabled: root.collectionHeadersDirty
                                        onClicked: root.saveCollectionHeaders()
                                    }
                                }
                                Label {
                                    text: "Enviados em todo request desta coleção. O request pode sobrescrever."
                                    opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                                KvTable {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    model: collectionHeadersModel
                                    keyPlaceholder: "cabeçalho"
                                    resolved: root.collectionResolvedVars
                                    collection: root.collectionPath
                                    onAddRequested: collectionHeadersModel.append({ name: "", value: "", enabled: true })
                                    onEdited: root.collectionHeadersDirty = true
                                }
                            }

                            // 2) variáveis
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.margins: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.smallSpacing
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Variáveis da coleção"; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1; Layout.fillWidth: true }
                                    RowLayout {
                                        visible: root.collectionVarsDirty
                                        spacing: Kirigami.Units.smallSpacing
                                        Kirigami.Icon { source: "media-record-symbolic"; color: Kirigami.Theme.neutralTextColor; implicitWidth: 10; implicitHeight: 10; Layout.alignment: Qt.AlignVCenter }
                                        Label { text: "alterações não salvas"; color: Kirigami.Theme.neutralTextColor }
                                    }
                                    Button {
                                        icon.name: "document-save"; text: "Salvar"
                                        highlighted: true
                                        enabled: root.collectionVarsDirty
                                        onClicked: root.saveCollectionVars()
                                    }
                                }
                                Label {
                                    text: "Use {{nome}} em qualquer request desta coleção. Marque como segredo para não versionar o valor."
                                    opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                                KvTable {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    model: collectionVarsModel
                                    keyPlaceholder: "variável"
                                    secretColumn: true
                                    resolved: root.collectionResolvedVars
                                    collection: root.collectionPath
                                    onAddRequested: collectionVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "" })
                                    onEdited: root.collectionVarsDirty = true
                                }
                            }
                            }
                        }

                        // ---- 2: vazio ----
                        ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon { Layout.alignment: Qt.AlignHCenter; source: "document-send"; implicitWidth: 64; implicitHeight: 64; opacity: 0.35 }
                            Label { Layout.alignment: Qt.AlignHCenter; text: "Nenhum request aberto"; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 3 }
                            Label { Layout.alignment: Qt.AlignHCenter; text: "Selecione um request na barra lateral ou crie um novo."; opacity: 0.6 }
                            Button { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: Kirigami.Units.smallSpacing; icon.name: "document-new"; text: "Novo request…"; onClicked: newReqDialog.openIn(root.targetFolder()) }
                        }
                    }
                }
            }
        }

        // "bloco" que segue o mouse durante o arrasto
        Rectangle {
            id: dragGhost
            visible: root.dragging
            x: root.ghostX - 12
            y: root.ghostY - 12
            z: 10000
            width: ghostRow.implicitWidth + 18
            height: 28
            radius: 5
            color: Kirigami.Theme.highlightColor
            opacity: 0.92
            RowLayout {
                id: ghostRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    visible: root.dragMethod.length > 0
                    implicitWidth: ghostBadge.implicitWidth + 8
                    implicitHeight: 15
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.25)
                    Text { id: ghostBadge; anchors.centerIn: parent; text: root.dragMethod; color: Kirigami.Theme.highlightedTextColor; font.pixelSize: 9; font.bold: true }
                }
                Kirigami.Icon {
                    visible: root.dragMethod.length === 0
                    source: "folder"; implicitWidth: 15; implicitHeight: 15
                    color: Kirigami.Theme.highlightedTextColor
                }
                Label { text: root.dragLabel; color: Kirigami.Theme.highlightedTextColor }
            }
        }
    }

    // ================= menus =================
    Menu {
        id: addMenu
        MenuItem { text: "Nova coleção…"; icon.name: "folder-new"; onTriggered: collectionDialog.open() }
        MenuItem { text: "Novo request…"; icon.name: "document-new"; onTriggered: newReqDialog.openIn(root.selectedIsFolder ? root.selectedPath : "") }
        MenuSeparator {}
        MenuItem { text: "Importar cURL…"; icon.name: "document-import"; onTriggered: { curlImportDialog.hint = ""; curlImportArea.text = ""; curlImportDialog.open(); } }
        MenuItem { text: "Colar request"; icon.name: "edit-paste"; onTriggered: root.pasteRequest() }
    }
    Menu {
        id: ctxMenu
        MenuItem { text: "Novo request aqui…"; icon.name: "document-new"; onTriggered: newReqDialog.openIn(root.targetFolder()) }
        MenuItem {
            text: "Nova pasta aqui"; icon.name: "folder-new"
            onTriggered: { root.selectedPath = root.targetFolder(); root.selectedIsFolder = root.selectedPath.length > 0; folderDialog.open(); }
        }
        MenuSeparator {}
        MenuItem { text: "Copiar request"; icon.name: "edit-copy"; enabled: root.selectedPath.length > 0 && !root.selectedIsFolder; onTriggered: root.copyTreeRequest(root.selectedPath) }
        MenuItem { text: "Mover para…"; icon.name: "edit-move"; enabled: root.selectedPath.length > 0; onTriggered: moveDialog.openFor(root.selectedPath) }
        MenuItem { text: "Renomear…"; icon.name: "edit-rename"; enabled: root.selectedPath.length > 0; onTriggered: renameDialog.openFor(root.selectedPath) }
        MenuItem { text: "Duplicar"; icon.name: "edit-copy"; enabled: root.selectedPath.length > 0; onTriggered: root.duplicateSelected() }
        MenuSeparator {}
        MenuItem { text: "Excluir"; icon.name: "edit-delete"; onTriggered: root.askDelete() }
    }

    Menu {
        id: reqMenu
        MenuItem { text: "Exportar código…"; icon.name: "document-export"; onTriggered: { curlExportDialog.refresh(); curlExportDialog.open(); } }
        MenuItem { text: "Copiar request"; icon.name: "edit-copy"; onTriggered: root.copyRequest() }
    }

    // ================= diálogos =================
    Dialog {
        id: newReqDialog
        title: "Novo request"; modal: true; anchors.centerIn: parent; width: 460; height: 300
        property string target: ""
        function openIn(folder) { target = folder; nrName.text = ""; nrUrl.text = ""; nrMethod.currentIndex = 0; open(); nrName.forceActiveFocus(); }
        function openPrefilled(folder, method, url) {
            target = folder;
            var base = url.split("?")[0].split("/").filter(function (s) { return s.length > 0; }).pop();
            nrName.text = base !== undefined && base.length > 0 ? base : "request";
            nrUrl.text = url;
            var i = nrMethod.find(method);
            nrMethod.currentIndex = i >= 0 ? i : 0;
            open();
            nrName.forceActiveFocus();
        }
        function create() {
            var n = nrName.text.trim();
            if (n.length === 0) { nrName.forceActiveFocus(); return; }
            var path = (target.length > 0 ? target + "/" : "") + n;
            var data = { method: nrMethod.currentText, url: nrUrl.text, params: [], headers: [], fields: [], body: "", bodyType: "none", auth: { type: "none" }, vars: [] };
            if (backend.saveRequest(path, data)) { root.reloadTree(); root.openRequest(path); close(); }
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { text: "Nome"; font.bold: true }
            TextField { id: nrName; Layout.fillWidth: true; placeholderText: "nome do request"; onAccepted: newReqDialog.create() }
            Label { text: "URL"; font.bold: true }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                ComboBox { id: nrMethod; model: ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS"]; implicitWidth: 110 }
                TextField { id: nrUrl; Layout.fillWidth: true; placeholderText: "https://..." }
            }
            Label { text: "Será criado em: " + (newReqDialog.target.length > 0 ? newReqDialog.target : "raiz"); opacity: 0.6 }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: newReqDialog.close() }
                Button { text: "Criar"; highlighted: true; onClicked: newReqDialog.create() }
            }
        }
    }

    Dialog {
        id: folderDialog
        title: "Nova pasta"; anchors.centerIn: parent; modal: true; width: 340; height: 140
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            var n = folderName.text.trim();
            if (n.length === 0) return;
            var base = root.targetFolder();
            backend.createFolder((base.length > 0 ? base + "/" : "") + n);
            root.reloadTree(); folderName.text = "";
        }
        ColumnLayout { anchors.fill: parent; TextField { id: folderName; Layout.fillWidth: true; placeholderText: "nome da pasta" } }
    }

    Dialog {
        id: collectionDialog
        title: "Nova coleção"; anchors.centerIn: parent; modal: true; width: 340; height: 140
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            var n = collectionName.text.trim();
            if (n.length === 0) return;
            backend.createFolder(n);
            root.reloadTree(); collectionName.text = "";
        }
        ColumnLayout { anchors.fill: parent; TextField { id: collectionName; Layout.fillWidth: true; placeholderText: "nome da coleção" } }
    }

    Dialog {
        id: confirmCloseDialog
        title: "Alterações não salvas"; modal: true; anchors.centerIn: parent; width: 400; height: 170
        property int tabIndex: -1
        ColumnLayout {
            anchors.fill: parent
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "O request '" + (confirmCloseDialog.tabIndex >= 0 && confirmCloseDialog.tabIndex < tabsModel.count ? tabsModel.get(confirmCloseDialog.tabIndex).name : "") + "' tem alterações não salvas."
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: confirmCloseDialog.close() }
                Button { text: "Descartar"; onClicked: { root.doCloseTab(confirmCloseDialog.tabIndex, false); confirmCloseDialog.close(); } }
                Button { text: "Salvar"; highlighted: true; onClicked: { root.doCloseTab(confirmCloseDialog.tabIndex, true); confirmCloseDialog.close(); } }
            }
        }
    }

    Dialog {
        id: quitDialog
        title: "Sair do katarina"; modal: true; anchors.centerIn: parent; width: 400; height: 170
        ColumnLayout {
            anchors.fill: parent
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Há requests com alterações não salvas." }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: quitDialog.close() }
                Button { text: "Descartar e sair"; onClicked: { root.persistSession(); root.forceQuit = true; quitDialog.close(); Qt.quit(); } }
                Button { text: "Salvar e sair"; highlighted: true; onClicked: { root.saveAllTabs(); root.persistSession(); root.forceQuit = true; quitDialog.close(); Qt.quit(); } }
            }
        }
    }

    // ---- import/export cURL ----
    Dialog {
        id: curlImportDialog
        title: "Importar cURL"; anchors.centerIn: parent; modal: true; width: 560; height: 320
        property string hint: ""
        ColumnLayout {
            anchors.fill: parent
            Label { text: "Cole um comando cURL:"; font.bold: true }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                TextArea { id: curlImportArea; font.family: "monospace"; wrapMode: TextEdit.Wrap; placeholderText: "curl 'https://…' -H '…' -d '…'" }
            }
            Label { text: curlImportDialog.hint; color: Kirigami.Theme.negativeTextColor; visible: text.length > 0 }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: curlImportDialog.close() }
                Button { text: "Importar"; highlighted: true; onClicked: root.importCurl(curlImportArea.text) }
            }
        }
    }
    Dialog {
        id: curlExportDialog
        title: "Exportar código"; anchors.centerIn: parent; modal: true; width: 640; height: 400
        function refresh() { curlExportArea.text = root.exportCode(exportFormat.currentText); }
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Label { text: "Formato:" }
                ComboBox {
                    id: exportFormat
                    implicitWidth: 200
                    model: ["cURL", "Python (requests)", "JavaScript (fetch)", "Go", "PHP", "Ruby", "HTTPie"]
                    currentIndex: Math.max(0, model.indexOf(settings.exportFormat))
                    onActivated: { settings.exportFormat = currentText; curlExportDialog.refresh(); }
                }
                Item { Layout.fillWidth: true }
                Button {
                    icon.name: "edit-copy"; text: "Copiar"
                    display: AbstractButton.TextBesideIcon
                    onClicked: { varSupport.copyText(curlExportArea.text); root.notify("Código copiado"); }
                }
            }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                TextArea { id: curlExportArea; readOnly: true; selectByMouse: true; font.family: "monospace"; wrapMode: TextEdit.NoWrap }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Fechar"; onClicked: curlExportDialog.close() }
            }
        }
    }

    // ---- configurações ----
    Dialog {
        id: settingsDialog
        title: "Configurações"; modal: true; anchors.centerIn: parent; width: 620; height: 640
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            ScrollView {
                id: settingsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: settingsScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing

                    Label { text: "Aparência"; font.bold: true }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Label { text: "Fonte do editor:"; Layout.preferredWidth: 170 }
                        SpinBox { from: 0; to: 28; value: settings.fontSize; onValueModified: settings.fontSize = value }
                        Label { text: "0 = padrão"; opacity: 0.6 }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }
                    Label { text: "Coleções"; font.bold: true }
                    Label { text: "Pasta onde as coleções são salvas:"; opacity: 0.7 }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        TextField { id: dirField; Layout.fillWidth: true; text: settings.storageDir }
                        Button { text: "Procurar…"; onClicked: folderPicker.open() }
                        Button {
                            text: "Aplicar"; highlighted: true
                            enabled: dirField.text.length > 0 && dirField.text !== backend.storageDir
                            onClicked: root.applyStorageDir(dirField.text)
                        }
                    }
                    Label {
                        text: "Ao aplicar, o katarina passa a usar essa pasta. As coleções atuais não são movidas — para trazê-las, copie os arquivos para lá."
                        opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }

                    Kirigami.Separator { Layout.fillWidth: true }
                    Label { text: "Rede"; font.bold: true }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Label { text: "Timeout (segundos):"; Layout.preferredWidth: 170 }
                        SpinBox { from: 0; to: 600; value: settings.timeoutSec; onValueModified: settings.timeoutSec = value }
                        Label { text: "0 = sem limite"; opacity: 0.6 }
                    }
                    CheckBox { text: "Ignorar erros de certificado TLS (self-signed)"; checked: settings.ignoreSsl; onToggled: settings.ignoreSsl = checked }

                    Kirigami.Separator { Layout.fillWidth: true }
                    Label { text: "Comportamento"; font.bold: true }
                    CheckBox { text: "Confirmar antes de excluir"; checked: settings.confirmDelete; onToggled: settings.confirmDelete = checked }
                    CheckBox { text: "Salvar automaticamente ao enviar"; checked: settings.autoSaveOnSend; onToggled: settings.autoSaveOnSend = checked }
                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Label { text: "Formato padrão de exportação:"; Layout.preferredWidth: 220 }
                        ComboBox {
                            id: exportFormatBox
                            implicitWidth: 180
                            model: ["cURL", "Python (requests)", "JavaScript (fetch)", "Go", "PHP", "Ruby", "HTTPie"]
                            currentIndex: Math.max(0, model.indexOf(settings.exportFormat))
                            onActivated: settings.exportFormat = currentText
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }
                    Label { text: "Atalhos"; font.bold: true }
                    Label { text: "Clique num atalho e pressione a nova combinação. Esc cancela."; opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Repeater {
                        model: root.shortcutDefs
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Label { text: modelData.label; Layout.fillWidth: true }
                            ShortcutField {
                                window: root
                                sequence: {
                                    var m = settings.shortcuts;
                                    return (m && m[modelData.id] !== undefined) ? m[modelData.id] : modelData.def;
                                }
                                onCaptured: function (seq) { settings.setShortcut(modelData.id, seq); }
                            }
                            ToolButton {
                                icon.name: "edit-undo"
                                enabled: { var m = settings.shortcuts; return m !== undefined && m[modelData.id] !== undefined; }
                                onClicked: settings.resetShortcut(modelData.id)
                                ToolTip.text: "Restaurar padrão"; ToolTip.visible: hovered
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: "As opções valem na hora."; opacity: 0.6; elide: Text.ElideRight; Layout.fillWidth: true }
                Button { text: "Fechar"; onClicked: settingsDialog.close() }
            }
        }
    }

    FolderDialog {
        id: folderPicker
        title: "Escolher pasta das coleções"
        onAccepted: dirField.text = selectedFolder.toString().replace("file://", "")
    }

    // ---- confirmar exclusão ----
    Dialog {
        id: confirmDeleteDialog
        title: "Excluir"; modal: true; anchors.centerIn: parent; width: 400; height: 175
        property string target: ""
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Excluir \"" + confirmDeleteDialog.target.split("/").pop() + "\"?"
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.7
                text: "Isso apaga do disco (recursivamente, se for pasta) e não pode ser desfeito."
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: confirmDeleteDialog.close() }
                Button {
                    text: "Excluir"; highlighted: true
                    onClicked: { root.deleteSelected(); confirmDeleteDialog.close(); }
                }
            }
        }
    }

    // ---- mover para ----
    Dialog {
        id: moveDialog
        title: "Mover para"; modal: true; anchors.centerIn: parent; width: 440; height: 430
        property string item: ""
        ListModel { id: moveModel }
        function openFor(relPath) {
            item = relPath;
            moveModel.clear();
            moveModel.append({ label: "Raiz (topo)", path: "" });
            var t = backend.collectionTree();
            for (var i = 0; i < t.length; i++) {
                var e = t[i];
                if (!e.isFolder) continue;
                if (e.relPath === item || e.relPath.indexOf(item + "/") === 0) continue;  // não mover pra dentro de si
                moveModel.append({ label: e.relPath, path: e.relPath });
            }
            open();
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label {
                text: "Mover \"" + moveDialog.item.split("/").pop() + "\" para:"
                font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: moveModel
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: model.label
                    onClicked: {
                        var base = moveDialog.item.split("/").pop();
                        root.moveEntry(moveDialog.item, model.path);
                        root.selectedPath = model.path.length > 0 ? model.path + "/" + base : base;
                        root.selectedIsFolder = false;
                        moveDialog.close();
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: moveDialog.close() }
            }
        }
    }

    // ---- renomear ----
    Dialog {
        id: renameDialog
        title: "Renomear"; modal: true; anchors.centerIn: parent; width: 360; height: 150
        property string relPath: ""
        function openFor(p) {
            relPath = p;
            renameField.text = p.split("/").pop();
            open();
            renameField.forceActiveFocus();
            renameField.selectAll();
        }
        function apply() {
            var n = renameField.text.trim();
            if (n.length === 0) return;
            var parent = relPath.split("/").slice(0, -1).join("/");
            var newRel = parent.length > 0 ? parent + "/" + n : n;
            if (backend.renameEntry(relPath, n)) {
                root.remapTabs(relPath, newRel);
                if (root.selectedPath === relPath) root.selectedPath = newRel;
                root.reloadTree();
                close();
            }
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { text: "Novo nome:" }
            TextField { id: renameField; Layout.fillWidth: true; onAccepted: renameDialog.apply() }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: renameDialog.close() }
                Button { text: "Renomear"; highlighted: true; onClicked: renameDialog.apply() }
            }
        }
    }

    // ---- histórico ----
    Dialog {
        id: historyDialog
        title: "Histórico"; anchors.centerIn: parent; modal: true; width: 640; height: 460
        ListModel { id: historyModel }
        function openAndLoad() {
            historyModel.clear();
            var h = backend.history();
            for (var i = 0; i < h.length; i++) historyModel.append(h[i]);
            open();
        }
        ColumnLayout {
            anchors.fill: parent
            Label { text: "Clique para criar um novo request pré-preenchido."; opacity: 0.6; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                model: historyModel
                delegate: ItemDelegate {
                    width: ListView.view.width
                    onClicked: { historyDialog.close(); newReqDialog.openPrefilled(root.targetFolder(), model.method, model.url); }
                    contentItem: RowLayout {
                        spacing: 6
                        Rectangle {
                            implicitWidth: hb.implicitWidth + 8; implicitHeight: 16; radius: 3
                            color: Qt.rgba(root.methodColor(model.method).r, root.methodColor(model.method).g, root.methodColor(model.method).b, 0.18)
                            Text { id: hb; anchors.centerIn: parent; text: model.method; color: root.methodColor(model.method); font.pixelSize: 9; font.bold: true }
                        }
                        Label { Layout.fillWidth: true; text: model.url; elide: Text.ElideMiddle }
                        Label { text: model.status; opacity: 0.7 }
                    }
                }
            }
            Label { visible: historyModel.count === 0; text: "Nada no histórico ainda — envie um request."; opacity: 0.5 }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Limpar"; onClicked: { backend.clearHistory(); historyDialog.openAndLoad(); } }
                Button { text: "Fechar"; onClicked: historyDialog.close() }
            }
        }
    }

    // ---- tela de variáveis de ambiente ----
    Dialog {
        id: envScreen
        title: "Variáveis de ambiente"; anchors.centerIn: parent; modal: true; width: 880; height: 500
        property string editing: ""
        property string viewCollection: ""
        property bool envVarsDirty: false
        property string pendingEnv: ""

        ListModel { id: envVarsModel }

        function openFor(name) {
            if (name.length === 0 && root.envList.length > 0) name = root.envList[0].name;
            viewCollection = "";
            envNameField.text = name;
            loadVars(name);
            open();
        }
        function loadVars(name) {
            editing = name;
            envVarsDirty = false;
            envVarsModel.clear();
            if (name.length === 0) return;
            var vars = backend.environmentVariables(name);
            for (var i = 0; i < vars.length; i++) {
                var v = vars[i];
                var cols = v.collections !== undefined ? v.collections : [];
                envVarsModel.append({ name: v.name, value: v.value !== undefined ? v.value : "",
                                      secret: v.secret === true, secretId: v.secretId !== undefined ? v.secretId : "",
                                      scope: v.scope !== undefined ? v.scope : "all",
                                      collections: cols.join(",") });
            }
        }
        function save() {
            var newName = envNameField.text.trim();
            if (newName.length === 0) return;
            if (newName !== editing && editing.length > 0)
                backend.renameEnvironment(editing, newName);
            var vars = [];
            for (var i = 0; i < envVarsModel.count; i++) {
                var v = envVarsModel.get(i);
                if (v.name.length === 0) continue;
                vars.push({ name: v.name, value: v.value, secret: v.secret, secretId: v.secretId,
                            scope: v.scope, collections: v.collections.length > 0 ? v.collections.split(",") : [] });
            }
            if (backend.saveEnvironment(newName, vars)) {
                root.activateEnv(newName);
                envNameField.text = newName;
                loadVars(newName);
                notify("Ambiente salvo");
            }
        }
        function matchesView(scope, collections) {
            if (viewCollection.length === 0) return true;
            if (scope === "all") return true;
            return collections.split(",").indexOf(viewCollection) >= 0;
        }
        function selectEnv(name) {
            if (name === editing) return;
            if (envVarsDirty) { pendingEnv = name; discardEnvDialog.open(); return; }
            envNameField.text = name;
            loadVars(name);
        }

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            // coluna esquerda: ambientes
            ColumnLayout {
                Layout.preferredWidth: 200
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing
                Label { text: "Ambientes"; font.bold: true }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.envList
                    delegate: ItemDelegate {
                        width: ListView.view.width
                        text: modelData.name
                        highlighted: modelData.name === envNameField.text
                        onClicked: { envScreen.selectEnv(modelData.name); }
                    }
                }
                Button {
                    Layout.fillWidth: true; icon.name: "list-add"; text: "Novo ambiente…"
                    display: AbstractButton.TextBesideIcon
                    onClicked: createEnvDialog.open()
                }
                Button {
                    Layout.fillWidth: true; icon.name: "edit-delete"; text: "Excluir"
                    display: AbstractButton.TextBesideIcon
                    enabled: envNameField.text.length > 0
                    onClicked: {
                        backend.deleteEnvironment(envNameField.text);
                        root.reloadEnvs();
                        envNameField.text = "";
                        envVarsModel.clear();
                    }
                }
            }

            Kirigami.Separator { Layout.fillHeight: true }

            // coluna direita: variáveis do ambiente
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing

                TextField { id: envNameField; Layout.fillWidth: true; placeholderText: "nome do ambiente"; onTextEdited: envScreen.envVarsDirty = true }

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Label { text: "Ver:" }
                    ComboBox {
                        id: viewCombo
                        implicitWidth: 230
                        model: ["Todas as variáveis"].concat(root.collectionNames())
                        onActivated: envScreen.viewCollection = currentIndex === 0 ? "" : currentText
                    }
                    Label { text: "globais aparecem em toda visão"; opacity: 0.6 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Label { Layout.preferredWidth: 150; text: "Nome"; font.bold: true }
                    Label { Layout.fillWidth: true; text: "Valor"; font.bold: true }
                    Label { Layout.preferredWidth: 200; text: "Escopo"; font.bold: true }
                    Label { Layout.preferredWidth: 70; text: "Segredo"; font.bold: true }
                    Item { Layout.preferredWidth: 40 }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    border.width: 1
                    border.color: Kirigami.Theme.disabledTextColor
                    radius: 4
                    color: "transparent"
                    ListView {
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true
                    model: envVarsModel
                    delegate: RowLayout {
                        id: envRow
                        width: ListView.view.width
                        spacing: Kirigami.Units.smallSpacing
                        readonly property string scopeVal: model.scope
                        readonly property string collectionsVal: model.collections
                        readonly property bool shown: envScreen.matchesView(scopeVal, collectionsVal)
                        visible: shown
                        height: shown ? implicitHeight : 0
                        TextField { Layout.preferredWidth: 150; text: model.name; placeholderText: "variável"; onTextEdited: { model.name = text; envScreen.envVarsDirty = true; } }
                        TextField {
                            Layout.fillWidth: true
                            text: model.value
                            placeholderText: model.secret ? "segredo (no cofre)" : "valor"
                            echoMode: model.secret ? TextInput.Password : TextInput.Normal
                            onTextEdited: { model.value = text; envScreen.envVarsDirty = true; }
                        }
                        Button {
                            Layout.preferredWidth: 200
                            icon.name: envRow.scopeVal === "collections" ? "lock" : "globe"
                            display: AbstractButton.TextBesideIcon
                            text: {
                                if (envRow.scopeVal !== "collections") return "Global";
                                var c = envRow.collectionsVal.length > 0 ? envRow.collectionsVal.split(",") : [];
                                if (c.length === 0) return "escolher coleções…";
                                if (c.length <= 2) return c.join(", ");
                                return c.length + " coleções";
                            }
                            onClicked: scopeDialog.openFor(index)
                            ToolTip.text: "Quais coleções podem usar esta variável"
                            ToolTip.visible: hovered
                        }
                        CheckBox { checked: model.secret === true; onToggled: { model.secret = checked; envScreen.envVarsDirty = true; } }
                        ToolButton {
                            icon.name: "list-remove"
                            onClicked: { envVarsModel.remove(index); envScreen.envVarsDirty = true; }
                            ToolTip.text: "Remover variável"; ToolTip.visible: hovered
                        }
                    }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        icon.name: "list-add"; text: "Adicionar variável"
                        display: AbstractButton.TextBesideIcon
                        onClicked: { envVarsModel.append({ name: "", value: "", secret: false, secretId: "", scope: "all", collections: "" }); envScreen.envVarsDirty = true; }
                    }
                    Item { Layout.fillWidth: true }
                    RowLayout {
                        visible: envScreen.envVarsDirty
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon { source: "media-record-symbolic"; color: Kirigami.Theme.neutralTextColor; implicitWidth: 10; implicitHeight: 10; Layout.alignment: Qt.AlignVCenter }
                        Label { text: "alterações não salvas"; color: Kirigami.Theme.neutralTextColor }
                    }
                    Button { text: "Resetar"; enabled: envScreen.envVarsDirty; onClicked: envScreen.loadVars(envNameField.text) }
                    Button { text: "Salvar"; highlighted: true; enabled: envScreen.envVarsDirty; onClicked: envScreen.save() }
                }
            }
        }
    }

    // ---- criar ambiente (só o nome) ----
    Dialog {
        id: createEnvDialog
        title: "Criar ambiente"; anchors.centerIn: parent; modal: true; width: 380; height: 160
        function create() {
            var n = newEnvName.text.trim();
            if (n.length === 0) { newEnvName.forceActiveFocus(); return; }
            backend.saveEnvironment(n, []);
            root.activateEnv(n);
            if (envScreen.visible) { envNameField.text = n; envScreen.loadVars(n); }
            createEnvDialog.close();
            envScreen.openFor(n);
        }
        onAboutToShow: newEnvName.text = ""
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { text: "Nome do ambiente"; font.bold: true }
            TextField { id: newEnvName; Layout.fillWidth: true; placeholderText: "ex.: dev"; onAccepted: createEnvDialog.create() }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: createEnvDialog.close() }
                Button { text: "Criar"; highlighted: true; onClicked: createEnvDialog.create() }
            }
        }
    }

    // ---- descartar alterações do ambiente ----
    Dialog {
        id: discardEnvDialog
        title: "Descartar alterações?"; modal: true; anchors.centerIn: parent; width: 400; height: 170
        ColumnLayout {
            anchors.fill: parent
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Há alterações não salvas neste ambiente. Trocar de ambiente vai descartá-las." }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: discardEnvDialog.close() }
                Button {
                    text: "Descartar"; highlighted: true
                    onClicked: {
                        discardEnvDialog.close();
                        envNameField.text = envScreen.pendingEnv;
                        envScreen.loadVars(envScreen.pendingEnv);
                    }
                }
            }
        }
    }

    // ---- visibilidade da variável (global ou coleções específicas) ----
    Dialog {
        id: scopeDialog
        title: "Visibilidade da variável"; modal: true; anchors.centerIn: parent; width: 420; height: 440
        property int rowIndex: -1
        property bool global: true
        ListModel { id: scopeCollectionsModel }
        function openFor(index) {
            rowIndex = index;
            var row = envVarsModel.get(index);
            global = row.scope !== "collections";
            var sel = row.collections.length > 0 ? row.collections.split(",") : [];
            scopeCollectionsModel.clear();
            var names = root.collectionNames();
            for (var i = 0; i < names.length; i++)
                scopeCollectionsModel.append({ name: names[i], on: sel.indexOf(names[i]) >= 0 });
            open();
        }
        function apply() {
            if (global) {
                envVarsModel.setProperty(rowIndex, "scope", "all");
                envVarsModel.setProperty(rowIndex, "collections", "");
            } else {
                var sel = [];
                for (var i = 0; i < scopeCollectionsModel.count; i++)
                    if (scopeCollectionsModel.get(i).on) sel.push(scopeCollectionsModel.get(i).name);
                envVarsModel.setProperty(rowIndex, "scope", "collections");
                envVarsModel.setProperty(rowIndex, "collections", sel.join(","));
            }
            envScreen.envVarsDirty = true;
            close();
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { text: "Esta variável pode ser usada por:"; font.bold: true; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            RadioButton { text: "Todas as coleções (global)"; checked: scopeDialog.global; onToggled: { if (checked) scopeDialog.global = true; } }
            RadioButton { text: "Somente as coleções selecionadas"; checked: !scopeDialog.global; onToggled: { if (checked) scopeDialog.global = false; } }
            Label { visible: root.collectionNames().length === 0; text: "Você ainda não tem coleções."; opacity: 0.6 }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                enabled: !scopeDialog.global
                opacity: scopeDialog.global ? 0.4 : 1
                model: scopeCollectionsModel
                delegate: CheckBox {
                    text: model.name
                    checked: model.on
                    enabled: !scopeDialog.global
                    onToggled: model.on = checked
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: scopeDialog.close() }
                Button { text: "OK"; highlighted: true; onClicked: scopeDialog.apply() }
            }
        }
    }

    FileDialog {
        id: fileDialog
        property int targetIndex: -1
        title: "Escolher arquivo"
        onAccepted: {
            if (targetIndex >= 0 && targetIndex < fieldsModel.count)
                fieldsModel.setProperty(targetIndex, "fileName", selectedFile.toString().replace("file://", ""));
        }
    }

    Connections {
        target: backend
        function onStarted() { root.sending = true; statusLabel.text = "Enviando…"; }
        function onCanceled() {
            root.sending = false;
            statusLabel.text = "Cancelado"; timeLabel.text = ""; sizeLabel.text = "";
        }
        function onResponseReady(status, statusText, headers, body, elapsedMs, sizeBytes) {
            root.sending = false;
            var lines = [], cookieLines = [];
            for (var i = 0; i < headers.length; i++) {
                lines.push(headers[i].name + ": " + headers[i].value);
                if (headers[i].name.toLowerCase() === "set-cookie")
                    cookieLines.push(headers[i].value);
            }
            var rec = { status: status, statusText: statusText, time: elapsedMs + " ms",
                        size: root.fmtSize(sizeBytes), headers: lines.join("\n"),
                        cookies: cookieLines.join("\n"), body: body };
            if (root.currentTab >= 0 && root.currentTab < tabsModel.count)
                root.responses[tabsModel.get(root.currentTab).relPath] = rec;
            statusLabel.text = status + " " + statusText;
            timeLabel.text = rec.time;
            sizeLabel.text = rec.size;
            responseHeaders.text = rec.headers;
            responseCookies = rec.cookies;
            setResponseBody(body);
            jsonTree.load(body);
        }
        function onError(message) {
            root.sending = false;
            statusLabel.text = "Erro: " + message;
            timeLabel.text = ""; sizeLabel.text = "";
        }
        function onCollectionsChanged() { root.reloadTree(); }
        function onEnvironmentsChanged() { root.reloadEnvs(); root.refreshResolved(); }
    }

    // ---- paleta de comandos (Ctrl+K) ----
    Popup {
        id: cmdPalette
        anchors.centerIn: parent
        width: 480
        height: 380
        modal: true
        focus: true
        padding: Kirigami.Units.smallSpacing
        property var allActions: []
        property var filtered: []

        function openPalette() {
            allActions = [
                { group: "Globais", label: "Novo request…", run: function () { newReqDialog.openIn(root.targetFolder()); } },
                { group: "Globais", label: "Nova pasta…", run: function () { folderDialog.open(); } },
                { group: "Globais", label: "Nova coleção…", run: function () { collectionDialog.open(); } },
                { group: "Globais", label: "Importar cURL…", run: function () { curlImportDialog.hint = ""; curlImportArea.text = ""; curlImportDialog.open(); } },
                { group: "Globais", label: "Histórico", run: function () { historyDialog.openAndLoad(); } },
                { group: "Globais", label: "Configurações…", run: function () { settingsDialog.open(); } },
                { group: "Globais", label: "Gerenciar variáveis de ambiente…", run: function () { envScreen.openFor(root.activeEnv); } },
                { group: "Globais", label: "Criar ambiente…", run: function () { createEnvDialog.open(); } },
                { group: "Globais", label: "Fechar aba", run: function () { root.closeTab(root.currentTab); } },
                { group: "Globais", label: "Reabrir aba fechada", run: function () { root.reopenClosed(); } },
                { group: "Contexto atual", label: "Salvar request", run: function () { root.saveCurrent(); } },
                { group: "Contexto atual", label: "Enviar request", run: function () { root.doSend(); } },
                { group: "Contexto atual", label: "Exportar código…", run: function () { curlExportDialog.refresh(); curlExportDialog.open(); } },
                { group: "Contexto atual", label: "Copiar request", run: function () { root.copyRequest(); } },
                { group: "Contexto atual", label: "Colar request", run: function () { root.pasteRequest(); } },
                { group: "Contexto atual", label: "Mover selecionado…", run: function () { if (root.selectedPath.length > 0) moveDialog.openFor(root.selectedPath); } },
                { group: "Contexto atual", label: "Renomear selecionado…", run: function () { if (root.selectedPath.length > 0) renameDialog.openFor(root.selectedPath); } },
                { group: "Contexto atual", label: "Duplicar selecionado", run: function () { root.duplicateSelected(); } }
            ];
            paletteField.text = "";
            applyFilter("");
            open();
            paletteField.forceActiveFocus();
        }
        function applyFilter(q) {
            q = q.toLowerCase();
            var out = [];
            for (var i = 0; i < allActions.length; i++)
                if (q.length === 0 || allActions[i].label.toLowerCase().indexOf(q) >= 0)
                    out.push(allActions[i]);
            filtered = out;
            paletteList.currentIndex = out.length > 0 ? 0 : -1;
        }
        function trigger() {
            if (paletteList.currentIndex >= 0 && paletteList.currentIndex < filtered.length) {
                var a = filtered[paletteList.currentIndex];
                cmdPalette.close();
                a.run();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { text: "Paleta de comandos"; font.bold: true }
            TextField {
                id: paletteField
                Layout.fillWidth: true
                placeholderText: "Digite um comando…"
                onTextChanged: cmdPalette.applyFilter(text)
                onAccepted: cmdPalette.trigger()
                Keys.onDownPressed: paletteList.currentIndex = Math.min(paletteList.currentIndex + 1, cmdPalette.filtered.length - 1)
                Keys.onUpPressed: paletteList.currentIndex = Math.max(paletteList.currentIndex - 1, 0)
            }
            ListView {
                id: paletteList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: cmdPalette.filtered
                section.property: "group"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    width: paletteList.width
                    implicitHeight: 28
                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: section
                        font.bold: true
                        font.pixelSize: 11
                        opacity: 0.55
                    }
                }
                onCurrentIndexChanged: { if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain); }
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: modelData.label
                    highlighted: index === paletteList.currentIndex
                    onClicked: { paletteList.currentIndex = index; cmdPalette.trigger(); }
                }
            }
        }
    }
}
