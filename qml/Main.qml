import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Util.js" as Util
import "Strings.js" as Strings
import "dialogs"
import "screens"

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
    property bool collectionAuthDirty: false
    // estado salvo da coleção, para o dirty cair sozinho ao desfazer na mão
    property string collectionVarsBaseline: ""
    property string collectionHeadersBaseline: ""
    property string collectionAuthBaseline: ""

    // ---- abas ----
    ListModel { id: tabsModel }
    property int currentTab: -1
    property var closedTabs: []
    property var responses: ({})       // relPath -> { status, statusText, time, size, headers, body }
    property bool treeReloadQueued: false
    property bool sending: false

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
    property bool currentDirty: false
    property int paramsRevision: 0   // bump nas edições da tabela de params (preview da URL)
    // cores dos tokens JSON (tema escuro/claro) usadas pelos editores (corpo e resposta)
    readonly property bool darkTheme: Kirigami.Theme.backgroundColor.hsvValue < 0.5
    readonly property color jsonStringColor: darkTheme ? "#98c379" : "#2e7d32"
    readonly property color jsonNumberColor: darkTheme ? "#d19a66" : "#b26a00"
    readonly property color jsonKeywordColor: darkTheme ? "#d19a66" : "#b26a00"
    readonly property color jsonKeyColor: darkTheme ? "#61afef" : "#005cc5"

    ListModel { id: paramsModel }
    ListModel { id: headersModel }
    ListModel { id: fieldsModel }
    ListModel { id: requestVarsModel }
    ListModel { id: collectionVarsModel }
    ListModel { id: collectionHeadersModel }
    ListModel { id: treeModel }

    title: Strings.t.appName + (currentTab >= 0 && currentTab < tabsModel.count
                     ? " — " + tabsModel.get(currentTab).name : "")



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
        envVarsWarning = varsWarning(envScreen.varsModel);
    }
    function currentAuth() {
        return requestEditor.authEditor.value();
    }
    // Preview na barra da query que os params ativos anexam à URL (lógica em Util.js).
    // Lê `paramsRevision` só para a binding reavaliar a cada edição da tabela de params.
    function querySuffix() {
        var rev = paramsRevision;
        return Util.querySuffix(requestEditor.url, modelToArray(paramsModel));
    }
    function collectRequest() {
        return { method: requestEditor.method, url: requestEditor.url,
                 params: modelToArray(paramsModel), headers: modelToArray(headersModel),
                 fields: modelToArray(fieldsModel),
                 body: requestEditor.body, bodyType: requestEditor.bodyType,
                 auth: currentAuth(),
                 vars: modelToArray(requestVarsModel) };
    }
    // estado atual do editor num JSON canônico (compara com o salvo p/ dirty)
    function requestSnapshot() { return Util.stableStringify(collectRequest()); }
    function recomputeCollectionDirty() {
        collectionVarsDirty = Util.stableStringify(modelToArray(collectionVarsModel)) !== collectionVarsBaseline;
        collectionHeadersDirty = Util.stableStringify(modelToArray(collectionHeadersModel)) !== collectionHeadersBaseline;
        collectionAuthDirty = Util.stableStringify(collectionScreen.authEditor.value()) !== collectionAuthBaseline;
    }
    function fillModels(list, model) {
        model.clear();
        var a = list !== undefined ? list : [];
        for (var i = 0; i < a.length; i++)
            model.append(entryOf(a[i]));
    }

    function applyRequest(r, relPath) {
        requestEditor.setMethod(r.method !== undefined ? r.method : "GET");
        requestEditor.url = r.url !== undefined ? r.url : "";
        fillModels(r.params, paramsModel);
        fillModels(r.headers, headersModel);
        fillModels(r.fields, fieldsModel);
        fillModels(backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []), requestVarsModel);
        requestEditor.body = r.body !== undefined ? r.body : "";
        requestEditor.setBodyType(r.bodyType !== undefined ? r.bodyType : "none");
        var auth = r.auth !== undefined ? r.auth : {};
        requestEditor.authEditor.load(auth);
        responsePane.restoreResponse(relPath);
        collectionVarsDirty = false;        // saímos da coleção: edições pendentes não valem mais
        collectionHeadersDirty = false;
        collectionAuthDirty = false;
        refreshResolved();
        updateVarsWarnings();
        // aba limpa: o estado exibido vira a referência do "salvo" (desfazer zera o dirty)
        if (currentTab >= 0 && currentTab < tabsModel.count && tabsModel.get(currentTab).dirty !== true)
            tabsModel.setProperty(currentTab, "savedJson", requestSnapshot());
    }
    function clearEditor() {
        requestEditor.setMethod("GET");
        requestEditor.url = "";
        paramsModel.clear(); headersModel.clear(); fieldsModel.clear(); requestVarsModel.clear();
        requestEditor.body = "";
        requestEditor.setBodyType("none");
        requestEditor.authEditor.clear();
        collectionVarsDirty = false;
        collectionHeadersDirty = false;
        collectionAuthDirty = false;
        responsePane.restoreResponse("");
    }
    function formatBody() {
        if (requestEditor.body.trim().length === 0) return;
        try {
            requestEditor.body = JSON.stringify(JSON.parse(requestEditor.body), null, 2);
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

    // ================= abas =================
    function snapshotCurrent() {
        if (currentTab < 0 || currentTab >= tabsModel.count) return;
        var t = tabsModel.get(currentTab);
        if (t.isCollection || t.isEnvironment || t.isSettings) return;   // abas utilitárias não têm editor
        tabsModel.setProperty(currentTab, "dataJson", JSON.stringify(collectRequest()));
        tabsModel.setProperty(currentTab, "method", requestEditor.method);
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
        if (currentTab < 0 || currentTab >= tabsModel.count) return;
        var t = tabsModel.get(currentTab);
        if (t.isCollection || t.isEnvironment || t.isSettings) return;
        // dirty = estado atual != estado salvo; desfazer na mão volta a ficar limpo
        var changed = requestSnapshot() !== t.savedJson;
        tabsModel.setProperty(currentTab, "dirty", changed);
        if (changed)
            tabsModel.setProperty(currentTab, "preview", false);   // editar tira a aba da prévia (fica permanente), como no VS Code
        currentDirty = changed;
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
                               method: r.method, dirty: false, dataJson: JSON.stringify(r), savedJson: "",
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
                               dirty: false, dataJson: "", savedJson: "",
                               isCollection: false, isEnvironment: true, isSettings: false,
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
                               dirty: false, dataJson: "", savedJson: "",
                               isCollection: false, isEnvironment: false, isSettings: true,
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
        for (var i = 0; i < paths.length; i++) {
            var rp = paths[i];
            if (rp.length === 0) continue;
            if (rp === "__environment__") {
                tabsModel.append({ relPath: rp, name: Strings.t.environments, method: "", dirty: false,
                                   dataJson: "", savedJson: "", isCollection: false, isEnvironment: true, isSettings: false,
                                   pinned: false, preview: false });
                continue;
            }
            if (rp === "__settings__") {
                tabsModel.append({ relPath: rp, name: Strings.t.settings, method: "", dirty: false,
                                   dataJson: "", savedJson: "", isCollection: false, isEnvironment: false, isSettings: true,
                                   pinned: false, preview: false });
                continue;
            }
            if (backend.isCollection(rp)) {
                tabsModel.append({ relPath: rp, name: rp.split("/").pop(),
                                   method: "", dirty: false, dataJson: "", savedJson: "", isCollection: true, isEnvironment: false, isSettings: false,
                                   pinned: false, preview: false });
                continue;
            }
            var r = backend.loadRequest(rp);
            if (r.method === undefined) continue;
            r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);   // valor real do cofre
            // só abas fixadas são persistidas, então restauram já fixadas
            tabsModel.append({ relPath: rp, name: rp.split("/").pop(),
                               method: r.method, dirty: false, dataJson: JSON.stringify(r), savedJson: Util.stableStringify(r),
                               isCollection: false, isEnvironment: false, isSettings: false,
                               pinned: true, preview: false });
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
        for (var i = 0; i < tabStrip.row.children.length; i++) {
            var it = tabStrip.row.children[i];
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
                        ? (i === currentTab && (collectionVarsDirty || collectionHeadersDirty || collectionAuthDirty))
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
                saveCollectionAuth();
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

    // abre o diálogo de novo item: pasta (dentro da seleção) ou coleção (raiz)
    function openNewFolder() { nameDialog.base = root.targetFolder(); nameDialog.asCollection = false; nameDialog.open(); }
    function openNewCollection() { nameDialog.base = ""; nameDialog.asCollection = true; nameDialog.open(); }

    // abre (ou foca) a aba da coleção/pasta
    function openCollection(relPath) {
        var existing = tabIndexFor(relPath, true);
        if (existing >= 0) { switchTab(existing); return; }
        snapshotCurrent();
        tabsModel.append({ relPath: relPath, name: relPath.split("/").pop(),
                           method: "", dirty: false, dataJson: "", savedJson: "",
                           isCollection: true, isEnvironment: false, isSettings: false,
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
            collectionScreen.authEditor.load({});
        } else {
            fillModels(backend.withResolvedSecrets(backend.collectionVariables(relPath)), collectionVarsModel);
            fillModels(backend.withResolvedSecrets(backend.collectionHeaders(relPath)), collectionHeadersModel);
            collectionScreen.authEditor.load(backend.collectionAuth(relPath));
        }
        refreshCollectionResolved();
        collectionVarsBaseline = Util.stableStringify(modelToArray(collectionVarsModel));
        collectionHeadersBaseline = Util.stableStringify(modelToArray(collectionHeadersModel));
        collectionAuthBaseline = Util.stableStringify(collectionScreen.authEditor.value());
        collectionVarsDirty = false;
        collectionHeadersDirty = false;
        collectionAuthDirty = false;
        updateVarsWarnings();
        showingCollection = true;
        showingEnv = false;
    }
    function saveCollectionVars() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem variáveis
        var dup = backend.duplicateVariableName(modelToArray(collectionVarsModel));
        if (dup.length > 0) { notify(Strings.duplicateInCollection(dup)); return; }
        backend.saveCollectionVariables(collectionPath, modelToArray(collectionVarsModel));
        collectionVarsBaseline = Util.stableStringify(modelToArray(collectionVarsModel));
        collectionVarsDirty = false;
        refreshCollectionResolved();   // visão geral reflete secret/normal sem precisar reabrir
        notify(Strings.t.collectionVarsSaved);
    }
    function revertCollectionVars() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;
        fillModels(backend.withResolvedSecrets(backend.collectionVariables(collectionPath)), collectionVarsModel);
        collectionVarsBaseline = Util.stableStringify(modelToArray(collectionVarsModel));
        collectionVarsDirty = false;
        notify(Strings.t.changesDiscarded);
    }
    function saveCollectionHeaders() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem cabeçalhos
        backend.saveCollectionHeaders(collectionPath, modelToArray(collectionHeadersModel));
        collectionHeadersBaseline = Util.stableStringify(modelToArray(collectionHeadersModel));
        collectionHeadersDirty = false;
        notify(Strings.t.collectionHeadersSaved);
    }
    function revertCollectionHeaders() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;
        fillModels(backend.withResolvedSecrets(backend.collectionHeaders(collectionPath)), collectionHeadersModel);
        collectionHeadersBaseline = Util.stableStringify(modelToArray(collectionHeadersModel));
        collectionHeadersDirty = false;
        notify(Strings.t.changesDiscarded);
    }
    function saveCollectionAuth() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;   // pasta não tem auth
        backend.saveCollectionAuth(collectionPath, collectionScreen.authEditor.value());
        collectionAuthBaseline = Util.stableStringify(collectionScreen.authEditor.value());
        collectionAuthDirty = false;
        notify(Strings.t.collectionAuthSaved);
    }
    function revertCollectionAuth() {
        if (collectionPath.length === 0 || collectionIsSubfolder) return;
        collectionScreen.authEditor.load(backend.collectionAuth(collectionPath));
        collectionAuthBaseline = Util.stableStringify(collectionScreen.authEditor.value());
        collectionAuthDirty = false;
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
            if (collectionAuthDirty) saveCollectionAuth();
            return;
        }
        var dup = backend.duplicateVariableName(modelToArray(requestVarsModel));
        if (dup.length > 0) { notify(Strings.duplicateInRequest(dup)); return; }
        if (backend.saveRequest(t.relPath, collectRequest())) {
            tabsModel.setProperty(currentTab, "method", requestEditor.method);
            tabsModel.setProperty(currentTab, "savedJson", requestSnapshot());
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
        if (requestEditor.url.length === 0) { notify(Strings.t.provideUrl); return; }
        var dup = backend.duplicateVariableName(modelToArray(requestVarsModel));
        if (dup.length > 0) { notify(Strings.duplicateInRequest(dup)); return; }
        if (settings.autoSaveOnSend && currentDirty) saveCurrent();
        var t = tabsModel.get(currentTab);
        responsePane.clearResponse();
        backend.send(collectRequest(), collectionOf(t.relPath));
    }
    function persistSession() {
        // só abas fixadas voltam na próxima sessão (preview/não-fixadas são transientes)
        var arr = [];
        for (var i = 0; i < tabsModel.count; i++) arr.push(tabsModel.get(i));
        var s = Util.sessionPaths(arr, currentTab);
        settings.saveSession(s.paths, s.current);
    }

    function hasDirtyTabs() {
        if (currentTab >= 0 && currentTab < tabsModel.count) {
            var ct = tabsModel.get(currentTab);
            if (ct.isEnvironment && envScreen.envVarsDirty) return true;
            if (ct.isCollection && (collectionVarsDirty || collectionHeadersDirty || collectionAuthDirty)) return true;
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
                if (collectionAuthDirty) saveCollectionAuth();
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
    // ponytail: base64/formatação/parse de cURL vivem em Util.js (domínio puro);
    // as partes efetivas (auth + Content-Type) vêm de Backend::requestParts.

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
    Shortcut { enabled: !root.recordingShortcut; sequence: root.shortcutSeq("findInResponse"); onActivated: responsePane.openFind() }
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
                Kirigami.Icon { source: "qrc:/icons/katarina.svg"; implicitWidth: 22; implicitHeight: 22
                                isMask: true; color: Kirigami.Theme.textColor }
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
                handle: SplitGrip {}

                // ================= SIDEBAR =================
                Sidebar {
                    id: sidebar
                    app: root
                    treeModel: treeModel
                    addMenu: addMenu
                    ctxMenu: ctxMenu
                }

                // ================= ÁREA PRINCIPAL =================
                ColumnLayout {
                    SplitView.fillWidth: true
                    spacing: 0

                    // barra de abas
                    TabStrip {
                        id: tabStrip
                        app: root
                        tabsModel: tabsModel
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
                            handle: SplitGrip {}

                            RequestEditor {
                                id: requestEditor
                                app: root
                                paramsModel: paramsModel
                                headersModel: headersModel
                                fieldsModel: fieldsModel
                                requestVarsModel: requestVarsModel
                                fileDialog: fileDialog
                            }

                            ResponsePane {
                                id: responsePane
                                app: root
                            }
                        }

                        // ---- 1: tela da coleção ----
                        CollectionScreen {
                            id: collectionScreen
                            app: root
                            newReqDialog: newReqDialog
                            collectionHeadersModel: collectionHeadersModel
                            collectionVarsModel: collectionVarsModel
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
                        EnvironmentScreen {
                            id: envScreen
                            app: root
                            scopePopup: scopePopup
                            createEnvDialog: createEnvDialog
                            renameEnvDialog: renameEnvDialog
                            discardEnvDialog: discardEnvDialog
                        }

                        // ---- 4: configurações (aba própria) ----
                        SettingsScreen {
                            id: settingsPage
                            app: root
                            folderPicker: folderPicker
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
        MenuItem { text: Strings.t.newCollection; icon.name: "folder-documents"; onTriggered: root.openNewCollection() }
        MenuItem { text: Strings.t.newRequest; icon.name: "document-new"; onTriggered: newReqDialog.openIn(root.selectedIsFolder ? root.selectedPath : "") }
        MenuSeparator {}
        MenuItem { text: Strings.t.importCurl; icon.name: "document-import"; onTriggered: curlImportDialog.openFresh() }
    }
    Menu {
        id: ctxMenu
        MenuItem { text: Strings.t.newRequestHere; icon.name: "document-new"; onTriggered: newReqDialog.openIn(root.targetFolder()) }
        MenuItem {
            text: Strings.t.newFolderHere; icon.name: "folder-new"
            onTriggered: { root.selectedPath = root.targetFolder(); root.selectedIsFolder = root.selectedPath.length > 0; root.openNewFolder(); }
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

    // ================= diálogos (extraídos p/ qml/dialogs) =================
    NewReqDialog { id: newReqDialog; app: root }
    NameDialog { id: nameDialog; app: root }
    ConfirmCloseDialog { id: confirmCloseDialog; app: root; tabsModel: tabsModel }
    QuitDialog { id: quitDialog; app: root }
    CurlImportDialog { id: curlImportDialog; app: root }
    CurlExportDialog { id: curlExportDialog; app: root }
    FolderPicker { id: folderPicker; dirField: dirField }
    MoveDialog { id: moveDialog; app: root; treeModel: treeModel; treeView: sidebar.view }
    RenameDialog { id: renameDialog; app: root }
    HistoryDialog { id: historyDialog; app: root; newReqDialog: newReqDialog }
    CreateEnvDialog { id: createEnvDialog; app: root }
    DiscardEnvDialog { id: discardEnvDialog; envScreen: envScreen }
    RenameEnvDialog { id: renameEnvDialog; app: root; envScreen: envScreen }
    ScopePopup { id: scopePopup; app: root; envVarsModel: envScreen.varsModel; envScreen: envScreen }
    FilePickDialog { id: fileDialog; fieldsModel: fieldsModel }

    Connections {
        target: backend
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

    CommandPalette {
        id: cmdPalette
        app: root
        newReqDialog: newReqDialog
        curlImportDialog: curlImportDialog
        historyDialog: historyDialog
        createEnvDialog: createEnvDialog
        moveDialog: moveDialog
        renameDialog: renameDialog
        curlExportDialog: curlExportDialog
    }

    // Declarado por último para ficar acima de qualquer outra tela/dialog aberto.
    DeleteDialog { id: deleteDialog }
}
