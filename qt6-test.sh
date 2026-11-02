#!/usr/bin/env bash
# fix-mobileui-front.sh — run from the firebird repo root
set -euo pipefail
ROOT="${1:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
[ -f "$ROOT/firebird.pro" ] || { echo "not a firebird checkout" >&2; exit 2; }

FILE="$ROOT/qml/MobileUIFront.qml"
[ -f "$FILE" ] || { echo "missing $FILE" >&2; exit 2; }
cp "$FILE" "$FILE.bak.$(date +%s)"

cat > "$FILE" <<'QML'
import Firebird.Emu 1.0
import Firebird.UIComponents 1.0

import QtQuick 2.0
import QtQuick.Layouts 1.0

GridLayout {
    id: mobileui

    // For previewing just this component
    width: 600
    height: 800

    columns: 2
    columnSpacing: 0
    rowSpacing: 0

    // Height the keypad occupies when it fills the full width (portrait).
    readonly property real _keypadHeight: keypad.height * width / keypad.width + iosmargin.height

    // Remaining space for the emulator: width after the swipe bar,
    // height after the keypad.
    readonly property real _availWidth: width - swipeBar.implicitWidth
    readonly property real _availHeight: height - _keypadHeight

    // Fit a 4:3 screen into that box.
    readonly property real _fitHeight: Math.min(_availWidth * 3 / 4, _availHeight)

    // In landscape the keypad sits in its own column, so fitHeight is
    // not used; the screen fills the row and is aspect-fitted inside.
    readonly property bool _tablet: width > height

    VerticalSwipeBar {
        id: swipeBar
        Layout.preferredHeight: mobileui._fitHeight
        Layout.maximumHeight: mobileui._fitHeight

        onClicked: listView.openDrawer()
    }

    // Wrapper fills the column so the screen can be centred, while the
    // screen itself is sized to fit without overflow.
    Item {
        id: screenWrapper
        Layout.fillWidth: true
        Layout.fillHeight: mobileui._tablet
        Layout.preferredHeight: mobileui._tablet ? -1 : mobileui._fitHeight
        Layout.maximumHeight: mobileui._tablet ? Number.POSITIVE_INFINITY : mobileui._fitHeight

        EmuScreen {
            id: screen
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height * 4 / 3)
            height: width * 3 / 4

            focus: true

            Timer {
                interval: 35
                running: true
                repeat: true
                onTriggered: screen.update()
            }
        }
    }

    Flickable {
        id: controls

        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.preferredHeight: contentHeight
        Layout.maximumHeight: contentHeight
        Layout.columnSpan: 2

        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        contentWidth: parent.width
        contentHeight: keypad.height*controls.width/keypad.width + iosmargin.height
        clip: true
        pixelAligned: true

        Keypad {
            id: keypad
            transform: Scale { origin.x: 0; origin.y: 0; xScale: controls.width/keypad.width; yScale: controls.width/keypad.width }
        }

        Rectangle {
            id: iosmargin
            color: keypad.color

            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            // This is needed to avoid opening the control center
            height: Qt.platform.os === "ios" ? 20 : 0
        }
    }

    Rectangle {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.columnSpan: 2
        color: keypad.color
    }

    states: [ State {
        name: "tabletMode"
        when: mobileui.width > mobileui.height

        PropertyChanges {
            target: mobileui
            columns: 3
            layoutDirection: Emu.leftHanded ? Qt.RightToLeft : Qt.LeftToRight
        }

        PropertyChanges {
            target: swipeBar
            visible: false
        }

        /* Keypad fills right side, as wide as needed */
        PropertyChanges {
            target: controls
            Layout.minimumWidth: Math.floor(keypad.width/keypad.height * (mobileui.height - iosmargin.height))
            Layout.maximumWidth: Layout.minimumWidth
            Layout.fillHeight: true
            Layout.columnSpan: 1
        }
    }]
}
QML

echo "Rewritten: $FILE"
