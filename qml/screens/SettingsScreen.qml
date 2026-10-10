import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// App settings screen (its own tab). `app` = window; `folderPicker` = FolderDialog.
Item {
    id: settingsPage
    property var app
    property var folderPicker
    property alias dirField: storageDirField   // exposed for Main to wire to FolderPicker
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
                    TextField { id: storageDirField; Layout.fillWidth: true; text: settings.storageDir }
                    Button { text: Strings.t.browse; onClicked: folderPicker.open() }
                    Button {
                        text: Strings.t.apply; highlighted: true
                        enabled: storageDirField.text.length > 0 && storageDirField.text !== backend.storageDir
                        onClicked: app.applyStorageDir(storageDirField.text)
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
                    model: app.shortcutDefs
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Label { text: modelData.label; Layout.fillWidth: true }
                        ShortcutField {
                            window: app
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
