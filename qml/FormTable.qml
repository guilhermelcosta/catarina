import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Campos de formulário (x-www-form-urlencoded / multipart), com tipo texto/arquivo.
ColumnLayout {
    id: table
    property var model
    property bool allowFiles: false
    signal addRequested()
    signal edited()
    signal pickFile(int index)

    readonly property bool empty: model === undefined || model === null || model.count === 0

    spacing: Kirigami.Units.smallSpacing

    ListView {
        id: view
        visible: !table.empty
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        clip: true
        model: table.model
        delegate: RowLayout {
            width: view.width
            CheckBox {
                checked: model.enabled
                onToggled: { model.enabled = checked; table.edited(); }
            }
            TextField {
                Layout.fillWidth: true
                text: model.name
                placeholderText: "campo"
                onTextEdited: { model.name = text; table.edited(); }
            }
            TextField {
                Layout.fillWidth: true
                visible: model.type !== "file"
                text: model.value
                placeholderText: "valor"
                onTextEdited: { model.value = text; table.edited(); }
            }
            Button {
                Layout.fillWidth: true
                visible: model.type === "file"
                text: model.fileName && model.fileName.length > 0
                      ? model.fileName.split("/").pop() : "Escolher arquivo…"
                icon.name: "document-open"
                onClicked: table.pickFile(index)
            }
            ComboBox {
                visible: table.allowFiles
                implicitWidth: 100
                model: ["text", "file"]
                currentIndex: model.type === "file" ? 1 : 0
                onActivated: {
                    view.model.setProperty(index, "type", currentText);
                    table.edited();
                }
            }
            ToolButton {
                icon.name: "list-remove"
                onClicked: { table.model.remove(index); table.edited(); }
                ToolTip.text: "Remover campo"
                ToolTip.visible: hovered
            }
        }
    }

    Item {
        visible: table.empty
        Layout.fillWidth: true
        Layout.fillHeight: true
        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Label { Layout.alignment: Qt.AlignHCenter; text: "Nenhum campo ainda."; opacity: 0.5 }
            ToolButton {
                Layout.alignment: Qt.AlignHCenter
                icon.name: "list-add"
                text: "Adicionar"
                display: AbstractButton.TextBesideIcon
                highlighted: true
                onClicked: { table.addRequested(); table.edited(); }
            }
        }
    }

    ToolButton {
        visible: !table.empty
        icon.name: "list-add"
        text: "Adicionar"
        display: AbstractButton.TextBesideIcon
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        onClicked: { table.addRequested(); table.edited(); }
    }
}
