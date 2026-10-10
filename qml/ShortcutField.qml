import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "Strings.js" as Strings

// Field that captures a key combination. Click and press; Esc cancels.
FocusScope {
    id: field
    property var window: null          // window (to suspend global shortcuts)
    property string sequence: ""
    property bool recording: false
    signal captured(string sequence)

    implicitWidth: 170
    implicitHeight: Kirigami.Units.gridUnit * 1.7
    focus: recording

    Rectangle {
        anchors.fill: parent
        radius: 3
        color: Kirigami.Theme.backgroundColor
        border.width: field.recording ? 2 : 1
        border.color: field.recording ? Kirigami.Theme.focusColor : Kirigami.Theme.disabledTextColor
        Label {
            anchors.centerIn: parent
            text: field.recording ? Strings.t.pressCombination : (field.sequence.length > 0 ? field.sequence : "—")
            opacity: field.recording ? 0.7 : 1
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { field.recording = true; field.forceActiveFocus(); }
    }
    onRecordingChanged: if (field.window) field.window.recordingShortcut = field.recording
    Keys.onPressed: function (e) {
        if (!field.recording) return;
        e.accepted = true;
        if (e.key === Qt.Key_Escape) { field.recording = false; return; }
        if (e.key === Qt.Key_Control || e.key === Qt.Key_Shift || e.key === Qt.Key_Alt || e.key === Qt.Key_Meta) return;
        var hasMod = (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0;
        var isFn = e.key >= Qt.Key_F1 && e.key <= Qt.Key_F35;
        if (!hasMod && !isFn) return;   // requires a modifier (or a function key)
        var seq = settings.keySequence(e.key, e.modifiers);
        if (seq.length > 0) { field.recording = false; field.captured(seq); }
    }
}
