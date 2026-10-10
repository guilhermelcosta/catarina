import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings
import "../Util.js" as Util

// Tela de variáveis de ambiente (aba própria). `app` = janela; escopo/criar/renomear/descartar injetados.
Item {
    id: envScreen
    property var app
    property var scopePopup
    property var createEnvDialog
    property var renameEnvDialog
    property var discardEnvDialog
    readonly property alias varsModel: envVarsModel
    property string editing: ""
    property string viewCollection: ""
    property bool envVarsDirty: false
    property string envVarsBaseline: ""
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
    // estado atual das variáveis (inclui escopo) num JSON canônico
    function snapshot() {
        var arr = [];
        for (var i = 0; i < envVarsModel.count; i++) {
            var v = envVarsModel.get(i);
            arr.push({ name: v.name, value: v.value, enabled: v.enabled !== false,
                       secret: v.secret === true, secretId: v.secretId,
                       scope: v.scope, collections: v.collections });
        }
        return Util.stableStringify(arr);
    }
    function recomputeDirty() { envVarsDirty = snapshot() !== envVarsBaseline; }
    function openFor(name) {
        if (name.length === 0 && app.envList.length > 0) name = app.envList[0].name;
        viewCollection = "";
        loadVars(name);
    }
    function loadVars(name) {
        editing = name;
        envVarsDirty = false;
        envVarsModel.clear();
        if (name.length === 0) { resolvedVars = []; envVarsBaseline = snapshot(); return; }
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
        app.updateVarsWarnings();
        envVarsBaseline = snapshot();
    }
    function save() {
        if (editing.length === 0) return;
        var dup = backend.duplicateVariableName(app.modelToArray(envVarsModel));
        if (dup.length > 0) { app.notify(Strings.duplicateInEnvironment(dup)); return; }
        var vars = [];
        for (var i = 0; i < envVarsModel.count; i++) {
            var v = envVarsModel.get(i);
            if (v.name.length === 0) continue;
            vars.push({ name: v.name, value: v.value, enabled: v.enabled !== false, secret: v.secret, secretId: v.secretId,
                        scope: v.scope, collections: v.collections.length > 0 ? v.collections.split(",") : [] });
        }
        if (backend.saveEnvironment(editing, vars)) {
            app.activateEnv(editing);
            loadVars(editing);
            app.notify(Strings.t.environmentSaved);
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
        if (envVarsDirty) { app.notify(Strings.t.saveBeforeRename); return; }
        renameEnvDialog.oldName = name;
        renameEnvDialog.open();
    }
    function renameTo(oldName, newName) {
        if (!backend.renameEnvironment(oldName, newName)) {
            app.notify(Strings.t.environmentExists);
            return;
        }
        app.reloadEnvs();
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
                model: app.envList
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
                    app.confirmDelete(Strings.deleteEnvConfirm(name), function () {
                        backend.deleteEnvironment(name);
                        app.reloadEnvs();
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
                canSave: app.envVarsWarning.length === 0
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
                    model: [Strings.t.viewAllVariables].concat(app.collectionNames())
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
                onEdited: { envScreen.recomputeDirty(); envScreen.refreshResolved(); app.updateVarsWarnings(); }
            }
        }
    }
}
