import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Dialogs as FBDialogs
import Firebird.Emu 1.0
import Firebird.UIComponents 1.0

Controls.Dialog {
    id: flashDialog
    title: qsTr("Create Flash Image")
    header: null               // (1) hide the title bar
    modal: true
    focus: true

    // Center in the overlay (fills the screen)
    parent: Controls.Overlay.overlay
    x: parent ? Math.max(10, (parent.width - width) / 2) : 10
    y: parent ? Math.max(10, (parent.height - height) / 2) : 10  // (2) center

    readonly property real _maxW: parent ? parent.width  - 20 : 400
    readonly property real _maxH: parent ? parent.height - 20 : 600

    // (3)(5) size to content, minimum 320, cap to screen
    width:  Math.min(Math.max(implicitWidth,  320), _maxW)
    height: Math.min(implicitHeight, _maxH)

    leftPadding: 5
    rightPadding: 5
    topPadding: 5
    bottomPadding: 5

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

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: 5

        Controls.ScrollView {
            id: scroller
            Layout.fillWidth: true
            // (3) prefer the natural content height, capped so the button
            // row is always visible on small screens
            Layout.preferredHeight: Math.min(
                layout.implicitHeight,
                Math.max(100, _maxH - buttonRow.implicitHeight - 40))
            clip: true

            // (4) no horizontal scrolling; vertical only when needed
            Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
            Controls.ScrollBar.vertical.policy:   Controls.ScrollBar.AsNeeded

            GridLayout {
                id: layout
                width: scroller.availableWidth
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
                    Layout.columnSpan: layout.columns
                    color: "red"
                    text: layout.validationText
                }
            }
        }

        RowLayout {
            id: buttonRow
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
