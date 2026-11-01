import QtQuick
import QtQuick.Controls
FBLabel {
    signal clicked

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: parent.clicked()
    }
    
    color: "white"
    font.bold: true
}
