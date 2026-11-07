import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Firebird.Emu 1.0
import Firebird.UIComponents 1.0

ColumnLayout {
    id: pageRoot
    property var kitModel
    SystemPalette { id: paletteActive }
    readonly property color _fg: (paletteActive.window.hslLightness < 0.5) ? "white" : paletteActive.text
    readonly property color _hint: (paletteActive.window.hslLightness < 0.5) ? "#aaaaaa" : "#666666"

    readonly property bool isWasm: Qt.platform.os === "wasm"

    Component.onCompleted: kitModel = Emu.kits

    spacing: 5

    KitList {
        id: kitList

        Layout.fillHeight: true
        Layout.fillWidth: true

        Layout.rightMargin: 1
        Layout.leftMargin: 1
        Layout.topMargin: 5

        kitModel: parent.kitModel
    }

    GroupBox {
        Layout.fillWidth: true
        Layout.minimumWidth: contentItem.Layout.minimumWidth
        title: qsTr("Kit Properties")

        GridLayout {
            anchors.fill: parent
            columns: {
                const narrow = width < 550 || Qt.platform.os === "android";
                if (pageRoot.isWasm)
                    return narrow ? 3 : 6;
                return narrow ? 2 : 4;
            }
            FBLabel {
                Layout.columnSpan: parent.columns
                Layout.fillWidth: true
                color: "red"
                visible: kitList.currentItem
                    && (kitList.currentItem.myData.boot1 === "" || kitList.currentItem.myData.flash === "")
                wrapMode: Text.WordWrap
                text: qsTr("You need to specify files for Boot1 and Flash")
            }

            FBLabel {
                text: qsTr("Name:")
                elide: Text.ElideMiddle
            }

            TextField {
                id: nameEdit
                color: pageRoot._fg
                placeholderTextColor: pageRoot._hint
                placeholderText: qsTr("Name")
                Layout.fillWidth: true
                Layout.columnSpan: pageRoot.isWasm ? 2 : 1

                text: kitList.currentItem.myData.name
                onTextChanged: {
                    if(text !== kitList.currentItem.myData.name)
                        kitModel.setDataRow(kitList.currentIndex, text, KitModel.NameRole);
                    text = Qt.binding(function() { return kitList.currentItem.myData.name; });
                }
            }

            FBLabel {
                text: qsTr("Boot1:")
                elide: Text.ElideMiddle
            }

            // Desktop / Android / iOS
            FileSelect {
                id: boot1Edit
                visible: !pageRoot.isWasm
                Layout.fillWidth: true
                filePath: kitList.currentItem.myData.boot1
                onFilePathChanged: {
                    if(filePath !== kitList.currentItem.myData.boot1)
                        kitModel.setDataRow(kitList.currentIndex, filePath, KitModel.Boot1Role);
                    filePath = Qt.binding(function() { return kitList.currentItem.myData.boot1; });
                }
            }

            // Wasm: read-only label + button that opens the browser picker
            FBLabel {
                visible: pageRoot.isWasm
                property string filePath: kitList.currentItem.myData.boot1
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                font.italic: filePath === ""
                text: filePath === "" ? qsTr("(none)") : Emu.basename(filePath)
            }

            IconButton {
                visible: pageRoot.isWasm
                iconSource: "qrc:/icons/resources/icons/document-edit.png"
                onClicked: Emu.loadFile(kitList.currentIndex, KitModel.Boot1Role)
            }

            FBLabel {
                text: qsTr("Flash:")
                elide: Text.ElideMiddle
            }

            // Desktop / Android / iOS
            FileSelect {
                id: flashEdit
                visible: !pageRoot.isWasm
                Layout.fillWidth: true
                filePath: kitList.currentItem.myData.flash
                onFilePathChanged: {
                    if(filePath !== kitList.currentItem.myData.flash)
                        kitModel.setDataRow(kitList.currentIndex, filePath, KitModel.FlashRole);
                    filePath = Qt.binding(function() { return kitList.currentItem.myData.flash; });
                }
                showCreateButton: true
                onCreate: flashDialog.visible = true
                onCreate: flashDialog.open()
            }

            FBLabel {
                visible: pageRoot.isWasm
                property string filePath: kitList.currentItem.myData.flash
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                font.italic: filePath === ""
                text: filePath === "" ? qsTr("(none)") : Emu.basename(filePath)
            }

            IconButton {
                visible: pageRoot.isWasm
                iconSource: "qrc:/icons/resources/icons/document-edit.png"
                onClicked: Emu.loadFile(kitList.currentIndex, KitModel.FlashRole)
            }

            FlashDialog {
                id: flashDialog
                onFlashCreated: function(filePath) {
                    kitModel.setDataRow(kitList.currentIndex, filePath, KitModel.FlashRole);
                }
            }

            FBLabel {
                text: qsTr("Snapshot:")
                elide: Text.ElideMiddle
            }

            // Desktop / Android / iOS
            FileSelect {
                id: snapshotEdit
                visible: !pageRoot.isWasm
                Layout.fillWidth: true
                selectExisting: false
                filePath: kitList.currentItem.myData.snapshot
                onFilePathChanged: {
                    if(filePath !== kitList.currentItem.myData.snapshot)
                        kitModel.setDataRow(kitList.currentIndex, filePath, KitModel.SnapshotRole);
                    filePath = Qt.binding(function() { return kitList.currentItem.myData.snapshot; });
                }
            }

            // Wasm: the snapshot path is chosen automatically by
            // Emu.saveSnapshot() on first save, so this is display-only.
            FBLabel {
                visible: pageRoot.isWasm
                property string filePath: kitList.currentItem.myData.snapshot
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                font.italic: filePath === ""
                text: filePath === "" ? qsTr("(none)") : Emu.basename(filePath)
            }

            IconButton {
                visible: pageRoot.isWasm
                iconSource: "qrc:/icons/resources/icons/document-edit.png"
                onClicked: Emu.loadFile(kitList.currentIndex, KitModel.SnapshotRole)
            }
        }
    }
}
