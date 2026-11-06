import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Dialogs as FBDialogs
import Firebird.Emu 1.0
import Firebird.UIComponents 1.0

Controls.Dialog {
    id: flashDialog
    title: qsTr("Create Flash Image")
    modal: true
    focus: true

    // Size from the available screen area, not from the scrollable content.
    // Overlay.overlay is the Popup overlay item; its size is the window size.
    readonly property real _availW: Controls.Overlay.overlay ? Controls.Overlay.overlay.width  : 720
    readonly property real _availH: Controls.Overlay.overlay ? Controls.Overlay.overlay.height : 1280
    width:  Math.min(640, _availW - 32)
    height: Math.min(860, _availH - 32)

    background: Rectangle {
        color: paletteActive.window
        border.color: paletteActive.mid
        border.width: 1
    }

    SystemPalette {
        id: paletteActive
    }
    readonly property color _fg: (paletteActive.window.hslLightness < 0.5) ? "white" : paletteActive.windowText
    palette.windowText: _fg
    palette.text: _fg
    palette.buttonText: _fg

    signal flashCreated(string filePath)

    // Single child => becomes the popup's contentItem, sized to the dialog
    // minus padding. Buttons live here, NOT inside the ScrollView.
    ColumnLayout {
        spacing: 8

        Controls.ScrollView {
            id: flashScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Inside a ScrollView the content must not use anchors.fill: parent
            // (that kills scrolling and clips the tail). Bind width to the
            // available viewport width instead.
            GridLayout {
                id: layout
                width: flashScroll.availableWidth
                columns: 2
                columnSpacing: 5
                rowSpacing: 5

                FBLabel {
                    Layout.minimumHeight: implicitHeight
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("Model:")
                }

                Controls.ComboBox {
                    id: modelCombo
                    property bool cxSelected: modelCombo.currentIndex == 2 || modelCombo.currentIndex == 3
                    property bool cx2Selected: modelCombo.currentIndex == 4
                    property int productId: [0x0E0, 0x0C2, 0x100, 0x0F0, 0x1C0][currentIndex]
                    Layout.fillWidth: true
                    model: ["Touchpad", "Touchpad CAS", "CX", "CX CAS", "CX II (/-T/CAS)"]
                    currentIndex: 3
                }

                FBLabel {
                    visible: subtypeCombo.visible
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("CX Subtype:")
                }

                Controls.ComboBox {
                    id: subtypeCombo
                    property int featureValue: [0x005, 0x085, 0x185][currentIndex]
                    Layout.fillWidth: true
                    visible: modelCombo.cxSelected
                    model: ["HW-A", "HW-J (CXCR)", "HW-W (CXCR4)"]
                }

                FBLabel {
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("Manuf:")
                }

                FileSelect {
                    id: manufSelect
                    Layout.maximumWidth: parent.width
                    Layout.fillWidth: true
                    subtext: filePath ? Emu.manufDescription(filePath) : ""
                }

                FBLabel {
                    visible: boot2Select.visible
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("Boot2:")
                }

                FileSelect {
                    id: boot2Select
                    visible: !modelCombo.cx2Selected
                    Layout.fillWidth: true
                    subtext: filePath ? Emu.componentDescription(filePath, "BOOT2     ") : ""
                }

                FBLabel {
                    visible: osSelect.visible
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("OS:")
                }

                FileSelect {
                    id: osSelect
                    visible: !modelCombo.cx2Selected
                    Layout.fillWidth: true
                    subtext: filePath ? Emu.osDescription(filePath) : ""
                }

                FBLabel {
                    visible: bootloaderSelect.visible
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("Bootloader:")
                }

                FileSelect {
                    id: bootloaderSelect
                    visible: modelCombo.cx2Selected
                    Layout.fillWidth: true
                    subtext: filePath ? Emu.componentDescription(filePath, "BOOT LOADE") : ""
                }

                FBLabel {
                    visible: installerSelect.visible
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("Installer:")
                }

                FileSelect {
                    id: installerSelect
                    visible: modelCombo.cx2Selected
                    Layout.fillWidth: true
                    subtext: filePath ? Emu.componentDescription(filePath, "INSTALLER ") : ""
                }

                FBLabel {
                    Layout.alignment: Qt.AlignLeft
                    text: qsTr("Diags:")
                }

                FileSelect {
                    id: diagsSelect
                    Layout.fillWidth: true
                    subtext: filePath ? Emu.componentDescription(filePath, "DIAGS     ") : ""
                }

                property string validationText: (modelCombo.cx2Selected && !manufSelect.filePath) ? qsTr("Manuf required for CX II") : ""

                FBLabel {
                    Layout.alignment: Qt.AlignCenter
                    Layout.columnSpan: 2
                    color: "red"
                    text: parent.validationText
                }

                // NOTE: the old Item { Layout.fillHeight: true } spacer is gone.
                // In this structure the ScrollView already takes the remaining
                // space; keeping the spacer would push the button row off again.
            }
        }

        // Buttons live outside the ScrollView so they are always visible.
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Controls.Button {
                text: qsTr("Cancel")
                onClicked: flashDialog.close()
            }

            Controls.Button {
                text: qsTr("Save")
                enabled: layout.validationText === ""
                onClicked: {
                    fileDialogLoader.active = true;
                    fileDialogLoader.item.open();
                }
            }
        }
    }

    FBDialogs.MessageDialog {
        id: failureDialog
        title: qsTr("Flash saving failed")
        text: qsTr("Saving the flash file failed!")
    }

    Loader {
        id: fileDialogLoader
        active: false
        sourceComponent: FBDialogs.FileDialog {
            fileMode: FBDialogs.FileDialog.SaveFile
            onAccepted: {
                var filePath = Emu.toLocalFile(selectedFile);
                var success = false;
                if (!modelCombo.cx2Selected)
                    success = Emu.createFlash(filePath, modelCombo.productId, subtypeCombo.featureValue, manufSelect.filePath, boot2Select.filePath, osSelect.filePath, diagsSelect.filePath);
                else
                    success = Emu.createFlash(filePath, modelCombo.productId, subtypeCombo.featureValue, manufSelect.filePath, bootloaderSelect.filePath, installerSelect.filePath, diagsSelect.filePath);

                if (success) {
                    flashCreated(filePath);
                    flashDialog.close();
                }
            }
        }
    }
}
