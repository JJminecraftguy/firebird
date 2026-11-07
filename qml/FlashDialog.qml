import QtQuick

Item {
    id: root
    width: 0
    height: 0
    visible: false 

    readonly property bool _isAndroid: Qt.platform.os === "android"

    signal flashCreated(string filePath)

    function open() {
        if (_isAndroid) {
            if (androidLoader.item) androidLoader.item.open();
        } else {
            if (desktopLoader.item) desktopLoader.item.show();
        }
    }

    function close() {
        if (_isAndroid) {
            if (androidLoader.item) androidLoader.item.close();
        } else {
            if (desktopLoader.item) desktopLoader.item.close();
        }
    }

    Loader {
        id: androidLoader
        active: root._isAndroid
        source: Qt.resolvedUrl("FlashDialogAndroid.qml")
        onLoaded: item.flashCreated.connect(function(filePath) {
            root.flashCreated(filePath);
        })
    }

    Loader {
        id: desktopLoader
        active: !root._isAndroid
        source: Qt.resolvedUrl("FlashDialogDesktop.qml")
        onLoaded: item.flashCreated.connect(function(filePath) {
            root.flashCreated(filePath);
        })
    }
}
