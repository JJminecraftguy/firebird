import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import Firebird.UIComponents 1.0

Item {
    Layout.fillHeight: true
    Layout.fillWidth: true

    ConfigPagesModel {
        id: pagesModel
    }

    ColumnLayout {
        id: tabLayout
        anchors {
            left: parent.left
            right: swipeBar.left
            top: parent.top
            bottom: autoSaveLabel.top
            bottomMargin: 2
        }

        TabBar {
            id: bar
            Layout.fillWidth: true

            Repeater {
                model: pagesModel

                TabButton {
                    // "&" would be treated as a mnemonic, "&&" is a literal one
                    text: qsTranslate("ConfigPagesModel", model.title).replace(/&/g, "&&")
                    // Let the tab bar scroll if the tabs don't fit
                    width: Math.max(implicitWidth, tabLayout.width / pagesModel.count)
                }
            }
        }

        // Not a SwipeView: swipes would interfere with the controls on the pages.
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: bar.currentIndex

            Repeater {
                model: pagesModel

                Loader {
                    source: model.file
                }
            }
        }
    }

    FBLabel {
        id: autoSaveLabel

        anchors {
            left: parent.left
            leftMargin: 2
            right: swipeBar.left
            bottom: parent.bottom
        }

        text: qsTr("Changes are saved automatically")
        font.italic: true
        color: "grey"
    }

    VerticalSwipeBar {
        id: swipeBar

        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }

        onClicked: {
            listView.openDrawer();
        }
    }
}
