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
    property int currentIndex: -1
    width: 480
    height: 330
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Kirigami.Units.smallSpacing
    x: Math.max(0, (parent ? parent.width - width : 0) / 2)
    y: Kirigami.Units.gridUnit

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
            model: tabSearch.matches
            currentIndex: tabSearch.currentIndex
            delegate: Rectangle {
                width: resultList.width
                height: rowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: 4
                color: index === tabSearch.currentIndex ? app.theme.selectionTint : "transparent"
                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing
                    Label {
                        objectName: "tabSearchLabel"
                        text: modelData.label
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.maximumWidth: 150
                    }
                    Label {
                        objectName: "tabSearchSnippet"
                        text: modelData.snippet
                        elide: Text.ElideRight
                        opacity: app.theme.textInformational
                        Layout.fillWidth: true
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: tabSearch.activate(modelData)
                }
            }
        }

        Label {
            objectName: "tabSearchEmpty"
            visible: tabSearch.matches.length === 0
            text: Strings.t.tabSearchNoMatches
            opacity: app.theme.textInformational
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
