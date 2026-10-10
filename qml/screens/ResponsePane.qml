import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."
import "../Strings.js" as Strings
import "../Util.js" as Util

// Response pane (body/tree/headers/cookies/network) + find and status.
// `app` = window; receives the backend's network signals directly.
Item {
    id: responsePane
    property var app
    property var responseHeaders: []
    property var responseCookies: ""
    property var netMeta: ({})
    property bool findVisible: false
    property int findMatchIndex: 0
    property int findMatchTotal: 0
    property string responseHint: ""
    function clearResponse() { setResponseBody(""); responseHeaders = []; netMeta = ({}); }

    function hint(text) { responseHint = text; }
    function openFind() {
        if (responseBody.text.length === 0) return;
        findVisible = true;
        findField.forceActiveFocus();
        findField.selectAll();
    }
    function closeFind() { findVisible = false; findMatchIndex = 0; findMatchTotal = 0; }
    function countMatches(q) {
        if (q.length === 0) return [];
        var body = responseBody.text, out = [], i = body.indexOf(q);
        while (i >= 0) { out.push(i); i = body.indexOf(q, i + q.length); }
        return out;
    }
    function updateFindCounter() {
        var q = findField.text;
        var all = countMatches(q);
        findMatchTotal = all.length;
        findMatchIndex = 0;
    }
    function findNext(backwards) {
        var q = findField.text;
        if (q.length === 0) { findMatchTotal = 0; findMatchIndex = 0; return; }
        var all = countMatches(q);
        findMatchTotal = all.length;
        if (all.length === 0) { findMatchIndex = 0; app.notify(Strings.notFound(q)); return; }
        var cur = backwards ? responseBody.selectionStart - 1 : responseBody.selectionEnd;
        var idx;
        if (backwards) {
            idx = all[all.length - 1];
            for (var i = all.length - 1; i >= 0; i--) if (all[i] <= cur) { idx = all[i]; break; }
        } else {
            idx = all[0];
            for (var j = 0; j < all.length; j++) if (all[j] >= cur) { idx = all[j]; break; }
        }
        findMatchIndex = all.indexOf(idx) + 1;
        var end = idx + q.length;
        responseBody.deselect();
        responseBody.select(idx, end);
        var r = responseBody.positionToRectangle(idx);
        var targetY = r.y - (bodyScroll.height / 2 - r.height / 2);
        bodyScroll.contentItem.contentY = Math.max(0, Math.min(targetY,
            Math.max(0, responseBody.contentHeight - bodyScroll.height + Kirigami.Units.smallSpacing)));
        bodyScroll.contentItem.contentX = 0;
    }
    function setResponseBody(body) {
        responseBody.text = body;   // full body: Ctrl+F searches all of the content
    }
    // parses the JSON only when the "Tree" tab is visible
    function syncJsonTree() {
        if (respTabBar.currentIndex !== 1) return;
        jsonTree.load(responseBody.text);
    }
    // caps the response cache (the app is lightweight; it doesn't keep everything forever)
    function evictResponses() {
        var MAX_ENTRIES = 15;
        var MAX_CHARS = 24 * 1024 * 1024;   // approximate cache ceiling
        var keys = Object.keys(app.responses);
        var total = 0;
        for (var i = 0; i < keys.length; i++) {
            var r = app.responses[keys[i]];
            total += (r && r.body ? r.body.length : 0);
        }
        while (keys.length > 1 && (keys.length > MAX_ENTRIES || total > MAX_CHARS)) {
            var k = keys.shift();
            var ev = app.responses[k];
            total -= (ev && ev.body ? ev.body.length : 0);
            delete app.responses[k];
        }
    }
    function restoreResponse(relPath) {
        var r = relPath.length > 0 ? app.responses[relPath] : undefined;
        if (r === undefined) {
            setResponseBody("");
            responseHeaders = [];
            responseCookies = "";
            netMeta = ({});
            syncJsonTree();
            statusLabel.text = "";
            timeLabel.text = "";
            sizeLabel.text = "";
        } else {
            statusLabel.text = r.status + " " + r.statusText;
            timeLabel.text = r.time;
            sizeLabel.text = r.size;
            responseHeaders = r.headers !== undefined ? r.headers : [];
            responseCookies = r.cookies !== undefined ? r.cookies : "";
            netMeta = r.meta !== undefined ? r.meta : ({});
            setResponseBody(r.body);
            syncJsonTree();
        }
    }
    function statusColor(t) {
        if (t.length === 0 || app.sending) return Kirigami.Theme.textColor;
        if (t === Strings.t.canceled) return Kirigami.Theme.disabledTextColor;
        var code = parseInt(t);
        if (!isNaN(code)) {
            if (code >= 200 && code < 300) return Kirigami.Theme.positiveTextColor;
            if (code >= 300 && code < 400) return Kirigami.Theme.neutralTextColor;
            if (code >= 400) return Kirigami.Theme.negativeTextColor;
        }
        return Kirigami.Theme.negativeTextColor;   // "Error: …"
    }

    Connections {
        target: backend
        function onStarted() { app.sending = true; statusLabel.text = Strings.t.sending; }
        function onCanceled() {
            app.sending = false;
            statusLabel.text = Strings.t.canceled; timeLabel.text = ""; sizeLabel.text = "";
        }
        function onResponseReady(status, statusText, headers, body, elapsedMs, sizeBytes) {
            app.sending = false;
            var cookieLines = [];
            for (var i = 0; i < headers.length; i++) {
                if (headers[i].name.toLowerCase() === "set-cookie")
                    cookieLines.push(headers[i].value);
            }
            var rec = { status: status, statusText: statusText, time: elapsedMs + " ms",
                        size: Util.fmtSize(sizeBytes), headers: headers,
                        cookies: cookieLines.join("\n"), body: body };
            // stores the response on the request tab (not on a collection tab)
            if (app.currentTab >= 0 && app.currentTab < app.tabsModel.count
                    && !app.tabsModel.get(app.currentTab).isCollection)
                app.responses[app.tabsModel.get(app.currentTab).relPath] = rec;
            evictResponses();
            statusLabel.text = status + " " + statusText;
            timeLabel.text = rec.time;
            sizeLabel.text = rec.size;
            responseHeaders = rec.headers;
            responseCookies = rec.cookies;
            setResponseBody(body);
            syncJsonTree();
        }
        function onError(code, args) {
            app.sending = false;
            statusLabel.text = Strings.backendError(code, args);
            timeLabel.text = ""; sizeLabel.text = "";
        }
        function onResponseMeta(meta) {
            netMeta = meta;
            // stores the meta alongside the current tab's response (to restore when switching tabs)
            if (app.currentTab >= 0 && app.currentTab < app.tabsModel.count
                    && !app.tabsModel.get(app.currentTab).isCollection
                    && !app.tabsModel.get(app.currentTab).isEnvironment) {
                var rp = app.tabsModel.get(app.currentTab).relPath;
                if (app.responses[rp] !== undefined)
                    app.responses[rp].meta = meta;
            }
        }
    }

    property real expandedWidth: 330
    // current width of the split item. Applied imperatively (not via a binding)
    // because dragging the handle makes SplitView overwrite preferredWidth, which
    // would destroy a binding and break the animation.
    property real splitWidth: 330
    SplitView.preferredWidth: splitWidth
    onSplitWidthChanged: SplitView.preferredWidth = splitWidth
    visible: app.responseVisible || splitWidth > 0.5
    // min follows the animation so collapse/expand slides instead of clamping
    SplitView.minimumWidth: app.responseVisible ? Math.min(230, splitWidth) : 0
    NumberAnimation { id: splitAnim; target: responsePane; property: "splitWidth"; duration: 160; easing.type: Easing.InOutQuad }
    Connections {
        target: app
        function onResponseVisibleChanged() {
            splitAnim.stop();
            if (app.responseVisible) {
                splitAnim.from = responsePane.splitWidth;
                splitAnim.to = responsePane.expandedWidth;
            } else {
                responsePane.expandedWidth = responsePane.width;   // remember the dragged size
                responsePane.splitWidth = responsePane.width;      // sync before collapsing
                splitAnim.from = responsePane.width;
                splitAnim.to = 0;
            }
            splitAnim.start();
        }
    }
    // keep the content at full width and clip it: collapsing slides it out
    // instead of squeezing the labels/badges to zero
    clip: true
    ColumnLayout {
        anchors.right: parent.right
        width: splitAnim.running ? responsePane.expandedWidth : responsePane.width
        height: responsePane.height
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2   // reserves the height even with no response
            spacing: Kirigami.Units.smallSpacing
            Rectangle {
                visible: statusLabel.text.length > 0
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: statusLabel.implicitWidth + 14
                implicitHeight: statusLabel.implicitHeight + 6
                radius: 4
                color: Qt.rgba(statusColor(statusLabel.text).r,
                               statusColor(statusLabel.text).g,
                               statusColor(statusLabel.text).b, 0.18)
                Label {
                    id: statusLabel
                    anchors.centerIn: parent
                    font.bold: true
                    elide: Text.ElideRight
                    color: statusColor(text)
                }
            }
            Item { Layout.fillWidth: true }
            Label { id: timeLabel; visible: text.length > 0; opacity: 0.7 }
            Label { id: sizeLabel; visible: text.length > 0; opacity: 0.7 }
            ToolButton {
                visible: responseBody.text.length > 0
                icon.name: "edit-copy"; text: Strings.t.copy
                display: AbstractButton.TextBesideIcon
                onClicked: { varSupport.copyText(responseBody.text.length > 0 ? responseBody.text : ""); app.notify(Strings.t.responseCopied); }
                onHoveredChanged: hint(hovered ? Strings.t.copyResponse : "")
            }
            ToolButton {
                visible: responseBody.text.length > 0
                icon.name: "edit-find"
                onClicked: openFind()
                onHoveredChanged: hint(hovered ? Strings.t.findTooltip : "")
            }
        }

        TabBar {
            id: respTabBar
            Layout.fillWidth: true
            onCurrentIndexChanged: if (currentIndex === 1) syncJsonTree()
            TabButton { text: Strings.t.responseBody; onHoveredChanged: hint(hovered ? Strings.t.bodyHint : "") }
            TabButton { text: Strings.t.responseTree; onHoveredChanged: hint(hovered ? Strings.t.treeHint : "") }
            TabButton { text: Strings.t.responseHeaders; onHoveredChanged: hint(hovered ? Strings.t.headersHint : "") }
            TabButton { text: Strings.t.responseCookies; onHoveredChanged: hint(hovered ? Strings.t.cookiesHint : "") }
            TabButton { text: Strings.t.responseNetwork; onHoveredChanged: hint(hovered ? Strings.t.networkHint : "") }
        }

        // inline find (Ctrl+F) — only appears when triggered
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: findVisible
            TextField {
                id: findField
                Layout.fillWidth: true
                placeholderText: Strings.t.searchResponse
                onAccepted: findNext(false)
                onTextChanged: { if (text.length > 0) findNext(false); else updateFindCounter(); }
                Keys.onEscapePressed: closeFind()
            }
            Label {
                visible: findMatchTotal > 0
                text: findMatchIndex + "/" + findMatchTotal
                opacity: 0.75
                font.family: "monospace"
            }
            ToolButton {
                icon.name: "go-up"; onClicked: findNext(true)
                onHoveredChanged: hint(hovered ? Strings.t.prevMatch : "")
            }
            ToolButton {
                icon.name: "go-down"; onClicked: findNext(false)
                onHoveredChanged: hint(hovered ? Strings.t.nextMatch : "")
            }
            ToolButton {
                icon.name: "window-close"; onClicked: closeFind()
                onHoveredChanged: hint(hovered ? Strings.t.clearFind : "")
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            StackLayout {
                anchors.fill: parent
                currentIndex: respTabBar.currentIndex
                // ---- Body ----
                ScrollView {
                    id: bodyScroll
                    Layout.fillWidth: true; Layout.fillHeight: true
                    padding: Kirigami.Units.smallSpacing
                    TextArea {
                        id: responseBody
                        readOnly: true
                        font.family: "monospace"
                        font.pointSize: settings.fontSize > 0 ? settings.fontSize : Kirigami.Theme.defaultFont.pointSize
                        wrapMode: TextEdit.Wrap
                        selectionColor: Kirigami.Theme.highlightColor
                        selectedTextColor: Kirigami.Theme.highlightedTextColor
                        Component.onCompleted:
                            varSupport.attach(responseBody.textDocument, "#c678dd", true, true,
                                app.jsonStringColor, app.jsonNumberColor, app.jsonKeywordColor,
                                app.jsonKeyColor)
                    }
                }
                JsonTree { id: jsonTree; Layout.fillWidth: true; Layout.fillHeight: true }
                HeaderTable {
                    id: responseHeadersTable
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing; Layout.rightMargin: Kirigami.Units.smallSpacing; Layout.bottomMargin: Kirigami.Units.smallSpacing
                    headers: responseHeaders
                    onCopyRequested: function (text) { varSupport.copyText(text); app.notify(Strings.t.headersCopied); }
                }
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    padding: Kirigami.Units.smallSpacing
                    TextArea { id: responseCookiesArea; readOnly: true; font.family: "monospace"; wrapMode: TextEdit.Wrap; text: responseCookies; placeholderText: Strings.t.noCookies }
                }
                NetworkView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    meta: netMeta
                }
            }
            // empty state (no response yet) — only on the "Body" tab
            EmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, 340)
                visible: responseBody.text.length === 0 && !app.sending && respTabBar.currentIndex === 0
                iconSource: "qrc:/icons/catarina.svg"
                iconIsMask: true
                title: Strings.t.noResponseYet
                message: Strings.t.noResponseHint
                shortcut: "Ctrl+K"
                shortcutLabel: Strings.t.openPaletteHint
            }
        }

        // panel status/hint strip (replaces floating tooltips)
        Kirigami.Separator { Layout.fillWidth: true }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: hintLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
            color: Kirigami.Theme.alternateBackgroundColor
            Label {
                id: hintLabel
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.smallSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font.pixelSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.75
                text: responseHint
            }
        }
    }
}
