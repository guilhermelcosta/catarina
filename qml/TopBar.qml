import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "Strings.js" as Strings

// One 40 px row: breadcrumb on the left, panel toggles + environment pill +
// one overflow (History/Settings) on the right. No logo, no wordmark.
// `app` = AppController (the window's controller). docs/DESIGN.md §2 "Chrome".
Item {
    id: topBar
    objectName: "topBar"
    property var app
    implicitHeight: app.theme.topBarHeight
    Layout.fillWidth: true

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // ---- breadcrumb: context, not a menu ----
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            Layout.maximumWidth: topBar.width * 0.45

            Label {
                id: crumbCollection
                objectName: "topBarBreadcrumb"
                Layout.maximumWidth: topBar.width * 0.4
                text: app.breadcrumbCollection.length > 0
                      ? app.breadcrumbCollection : Strings.t.noRequestOpen
                elide: Text.ElideRight
                font.pixelSize: app.theme.fontSizeSecondary
                opacity: app.breadcrumbRequest.length > 0 ? app.theme.textInformational
                       : (app.breadcrumbCollection.length > 0 ? 1 : app.theme.textInformational)
            }
            Label {
                id: crumbSeparator
                visible: app.breadcrumbRequest.length > 0
                text: Strings.t.breadcrumbSeparator
                font.pixelSize: app.theme.fontSizeSecondary
                opacity: app.theme.textDecoration
            }
            Label {
                id: crumbRequest
                objectName: "topBarBreadcrumbRequest"
                visible: app.breadcrumbRequest.length > 0
                Layout.maximumWidth: topBar.width * 0.4
                text: app.breadcrumbRequest
                elide: Text.ElideRight
                font.pixelSize: app.theme.fontSizeSecondary
            }
        }

        Item { Layout.fillWidth: true }

        // ---- panel toggles (unchanged bindings) ----
        RowLayout {
            spacing: 0
            ToolButton {
                objectName: "topBarSidebarToggle"
                checkable: true; checked: app.sidebarVisible
                icon.name: app.sidebarVisible ? "view-left-close" : "view-left-new"
                implicitWidth: app.theme.hitTarget
                implicitHeight: app.theme.controlToolbar
                onToggled: app.sidebarVisible = checked
                ToolTip.text: app.sidebarVisible ? Strings.t.hideCollections : Strings.t.showCollections
                ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            ToolButton {
                objectName: "topBarResponseToggle"
                checkable: true; checked: app.responseVisible
                icon.name: app.responseVisible ? "view-right-close" : "view-right-new"
                implicitWidth: app.theme.hitTarget
                implicitHeight: app.theme.controlToolbar
                onToggled: app.responseVisible = checked
                ToolTip.text: app.responseVisible ? Strings.t.hideResponse : Strings.t.showResponse
                ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // ---- environment: the one outlined control in the chrome ----
        Button {
            id: envPill
            objectName: "envPill"
            Layout.maximumWidth: 160
            Layout.preferredHeight: app.theme.controlToolbar
            leftPadding: Kirigami.Units.smallSpacing * 2
            rightPadding: Kirigami.Units.smallSpacing * 2
            topPadding: 0
            bottomPadding: 0
            text: app.activeEnv.length > 0 ? app.activeEnv : Strings.t.noEnvironment
            onClicked: envPopup.open()
            ToolTip.text: Strings.t.activeEnvironment
            ToolTip.delay: Kirigami.Units.toolTipDelay

            background: Rectangle {
                radius: app.theme.radiusControl
                color: envPill.hovered ? app.theme.hoverTint : "transparent"
                border.width: 1
                border.color: app.theme.chromeBorder
                Behavior on color {
                    ColorAnimation { duration: app.theme.hoverDurationMs; easing.type: Easing.InOutQuad }
                }
            }
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Label {
                    Layout.fillWidth: true
                    text: envPill.text
                    elide: Text.ElideRight
                    font.pixelSize: app.theme.fontSizeSecondary
                    opacity: app.activeEnv.length > 0 ? 1 : app.theme.textInformational
                }
                Kirigami.Icon {
                    objectName: "envPillChevron"
                    source: "arrow-down"
                    implicitWidth: app.theme.iconSize
                    implicitHeight: app.theme.iconSize
                    color: Kirigami.Theme.textColor
                }
            }
        }

        // ---- one overflow: History, then Settings ----
        ToolButton {
            id: overflowButton
            objectName: "topBarOverflow"
            icon.name: "overflow-menu"
            implicitWidth: app.theme.hitTarget
            implicitHeight: app.theme.controlToolbar
            onClicked: overflowMenu.popup(overflowButton)
            ToolTip.text: Strings.t.moreActions
            ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        Menu {
            id: overflowMenu
            objectName: "topBarOverflowMenu"
            background: Rectangle {
                radius: app.theme.radiusPanel
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: app.theme.chromeBorder
            }
            MenuItem {
                text: Strings.t.history
                onTriggered: app.historyDialog.openAndLoad()
            }
            MenuItem {
                text: Strings.t.settings
                onTriggered: app.openSettingsTab()
            }
        }
    }

    // ---- environment popup, anchored to the pill ----
    Popup {
        id: envPopup
        objectName: "envPopup"
        parent: envPill
        x: 0
        y: envPill.height + Kirigami.Units.smallSpacing
        width: 260
        padding: Kirigami.Units.smallSpacing
        onOpened: app.reloadEnvs()
        background: Rectangle {
            radius: app.theme.radiusPanel
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: app.theme.chromeBorder
        }
        ColumnLayout {
            width: envPopup.availableWidth
            spacing: Kirigami.Units.smallSpacing

            Label {
                visible: app.envList.length > 0
                text: Strings.t.activeEnvironment
                font.bold: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
            }
            Repeater {
                model: app.envList
                delegate: ItemDelegate {
                    Layout.fillWidth: true
                    text: modelData.name
                    font.bold: modelData.name === app.activeEnv
                    icon.name: modelData.name === app.activeEnv ? "checkmark" : ""
                    onClicked: {
                        app.activateEnv(modelData.name);
                        envPopup.close();
                    }
                }
            }

            ColumnLayout {
                visible: app.envList.length === 0
                spacing: Kirigami.Units.smallSpacing
                Label { text: Strings.t.readyToStart; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                Label {
                    text: Strings.t.createEnvHint
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter; opacity: app.theme.textInformational
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }
            ItemDelegate {
                Layout.fillWidth: true; text: Strings.t.createEnvironment; icon.name: "list-add"
                onClicked: { envPopup.close(); app.createEnvDialog.open(); }
            }
            ItemDelegate {
                Layout.fillWidth: true; text: Strings.t.manageVariables; icon.name: "configure"
                visible: app.envList.length > 0
                onClicked: { envPopup.close(); app.openEnvTab(app.activeEnv); }
            }
        }
    }
}
