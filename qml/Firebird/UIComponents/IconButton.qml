import QtQuick
import QtQuick.Controls

/* A push button with a symbol instead of text.
 * QQC2 buttons have a built-in "icon" group property, so the
 * image is exposed as "iconSource" instead. */

Button {
    property url iconSource

    readonly property int iconSize: Math.round(FBTextMetrics.normalSize * 1.5)

    display: AbstractButton.IconOnly
    icon.source: iconSource
    icon.width: iconSize
    icon.height: iconSize
    // Keep the original look: a square button
    implicitWidth: implicitHeight
}
