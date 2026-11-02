import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Firebird.Emu 1.0
ColumnLayout {
    SystemPalette { id: paletteActive }
    readonly property color _fg: (paletteActive.window.hslLightness < 0.5) ? "white" : paletteActive.text
    property alias kitName: label.text
    property alias flashFile: flashName.text
    property alias stateFile: stateName.text

    RowLayout {
        Layout.maximumWidth: parent.width

        FBLabel {
            id: label
            color: parent._fg
            font.bold: true
            elide: Text.ElideMiddle

            text: "Name"

            Layout.maximumWidth: parent.width
        }

        /*FBLabel {
            id: type
            color: parent._fg
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            Layout.leftMargin: 10

            text: "CX CAS (HW J)"
        }*/
    }

    RowLayout {
        FBLabel {
            id: flashName
            color: parent._fg
            text: "flash.img"
        }

        FBLabel {
            id: stateName
            color: parent._fg
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            Layout.leftMargin: 10

            text: "state"
        }
    }
}
