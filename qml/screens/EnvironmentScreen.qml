import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings
import "../Util.js" as Util

// Environment variables screen (its own tab). `app` = window; scope/create/rename/discard injected.
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
    property var resolvedVars: []   // for autocomplete of environment variables

    ListModel { id: envVarsModel }

    function refreshResolved() {
        var arr = [];
        for (var i = 0; i < envVarsModel.count; i++) {
            var v = envVarsModel.get(i);
            arr.push({ name: v.name, value: v.value, enabled: v.enabled !== false,
                       secret: v.secret === true, secretId: v.secretId });
        }
        resolvedVars = backend.resolvedVariables("", arr);
        // {{refs}} inside the environment's own variables are validated too (red highlight)
        if (app)
            app.setMissingVars(backend.variablesState({ vars: arr }, "").missing);
    }
    // current state of the variables (includes scope) as canonical JSON
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
        var vars = backend.withResolvedSecrets(backend.environmentVariables(name));   // real value from the vault
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

        // left column: environments
        ColumnLayout {
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.environments; font.bold: true }
            ListView {
                objectName: "envList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: app.envList
                delegate: ItemDelegate {
                    id: envRow
                    width: ListView.view.width
                    text: modelData.name
                    leftPadding: (modelData.color !== undefined && modelData.color.length > 0) ? 16 : 6
                    highlighted: modelData.name === envScreen.editing
                    // selection is a tinted surface, not the Breeze solid highlight:
                    // keep the normal text role or the label vanishes into the tint
                    contentItem: Label {
                        text: envRow.text
                        color: Kirigami.Theme.textColor
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    // colour dot before the label (8 px, unset = no dot)
                    Rectangle {
                        objectName: "envListDot"
                        visible: modelData.color !== undefined && modelData.color.length > 0
                        width: 8
                        height: 8
                        radius: 4
                        color: modelData.color !== undefined ? modelData.color : "transparent"
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    background: Rectangle {
                        color: envRow.highlighted ? app.theme.selectionTint
                             : envRow.hovered ? app.theme.hoverTint
                             : "transparent"
                    }
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

        // right column: environment variables
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: app.envList.length > 0
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

            // identity colour: 8 decorative swatches + a custom picker + clear.
            // Colour is a dot/icon, never text, so the WCAG text floor does not apply.
            RowLayout {
                objectName: "envColorRow"
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Label { text: Strings.t.environmentColour; opacity: app.theme.textInformational }
                Repeater {
                    model: app.theme.swatchColors
                    delegate: Rectangle {
                        objectName: "envColorSwatch"
                        implicitWidth: 18
                        implicitHeight: 18
                        radius: 9
                        color: modelData
                        border.width: app.environmentColor(envScreen.editing) === modelData ? 2 : 0
                        border.color: app.theme.chromeBorder
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (backend.setEnvironmentColor(envScreen.editing, modelData))
                                    app.reloadEnvs();
                            }
                        }
                    }
                }
                Button {
                    text: Strings.t.customColour
                    onClicked: envColorDialog.open()
                }
                ToolButton {
                    objectName: "envColorReset"
                    icon.name: "edit-clear"
                    visible: app.environmentColor(envScreen.editing).length > 0
                    onClicked: {
                        if (backend.setEnvironmentColor(envScreen.editing, ""))
                            app.reloadEnvs();
                    }
                    ToolTip.text: Strings.t.resetColour; ToolTip.visible: hovered
                }
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
                Label { text: Strings.t.globalsEverywhere; opacity: app.theme.textInformational }
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
                // color by scope: global (green) / restricted to collections (blue)
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

        // no environment at all: the table and SaveBar have nothing to act on
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: app.envList.length === 0
            EmptyState {
                objectName: "envEmptyState"
                anchors.centerIn: parent
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                title: Strings.t.noEnvironments
                message: Strings.t.noEnvironmentsHint
                actionText: Strings.t.newEnvironment
                actionIcon: "list-add"
                onActionTriggered: createEnvDialog.open()
            }
        }
    }

    // custom environment colour: writes only on accepted
    ColorDialog {
        id: envColorDialog
        objectName: "envColorDialog"
        title: Strings.t.environmentColour
        selectedColor: app.environmentColor(envScreen.editing).length > 0
                       ? app.environmentColor(envScreen.editing)
                       : Kirigami.Theme.highlightColor
        onAccepted: {
            if (backend.setEnvironmentColor(envScreen.editing, color))
                app.reloadEnvs();
        }
    }
}
