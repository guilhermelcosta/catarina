import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// Collection screen (overview/headers/variables/authentication). `app` = window;
// models and new-request dialog injected; the auth editor exposed to the window.
ColumnLayout {
    id: collectionScreen
    property var app
    property var newReqDialog
    property var collectionHeadersModel
    property var collectionVarsModel
    property alias authEditor: collectionAuthEditor
    // curated Breeze names, all confirmed in the theme (docs/DESIGN.md §4)
    readonly property var identityIcons: app.collectionIcons
    property var collectionIdentity: ({ icon: "", color: "" })
    function refreshIdentity() {
        if (app.collectionIsSubfolder) {
            collectionIdentity = ({ icon: "", color: "" });
            return;
        }
        var id = backend.collectionIdentity(app.collectionPath);
        collectionIdentity = ({ icon: id.icon !== undefined ? id.icon : "",
                                color: id.color !== undefined ? id.color : "" });
    }
    function writeIdentity(icon, color) {
        if (backend.setCollectionIdentity(app.collectionPath, icon, color))
            refreshIdentity();
    }
    Component.onCompleted: refreshIdentity()
    Connections {
        target: app
        function onCollectionPathChanged() { refreshIdentity(); }
    }
    Connections {
        target: backend
        function onCollectionsChanged() { refreshIdentity(); }
    }
    spacing: 0
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        Kirigami.Icon {
            source: app.collectionIsSubfolder ? "folder"
                  : (collectionIdentity.icon.length > 0
                     ? app.collectionIcon(collectionIdentity.icon) : "folder-documents")
            implicitWidth: 48; implicitHeight: 48
            color: collectionIdentity.color.length > 0 ? collectionIdentity.color
                                                       : Kirigami.Theme.highlightColor
        }
        ColumnLayout {
            spacing: 0
            Label { text: app.collectionPath.split("/").pop(); font.bold: true; font.pixelSize: app.theme.fontSizeCollectionTitle }
            Label { text: app.collectionIsSubfolder ? Strings.t.folder : Strings.t.collection; opacity: 0.75 }
        }
        // identity of a top-level collection only (subfolders have none)
        RowLayout {
            objectName: "collectionIdentityRow"
            visible: !app.collectionIsSubfolder
            Layout.leftMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing
            Label { text: Strings.t.collectionIcon; opacity: app.theme.textInformational }
            ComboBox {
                id: iconCombo
                objectName: "collectionIconCombo"
                implicitWidth: 180
                model: [Strings.t.resetIcon].concat(collectionScreen.identityIcons)
                currentIndex: {
                    var i = collectionIdentity.icon.length > 0
                            ? collectionScreen.identityIcons.indexOf(collectionIdentity.icon) : -1;
                    return i < 0 ? 0 : i + 1;
                }
                onActivated: writeIdentity(index === 0 ? "" : model[index],
                                           collectionIdentity.color)
            }
            Label { text: Strings.t.collectionColour; opacity: app.theme.textInformational }
            Rectangle {
                objectName: "collectionColorChip"
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: collectionIdentity.color.length > 0
                       ? collectionIdentity.color : "transparent"
                border.width: 1
                border.color: app.theme.chromeBorder
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: collectionColorDialog.open()
                }
            }
            ToolButton {
                objectName: "collectionColorReset"
                icon.name: "edit-clear"
                visible: collectionIdentity.color.length > 0
                onClicked: writeIdentity(collectionIdentity.icon, "")
                ToolTip.text: Strings.t.resetColour; ToolTip.visible: hovered
            }
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
                Label { text: backend.storageDir + "/" + app.collectionPath; opacity: 0.8 }
                Label { text: Strings.t.requests; font.bold: true }
                Label { text: app.collectionRequests.length }
                Label { text: Strings.t.subfolders; font.bold: true }
                Label { text: app.collectionFolders }
            }
            Kirigami.Separator { Layout.fillWidth: true }
            Label {
                visible: app.collectionIsSubfolder
                text: Strings.t.folderHint
                opacity: 0.75; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Label {
                visible: !app.collectionIsSubfolder
                text: Strings.t.effectiveVariables
                font.bold: true
                font.pixelSize: app.theme.fontSizeEmphasis
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
                opacity: 0.75
            }
            Kirigami.Separator { Layout.fillWidth: true }
            Label { text: app.collectionIsSubfolder ? Strings.t.requestsInFolder : Strings.t.requestsInCollection; font.bold: true; font.pixelSize: app.theme.fontSizeEmphasis }
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
            Label { visible: app.collectionRequests.length === 0; text: app.collectionIsSubfolder ? Strings.t.noRequestsInFolder : Strings.t.noRequestsInCollection; opacity: 0.75 }
        }
    }

    // 1) headers
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
                opacity: 0.75; wrapMode: Text.WordWrap; Layout.fillWidth: true
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

    // 2) variables
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
                opacity: 0.75; wrapMode: Text.WordWrap; Layout.fillWidth: true
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

    // 3) authentication
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
                opacity: 0.75; wrapMode: Text.WordWrap; Layout.fillWidth: true
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

    // custom identity colour: writes only on accepted
    ColorDialog {
        id: collectionColorDialog
        objectName: "collectionColorDialog"
        title: Strings.t.collectionColour
        selectedColor: collectionIdentity.color.length > 0
                       ? collectionIdentity.color : Kirigami.Theme.highlightColor
        onAccepted: writeIdentity(collectionIdentity.icon, color)
    }
}
