import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// "Variables" tab: editable (top) + resolved effective ones (bottom), draggable divider.
SplitView {
    property var app
    property var requestVarsModel
    id: requestVarsSplit
    orientation: Qt.Vertical
    handle: SplitGrip {}

    KvTable {
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        SplitView.minimumHeight: Kirigami.Units.gridUnit * 3
        model: requestVarsModel
        keyPlaceholder: Strings.t.variable
        secretColumn: true
        uniqueNames: true
        resolved: app.resolvedVars
        collection: app.currentCollection
        onAddRequested: requestVarsModel.append({ name: "", value: "", enabled: true, secret: false, secretId: "" })
        onEdited: { app.markDirty(); app.updateVarsWarnings(); }
    }
    Item {
        id: requestResolvedPane
        // opens at this size and won't let it shrink below it
        readonly property int defaultHeight: 190
        SplitView.fillWidth: true
        SplitView.preferredHeight: defaultHeight
        SplitView.minimumHeight: defaultHeight
        // ceiling = half the height; guards against the 0 of the first layout
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
                vars: app.resolvedVars
            }
            Label {
                visible: requestResolvedTable.count === 0
                text: Strings.t.noVariablesDefined
                opacity: 0.6
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            // with no table (count 0) nothing fills; the filler holds
            // the labels at the top instead of redistributing the space.
            Item {
                Layout.fillHeight: true
                visible: requestResolvedTable.count === 0
            }
        }
    }
}
