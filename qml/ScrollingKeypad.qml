import QtQuick

// The keypad scaled to the available width. If that's taller than
// the view, it can be scrolled vertically (without visible scroll bars).
Flickable {
    id: controls
    property alias keypad: keypad

    clip: true
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds

    contentWidth: width
    contentHeight: keypad.height*controls.width/keypad.width

    Keypad {
        id: keypad
        transform: Scale { origin.x: 0; origin.y: 0; xScale: controls.width/keypad.width; yScale: controls.width/keypad.width }
    }
}
