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

    // ---- abas ----
    ListModel { id: tabsModel }

    ListModel { id: paramsModel }
    ListModel { id: headersModel }
    ListModel { id: fieldsModel }
    ListModel { id: requestVarsModel }
    ListModel { id: collectionVarsModel }
    ListModel { id: collectionHeadersModel }
    ListModel { id: treeModel }

    // exposto para os testes de comportamento de tela (tests/tst_app.qml)
    readonly property var appController: controller

    AppController {
        id: controller
        window: root
        tabsModel: tabsModel
        paramsModel: paramsModel
        headersModel: headersModel
        fieldsModel: fieldsModel
        requestVarsModel: requestVarsModel
        collectionVarsModel: collectionVarsModel
        collectionHeadersModel: collectionHeadersModel
        treeModel: treeModel
        requestEditor: requestEditor
        responsePane: responsePane
        collectionScreen: collectionScreen
        envScreen: envScreen
        sidebar: sidebar
        tabStrip: tabStrip
        newReqDialog: newReqDialog
        nameDialog: nameDialog
        confirmCloseDialog: confirmCloseDialog
        curlImportDialog: curlImportDialog
        curlExportDialog: curlExportDialog
        moveDialog: moveDialog
        renameDialog: renameDialog
        historyDialog: historyDialog
        createEnvDialog: createEnvDialog
        renameEnvDialog: renameEnvDialog
        discardEnvDialog: discardEnvDialog
        scopePopup: scopePopup
        fileDialog: fileDialog
    }

    title: Strings.t.appName + (controller.currentTab >= 0 && controller.currentTab < tabsModel.count
                     ? " — " + tabsModel.get(controller.currentTab).name : "")



    // ================= ciclo de vida =================
    Component.onCompleted: {
        controller.rebuildTree();      // imediato (a restauração usa o modelo já preenchido)
        controller.reloadEnvs();
        // A Kirigami registra Alt+Left/Right (StandardKey Back/Forward) no pageStack,
        // o que dá atalho ambíguo e anula a nossa navegação entre abas. Desativamos.
        var pr = pageStack.data;
        for (var pi = 0; pi < pr.length; pi++)
            if (pr[pi] && pr[pi].sequences !== undefined) pr[pi].enabled = false;
        var saved = settings.openTabs;      // restaura as abas da sessão anterior
        controller.restoreSessionTabs(saved);
        if (tabsModel.count > 0) {
            var idx = settings.openTabIndex;
            if (idx < 0 || idx >= tabsModel.count) idx = 0;
            controller.switchTab(idx);
        }
        // sem abas salvas: ficamos no placeholder "Nenhum request aberto"
        // (não abrimos a primeira coleção da árvore automaticamente)
    }


    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("save"); onActivated: controller.saveCurrent() }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("send"); onActivated: controller.doSend() }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("closeTab"); onActivated: controller.closeTab(controller.currentTab) }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("reopenTab"); onActivated: controller.reopenClosed() }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("newRequest"); onActivated: newReqDialog.openIn(controller.targetFolder()) }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("palette"); onActivated: cmdPalette.openPalette() }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("findInResponse"); onActivated: responsePane.openFind() }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("prevTab"); onActivated: controller.prevTab() }
    Shortcut { enabled: !controller.recordingShortcut; sequence: controller.shortcutSeq("nextTab"); onActivated: controller.nextTab() }
    onClosing: function (close) {
        controller.persistSession();
        if (!controller.forceQuit && controller.hasDirtyTabs()) { close.accepted = false; quitDialog.open(); }
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
                Kirigami.Icon { source: "qrc:/icons/catarina.svg"; implicitWidth: 22; implicitHeight: 22
                                isMask: true; color: Kirigami.Theme.textColor }
                Label { text: Strings.t.appName; font.bold: true }
                Item { Layout.fillWidth: true }
                // grupo de painéis: esquerda (coleções) e direita (resposta)
                RowLayout {
                    spacing: 0
                    ToolButton {
                        checkable: true; checked: controller.sidebarVisible
                        icon.name: controller.sidebarVisible ? "view-left-close" : "view-left-new"
                        onToggled: controller.sidebarVisible = checked
                        ToolTip.text: controller.sidebarVisible ? Strings.t.hideCollections : Strings.t.showCollections
                        ToolTip.visible: hovered
                    }
                    ToolButton {
                        checkable: true; checked: controller.responseVisible
                        icon.name: controller.responseVisible ? "view-right-close" : "view-right-new"
                        onToggled: controller.responseVisible = checked
                        ToolTip.text: controller.responseVisible ? Strings.t.hideResponse : Strings.t.showResponse
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
                    text: controller.activeEnv.length > 0 ? controller.activeEnv : Strings.t.noEnvironment
                    onClicked: envPopup.open()
                }
                ToolButton {
                    icon.name: "configure"
                    onClicked: controller.openSettingsTab()
                    ToolTip.text: Strings.t.settings; ToolTip.visible: hovered
                }
                Popup {
                    id: envPopup
                    x: mainPage.width - width - 12
                    y: 46
                    width: 260
                    padding: Kirigami.Units.smallSpacing
                    onOpened: controller.reloadEnvs()
                    ColumnLayout {
                        width: envPopup.availableWidth
                        spacing: Kirigami.Units.smallSpacing

                        Label {
                            visible: controller.envList.length > 0
                            text: Strings.t.activeEnvironment
                            font.bold: true
                            Layout.leftMargin: Kirigami.Units.smallSpacing
                        }
                        Repeater {
                            model: controller.envList
                            delegate: ItemDelegate {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.bold: modelData.name === controller.activeEnv
                                icon.name: modelData.name === controller.activeEnv ? "checkmark" : ""
                                onClicked: {
                                    controller.activateEnv(modelData.name);
                                    envPopup.close();
                                }
                            }
                        }

                        ColumnLayout {
                            visible: controller.envList.length === 0
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
                            visible: controller.envList.length > 0
                            onClicked: { envPopup.close(); controller.openEnvTab(controller.activeEnv); }
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
                    app: controller
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
                        app: controller
                        tabsModel: tabsModel
                    }
                    Kirigami.Separator { Layout.fillWidth: true; visible: tabsModel.count > 0 }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: controller.showingSettings ? 4
                                      : (controller.showingEnv ? 3
                                      : (controller.showingCollection ? 1 : (controller.currentTab >= 0 ? 0 : 2)))

                        // ---- 0: editor + resposta ----
                        SplitView {
                            orientation: Qt.Horizontal
                            handle: SplitGrip {}

                            RequestEditor {
                                id: requestEditor
                                app: controller
                                paramsModel: paramsModel
                                headersModel: headersModel
                                fieldsModel: fieldsModel
                                requestVarsModel: requestVarsModel
                                fileDialog: fileDialog
                            }

                            ResponsePane {
                                id: responsePane
                                app: controller
                            }
                        }

                        // ---- 1: tela da coleção ----
                        CollectionScreen {
                            id: collectionScreen
                            app: controller
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
                                onActionTriggered: newReqDialog.openIn(controller.targetFolder())
                            }
                        }

                        // ---- 3: variáveis de ambiente (aba própria) ----
                        EnvironmentScreen {
                            id: envScreen
                            app: controller
                            scopePopup: scopePopup
                            createEnvDialog: createEnvDialog
                            renameEnvDialog: renameEnvDialog
                            discardEnvDialog: discardEnvDialog
                        }

                        // ---- 4: configurações (aba própria) ----
                        SettingsScreen {
                            id: settingsPage
                            app: controller
                            folderPicker: folderPicker
                        }


                    }
                }
            }
        }

        // "bloco" que segue o mouse durante o arrasto
        Rectangle {
            id: dragGhost
            visible: controller.dragging
            x: controller.ghostX - 12
            y: controller.ghostY - 12
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
                    visible: controller.dragMethod.length > 0
                    implicitWidth: ghostBadge.implicitWidth + 8
                    implicitHeight: 15
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.25)
                    Text { id: ghostBadge; anchors.centerIn: parent; text: controller.dragMethod; color: Kirigami.Theme.highlightedTextColor; font.pixelSize: 9; font.bold: true }
                }
                Kirigami.Icon {
                    visible: controller.dragMethod.length === 0
                    source: controller.dragIsCollection ? "folder-documents" : "folder"
                    implicitWidth: 15; implicitHeight: 15
                    color: Kirigami.Theme.highlightedTextColor
                }
                Label { text: controller.dragLabel; color: Kirigami.Theme.highlightedTextColor }
            }
        }
    }

    // ================= menus =================
    Menu {
        id: addMenu
        MenuItem { text: Strings.t.newCollection; icon.name: "folder-documents"; onTriggered: controller.openNewCollection() }
        MenuItem { text: Strings.t.newRequest; icon.name: "document-new"; onTriggered: newReqDialog.openIn(controller.selectedIsFolder ? controller.selectedPath : "") }
        MenuSeparator {}
        MenuItem { text: Strings.t.importCurl; icon.name: "document-import"; onTriggered: curlImportDialog.openFresh() }
    }
    Menu {
        id: ctxMenu
        MenuItem { text: Strings.t.newRequestHere; icon.name: "document-new"; onTriggered: newReqDialog.openIn(controller.targetFolder()) }
        MenuItem {
            text: Strings.t.newFolderHere; icon.name: "folder-new"
            onTriggered: { controller.selectedPath = controller.targetFolder(); controller.selectedIsFolder = controller.selectedPath.length > 0; controller.openNewFolder(); }
        }
        MenuSeparator {}
        MenuItem { text: Strings.t.moveToEllipsis; icon.name: "edit-move"; enabled: controller.selectedPath.length > 0; onTriggered: moveDialog.openFor(controller.selectedPath) }
        MenuItem { text: Strings.t.renameEllipsis; icon.name: "edit-rename"; enabled: controller.selectedPath.length > 0; onTriggered: renameDialog.openFor(controller.selectedPath) }
        MenuItem { text: Strings.t.duplicate; icon.name: "edit-duplicate"; enabled: controller.selectedPath.length > 0; onTriggered: controller.duplicateSelected() }
        MenuItem {
            text: Strings.t.exportCode; icon.name: "document-export"
            visible: controller.selectedPath.length > 0 && !controller.selectedIsFolder
            onTriggered: { controller.openRequest(controller.selectedPath); curlExportDialog.refresh(); curlExportDialog.open(); }
        }
        MenuSeparator {}
        MenuItem { text: Strings.t.delete; icon.name: "edit-delete"; onTriggered: controller.askDelete() }
    }

    // ================= diálogos (extraídos p/ qml/dialogs) =================
    NewReqDialog { id: newReqDialog; app: controller }
    NameDialog { id: nameDialog; app: controller }
    ConfirmCloseDialog { id: confirmCloseDialog; app: controller; tabsModel: tabsModel }
    QuitDialog { id: quitDialog; app: controller }
    CurlImportDialog { id: curlImportDialog; app: controller }
    CurlExportDialog { id: curlExportDialog; app: controller }
    FolderPicker { id: folderPicker; dirField: dirField }
    MoveDialog { id: moveDialog; app: controller; treeModel: treeModel; treeView: sidebar.view }
    RenameDialog { id: renameDialog; app: controller }
    HistoryDialog { id: historyDialog; app: controller; newReqDialog: newReqDialog }
    CreateEnvDialog { id: createEnvDialog; app: controller }
    DiscardEnvDialog { id: discardEnvDialog; envScreen: envScreen }
    RenameEnvDialog { id: renameEnvDialog; app: controller; envScreen: envScreen }
    ScopePopup { id: scopePopup; app: controller; envVarsModel: envScreen.varsModel; envScreen: envScreen }
    FilePickDialog { id: fileDialog; fieldsModel: fieldsModel }

    Connections {
        target: backend
        function onCollectionsChanged() { controller.reloadTree(); }
        // recarrega também as variáveis em edição (se não houver alterações não salvas),
        // para o escopo refletir um rename de coleção sem fechar a aba
        function onEnvironmentsChanged() {
            controller.reloadEnvs();
            controller.refreshResolved();
            if (!envScreen.envVarsDirty)
                envScreen.loadVars(envScreen.editing);
        }
    }

    CommandPalette {
        id: cmdPalette
        app: controller
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
