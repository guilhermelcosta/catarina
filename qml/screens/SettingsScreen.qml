import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings

// App settings screen (its own tab). Two panes: a 190 px category nav and the
// card pane. Every control writes its setting on change — there is no Apply.
// `app` = window; `folderPicker` = FolderDialog. docs/DESIGN.md §5.
Item {
    id: settingsPage
    property var app
    property var folderPicker
    property alias dirField: storageDirField   // exposed for Main to wire to FolderPicker
    readonly property var tokens: app.theme

    // active category, not persisted (Appearance on open)
    property int settingsCategory: 0
    // rows per category, filled once the tree exists (search needs rowSearch)
    property var cardRows: []
    readonly property string query: settingsSearch.text.toLowerCase()

    readonly property var categories: [
        { name: Strings.t.appearance },
        { name: Strings.t.editor },
        { name: Strings.t.network },
        { name: Strings.t.behavior },
        { name: Strings.t.shortcuts },
        { name: Strings.t.storage },
        { name: Strings.t.about }
    ]

    function rowMatches(row) {
        return query.length === 0 || String(row.rowSearch).indexOf(query) >= 0
    }
    function shortcutMatches() {
        if (query.length === 0) return false;
        for (var i = 0; i < app.shortcutDefs.length; i++)
            if (String(app.shortcutDefs[i].label).toLowerCase().indexOf(query) >= 0) return true;
        return false;
    }
    function cardShown(index) {
        var rows = cardRows[index] || [];
        if (query.length === 0)
            return settingsCategory === index;
        for (var i = 0; i < rows.length; i++)
            if (String(rows[i].rowSearch).indexOf(query) >= 0) return true;
        if (index === 4) return shortcutMatches();
        return false;
    }
    function anyMatch() {
        for (var c = 0; c < 7; c++)
            if (cardShown(c)) return true;
        return false;
    }

    // Ctrl+/ and the status-bar hint land here: select the Shortcuts category.
    function focusShortcuts() {
        settingsCategory = 4;
    }
    // Ctrl+F while the settings tab is shown
    function focusSearch() {
        settingsSearch.forceActiveFocus();
        settingsSearch.selectAll();
    }

    Component.onCompleted: cardRows = [
        [themeRow, accentRow, densityRow, scaleRow],
        [fontFamilyRow, fontSizeRow, lineNumbersRow, wrapRow, indentRow, bracketsRow],
        [timeoutRow, ignoreSslRow],
        [confirmDeleteRow, autoSaveRow],
        [],
        [storageRow],
        [aboutAppRow, aboutQtRow, aboutLicenceRow]
    ]

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // ---------- category nav (190 px) ----------
        ListView {
            id: settingsNav
            objectName: "settingsNav"
            Layout.preferredWidth: 190
            Layout.minimumWidth: 190
            Layout.maximumWidth: 190
            Layout.fillHeight: true
            clip: true
            model: settingsPage.categories
            interactive: false

            delegate: ItemDelegate {
                width: ListView.view.width
                implicitHeight: settingsPage.tokens.settingsRowHeight
                text: modelData.name
                highlighted: settingsPage.settingsCategory === index
                onClicked: settingsPage.settingsCategory = index
                contentItem: Label {
                    leftPadding: 8
                    text: modelData.name
                    elide: Text.ElideRight
                    font.bold: settingsPage.settingsCategory === index
                    font.pixelSize: settingsPage.tokens.fontSizeBase
                }
            }
        }

        // ---------- search + cards ----------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                TextField {
                    id: settingsSearch
                    objectName: "settingsSearch"
                    Layout.fillWidth: true
                    placeholderText: Strings.t.settingsSearchPlaceholder
                    Keys.onEscapePressed: text = ""
                }

                ScrollView {
                    id: settingsScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ColumnLayout {
                        objectName: "settingsForm"
                        width: settingsScroll.availableWidth
                        spacing: Kirigami.Units.smallSpacing

                        SettingsCard {
                            objectName: "settingsCard.appearance"
                            tokens: settingsPage.tokens
                            title: Strings.t.appearance
                            Layout.fillWidth: true
                            visible: settingsPage.cardShown(0)
                            SettingsRow {
                                id: themeRow
                                objectName: "settingsRow.theme"
                                tokens: settingsPage.tokens
                                label: Strings.t.themeLabel
                                description: Strings.t.themeDescription
                                visible: settingsPage.rowMatches(themeRow)
                                ComboBox {
                                    id: themeCombo
                                    objectName: "settingsTheme"
                                    Layout.fillWidth: true
                                    model: [Strings.t.themeSystem, Strings.t.themeLight, Strings.t.themeDark]
                                    Component.onCompleted: currentIndex = settingsPage.schemeIndex(backend.colorScheme)
                                    onActivated: backend.colorScheme = index === 1 ? "light"
                                                                   : (index === 2 ? "dark" : "system")
                                    Connections {
                                        target: backend
                                        function onColorSchemeChanged() {
                                            themeCombo.currentIndex = settingsPage.schemeIndex(backend.colorScheme);
                                        }
                                    }
                                }
                            }
                            SettingsRow {
                                id: accentRow
                                objectName: "settingsRow.accent"
                                tokens: settingsPage.tokens
                                label: Strings.t.accentLabel
                                description: Strings.t.accentDescription
                                visible: settingsPage.rowMatches(accentRow)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    ComboBox {
                                        id: accentCombo
                                        Layout.fillWidth: true
                                        model: [Strings.t.accentFollowSystem, Strings.t.accentCustom]
                                        Component.onCompleted: currentIndex = settings.accentColor.length > 0 ? 1 : 0
                                        onActivated: {
                                            if (index === 1) accentDialog.open();
                                            else settings.accentColor = "";
                                        }
                                    }
                                    Rectangle {
                                        visible: settings.accentColor.length > 0
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        radius: 4
                                        color: settings.accentColor
                                        border.width: 1
                                        border.color: settingsPage.tokens.chromeBorder
                                    }
                                }
                            }
                            SettingsRow {
                                id: densityRow
                                objectName: "settingsRow.density"
                                tokens: settingsPage.tokens
                                label: Strings.t.densityLabel
                                description: Strings.t.densityDescription
                                visible: settingsPage.rowMatches(densityRow)
                                ComboBox {
                                    id: densityCombo
                                    Layout.fillWidth: true
                                    model: [Strings.t.densityComfortable, Strings.t.densityCompact]
                                    Component.onCompleted: currentIndex = settings.density === "compact" ? 1 : 0
                                    onActivated: settings.density = index === 1 ? "compact" : "comfortable"
                                }
                            }
                            SettingsRow {
                                id: scaleRow
                                objectName: "settingsRow.uiScale"
                                tokens: settingsPage.tokens
                                label: Strings.t.uiScale
                                description: Strings.t.uiScaleDescription
                                visible: settingsPage.rowMatches(scaleRow)
                                SpinBox {
                                    id: scaleSpin
                                    objectName: "settingsUiScale"
                                    Layout.fillWidth: true
                                    from: 100
                                    to: 150
                                    stepSize: 5
                                    value: Math.round(settings.uiScale * 100)
                                    textFromValue: function (v) { return (v / 100).toFixed(2) + " ×" }
                                    valueFromText: function (text) { return Math.round(parseFloat(text) * 100) }
                                    onValueModified: settings.uiScale = value / 100
                                    Connections {
                                        target: settings
                                        function onSettingsChanged() {
                                            scaleSpin.value = Math.round(settings.uiScale * 100);
                                        }
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            objectName: "settingsCard.editor"
                            tokens: settingsPage.tokens
                            title: Strings.t.editor
                            Layout.fillWidth: true
                            visible: settingsPage.cardShown(1)
                            SettingsRow {
                                id: fontFamilyRow
                                objectName: "settingsRow.editorFontFamily"
                                tokens: settingsPage.tokens
                                label: Strings.t.editorFontFamily
                                description: Strings.t.editorFontFamilyDescription
                                visible: settingsPage.rowMatches(fontFamilyRow)
                                ComboBox {
                                    id: fontFamilyCombo
                                    objectName: "settingsEditorFontFamily"
                                    Layout.fillWidth: true
                                    model: [Strings.t.editorFontDefault].concat(backend.monospaceFamilies())
                                    Component.onCompleted: currentIndex = settingsPage.fontFamilyIndex()
                                    onActivated: settings.editorFontFamily = index === 0 ? "" : model[index]
                                }
                            }
                            SettingsRow {
                                id: fontSizeRow
                                objectName: "settingsRow.editorFontSize"
                                tokens: settingsPage.tokens
                                label: Strings.t.editorFontSize
                                description: Strings.t.editorFontSizeDescription
                                visible: settingsPage.rowMatches(fontSizeRow)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    SpinBox {
                                        id: sizeSpin
                                        objectName: "settingsEditorFontSize"
                                        Layout.fillWidth: true
                                        from: 6
                                        to: 28
                                        value: settings.editorFontSizeResolved
                                        onValueModified: settings.editorFontSize = value
                                        Connections {
                                            target: settings
                                            function onSettingsChanged() {
                                                sizeSpin.value = settings.editorFontSizeResolved;
                                            }
                                        }
                                    }
                                    Label {
                                        objectName: "editorFontPreview"
                                        text: "Aa"
                                        font.family: settings.editorFontResolved
                                        font.pointSize: settings.editorFontSizeResolved
                                    }
                                }
                            }
                            SettingsRow {
                                id: lineNumbersRow
                                objectName: "settingsRow.editorLineNumbers"
                                tokens: settingsPage.tokens
                                label: Strings.t.editorLineNumbers
                                description: Strings.t.editorLineNumbersDescription
                                visible: settingsPage.rowMatches(lineNumbersRow)
                                Switch {
                                    Layout.alignment: Qt.AlignRight
                                    checked: settings.editorLineNumbers
                                    onToggled: settings.editorLineNumbers = checked
                                }
                            }
                            SettingsRow {
                                id: wrapRow
                                objectName: "settingsRow.editorWrap"
                                tokens: settingsPage.tokens
                                label: Strings.t.editorWrap
                                description: Strings.t.editorWrapDescription
                                visible: settingsPage.rowMatches(wrapRow)
                                Switch {
                                    Layout.alignment: Qt.AlignRight
                                    checked: settings.editorWrap
                                    onToggled: settings.editorWrap = checked
                                }
                            }
                            SettingsRow {
                                id: indentRow
                                objectName: "settingsRow.editorIndent"
                                tokens: settingsPage.tokens
                                label: Strings.t.editorIndent
                                description: Strings.t.editorIndentDescription
                                visible: settingsPage.rowMatches(indentRow)
                                ComboBox {
                                    id: indentCombo
                                    Layout.fillWidth: true
                                    model: [2, 4]
                                    Component.onCompleted: currentIndex = settings.editorIndent === 4 ? 1 : 0
                                    onActivated: settings.editorIndent = model[index]
                                    Connections {
                                        target: settings
                                        function onSettingsChanged() {
                                            indentCombo.currentIndex = settings.editorIndent === 4 ? 1 : 0;
                                        }
                                    }
                                }
                            }
                            SettingsRow {
                                id: bracketsRow
                                objectName: "settingsRow.editorBrackets"
                                tokens: settingsPage.tokens
                                label: Strings.t.editorBrackets
                                description: Strings.t.editorBracketsDescription
                                visible: settingsPage.rowMatches(bracketsRow)
                                Switch {
                                    Layout.alignment: Qt.AlignRight
                                    checked: settings.editorBrackets
                                    onToggled: settings.editorBrackets = checked
                                }
                            }
                        }

                        SettingsCard {
                            objectName: "settingsCard.network"
                            tokens: settingsPage.tokens
                            title: Strings.t.network
                            Layout.fillWidth: true
                            visible: settingsPage.cardShown(2)
                            SettingsRow {
                                id: timeoutRow
                                tokens: settingsPage.tokens
                                label: Strings.t.timeoutSeconds
                                description: Strings.t.noLimit
                                visible: settingsPage.rowMatches(timeoutRow)
                                SpinBox {
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 600
                                    value: settings.timeoutSec
                                    onValueModified: settings.timeoutSec = value
                                }
                            }
                            SettingsRow {
                                id: ignoreSslRow
                                tokens: settingsPage.tokens
                                label: Strings.t.ignoreSsl
                                visible: settingsPage.rowMatches(ignoreSslRow)
                                Switch {
                                    Layout.alignment: Qt.AlignRight
                                    checked: settings.ignoreSsl
                                    onToggled: settings.ignoreSsl = checked
                                }
                            }
                        }

                        SettingsCard {
                            objectName: "settingsCard.behavior"
                            tokens: settingsPage.tokens
                            title: Strings.t.behavior
                            Layout.fillWidth: true
                            visible: settingsPage.cardShown(3)
                            SettingsRow {
                                id: confirmDeleteRow
                                tokens: settingsPage.tokens
                                label: Strings.t.confirmDeleteOption
                                visible: settingsPage.rowMatches(confirmDeleteRow)
                                Switch {
                                    Layout.alignment: Qt.AlignRight
                                    checked: settings.confirmDelete
                                    onToggled: settings.confirmDelete = checked
                                }
                            }
                            SettingsRow {
                                id: autoSaveRow
                                tokens: settingsPage.tokens
                                label: Strings.t.autoSaveOnSend
                                visible: settingsPage.rowMatches(autoSaveRow)
                                Switch {
                                    Layout.alignment: Qt.AlignRight
                                    checked: settings.autoSaveOnSend
                                    onToggled: settings.autoSaveOnSend = checked
                                }
                            }
                        }

                        SettingsCard {
                            objectName: "settingsCard.shortcuts"
                            tokens: settingsPage.tokens
                            title: Strings.t.shortcuts
                            Layout.fillWidth: true
                            visible: settingsPage.cardShown(4)
                            Label {
                                Layout.fillWidth: true
                                text: Strings.t.shortcutsHint
                                opacity: 0.75
                                wrapMode: Text.WordWrap
                                visible: settingsPage.query.length === 0
                            }
                            Repeater {
                                model: app.shortcutDefs
                                delegate: SettingsRow {
                                    Layout.fillWidth: true
                                    tokens: settingsPage.tokens
                                    label: modelData.label
                                    visible: settingsPage.query.length === 0
                                             || String(modelData.label).toLowerCase().indexOf(settingsPage.query) >= 0
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing
                                        ShortcutField {
                                            Layout.fillWidth: true
                                            window: settingsPage.app
                                            sequence: {
                                                var m = settings.shortcuts;
                                                return (m && m[modelData.id] !== undefined) ? m[modelData.id] : modelData.def;
                                            }
                                            onCaptured: function (seq) { settings.setShortcut(modelData.id, seq); }
                                        }
                                        ToolButton {
                                            Layout.alignment: Qt.AlignRight
                                            icon.name: "edit-undo"
                                            enabled: { var m = settings.shortcuts; return m !== undefined && m[modelData.id] !== undefined; }
                                            onClicked: settings.resetShortcut(modelData.id)
                                            ToolTip.text: Strings.t.restoreDefault; ToolTip.visible: hovered
                                        }
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            objectName: "settingsCard.storage"
                            tokens: settingsPage.tokens
                            title: Strings.t.storage
                            Layout.fillWidth: true
                            visible: settingsPage.cardShown(5)
                            SettingsRow {
                                id: storageRow
                                objectName: "settingsRow.storage"
                                tokens: settingsPage.tokens
                                label: Strings.t.collectionsFolder
                                description: Strings.t.storageDirHint
                                visible: settingsPage.rowMatches(storageRow)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    TextField {
                                        id: storageDirField
                                        Layout.fillWidth: true
                                        text: settings.storageDir
                                        onEditingFinished: settingsPage.applyStorage()
                                    }
                                    ToolButton {
                                        icon.name: "folder-open"
                                        onClicked: settingsPage.folderPicker.open()
                                        ToolTip.text: Strings.t.browse; ToolTip.visible: hovered
                                    }
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: storageDirField.text.length > 0
                                         && !backend.canUseStorageDir(storageDirField.text)
                                text: Strings.t.storageDirInvalid
                                color: Kirigami.Theme.negativeTextColor
                                wrapMode: Text.WordWrap
                                font.pixelSize: settingsPage.tokens.fontSizeSecondary
                            }
                        }

                        SettingsCard {
                            objectName: "settingsCard.about"
                            tokens: settingsPage.tokens
                            title: Strings.t.aboutTitle
                            Layout.fillWidth: true
                            visible: settingsPage.cardShown(6)
                            SettingsRow {
                                id: aboutAppRow
                                tokens: settingsPage.tokens
                                label: Strings.t.appName
                                visible: settingsPage.rowMatches(aboutAppRow)
                                Label {
                                    Layout.alignment: Qt.AlignRight
                                    text: Strings.t.aboutVersion + " " + backend.appVersion
                                    font.pixelSize: settingsPage.tokens.fontSizeSecondary
                                    opacity: 0.75
                                }
                            }
                            SettingsRow {
                                id: aboutQtRow
                                tokens: settingsPage.tokens
                                label: Strings.t.aboutQtVersion
                                visible: settingsPage.rowMatches(aboutQtRow)
                                Label {
                                    Layout.alignment: Qt.AlignRight
                                    text: backend.qtVersion
                                    font.pixelSize: settingsPage.tokens.fontSizeSecondary
                                    opacity: 0.75
                                }
                            }
                            SettingsRow {
                                id: aboutLicenceRow
                                tokens: settingsPage.tokens
                                label: Strings.t.aboutLicense
                                visible: settingsPage.rowMatches(aboutLicenceRow)
                                Label {
                                    Layout.alignment: Qt.AlignRight
                                    text: "GPLv3"
                                    font.pixelSize: settingsPage.tokens.fontSizeSecondary
                                    opacity: 0.75
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            text: Strings.t.settingsSubtitle
                            opacity: 0.75
                            font.pixelSize: settingsPage.tokens.fontSizeSecondary
                            visible: settingsPage.query.length === 0
                        }
                    }
                }
            }

            EmptyState {
                objectName: "settingsEmptyState"
                anchors.centerIn: parent
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                visible: settingsPage.query.length > 0 && !settingsPage.anyMatch()
                title: Strings.t.settingsNoMatches
                message: Strings.t.settingsSearchPlaceholder
            }
        }
    }

    // -------- helpers --------
    function schemeIndex(scheme) {
        return scheme === "light" ? 1 : (scheme === "dark" ? 2 : 0);
    }
    function fontFamilyIndex() {
        if (settings.editorFontFamily.length === 0) return 0;
        var families = backend.monospaceFamilies();
        var i = families.indexOf(settings.editorFontFamily);
        return i >= 0 ? i + 1 : 0;
    }
    function applyStorage() {
        var dir = storageDirField.text;
        if (dir.length === 0 || dir === backend.storageDir)
            return;
        if (backend.canUseStorageDir(dir))
            app.applyStorageDir(dir);
    }

    // ---- accent picker: applied only on accepted ----
    ColorDialog {
        id: accentDialog
        title: Strings.t.accentCustom
        selectedColor: settings.accentColor.length > 0 ? settings.accentColor : Kirigami.Theme.highlightColor
        onAccepted: {
            settings.accentColor = color;
            accentCombo.currentIndex = 1;
        }
        onRejected: accentCombo.currentIndex = settings.accentColor.length > 0 ? 1 : 0
    }
}
