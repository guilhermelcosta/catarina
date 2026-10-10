import QtQuick
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings
import "Util.js" as Util

// Non-visual controller: state + orchestration (tree, tabs, collection, environments,
// session, sending). The window and components talk to it via `app`.
QtObject {
    id: controller

    // injected by the window / components
    property var window
    property var tabsModel
    property var paramsModel
    property var headersModel
    property var fieldsModel
    property var requestVarsModel
    property var collectionVarsModel
    property var collectionHeadersModel
    property var treeModel
    property var requestEditor
    property var responsePane
    property var collectionScreen
    property var envScreen
    property var sidebar
    property var tabStrip
    property var newReqDialog
    property var nameDialog
    property var confirmCloseDialog
    property var curlImportDialog
    property var curlExportDialog
    property var moveDialog
    property var renameDialog
    property var historyDialog
    property var createEnvDialog
    property var renameEnvDialog
    property var discardEnvDialog
    property var scopePopup
    property var fileDialog

property string selectedPath: ""
property bool selectedIsFolder: false
property bool showingCollection: false
property bool showingEnv: false
property bool showingSettings: false
readonly property bool envTabDirty: envScreen ? envScreen.envVarsDirty : false   // unsaved state of the environments tab
property bool sidebarVisible: true
property bool responseVisible: true
property string collectionPath: ""
property bool collectionIsSubfolder: false
property string dropTarget: ""
property bool dropIsFolder: false
// dropping outside the rows (above the first / below the last item) → root
property bool dropRoot: false
property bool dragging: false
property bool justDragged: false
property string dragFrom: ""
property string dragLabel: ""
property string dragMethod: ""
property bool dragIsCollection: false
property bool dragIsFolder: false
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
// saved collection state, so dirty clears itself on manual undo
property string collectionVarsBaseline: ""
property string collectionHeadersBaseline: ""
property string collectionAuthBaseline: ""

property int currentTab: -1
property var closedTabs: []
property var responses: ({})       // relPath -> { status, statusText, time, size, headers, body }
property bool treeReloadQueued: false
property bool sending: false

// ---- environments ----
property var envList: []
property string activeEnv: ""
property var resolvedVars: []
property var collectionResolvedVars: []
property string currentCollection: ""
property string missingText: ""
// warnings for duplicate variable names in the same scope (block save/send)
property string requestVarsWarning: ""
property string collectionVarsWarning: ""
property string envVarsWarning: ""
property bool currentDirty: false
property int paramsRevision: 0   // bump on params table edits (URL preview)
// JSON token colors (dark/light theme) used by the editors (body and response)
readonly property bool darkTheme: Kirigami.Theme.backgroundColor.hsvValue < 0.5
readonly property color jsonStringColor: darkTheme ? "#98c379" : "#2e7d32"
readonly property color jsonNumberColor: darkTheme ? "#d19a66" : "#b26a00"
readonly property color jsonKeywordColor: darkTheme ? "#d19a66" : "#b26a00"
readonly property color jsonKeyColor: darkTheme ? "#61afef" : "#005cc5"

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
function reloadTree() {   // coalesce: several requests in the same tick become 1 rebuild
    if (treeReloadQueued) return;
    treeReloadQueued = true;
    Qt.callLater(function () { treeReloadQueued = false; rebuildTree(); });
}
function rebuildTree() {
    treeModel.clear();
    var a = backend.collectionTree();
    var collapsed = Object.keys(controller.collapsedFolders);
    for (var i = 0; i < a.length; i++) {
        var e = a[i];
        var hidden = false;
        for (var c = 0; c < collapsed.length; c++) {
            if (e.relPath !== collapsed[c] && e.relPath.indexOf(collapsed[c] + "/") === 0) {
                hidden = true;
                break;
            }
        }
        treeModel.append({ name: e.name, relPath: e.relPath, isFolder: e.isFolder,
                           method: e.method !== undefined ? e.method : "",
                           depth: e.depth !== undefined ? e.depth : 0,
                           hasChildren: e.hasChildren === true,
                           collapsed: controller.collapsedFolders[e.relPath] === true,
                           hidden: hidden });
    }
}
// updates the "hidden"/"collapsed" roles in place (no model reset) so the
// delegate height can animate when a folder is expanded/collapsed
function applyCollapse() {
    var collapsed = Object.keys(controller.collapsedFolders);
    for (var i = 0; i < treeModel.count; i++) {
        var e = treeModel.get(i);
        var hidden = false;
        for (var k = 0; k < collapsed.length; k++) {
            if (e.relPath !== collapsed[k] && e.relPath.indexOf(collapsed[k] + "/") === 0) {
                hidden = true;
                break;
            }
        }
        if (e.hidden !== hidden) treeModel.setProperty(i, "hidden", hidden);
        var isCollapsed = controller.collapsedFolders[e.relPath] === true;
        if (e.collapsed !== isCollapsed) treeModel.setProperty(i, "collapsed", isCollapsed);
    }
}
function toggleCollapse(relPath) {
    var c = Object.assign({}, controller.collapsedFolders);
    if (c[relPath]) delete c[relPath]; else c[relPath] = true;
    controller.collapsedFolders = c;
    applyCollapse();
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
    controller.activeEnv = name;                 // optimistic: the label updates immediately
    backend.setActiveEnvironment(name);    // emits environmentsChanged → reloadEnvs + refreshResolved
}
function targetFolder() {
    if (selectedPath.length === 0) return "";
    return selectedIsFolder ? selectedPath : parentOf(selectedPath);
}
// where a tree drag lands: a folder target, the parent of a request target,
// or the root ("") when dropped outside the rows (root=true). Returns
// `from` when there is no move to make.
function dragDestination(from, target, targetIsFolder, root) {
    if (root) return from.indexOf("/") < 0 ? from : "";
    if (target.length > 0 && target !== from)
        return targetIsFolder ? target : parentOf(target);
    return from;
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
// message when a variable name is duplicated in the same scope ("" if ok)
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
// Preview in the query bar that the active params append to the URL (logic in Util.js).
// Reads `paramsRevision` only so the binding re-evaluates on each params table edit.
function querySuffix() {
    var rev = paramsRevision;
    return backend.querySuffix(requestEditor.url, modelToArray(paramsModel));
}
function collectRequest() {
    return { method: requestEditor.method, url: requestEditor.url,
             params: modelToArray(paramsModel), headers: modelToArray(headersModel),
             fields: modelToArray(fieldsModel),
             body: requestEditor.body, bodyType: requestEditor.bodyType,
             auth: currentAuth(),
             vars: modelToArray(requestVarsModel) };
}
// current editor state as canonical JSON (compared with saved for dirty)
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
    collectionVarsDirty = false;        // we left the collection: pending edits no longer count
    collectionHeadersDirty = false;
    collectionAuthDirty = false;
    refreshResolved();
    updateVarsWarnings();
    // clean tab: the displayed state becomes the "saved" reference (undo clears dirty)
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
        controller.markDirty();
    } catch (e) {
        notify(Strings.t.invalidJsonShort);
    }
}
function refreshResolved() {
    resolvedDebounce.stop();   // cancels a scheduled refresh (this is the one running now)
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
        // in the collection tab the effective list is the collection's, not the request's
        resolvedVars = [];
        missingText = "";
        currentDirty = false;
        refreshCollectionResolved();
        return;
    }
    const collection = collectionOf(curTab.relPath);
    currentCollection = collection;
    // single backend pass: resolved list + what's missing
    const state = backend.variablesState(collectRequest(), collection);
    const miss = state.missing;
    const res = state.resolved;
    var notes = [];
    for (var i = 0; i < miss.length; i++) {
        var n = backend.variableNoteFor(miss[i], collection);
        var code = n.code;
        for (var j = 0; j < res.length; j++)   // disabled in the request is not "undefined"
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
// re-resolve with delay: typing does not recompute on every key
property Timer resolvedDebounce: Timer {
    interval: 180
    onTriggered: controller.refreshResolved()
}

// ================= tabs =================
function snapshotCurrent() {
    if (currentTab < 0 || currentTab >= tabsModel.count) return;
    var t = tabsModel.get(currentTab);
    if (t.isCollection || t.isEnvironment || t.isSettings) return;   // utility tabs have no editor
    tabsModel.setProperty(currentTab, "dataJson", JSON.stringify(collectRequest()));
    tabsModel.setProperty(currentTab, "method", requestEditor.method);
}
// index of the tab with this relPath and type (request vs collection), or -1
function tabIndexFor(relPath, isCollection) {
    for (var i = 0; i < tabsModel.count; i++) {
        var t = tabsModel.get(i);
        if (t.relPath === relPath && (t.isCollection === true) === isCollection) return i;
    }
    return -1;
}
// index of the transient "preview" request tab, or -1
function previewTabIndex() {
    for (var i = 0; i < tabsModel.count; i++)
        if (tabsModel.get(i).preview === true) return i;
    return -1;
}
// pins/unpins a tab: pinned tabs are not replaced; unpinning restores the
// transient preview so the next request opens over it (VS Code model).
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
    // dirty = current state != saved state; manual undo makes it clean again
    var changed = requestSnapshot() !== t.savedJson;
    tabsModel.setProperty(currentTab, "dirty", changed);
    if (changed)
        tabsModel.setProperty(currentTab, "preview", false);   // editing takes the tab out of preview (becomes permanent), like VS Code
    currentDirty = changed;
    resolvedDebounce.restart();   // debounce: does not re-resolve on every key
}
// expands the folders above relPath and selects it in the tree
function revealPath(relPath) {
    var c = Object.assign({}, controller.collapsedFolders);
    var parts = relPath.split("/"), prefix = "";
    for (var i = 0; i < parts.length - 1; i++) {
        prefix = prefix.length === 0 ? parts[i] : prefix + "/" + parts[i];
        delete c[prefix];
    }
    controller.collapsedFolders = c;
    controller.selectedPath = relPath;
    controller.selectedIsFolder = false;
    reloadTree();
}
function openRequest(relPath) {
    revealPath(relPath);           // selects in the tree and expands the folders above
    // already open? go to it (don't open again)
    for (var i = 0; i < tabsModel.count; i++) {
        var t = tabsModel.get(i);
        if (!t.isCollection && !t.isEnvironment && !t.isSettings && t.relPath === relPath) { switchTab(i); return; }
    }
    var r = backend.loadRequest(relPath);
    if (r.method === undefined) return;
    r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);   // real vault value

    // reuses the transient "preview" tab; if it has edits, pin it first
    var target = -1;
    var prev = previewTabIndex();
    if (prev >= 0) {
        if (tabsModel.get(prev).dirty === true) {
            tabsModel.setProperty(prev, "pinned", true);   // don't lose the edits
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
        if (envScreen.editing.length === 0) envScreen.openFor(controller.activeEnv);   // first display
        showingSettings = false;
        showingEnv = true;
        showingCollection = false;
    } else if (t.isCollection) {
        showingSettings = false;
        loadCollection(t.relPath);
    } else {
        revealPath(t.relPath);   // keeps the tree in sync with the active tab
        applyRequest(JSON.parse(t.dataJson), t.relPath);
        showingSettings = false;
        showingCollection = false;
        showingEnv = false;
    }
}
// opens (or focuses) the single environment variables tab
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
// opens (or focuses) the single settings tab
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
// applies the active tab without snapshot/guard (used after close/delete)
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
        if (envScreen.editing.length === 0) envScreen.openFor(controller.activeEnv);
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
// restores the saved tabs without applying each one to the editor (only the active one is applied later)
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
        r.vars = backend.withResolvedSecrets(r.vars !== undefined ? r.vars : []);   // real vault value
        // only pinned tabs are persisted, so they restore already pinned
        tabsModel.append({ relPath: rp, name: rp.split("/").pop(),
                           method: r.method, dirty: false, dataJson: JSON.stringify(r), savedJson: Util.stableStringify(r),
                           isCollection: false, isEnvironment: false, isSettings: false,
                           pinned: true, preview: false });
    }
}
// ---- reorder tabs by drag and drop ----
function moveTab(from, to) {
    const m = Util.tabMove(tabsModel.count, from, to, currentTab);
    if (m === null) return;
    tabsModel.move(from, m.dest, 1);
    currentTab = m.current;
}
// x in tabRow coordinates; returns the insertion point (0..count)
function tabIndexAt(x) {
    var n = 0;
    for (var i = 0; i < tabStrip.row.children.length; i++) {
        var it = tabStrip.row.children[i];
        if (!it.isTabDelegate) continue;   // ignores the Repeater and the like
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
        delete responses[relPath];   // releases the stored response of the closed tab
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

// opens the new item dialog: folder (inside the selection) or collection (root)
function openNewFolder() { nameDialog.base = controller.targetFolder(); nameDialog.asCollection = false; nameDialog.open(); }
function openNewCollection() { nameDialog.base = ""; nameDialog.asCollection = true; nameDialog.open(); }

// opens (or focuses) the collection/folder tab
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
// highlights the collection/folder in the tree (collection tabs have no applyRequest)
function revealCollection(relPath) {
    var c = Object.assign({}, controller.collapsedFolders);
    var parts = relPath.split("/"), prefix = "";
    for (var i = 0; i < parts.length - 1; i++) {
        prefix = prefix.length === 0 ? parts[i] : prefix + "/" + parts[i];
        delete c[prefix];
    }
    controller.collapsedFolders = c;
    controller.selectedPath = relPath;
    controller.selectedIsFolder = true;
    reloadTree();
}
// recomputes the collection's "Effective variables" (reopen the tab and return to the overview)
function refreshCollectionResolved() {
    if (collectionPath.length === 0 || collectionIsSubfolder) { collectionResolvedVars = []; return; }
    // includes the variables being edited (unsaved) so one can reference another,
    // but keeping the "collection" origin (not "request") in the overview
    collectionResolvedVars = backend.resolvedCollectionVariables(collectionOf(collectionPath), modelToArray(collectionVarsModel));
}
// populates the collection panel from disk
function loadCollection(relPath) {
    revealCollection(relPath);
    collectionPath = relPath;
    // uses the full tree (not the visible one): collapsed folders don't hide requests
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
        collectionVarsModel.clear();       // folder has no variables: they belong to the collection
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
    if (collectionPath.length === 0 || collectionIsSubfolder) return;   // folder has no variables
    var dup = backend.duplicateVariableName(modelToArray(collectionVarsModel));
    if (dup.length > 0) { notify(Strings.duplicateInCollection(dup)); return; }
    backend.saveCollectionVariables(collectionPath, modelToArray(collectionVarsModel));
    collectionVarsBaseline = Util.stableStringify(modelToArray(collectionVarsModel));
    collectionVarsDirty = false;
    refreshCollectionResolved();   // overview reflects secret/normal without needing to reopen
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
    if (collectionPath.length === 0 || collectionIsSubfolder) return;   // folder has no headers
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
    if (collectionPath.length === 0 || collectionIsSubfolder) return;   // folder has no auth
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
    if (t.isSettings) return;       // settings apply immediately
    if (t.isEnvironment) {          // Ctrl+S in the environments tab saves the pending changes
        if (envScreen.envVarsDirty) envScreen.save();
        return;
    }
    if (t.isCollection) {          // Ctrl+S in the collection saves whatever is pending
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
        notify(Strings.savedTo(backend.storageDir, t.relPath));
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
function notify(msg) { window.showPassiveNotification(msg); }
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
// single delete confirmation: respects settings.confirmDelete in ALL flows
function confirmDelete(message, onConfirm) {
    if (!settings.confirmDelete) { onConfirm(); return; }
    deleteDialog.message = message;
    deleteDialog.callback = onConfirm;
    deleteDialog.open();
}
function askDelete() {
    if (selectedPath.length === 0) return;
    const name = selectedPath.split("/").pop();
    controller.confirmDelete(Strings.deleteItemConfirm(name),
                       function () { controller.deleteSelected(); });
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
    // only pinned tabs come back in the next session (preview/unpinned are transient)
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
        if (t.isCollection || t.isEnvironment || t.isSettings) continue;   // not requests
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
// finds a free request path inside folder, suffixing -N if it already exists
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
// ponytail: base64/formatting/cURL parsing live in Util.js (pure domain);
// the effective parts (auth + Content-Type) come from Backend::requestParts.


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

property bool forceQuit: false
}
