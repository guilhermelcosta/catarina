import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Util.js" as Util

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
    property bool showingEnv: false
    property bool showingSettings: false
    readonly property bool envTabDirty: envScreen.envVarsDirty   // estado não-salvo da aba de ambientes
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
    property bool dragIsCollection: false
    property int tabDragIndex: -1
    property int tabDropIndex: -1
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
    property bool treeReloadQueued: false
    property bool sending: false
    property var responseHeaders: []
    property var netMeta: ({})
    property string responseHint: ""

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
    function methodBg(m) { var c = methodColor(m); return Qt.rgba(c.r, c.g, c.b, 0.18); }
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
    function reloadTree() {   // coalesce: vários pedidos no mesmo tick viram 1 rebuild
        if (treeReloadQueued) return;
        treeReloadQueued = true;
        Qt.callLater(function () { treeReloadQueued = false; rebuildTree(); });
    }
    function rebuildTree() {
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
            treeModel.append({ name: e.name, relPath: e.relPath, isFolder: e.isFolder,
                               method: e.method !== undefined ? e.method : "",
                               depth: e.depth !== undefined ? e.depth : 0,
                               hasChildren: e.hasChildren === true,
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
            if (rp === from) {
                tabsModel.setProperty(i, "relPath", to);
                tabsModel.setProperty(i, "name", to.split("/").pop());
            } else if (rp.indexOf(prefix) === 0) {
                tabsModel.setProperty(i, "relPath", to + "/" + rp.substring(prefix.length));
            }
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
        backend.setActiveEnvironment(name);    // emite environmentsChanged → reloadEnvs + refreshResolved
    }
    function targetFolder() {
        if (selectedPath.length === 0) return "";
        return selectedIsFolder ? selectedPath : parentOf(selectedPath);
    }
    function entryOf(o) {
        return { name: o.name !== undefined ? o.name : "",
                 value: o.value !== undefined ? o.value : "",
                 enabled: o.enabled !== undefined ? o.enabled : true,
                 secret: o.secret === true, secretId: o.secretId !== undefined ? o.secretId : "",
                 type: o.type !== undefined ? o.type : "text",
                 fileName: o.fileName !== undefined ? o.fileName : "" };
    }
    function modelToArray(model) {
        var out = [];
        for (var i = 0; i < model.count; i++) out.push(entryOf(model.get(i)));
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
    function fillModels(list, model) {
        model.clear();
        var a = list !== undefined ? list : [];
        for (var i = 0; i < a.length; i++)
            model.append(entryOf(a[i]));
    }

    function applyRequest(r, relPath) {
        var idx = methodBox.find(r.method !== undefined ? r.method : "GET");
        methodBox.currentIndex = idx >= 0 ? idx : 0;
        urlField.text = r.url !== undefined ? r.url : "";
        fillModels(r.params, paramsModel);
        fillModels(r.headers, headersModel);
        fillModels(r.fields, fieldsModel);
        fillModels(backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []), requestVarsModel);
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
        collectionVarsDirty = false;        // saímos da coleção: edições pendentes não valem mais
        collectionHeadersDirty = false;
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
        collectionVarsDirty = false;
        collectionHeadersDirty = false;
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
        resolvedDebounce.stop();   // cancela um refresh agendado (é este que está rodando agora)
        if (currentTab < 0 || currentTab >= tabsModel.count) {
            resolvedVars = [];
            missingText = "";
            currentDirty = false;
            return;
        }
        var curTab = tabsModel.get(currentTab);
        if (curTab.isEnvironment || curTab.isSettings) {
            resolvedVars = [];
            missingText = "";
            currentDirty = false;
            return;
        }
        if (curTab.isCollection) {
            // na aba da coleção a lista efetiva é a da coleção, não a do request
            resolvedVars = [];
            missingText = "";
            currentDirty = false;
            refreshCollectionResolved();
            return;
        }
        const collection = collectionOf(curTab.relPath);
        currentCollection = collection;
        // uma passada só no backend: lista resolvida + o que falta
        const state = backend.variablesState(collectRequest(), collection);
        const miss = state.missing;
        const res = state.resolved;
        var notes = [];
        for (var i = 0; i < miss.length; i++) {
            var note = backend.variableNoteFor(miss[i], collection);
            for (var j = 0; j < res.length; j++)   // desabilitada no request não é "não definida"
                if (res[j].name === miss[i] && res[j].enabled === false)
                    note = "desabilitada";
            notes.push(note.length > 0 ? miss[i] + " (" + note + ")" : miss[i]);
        }
        missingText = notes.length > 0 ? "Variáveis não resolvidas: " + notes.join(", ") : "";
        res.sort(function (a, b) { return a.name.localeCompare(b.name); });
        resolvedVars = res;
        currentDirty = tabsModel.get(currentTab).dirty;
    }
    // re-resolve com atraso: digitar não recalcula a cada tecla
    Timer {
        id: resolvedDebounce
        interval: 180
        onTriggered: root.refreshResolved()
    }
    // ---- buscar na resposta (Ctrl+F): barra embutida, não sobrepõe o conteúdo ----
    property bool findVisible: false
    property int findMatchIndex: 0
    property int findMatchTotal: 0
    function hint(text) { root.responseHint = text; }
    function openFind() {
        if (responseBody.text.length === 0) return;
        findVisible = true;
        findField.forceActiveFocus();
        findField.selectAll();
    }
    function closeFind() { findVisible = false; findMatchIndex = 0; findMatchTotal = 0; }
    function countMatches(q) {
        if (q.length === 0) return [];
        var body = responseBody.text, out = [], i = body.indexOf(q);
        while (i >= 0) { out.push(i); i = body.indexOf(q, i + q.length); }
        return out;
    }
    function updateFindCounter() {
        var q = findField.text;
        var all = countMatches(q);
        findMatchTotal = all.length;
        findMatchIndex = 0;
    }
    function findNext(backwards) {
        var q = findField.text;
        if (q.length === 0) { findMatchTotal = 0; findMatchIndex = 0; return; }
        var all = countMatches(q);
        findMatchTotal = all.length;
        if (all.length === 0) { findMatchIndex = 0; notify("Não encontrado: " + q); return; }
        var cur = backwards ? responseBody.selectionStart - 1 : responseBody.selectionEnd;
        var idx;
        if (backwards) {
            idx = all[all.length - 1];
            for (var i = all.length - 1; i >= 0; i--) if (all[i] <= cur) { idx = all[i]; break; }
        } else {
            idx = all[0];
            for (var j = 0; j < all.length; j++) if (all[j] >= cur) { idx = all[j]; break; }
        }
        findMatchIndex = all.indexOf(idx) + 1;
        var end = idx + q.length;
        responseBody.deselect(0, responseBody.length);
        responseBody.select(idx, end);
        var r = responseBody.positionToRectangle(idx);
        var targetY = r.y - (bodyScroll.height / 2 - r.height / 2);
        bodyScroll.contentItem.contentY = Math.max(0, Math.min(targetY,
            Math.max(0, responseBody.contentHeight - bodyScroll.height + Kirigami.Units.smallSpacing)));
        bodyScroll.contentItem.contentX = 0;
    }
    function setResponseBody(body) {
        responseBody.text = body;   // corpo completo: o Ctrl+F busca em todo o conteúdo
    }
    // parseia o JSON só quando a aba "Árvore" está visível
    function syncJsonTree() {
        if (respTabBar.currentIndex !== 1) return;
        jsonTree.load(responseBody.text);
    }
    // limita o cache de respostas (o app é lightweight; não guarda tudo pra sempre)
    function evictResponses() {
        var MAX_ENTRIES = 15;
        var MAX_CHARS = 24 * 1024 * 1024;   // teto aproximado do cache
        var keys = Object.keys(root.responses);
        var total = 0;
        for (var i = 0; i < keys.length; i++) {
            var r = root.responses[keys[i]];
            total += (r && r.body ? r.body.length : 0);
        }
        while (keys.length > 1 && (keys.length > MAX_ENTRIES || total > MAX_CHARS)) {
            var k = keys.shift();
            var ev = root.responses[k];
            total -= (ev && ev.body ? ev.body.length : 0);
            delete root.responses[k];
        }
    }
    function restoreResponse(relPath) {
        var r = relPath.length > 0 ? responses[relPath] : undefined;
        if (r === undefined) {
            setResponseBody("");
            responseHeaders = [];
            responseCookies = "";
            netMeta = ({});
            syncJsonTree();
            statusLabel.text = "";
            timeLabel.text = "";
            sizeLabel.text = "";
        } else {
            statusLabel.text = r.status + " " + r.statusText;
            timeLabel.text = r.time;
            sizeLabel.text = r.size;
            responseHeaders = r.headers !== undefined ? r.headers : [];
            responseCookies = r.cookies !== undefined ? r.cookies : "";
            netMeta = r.meta !== undefined ? r.meta : ({});
            setResponseBody(r.body);
            syncJsonTree();
        }
    }

    // ================= abas =================
    function snapshotCurrent() {
        if (currentTab < 0 || currentTab >= tabsModel.count) return;
        var t = tabsModel.get(currentTab);
        if (t.isCollection || t.isEnvironment || t.isSettings) return;   // abas utilitárias não têm editor
        tabsModel.setProperty(currentTab, "dataJson", JSON.stringify(collectRequest()));
        tabsModel.setProperty(currentTab, "method", methodBox.currentText);
    }
    // índice da aba com esse relPath e tipo (request vs coleção), ou -1
    function tabIndexFor(relPath, isCollection) {
        for (var i = 0; i < tabsModel.count; i++) {
            var t = tabsModel.get(i);
            if (t.relPath === relPath && (t.isCollection === true) === isCollection) return i;
        }
        return -1;
    }
    function markDirty() {
        if (currentTab >= 0 && currentTab < tabsModel.count
                && !tabsModel.get(currentTab).isCollection && !tabsModel.get(currentTab).isEnvironment
                && !tabsModel.get(currentTab).isSettings)
            tabsModel.setProperty(currentTab, "dirty", true);
        currentDirty = true;
        resolvedDebounce.restart();   // debounce: não re-resolve a cada tecla
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
            if (!tabsModel.get(i).isCollection && tabsModel.get(i).relPath === relPath) { switchTab(i); return; }
        }
        var r = backend.loadRequest(relPath);
        if (r.method === undefined) return;
        r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);   // valor real do cofre
        tabsModel.append({ relPath: relPath, name: relPath.split("/").pop(),
                           method: r.method, dirty: false, dataJson: JSON.stringify(r),
                           isCollection: false, isEnvironment: false, isSettings: false });
        currentTab = tabsModel.count - 1;
        applyRequest(r, relPath);
        showingCollection = false;
        showingEnv = false;
        showingSettings = false;
    }
    function switchTab(i) {
        if (i < 0 || i >= tabsModel.count || i === currentTab) return;
        var t = tabsModel.get(i);
        snapshotCurrent();
        currentTab = i;
        if (t.isSettings) {
            showingSettings = true;
            showingEnv = false;
            showingCollection = false;
        } else if (t.isEnvironment) {
            if (envScreen.editing.length === 0) envScreen.openFor(root.activeEnv);   // primeira exibição
            showingSettings = false;
            showingEnv = true;
            showingCollection = false;
        } else if (t.isCollection) {
            showingSettings = false;
            loadCollection(t.relPath);
        } else {
            revealPath(t.relPath);   // mantém a árvore em sincronia com a aba ativa
            applyRequest(JSON.parse(t.dataJson), t.relPath);
            showingSettings = false;
            showingCollection = false;
            showingEnv = false;
        }
    }
    // abre (ou foca) a aba única de variáveis de ambiente
    function openEnvTab(name) {
        var idx = -1;
        for (var i = 0; i < tabsModel.count; i++)
            if (tabsModel.get(i).isEnvironment === true) { idx = i; break; }
        if (idx < 0) {
            snapshotCurrent();
            tabsModel.append({ relPath: "__environment__", name: "Ambientes", method: "",
                               dirty: false, dataJson: "", isCollection: false, isEnvironment: true });
            idx = tabsModel.count - 1;
        }
        switchTab(idx);
        envScreen.openFor(name);
        showingEnv = true;
        showingCollection = false;
    }
    // abre (ou foca) a aba única de configurações
    function openSettingsTab() {
        var idx = -1;
        for (var i = 0; i < tabsModel.count; i++)
            if (tabsModel.get(i).isSettings === true) { idx = i; break; }
        if (idx < 0) {
            snapshotCurrent();
            tabsModel.append({ relPath: "__settings__", name: "Configurações", method: "",
                               dirty: false, dataJson: "", isCollection: false, isEnvironment: false, isSettings: true });
            idx = tabsModel.count - 1;
        }
        switchTab(idx);
        showingSettings = true;
        showingEnv = false;
        showingCollection = false;
    }
    // aplica a aba ativa sem snapshot/guard (usado depois de fechar/excluir)
    function activateCurrent() {
        if (currentTab < 0 || currentTab >= tabsModel.count) {
            clearEditor();
            showingCollection = false;
            showingEnv = false;
            showingSettings = false;
            return;
        }
        var t = tabsModel.get(currentTab);
        if (t.isSettings) {
            showingSettings = true;
            showingEnv = false;
            showingCollection = false;
            return;
        }
        if (t.isEnvironment) {
            if (envScreen.editing.length === 0) envScreen.openFor(root.activeEnv);
            showingSettings = false;
            showingEnv = true;
            showingCollection = false;
            return;
        }
        if (t.isCollection) { showingSettings = false; loadCollection(t.relPath); return; }
        revealPath(t.relPath);
        applyRequest(JSON.parse(t.dataJson), t.relPath);
        showingSettings = false;
        showingCollection = false;
        showingEnv = false;
    }
    // restaura as abas salvas sem aplicar cada uma no editor (só a ativa é aplicada depois)
    function restoreSessionTabs(paths) {
        for (var i = 0; i < paths.length; i++) {
            var rp = paths[i];
            if (rp.length === 0) continue;
            if (rp === "__environment__") {
                tabsModel.append({ relPath: rp, name: "Ambientes", method: "", dirty: false,
                                   dataJson: "", isCollection: false, isEnvironment: true, isSettings: false });
                continue;
            }
            if (rp === "__settings__") {
                tabsModel.append({ relPath: rp, name: "Configurações", method: "", dirty: false,
                                   dataJson: "", isCollection: false, isEnvironment: false, isSettings: true });
                continue;
            }
            if (backend.isCollection(rp)) {
                tabsModel.append({ relPath: rp, name: rp.split("/").pop(),
                                   method: "", dirty: false, dataJson: "", isCollection: true, isEnvironment: false, isSettings: false });
                continue;
            }
            var r = backend.loadRequest(rp);
            if (r.method === undefined) continue;
            r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);   // valor real do cofre
            tabsModel.append({ relPath: rp, name: rp.split("/").pop(),
                               method: r.method, dirty: false, dataJson: JSON.stringify(r),
                               isCollection: false, isEnvironment: false, isSettings: false });
        }
    }
    // ---- reordenar abas por drag and drop ----
    function moveTab(from, to) {
        const m = Util.tabMove(tabsModel.count, from, to, currentTab);
        if (m === null) return;
        tabsModel.move(from, m.dest, 1);
        currentTab = m.current;
    }
    // x em coordenadas do tabRow; devolve o ponto de inserção (0..count)
    function tabIndexAt(x) {
        var n = 0;
        for (var i = 0; i < tabRow.children.length; i++) {
            var it = tabRow.children[i];
            if (!it.isTabDelegate) continue;   // ignora o Repeater e afins
            if (x < it.x + it.width / 2) return n;
            ++n;
        }
        return tabsModel.count;
    }
    function closeTab(i) {
        if (i < 0 || i >= tabsModel.count) return;
        var t = tabsModel.get(i);
        var dirty = t.isSettings
                  ? false
                  : (t.isEnvironment
                     ? (i === currentTab && envScreen.envVarsDirty)
                     : (t.isCollection
                        ? (i === currentTab && (collectionVarsDirty || collectionHeadersDirty))
                        : t.dirty));
        if (dirty) { confirmCloseDialog.tabIndex = i; confirmCloseDialog.open(); return; }
        doCloseTab(i, false);
    }
    function doCloseTab(i, saveFirst) {
        var t = tabsModel.get(i);
        var relPath = t.relPath;
        if (saveFirst) {
            if (t.isEnvironment) {
                envScreen.save();
            } else if (t.isCollection) {
                saveCollectionVars();
                saveCollectionHeaders();
            } else if (!t.isSettings) {
                var dataJson = (i === currentTab) ? JSON.stringify(collectRequest()) : t.dataJson;
                backend.saveRequest(relPath, JSON.parse(dataJson));
            }
        }
        if (!t.isCollection && !t.isEnvironment && !t.isSettings) {
            closedTabs.push(relPath);
            delete responses[relPath];   // libera a resposta guardada da aba fechada
        }
        tabsModel.remove(i);
        if (tabsModel.count === 0) { currentTab = -1; clearEditor(); showingCollection = false; showingEnv = false; reloadTree(); return; }
        if (i < currentTab) currentTab--;
        else if (i === currentTab) currentTab = Math.min(i, tabsModel.count - 1);
        activateCurrent();
        reloadTree();
    }
    function reopenClosed() {
        if (closedTabs.length === 0) return;
        openRequest(closedTabs.pop());
    }

    // abre (ou foca) a aba da coleção/pasta
    function openCollection(relPath) {
        var existing = tabIndexFor(relPath, true);
        if (existing >= 0) { switchTab(existing); return; }
        snapshotCurrent();
        tabsModel.append({ relPath: relPath, name: relPath.split("/").pop(),
                           method: "", dirty: false, dataJson: "", isCollection: true, isEnvironment: false, isSettings: false });
        currentTab = tabsModel.count - 1;
        loadCollection(relPath);
    }
    // destaca a coleção/pasta na árvore (abas de coleção não têm applyRequest)
    function revealCollection(relPath) {
        var c = Object.assign({}, root.collapsedFolders);
        var parts = relPath.split("/"), prefix = "";
        for (var i = 0; i < parts.length - 1; i++) {
            prefix = prefix.length === 0 ? parts[i] : prefix + "/" + parts[i];
            delete c[prefix];
        }
        root.collapsedFolders = c;
        root.selectedPath = relPath;
        root.selectedIsFolder = true;
        reloadTree();
    }
    // recalcula "Variáveis efetivas" da coleção (reabrir a aba e voltar à visão geral)
    function refreshCollectionResolved() {
        if (collectionPath.length === 0 || collectionIsSubfolder) { collectionResolvedVars = []; return; }
        collectionResolvedVars = backend.resolvedVariables(collectionOf(collectionPath), []);
    }
    // popula o painel da coleção a partir do disco
    function loadCollection(relPath) {
        revealCollection(relPath);
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
            fillModels(backend.withResolvedSecrets(backend.collectionVariables(relPath)), collectionVarsModel);
            fillModels(backend.withResolvedSecrets(backend.collectionHeaders(relPath)), collectionHeadersModel);
        }
        refreshCollectionResolved();
        collectionVarsDirty = false;
        collectionHeadersDirty = false;
        showingCollection = true;
        showingEnv = false;
    }
    function saveCollectionVars() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem variáveis
        backend.saveCollectionVariables(collectionPath, modelToArray(collectionVarsModel));
        collectionVarsDirty = false;
        refreshCollectionResolved();   // visão geral reflete secret/normal sem precisar reabrir
        notify("Variáveis da coleção salvas");
    }
    function revertCollectionVars() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;
        fillModels(backend.withResolvedSecrets(backend.collectionVariables(collectionPath)), collectionVarsModel);
        collectionVarsDirty = false;
        notify("Alterações descartadas");
    }
    function saveCollectionHeaders() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem cabeçalhos
        backend.saveCollectionHeaders(collectionPath, modelToArray(collectionHeadersModel));
        collectionHeadersDirty = false;
        notify("Cabeçalhos da coleção salvos");
    }
    function revertCollectionHeaders() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;
        fillModels(backend.withResolvedSecrets(backend.collectionHeaders(collectionPath)), collectionHeadersModel);
        collectionHeadersDirty = false;
        notify("Alterações descartadas");
    }

    function saveCurrent() {
        if (currentTab < 0 || currentTab >= tabsModel.count) return;
        var t = tabsModel.get(currentTab);
        if (t.isSettings) return;       // configurações aplicam na hora
        if (t.isEnvironment) {          // Ctrl+S na aba de ambientes salva o pendente
            if (envScreen.envVarsDirty) envScreen.save();
            return;
        }
        if (t.isCollection) {          // Ctrl+S na coleção salva o que estiver pendente
            if (collectionVarsDirty) saveCollectionVars();
            if (collectionHeadersDirty) saveCollectionHeaders();
            return;
        }
        if (backend.saveRequest(t.relPath, collectRequest())) {
            tabsModel.setProperty(currentTab, "method", methodBox.currentText);
            tabsModel.setProperty(currentTab, "dirty", false);
            currentDirty = false;
            refreshResolved();
            reloadTree();
            notify("Salvo em ~/katarina-collections/" + t.relPath + ".json");
        }
    }
    function revertCurrent() {
        if (currentTab < 0 || currentTab >= tabsModel.count) return;
        var t = tabsModel.get(currentTab);
        if (t.isCollection || t.isEnvironment) return;
        var r = backend.loadRequest(t.relPath);
        if (r.method === undefined) return;
        r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);
        tabsModel.setProperty(currentTab, "dataJson", JSON.stringify(r));
        tabsModel.setProperty(currentTab, "dirty", false);
        currentDirty = false;
        applyRequest(r, t.relPath);
        notify("Alterações descartadas");
    }
    function moveEntry(from, to) {
        if (!backend.moveEntry(from, to))
            return;
        var newRel = (to.length > 0 ? to + "/" : "") + from.split("/").pop();
        remapTabs(from, newRel);
        reloadTree();
        if (showingCollection)
            loadCollection(collectionPath);
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
        showingEnv = false;
        showingSettings = false;
        reloadTree();
        reloadEnvs();
        notify("Coleções agora em " + dir);
    }
    // confirmação única de exclusão: respeita settings.confirmDelete em TODOS os fluxos
    function confirmDelete(message, onConfirm) {
        if (!settings.confirmDelete) { onConfirm(); return; }
        deleteDialog.message = message;
        deleteDialog.callback = onConfirm;
        deleteDialog.open();
    }
    function askDelete() {
        if (selectedPath.length === 0) return;
        const name = selectedPath.split("/").pop();
        root.confirmDelete("Excluir \"" + name + "\"?\n"
                           + "Isso apaga do disco (recursivamente, se for pasta).",
                           function () { root.deleteSelected(); });
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
        activateCurrent();
        selectedPath = ""; selectedIsFolder = false;
        reloadTree();
    }

    function doSend() {
        if (sending || showingCollection || showingEnv || showingSettings || currentTab < 0) return;
        if (urlField.text.length === 0) { notify("Informe uma URL"); return; }
        if (settings.autoSaveOnSend && currentDirty) saveCurrent();
        var t = tabsModel.get(currentTab);
        setResponseBody(""); responseHeaders = []; netMeta = ({});
        backend.send(collectRequest(), collectionOf(t.relPath));
    }
    function persistSession() {
        var paths = [];
        for (var i = 0; i < tabsModel.count; i++) paths.push(tabsModel.get(i).relPath);
        settings.saveSession(paths, currentTab);
    }

    function hasDirtyTabs() {
        if (currentTab >= 0 && currentTab < tabsModel.count) {
            var ct = tabsModel.get(currentTab);
            if (ct.isEnvironment && envScreen.envVarsDirty) return true;
            if (ct.isCollection && (collectionVarsDirty || collectionHeadersDirty)) return true;
        }
        for (var i = 0; i < tabsModel.count; i++) {
            var t = tabsModel.get(i);
            if (!t.isCollection && !t.isEnvironment && !t.isSettings && t.dirty) return true;
        }
        return false;
    }
    function saveAllTabs() {
        for (var i = 0; i < tabsModel.count; i++) {
            var t = tabsModel.get(i);
            if (t.isCollection || t.isEnvironment || t.isSettings) continue;   // não são requests
            var dataJson = (i === currentTab) ? JSON.stringify(collectRequest()) : t.dataJson;
            backend.saveRequest(t.relPath, JSON.parse(dataJson));
            tabsModel.setProperty(i, "dirty", false);
        }
        if (currentTab >= 0 && currentTab < tabsModel.count) {
            var ct = tabsModel.get(currentTab);
            if (ct.isEnvironment && envScreen.envVarsDirty) envScreen.save();
            if (ct.isCollection) {
                if (collectionVarsDirty) saveCollectionVars();
                if (collectionHeadersDirty) saveCollectionHeaders();
            }
        }
        currentDirty = false;
        reloadTree();
    }

    // ================= cURL =================
    function importCurl(text) {
        var r = Util.parseCurl(text);
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
    // ponytail: base64/formatação/parse de cURL vivem em Util.js (domínio puro).

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
            headers.push({ name: "Authorization", value: "Basic " + Util.b64(a.user + ":" + a.pass) });
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
    Component.onCompleted: {
        rebuildTree();      // imediato (a restauração usa o modelo já preenchido)
        reloadEnvs();
        // A Kirigami registra Alt+Left/Right (StandardKey Back/Forward) no pageStack,
        // o que dá atalho ambíguo e anula a nossa navegação entre abas. Desativamos.
        var pr = pageStack.data;
        for (var pi = 0; pi < pr.length; pi++)
            if (pr[pi] && pr[pi].sequences !== undefined) pr[pi].enabled = false;
        var saved = settings.openTabs;      // restaura as abas da sessão anterior
        restoreSessionTabs(saved);
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
        { id: "palette", label: "Paleta de comandos", def: "Ctrl+K" },
        { id: "findInResponse", label: "Buscar na resposta", def: "Ctrl+F" }
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
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("findInResponse"); onActivated: root.openFind() }
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
                    onClicked: root.openSettingsTab()
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
                            onClicked: { envPopup.close(); root.openEnvTab(root.activeEnv); }
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
                        Kirigami.Icon { source: "folder-documents"; implicitWidth: 16; implicitHeight: 16 }
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
                                    color: root.methodBg(model.method)
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
                                        root.dragIsCollection = model.isFolder && (model.depth || 0) === 0;
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

                            // ação rápida (⋯): aparece no hover / item selecionado
                            ToolButton {
                                id: itemMenuBtn
                                anchors.right: parent.right
                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                anchors.verticalCenter: parent.verticalCenter
                                visible: treeItem.hovered || model.relPath === root.selectedPath
                                icon.name: "overflow-menu"
                                onClicked: {
                                    root.selectedPath = model.relPath;
                                    root.selectedIsFolder = model.isFolder;
                                    ctxMenu.popup(itemMenuBtn);
                                }
                                ToolTip.text: "Mais ações"; ToolTip.visible: hovered
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
                                        property bool isTabDelegate: true
                                        opacity: (root.dragging && root.tabDragIndex === index) ? 0.4 : 1
                                        Rectangle {
                                            anchors.fill: parent
                                            color: index === root.currentTab ? Kirigami.Theme.backgroundColor : "transparent"
                                            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 2; visible: index === root.currentTab; color: Kirigami.Theme.highlightColor }
                                        }
                                        // ponto de inserção (à esquerda desta aba)
                                        Rectangle {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: 2; color: Kirigami.Theme.highlightColor
                                            visible: root.dragging && root.tabDragIndex >= 0 && root.tabDropIndex === index
                                        }
                                        // ponto de inserção no fim (após a última aba)
                                        Rectangle {
                                            anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: 2; color: Kirigami.Theme.highlightColor
                                            visible: root.dragging && root.tabDragIndex >= 0
                                                     && root.tabDropIndex === tabsModel.count && index === tabsModel.count - 1
                                        }
                                        RowLayout {
                                            id: tabContent
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            spacing: 6
                                            Rectangle {
                                                visible: !model.isCollection && !model.isEnvironment && !model.isSettings
                                                implicitWidth: tabBadge.implicitWidth + 8; implicitHeight: 14; radius: 3
                                                color: root.methodBg(model.method)
                                                Text { id: tabBadge; anchors.centerIn: parent; text: model.method; color: root.methodColor(model.method); font.pixelSize: 8; font.bold: true }
                                            }
                                            Kirigami.Icon {
                                                visible: model.isCollection || model.isEnvironment || model.isSettings
                                                source: model.isSettings ? "configure"
                                                      : (model.isEnvironment ? "vcs-branch"
                                                      : (model.relPath.indexOf("/") < 0 ? "folder-documents" : "folder"))
                                                implicitWidth: 14; implicitHeight: 14
                                                color: Kirigami.Theme.textColor
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                            Label { text: model.name; font.bold: index === root.currentTab; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                                            Kirigami.Icon {
                                                visible: model.dirty
                                                         || (model.isCollection && index === root.currentTab && (root.collectionVarsDirty || root.collectionHeadersDirty))
                                                         || (model.isEnvironment && index === root.currentTab && root.envTabDirty)
                                                source: "media-record-symbolic"
                                                color: Kirigami.Theme.highlightColor
                                                implicitWidth: 8; implicitHeight: 8
                                                Layout.alignment: Qt.AlignVCenter
                                            }
                                        }
                                        MouseArea {
                                            id: tabMouse
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            preventStealing: true
                                            property real pressX: 0
                                            property real pressY: 0
                                            onPressed: function (m) { root.justDragged = false; pressX = m.x; pressY = m.y; }
                                            onPositionChanged: function (m) {
                                                if (!pressed || !(m.buttons & Qt.LeftButton)) return;
                                                if (!root.dragging) {
                                                    if (Math.abs(m.x - pressX) + Math.abs(m.y - pressY) < 8) return;
                                                    root.dragging = true;
                                                    root.tabDragIndex = index;
                                                    root.dragFrom = model.relPath;
                                                    root.dragLabel = model.name;
                                                    root.dragMethod = model.method;
                                                    root.dragIsCollection = model.isCollection === true;
                                                }
                                                var gp = tabMouse.mapToItem(mainPage, m.x, m.y);
                                                root.ghostX = gp.x;
                                                root.ghostY = gp.y;
                                                var lp = tabMouse.mapToItem(tabRow, m.x, m.y);
                                                root.tabDropIndex = root.tabIndexAt(lp.x);
                                            }
                                            onReleased: {
                                                if (!root.dragging) return;
                                                root.justDragged = true;
                                                var from = root.tabDragIndex;
                                                var to = root.tabDropIndex;
                                                root.dragging = false;
                                                root.tabDragIndex = -1;
                                                root.tabDropIndex = -1;
                                                if (from >= 0 && to >= 0 && from !== to)
                                                    root.moveTab(from, to);
                                            }
                                            onCanceled: { root.dragging = false; root.tabDragIndex = -1; root.tabDropIndex = -1; }
                                            onClicked: function (mouse) {
                                                if (root.justDragged) { root.justDragged = false; return; }
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
                        currentIndex: root.showingSettings ? 4
                                      : (root.showingEnv ? 3
                                      : (root.showingCollection ? 1 : (root.currentTab >= 0 ? 0 : 2)))

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
                                        icon.name: "edit-undo"
                                        enabled: root.currentDirty
                                        onClicked: root.revertCurrent()
                                        ToolTip.text: "Descartar alterações não salvas"; ToolTip.visible: hovered
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
                                        KvTable {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            visible: bodyTypeBox.currentValue === "multipart" || bodyTypeBox.currentValue === "urlencoded"
                                            model: fieldsModel
                                            keyPlaceholder: "campo"
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
                                        RowLayout {
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.topMargin: Kirigami.Units.smallSpacing
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
                                                implicitWidth: 170
                                                onActivated: root.markDirty()
                                            }
                                        }
                                        TextArea {
                                            id: bearerToken
                                            Layout.fillWidth: true
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
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
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing
                                            TextField { id: basicUser; Layout.fillWidth: true; placeholderText: "Usuário"; onTextEdited: root.markDirty() }
                                            TextField { id: basicPass; Layout.fillWidth: true; placeholderText: "Senha"; echoMode: TextInput.Password; onTextEdited: root.markDirty() }
                                        }
                                        RowLayout {
                                            visible: authTypeBox.currentValue === "apikey"
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
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
                                        Label { visible: authTypeBox.currentValue === "none"; text: "Sem autenticação."; opacity: 0.7; Layout.leftMargin: Kirigami.Units.smallSpacing }
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
                                                opacity: modelData.enabled === false ? 0.4 : 1
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
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.margins: Kirigami.Units.smallSpacing
                                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2   // reserva a altura mesmo sem resposta
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
                                        onClicked: { varSupport.copyText(responseBody.text.length > 0 ? responseBody.text : ""); root.notify("Resposta copiada"); }
                                        onHoveredChanged: root.hint(hovered ? "Copiar a resposta para a área de transferência" : "")
                                    }
                                    ToolButton {
                                        visible: responseBody.text.length > 0
                                        icon.name: "edit-find"
                                        onClicked: root.openFind()
                                        onHoveredChanged: root.hint(hovered ? "Buscar na resposta (Ctrl+F)" : "")
                                    }
                                }

                                TabBar {
                                    id: respTabBar
                                    Layout.fillWidth: true
                                    onCurrentIndexChanged: if (currentIndex === 1) root.syncJsonTree()
                                    TabButton { text: "Corpo"; onHoveredChanged: root.hint(hovered ? "Corpo da resposta" : "") }
                                    TabButton { text: "Árvore"; onHoveredChanged: root.hint(hovered ? "Explorar o JSON em árvore" : "") }
                                    TabButton { text: "Cabeçalhos"; onHoveredChanged: root.hint(hovered ? "Cabeçalhos da resposta" : "") }
                                    TabButton { text: "Cookies"; onHoveredChanged: root.hint(hovered ? "Cookies da resposta" : "") }
                                    TabButton { text: "Rede"; onHoveredChanged: root.hint(hovered ? "Detalhes da conexão e do request enviado" : "") }
                                }

                                // busca embutida (Ctrl+F) — só aparece quando acionada
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Kirigami.Units.smallSpacing
                                    Layout.rightMargin: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    visible: root.findVisible
                                    TextField {
                                        id: findField
                                        Layout.fillWidth: true
                                        placeholderText: "Buscar na resposta…"
                                        onAccepted: root.findNext(false)
                                        onTextChanged: { if (text.length > 0) root.findNext(false); else root.updateFindCounter(); }
                                        Keys.onEscapePressed: root.closeFind()
                                    }
                                    Label {
                                        visible: root.findMatchTotal > 0
                                        text: root.findMatchIndex + "/" + root.findMatchTotal
                                        opacity: 0.75
                                        font.family: "monospace"
                                    }
                                    ToolButton {
                                        icon.name: "go-up"; onClicked: root.findNext(true)
                                        onHoveredChanged: root.hint(hovered ? "Ocorrência anterior" : "")
                                    }
                                    ToolButton {
                                        icon.name: "go-down"; onClicked: root.findNext(false)
                                        onHoveredChanged: root.hint(hovered ? "Próxima ocorrência" : "")
                                    }
                                    ToolButton {
                                        icon.name: "window-close"; onClicked: root.closeFind()
                                        onHoveredChanged: root.hint(hovered ? "Fechar busca" : "")
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    StackLayout {
                                        anchors.fill: parent
                                        currentIndex: respTabBar.currentIndex
                                        // ---- Corpo ----
                                        ScrollView {
                                            id: bodyScroll
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            padding: Kirigami.Units.smallSpacing
                                            TextArea {
                                                id: responseBody
                                                readOnly: true
                                                font.family: "monospace"
                                                font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize
                                                wrapMode: TextEdit.Wrap
                                                selectionColor: Kirigami.Theme.highlightColor
                                                selectedTextColor: Kirigami.Theme.highlightedTextColor
                                                Component.onCompleted: {
                                                    var dark = Kirigami.Theme.backgroundColor.hsvValue < 0.5;
                                                    varSupport.attach(responseBody.textDocument, "#c678dd", true, true,
                                                        dark ? "#98c379" : "#2e7d32",
                                                        dark ? "#d19a66" : "#b26a00",
                                                        dark ? "#d19a66" : "#b26a00");
                                                }
                                            }
                                        }
                                        JsonTree { id: jsonTree; Layout.fillWidth: true; Layout.fillHeight: true }
                                        HeaderTable {
                                            id: responseHeadersTable
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing
                                            headers: root.responseHeaders
                                        }
                                        ScrollView {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            padding: Kirigami.Units.smallSpacing
                                            TextArea { id: responseCookiesArea; readOnly: true; font.family: "monospace"; wrapMode: TextEdit.Wrap; text: root.responseCookies; placeholderText: "Sem cookies." }
                                        }
                                        NetworkView {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            meta: root.netMeta
                                        }
                                    }
                                    // estado vazio (ainda sem resposta) — só na aba "Corpo"
                                    EmptyState {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                                        visible: responseBody.text.length === 0 && !root.sending && respTabBar.currentIndex === 0
                                        iconSource: "qrc:/icons/katarina.svg"
                                        title: "Sem resposta ainda"
                                        message: "Envie a requisição (Ctrl+Enter) para ver a resposta aqui."
                                        shortcut: "Ctrl+K"
                                        shortcutLabel: "abre a paleta de comandos"
                                    }
                                }

                                // faixa de status/hint do painel (substitui tooltips flutuantes)
                                Kirigami.Separator { Layout.fillWidth: true }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: hintLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                                    color: Kirigami.Theme.alternateBackgroundColor
                                    Label {
                                        id: hintLabel
                                        anchors.fill: parent
                                        anchors.leftMargin: Kirigami.Units.smallSpacing
                                        anchors.rightMargin: Kirigami.Units.smallSpacing
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        font.pixelSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.75
                                        text: root.responseHint
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
                                onCurrentIndexChanged: { root.collectionTab = currentIndex; if (currentIndex === 0) root.refreshCollectionResolved(); }
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
                                padding: Kirigami.Units.largeSpacing
                                ColumnLayout {
                                    width: parent.width
                                    spacing: Kirigami.Units.largeSpacing
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
                                            opacity: modelData.enabled === false ? 0.4 : 1
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
                                                    color: root.methodBg(modelData.method)
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
                            Item {
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.largeSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    SaveBar {
                                        Layout.fillWidth: true
                                        title: "Cabeçalhos da coleção"
                                        dirty: root.collectionHeadersDirty
                                        showDiscard: true
                                        onSave: root.saveCollectionHeaders()
                                        onDiscard: root.revertCollectionHeaders()
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
                            }

                            // 2) variáveis
                            Item {
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.largeSpacing
                                    spacing: Kirigami.Units.smallSpacing
                                    SaveBar {
                                        Layout.fillWidth: true
                                        title: "Variáveis da coleção"
                                        dirty: root.collectionVarsDirty
                                        showDiscard: true
                                        onSave: root.saveCollectionVars()
                                        onDiscard: root.revertCollectionVars()
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
                        }

                        // ---- 2: vazio ----
                        Item {
                            EmptyState {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                                iconSource: "document-send"
                                title: "Nenhum request aberto"
                                message: "Selecione um request na barra lateral ou crie um novo."
                                actionText: "Novo request…"
                                actionIcon: "document-new"
                                onActionTriggered: newReqDialog.openIn(root.targetFolder())
                            }
                        }

                        // ---- 3: variáveis de ambiente (aba própria) ----
                        Item {
                            id: envScreen
                            property string editing: ""
                            property string viewCollection: ""
                            property bool envVarsDirty: false
                            property string pendingEnv: ""

                            ListModel { id: envVarsModel }

                            function openFor(name) {
                                if (name.length === 0 && root.envList.length > 0) name = root.envList[0].name;
                                viewCollection = "";
                                loadVars(name);
                            }
                            function loadVars(name) {
                                editing = name;
                                envVarsDirty = false;
                                envVarsModel.clear();
                                if (name.length === 0) return;
                                var vars = backend.withResolvedSecrets(backend.environmentVariables(name));   // valor real do cofre
                                for (var i = 0; i < vars.length; i++) {
                                    var v = vars[i];
                                    var cols = v.collections !== undefined ? v.collections : [];
                                    envVarsModel.append({ name: v.name, value: v.value !== undefined ? v.value : "",
                                                          enabled: v.enabled !== false,
                                                          secret: v.secret === true, secretId: v.secretId !== undefined ? v.secretId : "",
                                                          scope: v.scope !== undefined ? v.scope : "all",
                                                          collections: cols.join(",") });
                                }
                            }
                            function save() {
                                if (editing.length === 0) return;
                                var vars = [];
                                for (var i = 0; i < envVarsModel.count; i++) {
                                    var v = envVarsModel.get(i);
                                    if (v.name.length === 0) continue;
                                    vars.push({ name: v.name, value: v.value, enabled: v.enabled !== false, secret: v.secret, secretId: v.secretId,
                                                scope: v.scope, collections: v.collections.length > 0 ? v.collections.split(",") : [] });
                                }
                                if (backend.saveEnvironment(editing, vars)) {
                                    root.activateEnv(editing);
                                    loadVars(editing);
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
                                loadVars(name);
                            }
                            function startRename(name) {
                                if (envVarsDirty) { notify("Salve as alterações antes de renomear"); return; }
                                renameEnvDialog.oldName = name;
                                renameEnvDialog.open();
                            }
                            function renameTo(oldName, newName) {
                                if (!backend.renameEnvironment(oldName, newName)) {
                                    notify("Já existe um ambiente com esse nome");
                                    return;
                                }
                                root.reloadEnvs();
                                loadVars(newName);
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.largeSpacing
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
                                            highlighted: modelData.name === envScreen.editing
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
                                        enabled: envScreen.editing.length > 0
                                        onClicked: {
                                            const name = envScreen.editing;
                                            root.confirmDelete("Excluir o ambiente \"" + name + "\"?", function () {
                                                backend.deleteEnvironment(name);
                                                root.reloadEnvs();
                                                envScreen.editing = "";
                                                envVarsModel.clear();
                                            });
                                        }
                                    }
                                }

                                Kirigami.Separator { Layout.fillHeight: true }

                                // coluna direita: variáveis do ambiente
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: Kirigami.Units.smallSpacing

                                    SaveBar {
                                        Layout.fillWidth: true
                                        title: envScreen.editing
                                        dirty: envScreen.envVarsDirty
                                        showDiscard: true
                                        showRename: true
                                        canRename: envScreen.editing.length > 0 && !envScreen.envVarsDirty
                                        renameTooltip: envScreen.envVarsDirty ? "Salve antes de renomear" : "Renomear ambiente"
                                        onSave: envScreen.save()
                                        onDiscard: envScreen.loadVars(envScreen.editing)
                                        onRename: envScreen.startRename(envScreen.editing)
                                    }

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

                                    KvTable {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        model: envVarsModel
                                        keyPlaceholder: "variável"
                                        secretColumn: true
                                        scopeColumn: true
                                        resolved: root.resolvedVars
                                        rowFilter: function(i) {
                                            var v = envVarsModel.get(i);
                                            return v !== undefined && envScreen.matchesView(v.scope, v.collections);
                                        }
                                        scopeIcon: function(i) {
                                            var v = envVarsModel.get(i);
                                            return (v && v.scope === "collections") ? "lock" : "globe";
                                        }
                                        scopeText: function(i) {
                                            var v = envVarsModel.get(i);
                                            if (!v || v.scope !== "collections") return "Global";
                                            var c = (v.collections && v.collections.length > 0) ? v.collections.split(",") : [];
                                            if (c.length === 0) return "escolher coleções…";
                                            if (c.length <= 2) return c.join(", ");
                                            return c.length + " coleções";
                                        }
                                        scopeTooltip: function(i) {
                                            var v = envVarsModel.get(i);
                                            if (!v || v.scope !== "collections") return "Vale para todas as coleções";
                                            var c = (v.collections && v.collections.length > 0) ? v.collections.split(",") : [];
                                            return c.length > 0 ? c.join(", ") : "Nenhuma coleção selecionada";
                                        }
                                        onScopeRequested: function(i, gx, gy) { scopePopup.openFor(i, gx, gy); }
                                        onAddRequested: envVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "", scope: "all", collections: "" })
                                        onEdited: envScreen.envVarsDirty = true
                                    }
                                }
                            }
                        }

                        // ---- 4: configurações (aba própria) ----
                        Item {
                            id: settingsPage
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.largeSpacing
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
                                Label { text: "As opções valem na hora."; opacity: 0.6; Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }
                            }
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
                    source: root.dragIsCollection ? "folder-documents" : "folder"
                    implicitWidth: 15; implicitHeight: 15
                    color: Kirigami.Theme.highlightedTextColor
                }
                Label { text: root.dragLabel; color: Kirigami.Theme.highlightedTextColor }
            }
        }
    }

    // ================= menus =================
    Menu {
        id: addMenu
        MenuItem { text: "Nova coleção…"; icon.name: "folder-documents"; onTriggered: collectionDialog.open() }
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
        MenuItem { text: "Duplicar"; icon.name: "edit-duplicate"; enabled: root.selectedPath.length > 0; onTriggered: root.duplicateSelected() }
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
                text: {
                    var i = confirmCloseDialog.tabIndex;
                    if (i < 0 || i >= tabsModel.count) return "Alterações não salvas.";
                    var t = tabsModel.get(i);
                    var what = t.isCollection ? "A coleção" : (t.isEnvironment ? "O ambiente" : "O request");
                    return what + " '" + t.name + "' tem alterações não salvas.";
                }
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
        function refresh() { curlExportArea.text = Util.exportCode(root.requestParts()); }
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Label { text: "cURL"; font.bold: true }
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
    FolderDialog {
        id: folderPicker
        title: "Escolher pasta das coleções"
        onAccepted: dirField.text = selectedFolder.toString().replace("file://", "")
    }

    // ---- mover para ----
    // ---- mover para (popover ancorado à linha da árvore) ----
    Popup {
        id: moveDialog
        parent: Overlay.overlay
        modal: false
        padding: Kirigami.Units.smallSpacing
        width: 320
        height: Math.min(360, 64 + moveModel.count * 34)
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
            // ancora na linha selecionada da árvore
            var idx = -1;
            for (var k = 0; k < treeModel.count; k++)
                if (treeModel.get(k).relPath === relPath) { idx = k; break; }
            var it = idx >= 0 ? treeView.itemAtIndex(idx) : null;
            if (it) {
                var p = it.mapToItem(null, it.width, 0);
                x = Math.max(0, Math.min(p.x + 8, (parent ? parent.width : 800) - width));
                y = p.y;
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
                            color: root.methodBg(model.method)
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
                Button { text: "Limpar"; onClicked: root.confirmDelete("Limpar todo o histórico?", function () { backend.clearHistory(); historyDialog.openAndLoad(); }) }
                Button { text: "Fechar"; onClicked: historyDialog.close() }
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
            createEnvDialog.close();
            root.openEnvTab(n);
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
                        envScreen.loadVars(envScreen.pendingEnv);
                    }
                }
            }
        }
    }

    // ---- renomear ambiente ----
    Dialog {
        id: renameEnvDialog
        title: "Renomear ambiente"; modal: true; anchors.centerIn: parent; width: 380; height: 160
        property string oldName: ""
        function apply() {
            var n = envRenameField.text.trim();
            if (n.length === 0 || n === oldName) { close(); return; }
            envScreen.renameTo(oldName, n);
            close();
        }
        onAboutToShow: envRenameField.text = oldName
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { text: "Novo nome do ambiente"; font.bold: true }
            TextField { id: envRenameField; Layout.fillWidth: true; placeholderText: "nome do ambiente"; onAccepted: renameEnvDialog.apply() }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: renameEnvDialog.close() }
                Button { text: "Renomear"; highlighted: true; onClicked: renameEnvDialog.apply() }
            }
        }
    }

    // ---- escopo da variável (global ou coleções específicas) — popover ancorado ----
    Popup {
        id: scopePopup
        parent: Overlay.overlay
        modal: false
        padding: Kirigami.Units.smallSpacing
        width: 300
        property int rowIndex: -1
        property bool global: true
        ListModel { id: scopeCollectionsModel }
        function openFor(index, gx, gy) {
            rowIndex = index;
            var row = envVarsModel.get(index);
            global = row === undefined || row.scope !== "collections";
            var sel = (row && row.collections.length > 0) ? row.collections.split(",") : [];
            scopeCollectionsModel.clear();
            var names = root.collectionNames();
            for (var i = 0; i < names.length; i++)
                scopeCollectionsModel.append({ name: names[i], on: sel.indexOf(names[i]) >= 0 });
            x = Math.max(0, Math.min(gx, (parent ? parent.width : 800) - width));
            y = gy;
            open();
        }
        // aplica ao vivo (sem OK/Cancelar)
        function applyScope() {
            if (rowIndex < 0) return;
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
        }
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { text: "Escopo da variável"; font.bold: true; Layout.fillWidth: true }
            TabBar {
                id: scopeMode
                Layout.fillWidth: true
                currentIndex: scopePopup.global ? 0 : 1
                TabButton { text: "Global"; onClicked: { scopePopup.global = true; scopePopup.applyScope(); } }
                TabButton { text: "Coleções"; onClicked: { scopePopup.global = false; scopePopup.applyScope(); } }
            }
            Rectangle {
                visible: !scopePopup.global
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(240, Math.max(60, scopeCollectionsModel.count * 34 + 8))
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                radius: 4
                color: "transparent"
                ListView {
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true
                    model: scopeCollectionsModel
                    delegate: CheckDelegate {
                        width: ListView.view.width
                        text: model.name
                        checked: model.on
                        onToggled: { model.on = checked; scopePopup.applyScope(); }
                    }
                }
                Label {
                    anchors.centerIn: parent
                    visible: scopeCollectionsModel.count === 0
                    text: "Você ainda não tem coleções."
                    opacity: 0.6
                }
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
            var cookieLines = [];
            for (var i = 0; i < headers.length; i++) {
                if (headers[i].name.toLowerCase() === "set-cookie")
                    cookieLines.push(headers[i].value);
            }
            var rec = { status: status, statusText: statusText, time: elapsedMs + " ms",
                        size: Util.fmtSize(sizeBytes), headers: headers,
                        cookies: cookieLines.join("\n"), body: body };
            // guarda a resposta na aba do request (não numa aba de coleção)
            if (root.currentTab >= 0 && root.currentTab < tabsModel.count
                    && !tabsModel.get(root.currentTab).isCollection)
                root.responses[tabsModel.get(root.currentTab).relPath] = rec;
            evictResponses();
            statusLabel.text = status + " " + statusText;
            timeLabel.text = rec.time;
            sizeLabel.text = rec.size;
            responseHeaders = rec.headers;
            responseCookies = rec.cookies;
            setResponseBody(body);
            syncJsonTree();
        }
        function onError(message) {
            root.sending = false;
            statusLabel.text = "Erro: " + message;
            timeLabel.text = ""; sizeLabel.text = "";
        }
        function onResponseMeta(meta) {
            root.netMeta = meta;
            // guarda o meta junto da resposta da aba atual (para restaurar ao trocar de aba)
            if (root.currentTab >= 0 && root.currentTab < tabsModel.count
                    && !tabsModel.get(root.currentTab).isCollection
                    && !tabsModel.get(root.currentTab).isEnvironment) {
                var rp = tabsModel.get(root.currentTab).relPath;
                if (root.responses[rp] !== undefined)
                    root.responses[rp].meta = meta;
            }
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
                { group: "Globais", label: "Configurações…", run: function () { root.openSettingsTab(); } },
                { group: "Globais", label: "Gerenciar variáveis de ambiente…", run: function () { root.openEnvTab(root.activeEnv); } },
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

    // ---- confirmar exclusão (genérico; respeita settings.confirmDelete) ----
    // Declarado por último para ficar acima de qualquer outra tela/dialog aberto.
    Dialog {
        id: deleteDialog
        title: "Excluir"; modal: true; anchors.centerIn: parent; width: 400; height: 175
        property string message: ""
        property var callback: null
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: deleteDialog.message }
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.7; text: "Essa ação não pode ser desfeita." }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Cancelar"; onClicked: deleteDialog.close() }
                Button {
                    text: "Excluir"; highlighted: true
                    onClicked: { var f = deleteDialog.callback; deleteDialog.close(); if (f) f(); }
                }
            }
        }
    }
}
