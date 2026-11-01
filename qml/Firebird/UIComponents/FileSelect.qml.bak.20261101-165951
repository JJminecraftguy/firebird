import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Firebird.Emu 1.0

RowLayout {
    id: root
    property string filePath: ""
    property bool selectExisting: true
    property alias subtext: subtextLabel.text
    property bool showCreateButton: false
    signal create()

    // Hack to force reevaluation of Emu.fileExists(filePath) after reselection.
    // Needed on Android due to persistent permissions.
    property int forceRefresh: 0
    Loader {
        id: dialogLoader
        active: false
        sourceComponent: FileDialog {
            currentFolder: Emu.dir(root.filePath)
            // If save dialogs are not supported, force an open dialog
            fileMode: (root.selectExisting || !Emu.saveDialogSupported()) ? FileDialog.OpenFile : FileDialog.SaveFile
            onAccepted: {
                root.filePath = Emu.toLocalFile(selectedFile);
                root.forceRefresh++;
            }
        }
    }

    SystemPalette {
        id: paletteActive
    }

    ColumnLayout {
        Layout.fillWidth: true

        FBLabel {
            id: filenameLabel
            elide: "ElideRight"

            Layout.fillWidth: true
            // Allow the label to shrink below its implicitWidth.
            // Without this, the layout doesn't allow it to go smaller...
            Layout.preferredWidth: 100

            font.italic: filePath === ""
            text: { forceRefresh; return filePath === "" ? qsTr("(none)") : Emu.basename(filePath); }
            color: { forceRefresh; return ((!selectExisting && Emu.saveDialogSupported()) || filePath === "" || Emu.fileExists(filePath)) ? paletteActive.text : "red"; }
        }

        FBLabel {
            id: subtextLabel
            elide: "ElideRight"

            font.pixelSize: FBTextMetrics.normalSize * 0.8
            Layout.fillWidth: true
            visible: text !== ""
        }
    }

    // Button for either custom creation functionality (onCreate) or
    // if the open file dialog doesn't allow creation, to open a file creation dialog.
    Button {
        visible: showCreateButton || (!selectExisting && !Emu.saveDialogSupported())
        icon.source: "qrc:/icons/resources/icons/document-new.png"

        Loader {
            id: createDialogLoader
            active: false
            sourceComponent: FileDialog {
                currentFolder: Emu.dir(root.filePath)
                fileMode: FileDialog.SaveFile
                onAccepted: {
                    root.filePath = Emu.toLocalFile(selectedFile);
                    root.forceRefresh++;
                }
            }
        }

        onClicked: {
            if(root.showCreateButton)
                root.create()
            else {
                createDialogLoader.active = true;
                createDialogLoader.item.visible = true;
            }
        }
    }

    Button {
        icon.source: "qrc:/icons/resources/icons/document-edit.png"
        onClicked: {
            dialogLoader.active = true;
            dialogLoader.item.visible = true;
        }
    }
}
