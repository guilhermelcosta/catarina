import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Util.js" as Util
import "Strings.js" as Strings

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
    // avisos de nome de variável repetido no mesmo escopo (bloqueiam salvar/enviar)
    property string requestVarsWarning: ""
    property string collectionVarsWarning: ""
    property string envVarsWarning: ""
    property string responseCookies: ""
    property bool currentDirty: false

    ListModel { id: paramsModel }
    ListModel { id: headersModel }
    ListModel { id: fieldsModel }
    ListModel { id: requestVarsModel }
    ListModel { id: collectionVarsModel }
    ListModel { id: collectionHeadersModel }
    ListModel { id: treeModel }

    title: Strings.t.appName + (currentTab >= 0 && currentTab < tabsModel.count
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
    // mensagem quando há nome de variável repetido no mesmo escopo ("" se ok)
    function varsWarning(model) {
        var d = backend.duplicateVariableName(modelToArray(model));
        return d.length > 0 ? Strings.variableRepeated(d) : "";
    }
    function updateVarsWarnings() {
        requestVarsWarning = varsWarning(requestVarsModel);
        collectionVarsWarning = varsWarning(collectionVarsModel);
        envVarsWarning = varsWarning(envVarsModel);
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
        updateVarsWarnings();
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
            notify(Strings.t.invalidJsonShort);
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
            var n = backend.variableNoteFor(miss[i], collection);
            var code = n.code;
            for (var j = 0; j < res.length; j++)   // desabilitada no request não é "não definida"
                if (res[j].name === miss[i] && res[j].enabled === false)
                    code = "disabled";
            var note = Strings.variableNote(code, n.collections);
            notes.push(note.length > 0 ? miss[i] + " (" + note + ")" : miss[i]);
        }
        missingText = notes.length > 0 ? Strings.unresolvedVariables(notes.join(", ")) : "";
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
        if (all.length === 0) { findMatchIndex = 0; notify(Strings.notFound(q)); return; }
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
    // índice da aba "preview" (transiente) de request, ou -1
    function previewTabIndex() {
        for (var i = 0; i < tabsModel.count; i++)
            if (tabsModel.get(i).preview === true) return i;
        return -1;
    }
    // fixa/desfixa uma aba: fixadas não são substituídas; desfixar volta a prévia
    // (transiente) para a próxima request abrir sobre ela (modelo do VS Code).
    function pinTab(i) {
        var tabs = [];
        for (var k = 0; k < tabsModel.count; k++) {
            var t = tabsModel.get(k);
            tabs.push({ pinned: t.pinned === true, preview: t.preview === true });
        }
        var changes = Util.tabPin(tabs, i);
        for (var c = 0; c < changes.length; c++) {
            tabsModel.setProperty(changes[c].index, "pinned", changes[c].pinned);
            tabsModel.setProperty(changes[c].index, "preview", changes[c].preview);
        }
    }
    function markDirty() {
        if (currentTab >= 0 && currentTab < tabsModel.count
                && !tabsModel.get(currentTab).isCollection && !tabsModel.get(currentTab).isEnvironment
                && !tabsModel.get(currentTab).isSettings) {
            tabsModel.setProperty(currentTab, "dirty", true);
            tabsModel.setProperty(currentTab, "preview", false);   // editar tira a aba da prévia (fica permanente), como no VS Code
        }
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
        // já aberta? vai para ela (não abre de novo)
        for (var i = 0; i < tabsModel.count; i++) {
            var t = tabsModel.get(i);
            if (!t.isCollection && !t.isEnvironment && !t.isSettings && t.relPath === relPath) { switchTab(i); return; }
        }
        var r = backend.loadRequest(relPath);
        if (r.method === undefined) return;
        r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);   // valor real do cofre

        // reutiliza a aba "preview" (transiente); se tiver edições, fixa-a antes
        var target = -1;
        var prev = previewTabIndex();
        if (prev >= 0) {
            if (tabsModel.get(prev).dirty === true) {
                tabsModel.setProperty(prev, "pinned", true);   // não perde as edições
                tabsModel.setProperty(prev, "preview", false);
            } else {
                target = prev;
            }
        }
        snapshotCurrent();
        if (target >= 0) {
            tabsModel.setProperty(target, "relPath", relPath);
            tabsModel.setProperty(target, "name", relPath.split("/").pop());
            tabsModel.setProperty(target, "method", r.method);
            tabsModel.setProperty(target, "dataJson", JSON.stringify(r));
            tabsModel.setProperty(target, "dirty", false);
            currentTab = target;
        } else {
            tabsModel.append({ relPath: relPath, name: relPath.split("/").pop(),
                               method: r.method, dirty: false, dataJson: JSON.stringify(r),
                               isCollection: false, isEnvironment: false, isSettings: false,
                               pinned: false, preview: true });
            currentTab = tabsModel.count - 1;
        }
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
            tabsModel.append({ relPath: "__environment__", name: Strings.t.environments, method: "",
                               dirty: false, dataJson: "", isCollection: false, isEnvironment: true, isSettings: false,
                               pinned: false, preview: false });
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
            tabsModel.append({ relPath: "__settings__", name: Strings.t.settings, method: "",
                               dirty: false, dataJson: "", isCollection: false, isEnvironment: false, isSettings: true,
                               pinned: false, preview: false });
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
        var pinnedList = settings.pinnedTabs;
        for (var i = 0; i < paths.length; i++) {
            var rp = paths[i];
            if (rp.length === 0) continue;
            if (rp === "__environment__") {
                tabsModel.append({ relPath: rp, name: Strings.t.environments, method: "", dirty: false,
                                   dataJson: "", isCollection: false, isEnvironment: true, isSettings: false,
                                   pinned: false, preview: false });
                continue;
            }
            if (rp === "__settings__") {
                tabsModel.append({ relPath: rp, name: Strings.t.settings, method: "", dirty: false,
                                   dataJson: "", isCollection: false, isEnvironment: false, isSettings: true,
                                   pinned: false, preview: false });
                continue;
            }
            if (backend.isCollection(rp)) {
                tabsModel.append({ relPath: rp, name: rp.split("/").pop(),
                                   method: "", dirty: false, dataJson: "", isCollection: true, isEnvironment: false, isSettings: false,
                                   pinned: false, preview: false });
                continue;
            }
            var r = backend.loadRequest(rp);
            if (r.method === undefined) continue;
            r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);   // valor real do cofre
            tabsModel.append({ relPath: rp, name: rp.split("/").pop(),
                               method: r.method, dirty: false, dataJson: JSON.stringify(r),
                               isCollection: false, isEnvironment: false, isSettings: false,
                               pinned: false, preview: false });
        }
        // restaura o estado "fixada" (sobrevive ao restart)
        for (var k = 0; k < tabsModel.count; k++) {
            if (pinnedList.indexOf(tabsModel.get(k).relPath) >= 0) {
                tabsModel.setProperty(k, "pinned", true);
                tabsModel.setProperty(k, "preview", false);
            }
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
                           method: "", dirty: false, dataJson: "", isCollection: true, isEnvironment: false, isSettings: false,
                           pinned: false, preview: false });
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
        // inclui as variáveis em edição (não salvas) para uma referenciar a outra,
        // mas mantendo a origem "collection" (não "request") na visão geral
        collectionResolvedVars = backend.resolvedCollectionVariables(collectionOf(collectionPath), modelToArray(collectionVarsModel));
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
        updateVarsWarnings();
        showingCollection = true;
        showingEnv = false;
    }
    function saveCollectionVars() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem variáveis
        var dup = backend.duplicateVariableName(modelToArray(collectionVarsModel));
        if (dup.length > 0) { notify(Strings.duplicateInCollection(dup)); return; }
        backend.saveCollectionVariables(collectionPath, modelToArray(collectionVarsModel));
        collectionVarsDirty = false;
        refreshCollectionResolved();   // visão geral reflete secret/normal sem precisar reabrir
        notify(Strings.t.collectionVarsSaved);
    }
    function revertCollectionVars() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;
        fillModels(backend.withResolvedSecrets(backend.collectionVariables(collectionPath)), collectionVarsModel);
        collectionVarsDirty = false;
        notify(Strings.t.changesDiscarded);
    }
    function saveCollectionHeaders() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem cabeçalhos
        backend.saveCollectionHeaders(collectionPath, modelToArray(collectionHeadersModel));
        collectionHeadersDirty = false;
        notify(Strings.t.collectionHeadersSaved);
    }
    function revertCollectionHeaders() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;
        fillModels(backend.withResolvedSecrets(backend.collectionHeaders(collectionPath)), collectionHeadersModel);
        collectionHeadersDirty = false;
        notify(Strings.t.changesDiscarded);
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
        var dup = backend.duplicateVariableName(modelToArray(requestVarsModel));
        if (dup.length > 0) { notify(Strings.duplicateInRequest(dup)); return; }
        if (backend.saveRequest(t.relPath, collectRequest())) {
            tabsModel.setProperty(currentTab, "method", methodBox.currentText);
            tabsModel.setProperty(currentTab, "dirty", false);
            currentDirty = false;
            refreshResolved();
            reloadTree();
            notify(Strings.savedTo(t.relPath));
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
        notify(Strings.t.changesDiscarded);
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
        if (t === Strings.t.canceled) return Kirigami.Theme.disabledTextColor;
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
        tabsModel.clear();
        currentTab = -1;
        clearEditor();
        showingCollection = false;
        showingEnv = false;
        showingSettings = false;
        reloadTree();
        reloadEnvs();
        notify(Strings.collectionsNow(dir));
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
        root.confirmDelete(Strings.deleteItemConfirm(name),
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
        if (urlField.text.length === 0) { notify(Strings.t.provideUrl); return; }
        var dup = backend.duplicateVariableName(modelToArray(requestVarsModel));
        if (dup.length > 0) { notify(Strings.duplicateInRequest(dup)); return; }
        if (settings.autoSaveOnSend && currentDirty) saveCurrent();
        var t = tabsModel.get(currentTab);
        setResponseBody(""); responseHeaders = []; netMeta = ({});
        backend.send(collectRequest(), collectionOf(t.relPath));
    }
    function persistSession() {
        // só abas fixadas voltam na próxima sessão (preview/não-fixadas são transientes)
        var arr = [];
        for (var i = 0; i < tabsModel.count; i++) arr.push(tabsModel.get(i));
        var s = Util.sessionPaths(arr, currentTab);
        settings.saveSession(s.paths, s.current);
        settings.savePinnedTabs(s.paths);   // tudo que sobra é fixado → restore reaplica o pino
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
    // acha um caminho de request livre dentro de folder, sufixando -N se já existir
    function uniqueRequestPath(folder, base) {
        var prefix = folder.length > 0 ? folder + "/" : "";
        var path = prefix + base;
        var n = 1;
        while (backend.loadRequest(path).method !== undefined)
            path = prefix + base + "-" + (++n);
        return path;
    }
    function importCurl(text) {
        var r = Util.parseCurl(text);
        if (r.url.length === 0) { curlImportDialog.hint = Strings.curlNoUrl(); return; }
        var path = uniqueRequestPath(targetFolder(), "curl-import");
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
        }
        // sem abas salvas: ficamos no placeholder "Nenhum request aberto"
        // (não abrimos a primeira coleção da árvore automaticamente)
    }

    property var shortcutDefs: [
        { id: "send", label: Strings.t.shortcutSend, def: "Ctrl+Return" },
        { id: "newRequest", label: Strings.t.shortcutNewRequest, def: "Ctrl+T" },
        { id: "closeTab", label: Strings.t.shortcutCloseTab, def: "Ctrl+W" },
        { id: "save", label: Strings.t.shortcutSave, def: "Ctrl+S" },
        { id: "prevTab", label: Strings.t.shortcutPrevTab, def: "Alt+Left" },
        { id: "nextTab", label: Strings.t.shortcutNextTab, def: "Alt+Right" },
        { id: "reopenTab", label: Strings.t.shortcutReopenTab, def: "Ctrl+Shift+T" },
        { id: "palette", label: Strings.t.shortcutPalette, def: "Ctrl+K" },
        { id: "findInResponse", label: Strings.t.shortcutFind, def: "Ctrl+F" }
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
                Label { text: Strings.t.appName; font.bold: true }
                Item { Layout.fillWidth: true }
                // grupo de painéis: esquerda (coleções) e direita (resposta)
                RowLayout {
                    spacing: 0
                    ToolButton {
                        checkable: true; checked: root.sidebarVisible
                        icon.name: root.sidebarVisible ? "view-left-close" : "view-left-new"
                        onToggled: root.sidebarVisible = checked
                        ToolTip.text: root.sidebarVisible ? Strings.t.hideCollections : Strings.t.showCollections
                        ToolTip.visible: hovered
                    }
                    ToolButton {
                        checkable: true; checked: root.responseVisible
                        icon.name: root.responseVisible ? "view-right-close" : "view-right-new"
                        onToggled: root.responseVisible = checked
                        ToolTip.text: root.responseVisible ? Strings.t.hideResponse : Strings.t.showResponse
                        ToolTip.visible: hovered
                    }
                }
                ToolButton {
                    icon.name: "view-history"; text: Strings.t.history
                    display: AbstractButton.TextBesideIcon
                    onClicked: historyDialog.openAndLoad()
                }
                Button {
                    id: envButton
                    icon.name: "vcs-branch"
                    text: root.activeEnv.length > 0 ? root.activeEnv : Strings.t.noEnvironment
                    onClicked: envPopup.open()
                }
                ToolButton {
                    icon.name: "configure"
                    onClicked: root.openSettingsTab()
                    ToolTip.text: Strings.t.settings; ToolTip.visible: hovered
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
                            text: Strings.t.activeEnvironment
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
                            Label { text: Strings.t.readyToStart; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                            Label {
                                text: Strings.t.createEnvHint
                                wrapMode: Text.WordWrap; Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter; opacity: 0.75
                            }
                        }

                        Kirigami.Separator { Layout.fillWidth: true }
                        ItemDelegate {
                            Layout.fillWidth: true; text: Strings.t.createEnvironment; icon.name: "list-add"
                            onClicked: { envPopup.close(); createEnvDialog.open(); }
                        }
                        ItemDelegate {
                            Layout.fillWidth: true; text: Strings.t.manageVariables; icon.name: "configure"
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
                        Label { text: Strings.t.collections; font.bold: true }
                        Item { Layout.fillWidth: true }
                        ToolButton { icon.name: "list-add"; onClicked: addMenu.open(); ToolTip.text: Strings.t.add; ToolTip.visible: hovered }
                        ToolButton {
                            icon.name: "edit-delete"
                            enabled: root.selectedPath.length > 0
                            onClicked: root.askDelete()
                            ToolTip.text: Strings.t.deleteSelected; ToolTip.visible: hovered
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
                                        ctxMenu.popup(mainMouse, m.x, m.y);
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
                                ToolTip.text: Strings.t.moreActions; ToolTip.visible: hovered
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
                                        width: tabContent.implicitWidth + 74
                                        property bool isTabDelegate: true
                                        opacity: (root.dragging && root.tabDragIndex === index) ? 0.4 : 1
                                        HoverHandler { id: tabHover }
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
                                            Label { text: model.name; font.bold: index === root.currentTab; font.italic: model.preview === true; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                                            Kirigami.Icon {
                                                visible: !!(model.dirty === true
                                                         || (model.isCollection === true && index === root.currentTab && (root.collectionVarsDirty || root.collectionHeadersDirty))
                                                         || (model.isEnvironment === true && index === root.currentTab && root.envTabDirty))
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
                                        Kirigami.Icon {
                                            id: pinBtn
                                            anchors.right: parent.right
                                            anchors.rightMargin: model.pinned === true ? 6 : 26
                                            anchors.verticalCenter: parent.verticalCenter
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            source: "pin"
                                            // hover azul (como o × fica vermelho); fixada já aparece azul
                                            color: (pinHover.hovered || model.pinned === true) ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                                            opacity: (pinHover.hovered || model.pinned === true) ? 1.0 : 0.6
                                            visible: !model.isCollection && !model.isEnvironment && !model.isSettings
                                                     && (tabHover.hovered || model.pinned === true)
                                            HoverHandler { id: pinHover }
                                            TapHandler { onTapped: root.pinTab(index) }
                                            // ponytail: NÃO usar ToolTip.visible:hovered aqui — o popup
                                            // do tooltip rouba o clique (pino e × deixam de responder)
                                        }
                                        Label {
                                            id: closeBtn
                                            visible: model.pinned !== true
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
                                            // idem pino: tooltip aqui rouba o clique do ×
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
                                        placeholderText: Strings.t.urlExample
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
                                        text: root.sending ? Strings.t.cancel : Strings.t.send
                                        highlighted: !root.sending
                                        onClicked: root.sending ? backend.cancel() : root.doSend()
                                    }
                                    ToolButton {
                                        icon.name: "edit-undo"
                                        enabled: root.currentDirty
                                        onClicked: root.revertCurrent()
                                        ToolTip.text: Strings.t.discardTooltip; ToolTip.visible: hovered
                                    }
                                    ToolButton {
                                        icon.name: "document-save"
                                        enabled: root.currentDirty && root.requestVarsWarning.length === 0
                                        onClicked: root.saveCurrent()
                                        ToolTip.text: Strings.t.saveTooltip; ToolTip.visible: hovered
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
                                    TabButton { text: Strings.t.parameters }
                                    TabButton { text: Strings.t.headers }
                                    TabButton { text: Strings.t.body }
                                    TabButton { text: Strings.t.authentication }
                                    TabButton { text: Strings.t.variables }
                                }

                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: reqTabBar.currentIndex

                                    KvTable { model: paramsModel; keyPlaceholder: Strings.t.parameter; resolved: root.resolvedVars; collection: root.currentCollection; onAddRequested: paramsModel.append({ name: "", value: "", enabled: true }); onEdited: root.markDirty() }
                                    KvTable { model: headersModel; keyPlaceholder: Strings.t.header; resolved: root.resolvedVars; collection: root.currentCollection; onAddRequested: headersModel.append({ name: "", value: "", enabled: true }); onEdited: root.markDirty() }

                                    ColumnLayout {
                                        // O StackLayout limita o filho atual pela altura máxima que
                                        // calcula (newSize.expandedTo(min).boundedTo(max)) e, num
                                        // ColumnLayout aninhado com ScrollView, esse máximo sai
                                        // pequeno — o corpo do payload ficava "espremido" ao trocar
                                        // de aba. Liberar o máximo resolve. Ver DESIGN.md.
                                        Layout.maximumHeight: Number.POSITIVE_INFINITY
                                        spacing: Kirigami.Units.smallSpacing
                                        RowLayout {
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
                                            Layout.topMargin: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing
                                            Label { text: Strings.t.type + ":" }
                                            ComboBox {
                                                id: bodyTypeBox
                                                textRole: "text"; valueRole: "value"
                                                model: [
                                                    { text: Strings.t.bodyNone, value: "none" },
                                                    { text: "JSON", value: "json" },
                                                    { text: Strings.t.bodyText, value: "text" },
                                                    { text: "form-urlencoded", value: "urlencoded" },
                                                    { text: "multipart/form-data", value: "multipart" }
                                                ]
                                                implicitWidth: 170
                                                onActivated: root.markDirty()
                                            }
                                            Item { Layout.fillWidth: true }
                                            Button {
                                                visible: bodyTypeBox.currentValue === "json"
                                                icon.name: "tools-wizard"; text: Strings.t.formatButton
                                                display: AbstractButton.TextBesideIcon
                                                onClicked: root.formatBody()
                                                ToolTip.text: Strings.t.formatJson; ToolTip.visible: hovered
                                            }
                                        }
                                        Label {
                                            visible: bodyTypeBox.currentValue === "none"
                                            text: Strings.t.noBody
                                            opacity: 0.7
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                        }
                                        KvTable {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            visible: bodyTypeBox.currentValue === "multipart" || bodyTypeBox.currentValue === "urlencoded"
                                            model: fieldsModel
                                            keyPlaceholder: Strings.t.field
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
                                                placeholderText: Strings.t.jsonExample
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
                                                        // insert() programático não emite textEdited; sem
                                                        // isto o popup de {{var}} só abre ao digitar o 1º caractere
                                                        bodyCompleter.updateCompleter();
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
                                        // com maximumHeight liberado, o ColumnLayout ocupa a altura
                                        // inteira do StackLayout; sem filho que preencha, o Qt
                                        // redistribui o espaço e o cabeçalho "estica". Este filler
                                        // (só em "nenhum") âncora o topo, como na Autenticação.
                                        Item {
                                            Layout.fillHeight: true
                                            visible: bodyTypeBox.currentValue === "none"
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        RowLayout {
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
                                            Layout.topMargin: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing
                                            Label { text: Strings.t.type + ":" }
                                            ComboBox {
                                                id: authTypeBox
                                                textRole: "text"; valueRole: "value"
                                                model: [
                                                    { text: Strings.t.authNoneOption, value: "none" },
                                                    { text: Strings.t.authBearer, value: "bearer" },
                                                    { text: Strings.t.authBasic, value: "basic" },
                                                    { text: Strings.t.authApiKey, value: "apikey" }
                                                ]
                                                implicitWidth: 170
                                                onActivated: root.markDirty()
                                            }
                                        }
                                        VarField {
                                            id: bearerToken
                                            Layout.fillWidth: true
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
                                            visible: authTypeBox.currentValue === "bearer"
                                            placeholderText: Strings.t.token
                                            resolved: root.resolvedVars
                                            collection: root.currentCollection
                                            onTextEdited: root.markDirty()
                                        }
                                        RowLayout {
                                            visible: authTypeBox.currentValue === "basic"
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing
                                            VarField { id: basicUser; Layout.fillWidth: true; placeholderText: Strings.t.user; resolved: root.resolvedVars; collection: root.currentCollection; onTextEdited: root.markDirty() }
                                            TextField { id: basicPass; Layout.fillWidth: true; placeholderText: Strings.t.password; echoMode: TextInput.Password; onTextEdited: root.markDirty() }
                                        }
                                        RowLayout {
                                            visible: authTypeBox.currentValue === "apikey"
                                            Layout.leftMargin: Kirigami.Units.smallSpacing
                                            Layout.rightMargin: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing
                                            VarField { id: apiKeyName; Layout.fillWidth: true; placeholderText: Strings.t.headerName; resolved: root.resolvedVars; collection: root.currentCollection; onTextEdited: root.markDirty() }
                                            VarField {
                                                id: apiKeyValue
                                                Layout.fillWidth: true
                                                placeholderText: Strings.t.value
                                                resolved: root.resolvedVars
                                                collection: root.currentCollection
                                                onTextEdited: root.markDirty()
                                            }
                                        }
                                        Label { visible: authTypeBox.currentValue === "none"; text: Strings.t.authNone; opacity: 0.7; Layout.leftMargin: Kirigami.Units.smallSpacing }
                                        Item { Layout.fillHeight: true }
                                    }

                                    // variáveis editáveis (topo) + efetivas (embaixo), com divisor
                                    // arrastável — no máximo metade da altura da aba.
                                    SplitView {
                                        id: requestVarsSplit
                                        orientation: Qt.Vertical
                                        handle: SplitHandle {}

                                        KvTable {
                                            SplitView.fillWidth: true
                                            SplitView.fillHeight: true
                                            SplitView.minimumHeight: Kirigami.Units.gridUnit * 3
                                            model: requestVarsModel
                                            keyPlaceholder: Strings.t.variable
                                            secretColumn: true
                                            uniqueNames: true
                                            resolved: root.resolvedVars
                                            collection: root.currentCollection
                                            onAddRequested: requestVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "" })
                                            onEdited: { root.markDirty(); root.updateVarsWarnings(); }
                                        }
                                        Item {
                                            id: requestResolvedPane
                                            // abre neste tamanho e não deixa encolher abaixo dele
                                            readonly property int defaultHeight: 190
                                            SplitView.fillWidth: true
                                            SplitView.preferredHeight: defaultHeight
                                            SplitView.minimumHeight: defaultHeight
                                            // teto = metade da altura; guarda o 0 do primeiro layout
                                            SplitView.maximumHeight: requestVarsSplit.height > 0
                                                                    ? requestVarsSplit.height / 2 : 10000
                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                                spacing: Kirigami.Units.smallSpacing
                                                Label { text: Strings.t.effectiveVariables; font.bold: true; Layout.topMargin: Kirigami.Units.smallSpacing }
                                                ResolvedVarsTable {
                                                    id: requestResolvedTable
                                                    visible: requestResolvedTable.count > 0
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    vars: root.resolvedVars
                                                }
                                                Label {
                                                    visible: requestResolvedTable.count === 0
                                                    text: Strings.t.noVariablesDefined
                                                    opacity: 0.6
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                                // sem tabela (count 0) nada preenche; o filler segura
                                                // os labels no topo em vez de redistribuir o espaço.
                                                Item {
                                                    Layout.fillHeight: true
                                                    visible: requestResolvedTable.count === 0
                                                }
                                            }
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
                                        icon.name: "edit-copy"; text: Strings.t.copy
                                        display: AbstractButton.TextBesideIcon
                                        onClicked: { varSupport.copyText(responseBody.text.length > 0 ? responseBody.text : ""); root.notify(Strings.t.responseCopied); }
                                        onHoveredChanged: root.hint(hovered ? Strings.t.copyResponse : "")
                                    }
                                    ToolButton {
                                        visible: responseBody.text.length > 0
                                        icon.name: "edit-find"
                                        onClicked: root.openFind()
                                        onHoveredChanged: root.hint(hovered ? Strings.t.findTooltip : "")
                                    }
                                }

                                TabBar {
                                    id: respTabBar
                                    Layout.fillWidth: true
                                    onCurrentIndexChanged: if (currentIndex === 1) root.syncJsonTree()
                                    TabButton { text: Strings.t.responseBody; onHoveredChanged: root.hint(hovered ? Strings.t.bodyHint : "") }
                                    TabButton { text: Strings.t.responseTree; onHoveredChanged: root.hint(hovered ? Strings.t.treeHint : "") }
                                    TabButton { text: Strings.t.responseHeaders; onHoveredChanged: root.hint(hovered ? Strings.t.headersHint : "") }
                                    TabButton { text: Strings.t.responseCookies; onHoveredChanged: root.hint(hovered ? Strings.t.cookiesHint : "") }
                                    TabButton { text: Strings.t.responseNetwork; onHoveredChanged: root.hint(hovered ? Strings.t.networkHint : "") }
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
                                        placeholderText: Strings.t.searchResponse
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
                                        onHoveredChanged: root.hint(hovered ? Strings.t.prevMatch : "")
                                    }
                                    ToolButton {
                                        icon.name: "go-down"; onClicked: root.findNext(false)
                                        onHoveredChanged: root.hint(hovered ? Strings.t.nextMatch : "")
                                    }
                                    ToolButton {
                                        icon.name: "window-close"; onClicked: root.closeFind()
                                        onHoveredChanged: root.hint(hovered ? Strings.t.clearFind : "")
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
                                            onCopyRequested: function (text) { varSupport.copyText(text); root.notify(Strings.t.headersCopied); }
                                        }
                                        ScrollView {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            padding: Kirigami.Units.smallSpacing
                                            TextArea { id: responseCookiesArea; readOnly: true; font.family: "monospace"; wrapMode: TextEdit.Wrap; text: root.responseCookies; placeholderText: Strings.t.noCookies }
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
                                        title: Strings.t.noResponseYet
                                        message: Strings.t.noResponseHint
                                        shortcut: "Ctrl+K"
                                        shortcutLabel: Strings.t.openPaletteHint
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
                                    Label { text: root.collectionIsSubfolder ? Strings.t.folder : Strings.t.collection; opacity: 0.6 }
                                }
                                Item { Layout.fillWidth: true }
                                Button { icon.name: "document-new"; text: Strings.t.newRequest; onClicked: newReqDialog.openIn(root.collectionPath) }
                            }
                            Kirigami.Separator { Layout.fillWidth: true }
                            TabBar {
                                id: collectionTabBar
                                visible: !root.collectionIsSubfolder
                                Layout.fillWidth: true
                                currentIndex: root.collectionTab
                                onCurrentIndexChanged: { root.collectionTab = currentIndex; if (currentIndex === 0) root.refreshCollectionResolved(); }
                                TabButton { text: Strings.t.overview }
                                TabButton { text: Strings.t.headers }
                                TabButton { text: Strings.t.variables }
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
                                        Label { text: Strings.t.location; font.bold: true }
                                        Label { text: "~/katarina-collections/" + root.collectionPath; opacity: 0.8 }
                                        Label { text: Strings.t.requests; font.bold: true }
                                        Label { text: root.collectionRequests.length }
                                        Label { text: Strings.t.subfolders; font.bold: true }
                                        Label { text: root.collectionFolders }
                                    }
                                    Kirigami.Separator { Layout.fillWidth: true }
                                    Label {
                                        visible: root.collectionIsSubfolder
                                        text: Strings.t.folderHint
                                        opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                    Label {
                                        visible: !root.collectionIsSubfolder
                                        text: Strings.t.effectiveVariables
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                                    }
                                    ResolvedVarsTable {
                                        id: collectionResolvedTable
                                        visible: !root.collectionIsSubfolder && collectionResolvedTable.count > 0
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.min(200, 24 + collectionResolvedTable.count * 24)
                                        vars: root.collectionResolvedVars
                                    }
                                    Label {
                                        visible: !root.collectionIsSubfolder && collectionResolvedTable.count === 0
                                        text: Strings.t.noCollectionVariables
                                        opacity: 0.6
                                    }
                                    Kirigami.Separator { Layout.fillWidth: true }
                                    Label { text: root.collectionIsSubfolder ? Strings.t.requestsInFolder : Strings.t.requestsInCollection; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1 }
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
                                    Label { visible: root.collectionRequests.length === 0; text: root.collectionIsSubfolder ? Strings.t.noRequestsInFolder : Strings.t.noRequestsInCollection; opacity: 0.6 }
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
                                        title: Strings.t.collectionHeaders
                                        dirty: root.collectionHeadersDirty
                                        showDiscard: true
                                        onSave: root.saveCollectionHeaders()
                                        onDiscard: root.revertCollectionHeaders()
                                    }
                                    Label {
                                        text: Strings.t.collectionHeadersHint
                                        opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                    KvTable {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        model: collectionHeadersModel
                                        keyPlaceholder: Strings.t.header
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
                                        title: Strings.t.collectionVariables
                                        dirty: root.collectionVarsDirty
                                        canSave: root.collectionVarsWarning.length === 0
                                        showDiscard: true
                                        onSave: root.saveCollectionVars()
                                        onDiscard: root.revertCollectionVars()
                                    }
                                    Label {
                                        text: Strings.t.collectionVariablesHint
                                        opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                    KvTable {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        model: collectionVarsModel
                                        keyPlaceholder: Strings.t.variable
                                        secretColumn: true
                                        uniqueNames: true
                                        resolved: root.collectionResolvedVars
                                        collection: root.collectionPath
                                        onAddRequested: collectionVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "" })
                                        onEdited: { root.collectionVarsDirty = true; root.refreshCollectionResolved(); root.updateVarsWarnings(); }
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
                                title: Strings.t.noRequestOpen
                                message: Strings.t.noRequestOpenHint
                                actionText: Strings.t.newRequest
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
                            property var resolvedVars: []   // p/ o autocomplete das variáveis do ambiente

                            ListModel { id: envVarsModel }

                            function refreshResolved() {
                                var arr = [];
                                for (var i = 0; i < envVarsModel.count; i++) {
                                    var v = envVarsModel.get(i);
                                    arr.push({ name: v.name, value: v.value, enabled: v.enabled !== false,
                                               secret: v.secret === true, secretId: v.secretId });
                                }
                                resolvedVars = backend.resolvedVariables("", arr);
                            }
                            function openFor(name) {
                                if (name.length === 0 && root.envList.length > 0) name = root.envList[0].name;
                                viewCollection = "";
                                loadVars(name);
                            }
                            function loadVars(name) {
                                editing = name;
                                envVarsDirty = false;
                                envVarsModel.clear();
                                if (name.length === 0) { resolvedVars = []; return; }
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
                                refreshResolved();
                                root.updateVarsWarnings();
                            }
                            function save() {
                                if (editing.length === 0) return;
                                var dup = backend.duplicateVariableName(modelToArray(envVarsModel));
                                if (dup.length > 0) { notify(Strings.duplicateInEnvironment(dup)); return; }
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
                                    notify(Strings.t.environmentSaved);
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
                                if (envVarsDirty) { notify(Strings.t.saveBeforeRename); return; }
                                renameEnvDialog.oldName = name;
                                renameEnvDialog.open();
                            }
                            function renameTo(oldName, newName) {
                                if (!backend.renameEnvironment(oldName, newName)) {
                                    notify(Strings.t.environmentExists);
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
                                    Label { text: Strings.t.environments; font.bold: true }
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
                                        Layout.fillWidth: true; icon.name: "list-add"; text: Strings.t.newEnvironment
                                        display: AbstractButton.TextBesideIcon
                                        onClicked: createEnvDialog.open()
                                    }
                                    Button {
                                        Layout.fillWidth: true; icon.name: "edit-delete"; text: Strings.t.delete
                                        display: AbstractButton.TextBesideIcon
                                        enabled: envScreen.editing.length > 0
                                        onClicked: {
                                            const name = envScreen.editing;
                                            root.confirmDelete(Strings.deleteEnvConfirm(name), function () {
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
                                        canSave: root.envVarsWarning.length === 0
                                        showDiscard: true
                                        showRename: true
                                        canRename: envScreen.editing.length > 0 && !envScreen.envVarsDirty
                                        renameTooltip: envScreen.envVarsDirty ? Strings.t.saveBeforeRenameEnv : Strings.t.renameEnvTooltip
                                        onSave: envScreen.save()
                                        onDiscard: envScreen.loadVars(envScreen.editing)
                                        onRename: envScreen.startRename(envScreen.editing)
                                    }

                                    RowLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        Label { text: Strings.t.view }
                                        ComboBox {
                                            id: viewCombo
                                            implicitWidth: 230
                                            model: [Strings.t.viewAllVariables].concat(root.collectionNames())
                                            onActivated: envScreen.viewCollection = currentIndex === 0 ? "" : currentText
                                        }
                                        Label { text: Strings.t.globalsEverywhere; opacity: 0.6 }
                                    }

                                    KvTable {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        model: envVarsModel
                                        keyPlaceholder: Strings.t.variable
                                        secretColumn: true
                                        uniqueNames: true
                                        scopeColumn: true
                                        resolved: envScreen.resolvedVars
                                        rowFilter: function(i) {
                                            var v = envVarsModel.get(i);
                                            return v !== undefined && envScreen.matchesView(v.scope, v.collections);
                                        }
                                        scopeIcon: function(i) {
                                            var v = envVarsModel.get(i);
                                            return (v && v.scope === "collections") ? "folder-documents" : "globe";
                                        }
                                        // cor por escopo: global (verde) / restrita a coleções (azul)
                                        scopeColor: function(i) {
                                            var v = envVarsModel.get(i);
                                            return (v && v.scope === "collections")
                                                   ? Kirigami.Theme.activeTextColor
                                                   : Kirigami.Theme.positiveTextColor;
                                        }
                                        scopeText: function(i) {
                                            var v = envVarsModel.get(i);
                                            if (!v || v.scope !== "collections") return Strings.t.globalTab;
                                            var c = (v.collections && v.collections.length > 0) ? v.collections.split(",") : [];
                                            if (c.length === 0) return Strings.t.chooseCollections;
                                            if (c.length <= 2) return c.join(", ");
                                            return Strings.nCollections(c.length);
                                        }
                                        scopeTooltip: function(i) {
                                            var v = envVarsModel.get(i);
                                            if (!v || v.scope !== "collections") return Strings.t.validForAllCollections;
                                            var c = (v.collections && v.collections.length > 0) ? v.collections.split(",") : [];
                                            return c.length > 0 ? c.join(", ") : Strings.t.noCollectionSelected;
                                        }
                                        onScopeRequested: function(i, gx, gy) { scopePopup.openFor(i, gx, gy); }
                                        onAddRequested: envVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "", scope: "all", collections: "" })
                                        onEdited: { envScreen.envVarsDirty = true; envScreen.refreshResolved(); root.updateVarsWarnings(); }
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

                                        Label { text: Strings.t.appearance; font.bold: true }
                                        RowLayout {
                                            spacing: Kirigami.Units.smallSpacing
                                            Label { text: Strings.t.editorFont; Layout.preferredWidth: 170 }
                                            SpinBox { from: 0; to: 28; value: settings.fontSize; onValueModified: settings.fontSize = value }
                                            Label { text: Strings.t.defaultZero; opacity: 0.6 }
                                        }

                                        Kirigami.Separator { Layout.fillWidth: true }
                                        Label { text: Strings.t.collections; font.bold: true }
                                        Label { text: Strings.t.collectionsFolder; opacity: 0.7 }
                                        RowLayout {
                                            spacing: Kirigami.Units.smallSpacing
                                            TextField { id: dirField; Layout.fillWidth: true; text: settings.storageDir }
                                            Button { text: Strings.t.browse; onClicked: folderPicker.open() }
                                            Button {
                                                text: Strings.t.apply; highlighted: true
                                                enabled: dirField.text.length > 0 && dirField.text !== backend.storageDir
                                                onClicked: root.applyStorageDir(dirField.text)
                                            }
                                        }
                                        Label {
                                            text: Strings.t.storageDirHint
                                            opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
                                        }

                                        Kirigami.Separator { Layout.fillWidth: true }
                                        Label { text: Strings.t.network; font.bold: true }
                                        RowLayout {
                                            spacing: Kirigami.Units.smallSpacing
                                            Label { text: Strings.t.timeoutSeconds; Layout.preferredWidth: 170 }
                                            SpinBox { from: 0; to: 600; value: settings.timeoutSec; onValueModified: settings.timeoutSec = value }
                                            Label { text: Strings.t.noLimit; opacity: 0.6 }
                                        }
                                        CheckBox { text: Strings.t.ignoreSsl; checked: settings.ignoreSsl; onToggled: settings.ignoreSsl = checked }

                                        Kirigami.Separator { Layout.fillWidth: true }
                                        Label { text: Strings.t.behavior; font.bold: true }
                                        CheckBox { text: Strings.t.confirmDeleteOption; checked: settings.confirmDelete; onToggled: settings.confirmDelete = checked }
                                        CheckBox { text: Strings.t.autoSaveOnSend; checked: settings.autoSaveOnSend; onToggled: settings.autoSaveOnSend = checked }

                                        Kirigami.Separator { Layout.fillWidth: true }
                                        Label { text: Strings.t.shortcuts; font.bold: true }
                                        Label { text: Strings.t.shortcutsHint; opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true }
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
                                                    ToolTip.text: Strings.t.restoreDefault; ToolTip.visible: hovered
                                                }
                                            }
                                        }
                                    }
                                }
                                Label { text: Strings.t.optionsApplyInstantly; opacity: 0.6; Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }
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
        MenuItem { text: Strings.t.newCollection; icon.name: "folder-documents"; onTriggered: collectionDialog.open() }
        MenuItem { text: Strings.t.newRequest; icon.name: "document-new"; onTriggered: newReqDialog.openIn(root.selectedIsFolder ? root.selectedPath : "") }
        MenuSeparator {}
        MenuItem { text: Strings.t.importCurl; icon.name: "document-import"; onTriggered: { curlImportDialog.hint = ""; curlImportArea.text = ""; curlImportDialog.open(); } }
    }
    Menu {
        id: ctxMenu
        MenuItem { text: Strings.t.newRequestHere; icon.name: "document-new"; onTriggered: newReqDialog.openIn(root.targetFolder()) }
        MenuItem {
            text: Strings.t.newFolderHere; icon.name: "folder-new"
            onTriggered: { root.selectedPath = root.targetFolder(); root.selectedIsFolder = root.selectedPath.length > 0; folderDialog.open(); }
        }
        MenuSeparator {}
        MenuItem { text: Strings.t.moveToEllipsis; icon.name: "edit-move"; enabled: root.selectedPath.length > 0; onTriggered: moveDialog.openFor(root.selectedPath) }
        MenuItem { text: Strings.t.renameEllipsis; icon.name: "edit-rename"; enabled: root.selectedPath.length > 0; onTriggered: renameDialog.openFor(root.selectedPath) }
        MenuItem { text: Strings.t.duplicate; icon.name: "edit-duplicate"; enabled: root.selectedPath.length > 0; onTriggered: root.duplicateSelected() }
        MenuItem {
            text: Strings.t.exportCode; icon.name: "document-export"
            visible: root.selectedPath.length > 0 && !root.selectedIsFolder
            onTriggered: { root.openRequest(root.selectedPath); curlExportDialog.refresh(); curlExportDialog.open(); }
        }
        MenuSeparator {}
        MenuItem { text: Strings.t.delete; icon.name: "edit-delete"; onTriggered: root.askDelete() }
    }

    // ================= diálogos =================
    Dialog {
        id: newReqDialog
        title: Strings.t.newRequestTitle; modal: true; anchors.centerIn: parent; width: 460
        header: DialogHeader { dialogTitle: newReqDialog.title }
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
        function errorText() {
            var n = nrName.text.trim();
            if (n.length === 0) return "";
            if (n.indexOf("/") >= 0) return Strings.t.nameCannotContainSlash;
            var newRel = (target.length > 0 ? target + "/" : "") + n;
            if (backend.isCollection(newRel) || backend.loadRequest(newRel).method !== undefined)
                return Strings.t.itemExists;
            return "";
        }
        function create() {
            if (errorText().length > 0) return;
            var n = nrName.text.trim();
            if (n.length === 0) { nrName.forceActiveFocus(); return; }
            var path = (target.length > 0 ? target + "/" : "") + n;
            var data = { method: nrMethod.currentText, url: nrUrl.text, params: [], headers: [], fields: [], body: "", bodyType: "none", auth: { type: "none" }, vars: [] };
            if (backend.saveRequest(path, data)) { root.reloadTree(); root.openRequest(path); close(); }
        }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.nameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
            TextField { id: nrName; Layout.fillWidth: true; placeholderText: Strings.t.requestNamePlaceholder; KeyNavigation.down: nrUrl; onAccepted: newReqDialog.create() }
            Label { text: Strings.t.urlLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                ComboBox { id: nrMethod; model: ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS"]; implicitWidth: 110 }
                TextField { id: nrUrl; Layout.fillWidth: true; placeholderText: Strings.t.urlPlaceholder; KeyNavigation.down: nrCancel }
            }
            Label {
                text: newReqDialog.errorText(); color: Kirigami.Theme.negativeTextColor
                visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Label { text: Strings.willBeCreatedIn(newReqDialog.target.length > 0 ? newReqDialog.target : Strings.rootFolder()); opacity: 0.6 }
            DialogActions {
                Button { id: nrCancel; text: Strings.t.cancel; KeyNavigation.right: nrCreate; KeyNavigation.up: nrUrl; onClicked: newReqDialog.close() }
                Button { id: nrCreate; text: Strings.t.create; Accessible.defaultButton: true; enabled: newReqDialog.errorText().length === 0; KeyNavigation.left: nrCancel; KeyNavigation.up: nrUrl; onClicked: newReqDialog.create() }
            }
        }
    }

    Dialog {
        id: folderDialog
        title: Strings.t.newFolderTitle; anchors.centerIn: parent; modal: true; width: 340
        header: DialogHeader { dialogTitle: folderDialog.title }
        // rodapé explícito (em vez de standardButtons) para as setas navegarem entre os botões
        function accept() {
            var n = folderName.text.trim();
            if (n.length === 0) { folderName.forceActiveFocus(); return; }
            var base = root.targetFolder();
            backend.createFolder((base.length > 0 ? base + "/" : "") + n);
            root.reloadTree(); folderName.text = "";
            close();
        }
        onOpened: folderName.forceActiveFocus()
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            TextField { id: folderName; Layout.fillWidth: true; placeholderText: Strings.t.folderNamePlaceholder; KeyNavigation.down: folderOk; onAccepted: folderDialog.accept() }
            DialogActions {
                Button { id: folderCancel; text: Strings.t.cancel; KeyNavigation.right: folderOk; KeyNavigation.up: folderName; onClicked: folderDialog.close() }
                Button { id: folderOk; text: Strings.t.create; Accessible.defaultButton: true; KeyNavigation.left: folderCancel; KeyNavigation.up: folderName; onClicked: folderDialog.accept() }
            }
        }
    }

    Dialog {
        id: collectionDialog
        title: Strings.t.newCollectionTitle; anchors.centerIn: parent; modal: true; width: 340
        header: DialogHeader { dialogTitle: collectionDialog.title }
        // rodapé explícito (em vez de standardButtons) para as setas navegarem entre os botões
        function accept() {
            var n = collectionName.text.trim();
            if (n.length === 0) { collectionName.forceActiveFocus(); return; }
            backend.createFolder(n);
            root.reloadTree(); collectionName.text = "";
            close();
        }
        onOpened: collectionName.forceActiveFocus()
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            TextField { id: collectionName; Layout.fillWidth: true; placeholderText: Strings.t.collectionNamePlaceholder; KeyNavigation.down: collectionOk; onAccepted: collectionDialog.accept() }
            DialogActions {
                Button { id: collectionCancel; text: Strings.t.cancel; KeyNavigation.right: collectionOk; KeyNavigation.up: collectionName; onClicked: collectionDialog.close() }
                Button { id: collectionOk; text: Strings.t.create; Accessible.defaultButton: true; KeyNavigation.left: collectionCancel; KeyNavigation.up: collectionName; onClicked: collectionDialog.accept() }
            }
        }
    }

    Dialog {
        id: confirmCloseDialog
        title: Strings.t.unsavedChangesTitle; modal: true; anchors.centerIn: parent; width: 400
        header: DialogHeader { dialogTitle: confirmCloseDialog.title }
        property int tabIndex: -1
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: {
                    var i = confirmCloseDialog.tabIndex;
                    if (i < 0 || i >= tabsModel.count) return Strings.t.unsavedChanges;
                    var t = tabsModel.get(i);
                    var kind = t.isCollection ? "collection" : (t.isEnvironment ? "environment" : "request");
                    return Strings.unsavedItem(t.name, kind);
                }
            }
            DialogActions {
                Button { id: closeCancel; text: Strings.t.cancel; KeyNavigation.right: closeDiscard; onClicked: confirmCloseDialog.close() }
                Button { id: closeDiscard; text: Strings.t.discard; KeyNavigation.left: closeCancel; KeyNavigation.right: closeSave; onClicked: { root.doCloseTab(confirmCloseDialog.tabIndex, false); confirmCloseDialog.close(); } }
                Button { id: closeSave; text: Strings.t.save; Accessible.defaultButton: true; KeyNavigation.left: closeDiscard; onClicked: { root.doCloseTab(confirmCloseDialog.tabIndex, true); confirmCloseDialog.close(); } }
            }
        }
    }

    Dialog {
        id: quitDialog
        title: Strings.t.quitTitle; modal: true; anchors.centerIn: parent; width: 400
        header: DialogHeader { dialogTitle: quitDialog.title }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Strings.t.unsavedRequests }
            DialogActions {
                Button { id: quitCancel; text: Strings.t.cancel; KeyNavigation.right: quitDiscard; onClicked: quitDialog.close() }
                Button { id: quitDiscard; text: Strings.t.discardAndQuit; KeyNavigation.left: quitCancel; KeyNavigation.right: quitSave; onClicked: { root.persistSession(); root.forceQuit = true; quitDialog.close(); Qt.quit(); } }
                Button { id: quitSave; text: Strings.t.saveAndQuit; Accessible.defaultButton: true; KeyNavigation.left: quitDiscard; onClicked: { root.saveAllTabs(); root.persistSession(); root.forceQuit = true; quitDialog.close(); Qt.quit(); } }
            }
        }
    }

    // ---- import/export cURL ----
    Dialog {
        id: curlImportDialog
        title: Strings.t.importCurlTitle; anchors.centerIn: parent; modal: true; width: 560; height: 320
        header: DialogHeader { dialogTitle: curlImportDialog.title }
        property string hint: ""
        onOpened: curlImportArea.forceActiveFocus()
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.importCurlLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                TextArea { id: curlImportArea; font.family: "monospace"; wrapMode: TextEdit.Wrap; placeholderText: Strings.t.importCurlPlaceholder }
            }
            Label { text: curlImportDialog.hint; color: Kirigami.Theme.negativeTextColor; visible: text.length > 0 }
            DialogActions {
                Button { id: curlCancel; text: Strings.t.cancel; KeyNavigation.right: curlImportBtn; KeyNavigation.up: curlImportArea; onClicked: curlImportDialog.close() }
                Button { id: curlImportBtn; text: Strings.t.import; Accessible.defaultButton: true; KeyNavigation.left: curlCancel; KeyNavigation.up: curlImportArea; onClicked: root.importCurl(curlImportArea.text) }
            }
        }
    }
    Dialog {
        id: curlExportDialog
        title: Strings.t.exportTitle; anchors.centerIn: parent; modal: true; width: 640; height: 400
        header: DialogHeader { dialogTitle: curlExportDialog.title }
        function refresh() { curlExportArea.text = Util.exportCode(root.requestParts()); }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Label { text: "cURL"; Layout.bottomMargin: Kirigami.Units.smallSpacing }
                Item { Layout.fillWidth: true }
                Button {
                    icon.name: "edit-copy"; text: Strings.t.copy
                    display: AbstractButton.TextBesideIcon
                    onClicked: { varSupport.copyText(curlExportArea.text); root.notify(Strings.t.codeCopied); }
                }
            }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                TextArea { id: curlExportArea; readOnly: true; selectByMouse: true; font.family: "monospace"; wrapMode: TextEdit.NoWrap }
            }
            DialogActions {
                Button { text: Strings.t.close; onClicked: curlExportDialog.close() }
            }
        }
    }

    // ---- configurações ----
    FolderDialog {
        id: folderPicker
        title: Strings.t.chooseCollectionsFolder
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
            moveModel.append({ label: Strings.t.rootTop, path: "" });
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
                text: Strings.moveTo(moveDialog.item.split("/").pop())
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
        title: Strings.t.renameTitle; modal: true; anchors.centerIn: parent; width: 360
        header: DialogHeader { dialogTitle: renameDialog.title }
        property string relPath: ""
        // erro ao vivo (conforme digita); nome vazio não mostra nada
        function errorText() {
            var n = renameField.text.trim();
            if (n.length === 0) return "";
            if (n.indexOf("/") >= 0) return Strings.t.nameCannotContainSlash;
            var parent = relPath.split("/").slice(0, -1).join("/");
            var newRel = parent.length > 0 ? parent + "/" + n : n;
            if (newRel !== relPath && (backend.isCollection(newRel) || backend.loadRequest(newRel).method !== undefined))
                return Strings.t.itemExists;
            return "";
        }
        function openFor(p) {
            relPath = p;
            renameField.text = p.split("/").pop();
            open();
            renameField.forceActiveFocus();
            renameField.selectAll();
        }
        function apply() {
            if (errorText().length > 0) return;
            var n = renameField.text.trim();
            if (n.length === 0) return;
            var parent = relPath.split("/").slice(0, -1).join("/");
            var newRel = parent.length > 0 ? parent + "/" + n : n;
            if (backend.renameEntry(relPath, n)) {
                root.remapTabs(relPath, newRel);
                if (root.selectedPath === relPath) root.selectedPath = newRel;
                root.reloadTree();
                close();
            } else {
                notify(Strings.t.renameFailed);
            }
        }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.newNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
            TextField { id: renameField; Layout.fillWidth: true; KeyNavigation.down: renameCancel; onAccepted: renameDialog.apply() }
            Label {
                text: renameDialog.errorText(); color: Kirigami.Theme.negativeTextColor
                visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            DialogActions {
                Button { id: renameCancel; text: Strings.t.cancel; KeyNavigation.right: renameApply; KeyNavigation.up: renameField; onClicked: renameDialog.close() }
                Button { id: renameApply; text: Strings.t.rename; Accessible.defaultButton: true; enabled: renameDialog.errorText().length === 0; KeyNavigation.left: renameCancel; KeyNavigation.up: renameField; onClicked: renameDialog.apply() }
            }
        }
    }

    // ---- histórico ----
    Dialog {
        id: historyDialog
        title: Strings.t.historyTitle; anchors.centerIn: parent; modal: true; width: 640; height: 460
        header: DialogHeader { dialogTitle: historyDialog.title }
        ListModel { id: historyModel }
        function openAndLoad() {
            historyModel.clear();
            var h = backend.history();
            for (var i = 0; i < h.length; i++) historyModel.append(h[i]);
            open();
        }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.historyHint; opacity: 0.6; Layout.fillWidth: true; wrapMode: Text.WordWrap }
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
            Label { visible: historyModel.count === 0; text: Strings.t.historyEmpty; opacity: 0.5 }
            DialogActions {
                Button { id: historyClear; text: Strings.t.clear; KeyNavigation.right: historyClose; onClicked: root.confirmDelete(Strings.clearHistoryConfirm(), function () { backend.clearHistory(); historyDialog.openAndLoad(); }) }
                Button { id: historyClose; text: Strings.t.close; KeyNavigation.left: historyClear; onClicked: historyDialog.close() }
            }
        }
    }

    // ---- criar ambiente (só o nome) ----
    Dialog {
        id: createEnvDialog
        title: Strings.t.createEnvTitle; anchors.centerIn: parent; modal: true; width: 380
        header: DialogHeader { dialogTitle: createEnvDialog.title }
        function create() {
            var n = newEnvName.text.trim();
            if (n.length === 0) { newEnvName.forceActiveFocus(); return; }
            backend.saveEnvironment(n, []);
            root.activateEnv(n);
            createEnvDialog.close();
            root.openEnvTab(n);
        }
        onAboutToShow: newEnvName.text = ""
        onOpened: newEnvName.forceActiveFocus()
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.envNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
            TextField { id: newEnvName; Layout.fillWidth: true; placeholderText: Strings.t.envNamePlaceholder; KeyNavigation.down: envCreateCancel; onAccepted: createEnvDialog.create() }
            DialogActions {
                Button { id: envCreateCancel; text: Strings.t.cancel; KeyNavigation.right: envCreateBtn; KeyNavigation.up: newEnvName; onClicked: createEnvDialog.close() }
                Button { id: envCreateBtn; text: Strings.t.create; Accessible.defaultButton: true; KeyNavigation.left: envCreateCancel; KeyNavigation.up: newEnvName; onClicked: createEnvDialog.create() }
            }
        }
    }

    // ---- descartar alterações do ambiente ----
    Dialog {
        id: discardEnvDialog
        title: Strings.t.discardChangesTitle; modal: true; anchors.centerIn: parent; width: 400
        header: DialogHeader { dialogTitle: discardEnvDialog.title }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: Strings.t.discardEnvMessage }
            DialogActions {
                Button { id: discardEnvCancel; text: Strings.t.cancel; KeyNavigation.right: discardEnvConfirm; onClicked: discardEnvDialog.close() }
                Button {
                    id: discardEnvConfirm
                    text: Strings.t.discard; Accessible.defaultButton: true
                    KeyNavigation.left: discardEnvCancel
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
        title: Strings.t.renameEnvTitle; modal: true; anchors.centerIn: parent; width: 380
        header: DialogHeader { dialogTitle: renameEnvDialog.title }
        property string oldName: ""
        function errorText() {
            var n = envRenameField.text.trim();
            if (n.length === 0 || n === oldName) return "";
            for (var i = 0; i < root.envList.length; i++)
                if (root.envList[i].name === n) return Strings.t.environmentExists;
            return "";
        }
        function apply() {
            if (errorText().length > 0) return;
            var n = envRenameField.text.trim();
            if (n.length === 0 || n === oldName) { close(); return; }
            envScreen.renameTo(oldName, n);
            close();
        }
        onAboutToShow: envRenameField.text = oldName
        onOpened: { envRenameField.forceActiveFocus(); envRenameField.selectAll(); }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.newEnvNameLabel; Layout.bottomMargin: Kirigami.Units.smallSpacing }
            TextField { id: envRenameField; Layout.fillWidth: true; placeholderText: Strings.t.newEnvironmentShort; KeyNavigation.down: envRenameCancel; onAccepted: renameEnvDialog.apply() }
            Label {
                text: renameEnvDialog.errorText(); color: Kirigami.Theme.negativeTextColor
                visible: text.length > 0; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            DialogActions {
                Button { id: envRenameCancel; text: Strings.t.cancel; KeyNavigation.right: envRenameApply; KeyNavigation.up: envRenameField; onClicked: renameEnvDialog.close() }
                Button { id: envRenameApply; text: Strings.t.rename; Accessible.defaultButton: true; enabled: renameEnvDialog.errorText().length === 0; KeyNavigation.left: envRenameCancel; KeyNavigation.up: envRenameField; onClicked: renameEnvDialog.apply() }
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
            Label { text: Strings.t.scopeOfVariable; font.bold: true; Layout.fillWidth: true }
            TabBar {
                id: scopeMode
                Layout.fillWidth: true
                currentIndex: scopePopup.global ? 0 : 1
                TabButton { text: Strings.t.globalTab; onClicked: { scopePopup.global = true; scopePopup.applyScope(); } }
                TabButton { text: Strings.t.collectionsTab; onClicked: { scopePopup.global = false; scopePopup.applyScope(); } }
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
                    text: Strings.t.noCollectionsYet
                    opacity: 0.6
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        property int targetIndex: -1
        title: Strings.t.chooseFileTitle
        onAccepted: {
            if (targetIndex >= 0 && targetIndex < fieldsModel.count)
                fieldsModel.setProperty(targetIndex, "fileName", selectedFile.toString().replace("file://", ""));
        }
    }

    Connections {
        target: backend
        function onStarted() { root.sending = true; statusLabel.text = Strings.t.sending; }
        function onCanceled() {
            root.sending = false;
            statusLabel.text = Strings.t.canceled; timeLabel.text = ""; sizeLabel.text = "";
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
        function onError(code, args) {
            root.sending = false;
            statusLabel.text = Strings.backendError(code, args);
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
        // recarrega também as variáveis em edição (se não houver alterações não salvas),
        // para o escopo refletir um rename de coleção sem fechar a aba
        function onEnvironmentsChanged() {
            root.reloadEnvs();
            root.refreshResolved();
            if (!envScreen.envVarsDirty)
                envScreen.loadVars(envScreen.editing);
        }
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
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.newRequest, run: function () { newReqDialog.openIn(root.targetFolder()); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.newFolder, run: function () { folderDialog.open(); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.newCollection, run: function () { collectionDialog.open(); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.importCurl, run: function () { curlImportDialog.hint = ""; curlImportArea.text = ""; curlImportDialog.open(); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.history, run: function () { historyDialog.openAndLoad(); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.settingsEllipsis, run: function () { root.openSettingsTab(); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.manageEnvVariables, run: function () { root.openEnvTab(root.activeEnv); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.createEnvironment, run: function () { createEnvDialog.open(); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.closeTab, run: function () { root.closeTab(root.currentTab); } },
                { group: Strings.t.paletteGroupGlobal, label: Strings.t.reopenTab, run: function () { root.reopenClosed(); } },
                { group: Strings.t.paletteGroupContext, label: Strings.t.saveRequest, run: function () { root.saveCurrent(); } },
                { group: Strings.t.paletteGroupContext, label: Strings.t.sendRequest, run: function () { root.doSend(); } },
                { group: Strings.t.paletteGroupContext, label: Strings.t.exportCode, run: function () { curlExportDialog.refresh(); curlExportDialog.open(); } },
                { group: Strings.t.paletteGroupContext, label: Strings.t.moveSelected, run: function () { if (root.selectedPath.length > 0) moveDialog.openFor(root.selectedPath); } },
                { group: Strings.t.paletteGroupContext, label: Strings.t.renameSelected, run: function () { if (root.selectedPath.length > 0) renameDialog.openFor(root.selectedPath); } },
                { group: Strings.t.paletteGroupContext, label: Strings.t.duplicateSelected, run: function () { root.duplicateSelected(); } }
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
            Label { text: Strings.t.commandPalette; font.bold: true }
            TextField {
                id: paletteField
                Layout.fillWidth: true
                placeholderText: Strings.t.commandPlaceholder
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
        title: Strings.t.deleteTitle; modal: true; anchors.centerIn: parent; width: 400
        header: DialogHeader { dialogTitle: deleteDialog.title }
        property string message: ""
        property var callback: null
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: deleteDialog.message }
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.7; text: Strings.t.cannotBeUndone }
            DialogActions {
                Button { id: deleteCancel; text: Strings.t.cancel; KeyNavigation.right: deleteConfirm; onClicked: deleteDialog.close() }
                Button {
                    id: deleteConfirm
                    text: Strings.t.delete; Accessible.defaultButton: true
                    KeyNavigation.left: deleteCancel
                    onClicked: { var f = deleteDialog.callback; deleteDialog.close(); if (f) f(); }
                }
            }
        }
    }
}
