import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings
import "../Util.js" as Util

// Tab search (Ctrl+Shift+A): searches the open request's URL, tables and body,
// and navigates to the selected match. `app` = window controller; `editor` is
// the RequestEditor that owns this popup.
Popup {
    id: tabSearch
    objectName: "tabSearch"
    property var app
    property var editor
    property var matches: []
    readonly property int matchCount: matches.length
    readonly property bool hasQuery: searchField.text.length > 0
    property int currentIndex: -1
    parent: editor
    readonly property int margin: Kirigami.Units.gridUnit
    width: parent ? Math.min(480, parent.width - margin * 2) : 480
    height: 330
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Kirigami.Units.smallSpacing
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: margin

    function surfaceName(surface) {
        var names = { url: "URL", params: "Params", headers: "Headers",
                      fields: "Fields", vars: "Vars", body: "Body" };
        return names[surface] || "";
    }
    function refresh() {
        matches = editor && app ? Util.tabSearchMatches(app.collectRequest(), searchField.text) : [];
        currentIndex = matches.length > 0 ? 0 : -1;
    }
    function move(dir) {
        if (matches.length === 0) return;
        currentIndex = (currentIndex + dir + matches.length) % matches.length;
        resultList.positionViewAtIndex(currentIndex, ListView.Contain);
    }
    function activate(m) {
        close();
        if (!m || !editor) return;
        if (m.surface === "url") editor.revealUrlMatch();
        else if (m.surface === "body") editor.revealBodyRange(m.start, m.end);
        else editor.revealTableRow(m.surface, m.index);
    }
    onOpened: {
        searchField.text = "";
        refresh();
        searchField.forceActiveFocus();
    }

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        radius: app ? app.theme.radiusPanel : 8
        border.width: 1
        border.color: Kirigami.Theme.disabledTextColor
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        TextField {
            id: searchField
            objectName: "tabSearchField"
            Layout.fillWidth: true
            placeholderText: Strings.t.tabSearchPlaceholder
            onTextChanged: tabSearch.refresh()
            Keys.onDownPressed: tabSearch.move(1)
            Keys.onUpPressed: tabSearch.move(-1)
            Keys.onReturnPressed: tabSearch.activate(tabSearch.currentIndex >= 0
                                                   ? tabSearch.matches[tabSearch.currentIndex] : null)
            Keys.onEnterPressed: tabSearch.activate(tabSearch.currentIndex >= 0
                                                   ? tabSearch.matches[tabSearch.currentIndex] : null)
            Keys.onEscapePressed: tabSearch.close()
        }

        ListView {
            id: resultList
            objectName: "tabSearchList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: tabSearch.hasQuery && tabSearch.matches.length > 0
            model: tabSearch.matches
            currentIndex: tabSearch.currentIndex
            delegate: Rectangle {
                width: resultList.width
                height: Math.max(Math.round(44 * (app ? app.theme.uiScale : 1)),
                                 rowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2)
                radius: 4
                color: index === tabSearch.currentIndex ? app.theme.selectionTint : "transparent"
                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing
                    // the surface the match lives in (URL, Params, Headers, …)
                    Label {
                        objectName: "tabSearchSurface"
                        text: tabSearch.surfaceName(modelData.surface)
                        font.pixelSize: app.theme.fontSizeMeta
                        opacity: app.theme.textInformational
                        Layout.preferredWidth: 64
                        Layout.maximumWidth: 64
                        elide: Text.ElideRight
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            objectName: "tabSearchLabel"
                            text: modelData.label
                            font.pixelSize: app.theme.fontSizeBase
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            objectName: "tabSearchSnippet"
                            text: modelData.snippet
                            font.pixelSize: app.theme.fontSizeMeta
                            elide: Text.ElideRight
                            opacity: app.theme.textInformational
                            Layout.fillWidth: true
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: tabSearch.activate(modelData)
                }
            }
        }

        Label {
            objectName: "tabSearchEmptyHint"
            visible: !tabSearch.hasQuery
            text: Strings.t.tabSearchEmptyHint
            font.pixelSize: app.theme.fontSizeMeta
            opacity: app.theme.textInformational
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            objectName: "tabSearchEmpty"
            visible: tabSearch.hasQuery && tabSearch.matches.length === 0
            text: Strings.notFound(searchField.text)
            font.pixelSize: app.theme.fontSizeMeta
            opacity: app.theme.textInformational
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
