import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Tela da coleção (visão geral/cabeçalhos/variáveis/autenticação). `app` = janela;
// modelos e diálogo de novo request injetados; o editor de auth exposto p/ a janela.
ColumnLayout {
    property var app
    property var newReqDialog
    property var collectionHeadersModel
    property var collectionVarsModel
    property alias authEditor: collectionAuthEditor
    spacing: 0
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        Kirigami.Icon { source: app.collectionIsSubfolder ? "folder" : "folder-documents"; implicitWidth: 48; implicitHeight: 48; color: Kirigami.Theme.highlightColor }
        ColumnLayout {
            spacing: 0
            Label { text: app.collectionPath.split("/").pop(); font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 6 }
            Label { text: app.collectionIsSubfolder ? Strings.t.folder : Strings.t.collection; opacity: 0.6 }
        }
        Item { Layout.fillWidth: true }
        Button { icon.name: "document-new"; text: Strings.t.newRequest; onClicked: newReqDialog.openIn(app.collectionPath) }
    }
    Kirigami.Separator { Layout.fillWidth: true }
    TabBar {
        id: collectionTabBar
        visible: !app.collectionIsSubfolder
        Layout.fillWidth: true
        currentIndex: app.collectionTab
        onCurrentIndexChanged: { app.collectionTab = currentIndex; if (currentIndex === 0) app.refreshCollectionResolved(); }
        TabButton { text: Strings.t.overview }
        TabButton { text: Strings.t.headers }
        TabButton { text: Strings.t.variables }
        TabButton { text: Strings.t.authentication }
    }
    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: app.collectionIsSubfolder ? 0 : app.collectionTab
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
                Label { text: "~/catarina-collections/" + app.collectionPath; opacity: 0.8 }
                Label { text: Strings.t.requests; font.bold: true }
                Label { text: app.collectionRequests.length }
                Label { text: Strings.t.subfolders; font.bold: true }
                Label { text: app.collectionFolders }
            }
            Kirigami.Separator { Layout.fillWidth: true }
            Label {
                visible: app.collectionIsSubfolder
                text: Strings.t.folderHint
                opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Label {
                visible: !app.collectionIsSubfolder
                text: Strings.t.effectiveVariables
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
            }
            ResolvedVarsTable {
                id: collectionResolvedTable
                visible: !app.collectionIsSubfolder && collectionResolvedTable.count > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(200, 24 + collectionResolvedTable.count * 24)
                vars: app.collectionResolvedVars
            }
            Label {
                visible: !app.collectionIsSubfolder && collectionResolvedTable.count === 0
                text: Strings.t.noCollectionVariables
                opacity: 0.6
            }
            Kirigami.Separator { Layout.fillWidth: true }
            Label { text: app.collectionIsSubfolder ? Strings.t.requestsInFolder : Strings.t.requestsInCollection; font.bold: true; font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1 }
            Repeater {
                model: app.collectionRequests
                delegate: ItemDelegate {
                    Layout.fillWidth: true
                    onClicked: { app.revealPath(modelData.relPath); app.openRequest(modelData.relPath); }
                    contentItem: RowLayout {
                        spacing: 6
                        MethodBadge {
                            method: modelData.method
                            color: app.methodColor(modelData.method)
                        }
                        Label { Layout.fillWidth: true; text: modelData.name }
                    }
                }
            }
            Label { visible: app.collectionRequests.length === 0; text: app.collectionIsSubfolder ? Strings.t.noRequestsInFolder : Strings.t.noRequestsInCollection; opacity: 0.6 }
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
                dirty: app.collectionHeadersDirty
                showDiscard: true
                onSave: app.saveCollectionHeaders()
                onDiscard: app.revertCollectionHeaders()
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
                resolved: app.collectionResolvedVars
                collection: app.collectionPath
                onAddRequested: collectionHeadersModel.append({ name: "", value: "", enabled: true })
                onEdited: app.recomputeCollectionDirty()
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
                dirty: app.collectionVarsDirty
                canSave: app.collectionVarsWarning.length === 0
                showDiscard: true
                onSave: app.saveCollectionVars()
                onDiscard: app.revertCollectionVars()
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
                resolved: app.collectionResolvedVars
                collection: app.collectionPath
                onAddRequested: collectionVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "" })
                onEdited: { app.recomputeCollectionDirty(); app.refreshCollectionResolved(); app.updateVarsWarnings(); }
            }
        }
    }

    // 3) autenticação
    Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
            SaveBar {
                Layout.fillWidth: true
                title: Strings.t.collectionAuth
                dirty: app.collectionAuthDirty
                showDiscard: true
                onSave: app.saveCollectionAuth()
                onDiscard: app.revertCollectionAuth()
            }
            Label {
                text: Strings.t.collectionAuthHint
                opacity: 0.6; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            AuthEditor {
                id: collectionAuthEditor
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                resolvedVars: app.collectionResolvedVars
                collection: app.collectionPath
                onEdited: app.recomputeCollectionDirty()
            }
        }
    }
    }
}
