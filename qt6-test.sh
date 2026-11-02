#!/usr/bin/env bash
# fix-kititem-android-only.sh — run from the firebird repo root
set -euo pipefail
ROOT="${1:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
FILE="$ROOT/qml/Firebird/UIComponents/KitItem.qml"
[ -f "$FILE" ] || { echo "missing $FILE" >&2; exit 2; }

echo "=== BEFORE ==="
cat -n "$FILE"
echo
cp "$FILE" "$FILE.bak.$(date +%s)"

cat > "$FILE" <<'QML'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: kitItemRoot

    property alias kitName: label.text
    property alias flashFile: flashName.text
    property alias stateFile: stateName.text

    // Android's Material style leaves Label's default text colour black,
    // which is unreadable on the dark KitList background. Desktop themes
    // resolve Label's default correctly, so only override on Android; the
    // Binding's `when` guard leaves the colour untouched elsewhere.
    SystemPalette { id: paletteActive }
    readonly property bool _applyColor: Qt.platform.os === "android"
    readonly property color _androidColor: paletteActive.window.hslLightness < 0.5 ? "white" : paletteActive.text

    RowLayout {
        Layout.maximumWidth: parent.width

        FBLabel {
            id: label
            font.bold: true
            elide: Text.ElideMiddle
            text: "Name"
            Layout.maximumWidth: parent.width

            Binding {
                target: label
                property: "color"
                value: kitItemRoot._androidColor
                when: kitItemRoot._applyColor
            }
        }

        /*FBLabel {
            id: type
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            Layout.leftMargin: 10

            text: "CX CAS (HW J)"
        }*/
    }

    RowLayout {
        FBLabel {
            id: flashName
            text: "flash.img"

            Binding {
                target: flashName
                property: "color"
                value: kitItemRoot._androidColor
                when: kitItemRoot._applyColor
            }
        }

        FBLabel {
            id: stateName
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            Layout.leftMargin: 10
            text: "state"

            Binding {
                target: stateName
                property: "color"
                value: kitItemRoot._androidColor
                when: kitItemRoot._applyColor
            }
        }
    }
}
QML

echo "=== AFTER ==="
cat -n "$FILE"
