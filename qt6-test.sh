#!/usr/bin/env bash
# firebird-qt6-port.sh
#
# Reproduce the working Qt 6 port of Firebird on top of a base checkout.
#
#   ./firebird-qt6-port.sh /path/to/firebird             # apply
#   ./firebird-qt6-port.sh /path/to/firebird --check     # report state, write nothing
#   ./firebird-qt6-port.sh /path/to/firebird --dry-run   # alias for --check
#   ./firebird-qt6-port.sh /path/to/firebird --build     # apply, then qmake6+make
#   ./firebird-qt6-port.sh /path/to/firebird --no-dialog # never show a GUI dialog
#
# Reproduces every edit from the working session: QML Controls 1 -> 2 port,
# QML Dialogs 1 -> QtQuick.Dialogs, QML import version strip, TextMetrics ->
# FBTextMetrics, IconButton/FileSelect/KitList/ScrollingKeypad/FlashDialog/
# MobileUIConfig rewrites, handler-parameter fixes, C++ Qt 6 API fixes,
# os-android.cpp JNI port, qmlbridge save-dialog, firebird.pro, Android
# manifest + packaging.
#
# NOT reproduced (never touched in the working run, or out of scope):
#   * .github/workflows/*  (still Qt 5.15.2 in the working run)
#   * Android / Windows / macOS builds (unverified - Linux only)
#   * anything Qt 6.12-specific (built against Qt 6.4.2)

set -uo pipefail

ROOT=""
MODE="apply"
DO_BUILD=0
NO_DIALOG=0

for arg in "$@"; do
    case "$arg" in
        --check|--dry-run) MODE="check" ;;
        --build)           DO_BUILD=1 ;;
        --no-dialog)       NO_DIALOG=1 ;;
        -h|--help)         sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)                echo "unknown option: $arg" >&2; exit 2 ;;
        *)                 ROOT="$arg" ;;
    esac
done

ROOT="${ROOT:-$PWD}"
[ -f "$ROOT/firebird.pro" ] || { echo "error: $ROOT is not a firebird checkout" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT" || exit 2

command -v python3 >/dev/null || { echo "error: python3 required" >&2; exit 2; }

REPORT="${TMPDIR:-/tmp}/firebird-qt6-port-report.txt"
GIT=0; git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && GIT=1

echo "repo: $ROOT"
echo "mode: $MODE"
echo

# ---------------------------------------------------------------------------
# Phase 0: git operations that cannot be expressed as text edits
# ---------------------------------------------------------------------------
QDIR="$ROOT/qml/Firebird/UIComponents"

if [ -f "$QDIR/TextMetrics.qml" ] && [ ! -f "$QDIR/FBTextMetrics.qml" ]; then
    if [ "$MODE" = apply ]; then
        if [ "$GIT" = 1 ]; then
            git -C "$ROOT" mv qml/Firebird/UIComponents/TextMetrics.qml \
                              qml/Firebird/UIComponents/FBTextMetrics.qml \
                && echo "[git mv] TextMetrics.qml -> FBTextMetrics.qml"
        else
            mv "$QDIR/TextMetrics.qml" "$QDIR/FBTextMetrics.qml" \
                && echo "[mv] TextMetrics.qml -> FBTextMetrics.qml"
        fi
    else
        echo "[git mv] would rename TextMetrics.qml -> FBTextMetrics.qml"
    fi
else
    echo "[git mv] already renamed / not present"
fi

for f in android/build.gradle android/res/values/libs.xml; do
    [ -f "$ROOT/$f" ] || continue
    if [ "$MODE" = apply ]; then
        if [ "$GIT" = 1 ]; then git -C "$ROOT" rm -q "$f" && echo "[git rm] $f"
        else rm -f "$ROOT/$f" && echo "[rm] $f"; fi
    else
        echo "[git rm] would remove $f"
    fi
done

echo

# ---------------------------------------------------------------------------
# Phase 1..6: text edits
# ---------------------------------------------------------------------------
FB_ROOT="$ROOT" FB_MODE="$MODE" FB_REPORT="$REPORT" python3 - <<'PY'
import os, re, sys

ROOT   = os.environ["FB_ROOT"]
MODE   = os.environ["FB_MODE"]
REPORT = os.environ["FB_REPORT"]

rows = []
def rec(step, path, status, detail=""):
    rows.append((step, path, status, detail))
def rel(p):
    return os.path.relpath(p, ROOT)
def load(p):
    with open(p, encoding="utf-8") as f: return f.read()
def save(p, t):
    with open(p, "w", encoding="utf-8") as f: f.write(t)

def rep(step, path, old, new, count=1, required=True):
    p = os.path.join(ROOT, path)
    if not os.path.exists(p):
        rec(step, rel(p), "SKIP", "file missing"); return
    t = load(p)
    if old not in t:
        if new in t:
            rec(step, rel(p), "ALREADY", "already applied"); return
        rec(step, rel(p), "MISSING" if required else "SKIP", "anchor not found"); return
    out = t.replace(old, new, count)
    if out == t:
        rec(step, rel(p), "ALREADY", "no change"); return
    if MODE == "apply": save(p, out)
    rec(step, rel(p), "APPLIED" if MODE == "apply" else "WOULD-APPLY",
        "%d replacement(s)" % min(t.count(old), count))

def write(step, path, content):
    p = os.path.join(ROOT, path)
    if os.path.exists(p) and load(p) == content:
        rec(step, rel(p), "ALREADY", "identical content"); return
    if MODE == "apply":
        os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
        save(p, content)
        rec(step, rel(p), "APPLIED", "written")
    else:
        rec(step, rel(p), "WOULD-APPLY", "would be rewritten")

# ===========================================================================
# 1. Global QML import normalisation
#    (the session's `sed -i -E 's/^import (QtQuick...) [0-9.]+$/.../'`)
# ===========================================================================
IMPORT_PAT = re.compile(r"^import (QtQuick(?:\.[A-Za-z]+)?)\s+\d+\.\d+\s*$", re.M)
STYLES_PAT = re.compile(r"^import QtQuick\.Controls\.Styles[^\n]*\n", re.M)

for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "qml")):
    for fn in files:
        if not fn.endswith(".qml"): continue
        p = os.path.join(dirpath, fn)
        t = load(p); o = t
        t = STYLES_PAT.sub("", t)
        t = IMPORT_PAT.sub(lambda m: "import " + m.group(1), t)
        if t != o:
            if MODE == "apply": save(p, t)
            rec("strip imports", rel(p), "APPLIED" if MODE == "apply" else "WOULD-APPLY", "")

# ===========================================================================
# 2. Full rewrites
# ===========================================================================

# --- IconButton: QQC2 button with an "icon" group property -----------------
write("IconButton", "qml/Firebird/UIComponents/IconButton.qml",
"""import QtQuick
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
""")

# --- FileSelect: FileDialog API + id: root ---------------------------------
write("FileSelect", "qml/Firebird/UIComponents/FileSelect.qml",
"""import QtQuick
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
        iconSource: "qrc:/icons/resources/icons/document-new.png"

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
        iconSource: "qrc:/icons/resources/icons/document-edit.png"
        onClicked: {
            dialogLoader.active = true;
            dialogLoader.item.visible = true;
        }
    }
}
""")

# --- KitList: ScrollView -> Item + ListView + ScrollBar --------------------
write("KitList", "qml/Firebird/UIComponents/KitList.qml",
"""import QtQuick
import QtQuick.Controls
import Firebird.Emu 1.0

Rectangle {
    property alias currentItem: listView.currentItem
    property alias currentIndex: listView.currentIndex
    property alias kitModel: listView.model

    SystemPalette {
        id: paletteActive
    }

    color: paletteActive.base
    border {
        color: paletteActive.alternateBase
        width: 1
    }

    Item {
        anchors.margins: parent.border.width
        anchors.fill: parent
        clip: true

        ListView {
            id: listView

            anchors.fill: parent
            activeFocusOnTab: true
            focus: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {}

            highlightMoveDuration: 50
            highlightResizeDuration: 0

            highlight: Rectangle {
                color: paletteActive.highlight
                anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
            }

            delegate: Item {
                property variant myData: model

                height: item.height + 10
                width: listView.width

                MouseArea {
                    anchors.fill: parent
                    onClicked: function() {
                        parent.ListView.view.currentIndex = index
                        parent.forceActiveFocus()
                    }
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }

                    color: paletteActive.shadow
                    height: 1
                }

                KitItem {
                    id: item
                    width: parent.width - 15
                    anchors.centerIn: parent

                    kitName: name
                    flashFile: Emu.basename(flash)
                    stateFile: Emu.basename(snapshot)
                }

                FBLink {
                    anchors {
                        top: parent.top
                        right: copyButton.left
                        topMargin: 5
                        rightMargin: 5
                    }

                    text: qsTr("Remove")
                    visible: parent.ListView.view.currentIndex === index && parent.ListView.view.count > 1
                    onClicked: {
                        kitModel.remove(index)
                    }
                }

                FBLink {
                    id: copyButton

                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 5
                        rightMargin: 5
                    }

                    text: qsTr("Copy")
                    visible: parent.ListView.view.currentIndex === index
                    onClicked: {
                        kitModel.copy(index)
                    }
                }
            }

            section.property: "type"
            section.criteria: ViewSection.FullString
            section.delegate: Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                color: paletteActive.window
                height: label.implicitHeight + 4
                width: listView.width

                FBLabel {
                    id: label
                    font.bold: true
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    verticalAlignment: Text.AlignVCenter
                    text: section
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }

                    color: paletteActive.shadow
                    height: 1
                }
            }
        }
    }
}
""")

# --- ScrollingKeypad: ScrollView -> Flickable ------------------------------
write("ScrollingKeypad", "qml/ScrollingKeypad.qml",
"""import QtQuick

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
""")

# --- MobileUIConfig: TabView -> TabBar + StackLayout ------------------------
write("MobileUIConfig", "qml/MobileUIConfig.qml",
"""import QtQuick
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
""")

# ===========================================================================
# 3. Targeted replacements
# ===========================================================================

# --- FlashDialog: Dialog -> Window, Save/Cancel row, FileDialog API --------
rep("FlashDialog", "qml/FlashDialog.qml",
"""Dialog {
    id: flashDialog
    title: qsTr("Create Flash Image")
    // Work around QTBUG-89607: Menu (used by ComboBox) doesn't work in modal windows
    modality: Qt.platform.pluginName == "cocoa" ? Qt.NonModal : Qt.WindowModal
    standardButtons: Dialog.Save | Dialog.Cancel
    onVisibleChanged: {
        // For some reason the initial size on wayland is too big.
        // Setting it to -1 initially appears to work around that.
        if (Qt.platform.pluginName.startsWith("wayland")) {
            width = -1;
            height = -1;
        }
    }

    signal flashCreated(string filePath)

    GridLayout {
        id: layout
        width: parent.width
        columns: 2
""",
"""// Qt Quick Controls 2 has no window based Dialog, so this is a plain Window.
Window {
    id: flashDialog
    title: qsTr("Create Flash Image")
    modality: Qt.WindowModal
    flags: Qt.Dialog

    // The layout's height depends on which rows are visible
    minimumWidth: 400
    minimumHeight: layout.implicitHeight + 2 * layout.anchors.margins
    width: Math.max(minimumWidth, layout.implicitWidth + 2 * layout.anchors.margins)
    height: minimumHeight

    SystemPalette {
        id: paletteActive
    }

    color: paletteActive.window

    signal flashCreated(string filePath)

    GridLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 5
        columns: 2
""")

rep("FlashDialog", "qml/FlashDialog.qml",
"""        FBLabel {
            Layout.alignment: Qt.AlignCenter
            Layout.columnSpan: 2
            color: "red"
            text: parent.validationText
        }
    }
""",
"""        FBLabel {
            Layout.alignment: Qt.AlignCenter
            Layout.columnSpan: 2
            color: "red"
            text: parent.validationText
        }

        Item {
            Layout.fillHeight: true
            Layout.columnSpan: 2
        }

        RowLayout {
            Layout.columnSpan: 2
            Layout.alignment: Qt.AlignRight

            Button {
                text: qsTr("Cancel")
                onClicked: flashDialog.visible = false
            }

            Button {
                text: qsTr("Save")
                enabled: layout.validationText === ""
                onClicked: {
                    // Don't close the dialog now, but only
                    // after successful saving
                    fileDialogLoader.active = true;
                    fileDialogLoader.item.visible = true;
                }
            }
        }
    }
""")

rep("FlashDialog", "qml/FlashDialog.qml",
"""            selectExisting: false
            onAccepted: {
                var filePath = Emu.toLocalFile(fileUrl);""",
"""            fileMode: FileDialog.SaveFile
            onAccepted: {
                var filePath = Emu.toLocalFile(selectedFile);""")

# Drop the old onActionChosen handler (last member before the closing brace)
p = os.path.join(ROOT, "qml/FlashDialog.qml")
if os.path.exists(p):
    t = load(p)
    i = t.find("\n    onActionChosen:")
    if i >= 0:
        out = t[:i].rstrip() + "\n}\n"
        if MODE == "apply": save(p, out)
        rec("FlashDialog", rel(p), "APPLIED" if MODE == "apply" else "WOULD-APPLY",
            "removed onActionChosen")
    else:
        rec("FlashDialog", rel(p), "ALREADY", "onActionChosen gone")

# --- ConfigPageDebug: SpinBox + layout -------------------------------------
for port in ("gdbPort", "rdbPort"):
    rep("ConfigPageDebug", "qml/ConfigPageDebug.qml",
"""            minimumValue: 1
            maximumValue: 65535

            value: Emu.%s""" % port,
"""            from: 1
            to: 65535
            editable: true
            // Don't show a locale dependent group separator in port numbers
            textFromValue: function(value, locale) { return String(value); }

            value: Emu.%s""" % port, required=False)

rep("ConfigPageDebug", "qml/ConfigPageDebug.qml",
"""        spacing: 0
        width: parent.width
        Layout.fillWidth: true""",
"""        spacing: 0
        Layout.fillWidth: true""", required=False)
for port in ("gdbPort", "rdbPort"):
    rep("ConfigPageDebug", "qml/ConfigPageDebug.qml",
        "Layout.maximumWidth: parent.parent.width - %s.width" % port,
        "Layout.fillWidth: true", required=False)

# --- ConfigPageEmulation: ComboBox model + layout --------------------------
rep("ConfigPageEmulation", "qml/ConfigPageEmulation.qml",
    "Emu.defaultKit = model.getDataRow(currentIndex, KitModel.IDRole);",
    "Emu.defaultKit = Emu.kits.getDataRow(currentIndex, KitModel.IDRole);")
rep("ConfigPageEmulation", "qml/ConfigPageEmulation.qml",
"""        spacing: 0
        width: parent.width
        Layout.fillWidth: true""",
"""        spacing: 0
        Layout.fillWidth: true""", required=False)
rep("ConfigPageEmulation", "qml/ConfigPageEmulation.qml",
    "Layout.maximumWidth: parent.parent.width - startupKit.width",
    "Layout.fillWidth: true", required=False)
rep("ConfigPageEmulation", "qml/ConfigPageEmulation.qml",
    "Layout.maximumWidth: parent.parent.width * 0.4",
    "Layout.maximumWidth: parent.width * 0.4", required=False)
# the "// The hell, QML!" line and the other parent.width maximums
rep("ConfigPageEmulation", "qml/ConfigPageEmulation.qml",
"""        // The hell, QML!
        Layout.maximumWidth: parent.width
""",
"""        Layout.fillWidth: true
""", required=False)
rep("ConfigPageEmulation", "qml/ConfigPageEmulation.qml",
    "        Layout.maximumWidth: parent.width\n",
    "        Layout.fillWidth: true\n", count=10**6, required=False)

# --- ConfigPageFileTransfer: FileDialog + ProgressBar ----------------------
rep("ConfigPageFileTransfer", "qml/ConfigPageFileTransfer.qml",
    "            selectMultiple: true\n",
    "            fileMode: FileDialog.OpenFiles\n", required=False)
rep("ConfigPageFileTransfer", "qml/ConfigPageFileTransfer.qml",
"""                for(let i = 0; i < fileUrls.length; ++i)
                    Emu.sendFile(fileUrls[i], Emu.usbdir);""",
"""                for(let i = 0; i < selectedFiles.length; ++i)
                    Emu.sendFile(selectedFiles[i], Emu.usbdir);""", required=False)
rep("ConfigPageFileTransfer", "qml/ConfigPageFileTransfer.qml",
"""        minimumValue: 0
        maximumValue: 100""",
"""        from: 0
        to: 100""", required=False)

# --- ConfigPageKits --------------------------------------------------------
rep("ConfigPageKits", "qml/ConfigPageKits.qml",
    "        Layout.bottomMargin: -1\n", "", required=False)
rep("ConfigPageKits", "qml/ConfigPageKits.qml",
    "                onFlashCreated: {",
    "                onFlashCreated: function(filePath) {", required=False)

# --- Toast -----------------------------------------------------------------
rep("Toast", "qml/Firebird/UIComponents/Toast.qml",
    "Text.Center", "Text.AlignHCenter", required=False)

# --- SidebarButton ---------------------------------------------------------
rep("SidebarButton", "qml/SidebarButton.qml",
    "property alias icon: image.source",
"""// QQC2 buttons already have an "icon" group property
    property alias iconSource: image.source""", required=False)

# --- MobileUI: handlers + loader guard -------------------------------------
rep("MobileUI", "qml/MobileUI.qml", "    onClosing: {\n",
    "    onClosing: function(close) {\n", required=False)
rep("MobileUI", "qml/MobileUI.qml",
"""        standardButtons: StandardButton.Yes | StandardButton.No
        icon: StandardIcon.Warning
        title: qsTr("Suspend failed")
        text: qsTr("Suspending the emulation failed. Do you still want to quit Firebird?")

        onYes: {""",
"""        buttons: MessageDialog.Yes | MessageDialog.No
        title: qsTr("Suspend failed")
        text: qsTr("Suspending the emulation failed. Do you still want to quit Firebird?")

        onButtonClicked: function(button, role) {
            if(button !== MessageDialog.Yes)
                return;
""", required=False)
rep("MobileUI", "qml/MobileUI.qml",
    "        onEmuSuspended: {", "        function onEmuSuspended(success) {", required=False)
rep("MobileUI", "qml/MobileUI.qml",
    "        onToastMessage: {", "        function onToastMessage(msg) {", required=False)
rep("MobileUI", "qml/MobileUI.qml",
    "        onStateChanged: {", "        function onStateChanged() {", required=False)
rep("MobileUI", "qml/MobileUI.qml",
    'width: modelData === "MobileUIDrawer.qml" ? loader.item.implicitWidth : app.width',
    'width: (modelData === "MobileUIDrawer.qml" && loader.item) ? loader.item.implicitWidth : app.width',
    required=False)

# --- MobileUIDrawer: drop StandardIcon -------------------------------------
p = os.path.join(ROOT, "qml/MobileUIDrawer.qml")
if os.path.exists(p):
    t = load(p)
    out, n = re.subn(r"^[ \t]*icon: StandardIcon\.\w+[ \t]*\n", "", t, flags=re.M)
    if n:
        if MODE == "apply": save(p, out)
        rec("MobileUIDrawer", rel(p), "APPLIED" if MODE == "apply" else "WOULD-APPLY",
            "removed %d StandardIcon line(s)" % n)
    else:
        rec("MobileUIDrawer", rel(p), "ALREADY", "no StandardIcon")

# --- Handler parameters ----------------------------------------------------
rep("VerticalSwipeBar", "qml/Firebird/UIComponents/VerticalSwipeBar.qml",
    "        onPressed: {", "        onPressed: function(mouse) {", required=False)
rep("VerticalSwipeBar", "qml/Firebird/UIComponents/VerticalSwipeBar.qml",
    "        onReleased: {", "        onReleased: function(mouse) {", required=False)
rep("Touchpad", "qml/Touchpad.qml",
"""        onPressed: {
            origX = mouse.x;""",
"""        onPressed: function(mouse) {
            origX = mouse.x;""", required=False)
rep("NButton", "qml/NButton.qml",
    "        onTouchUpdated: {", "        onTouchUpdated: function(touchPoints) {", required=False)
rep("NButton", "qml/NButton.qml",
"""        onPressed: {
            mouse.accepted = true;""",
"""        onPressed: function(mouse) {
            mouse.accepted = true;""", required=False)
rep("NButton", "qml/NButton.qml",
"""        onReleased: {
            mouse.accepted = true;""",
"""        onReleased: function(mouse) {
            mouse.accepted = true;""", required=False)

# ===========================================================================
# 4. TextMetrics -> FBTextMetrics (qml/ + resources.qrc + qmldir)
# ===========================================================================
REN = re.compile(r"(?<!FB)\bTextMetrics\b")
for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "qml")):
    for fn in files:
        if not (fn.endswith(".qml") or fn == "qmldir"): continue
        p = os.path.join(dirpath, fn)
        t = load(p); out = REN.sub("FBTextMetrics", t)
        if out != t:
            if MODE == "apply": save(p, out)
            rec("rename TextMetrics", rel(p), "APPLIED" if MODE == "apply" else "WOULD-APPLY", "")

qrc = os.path.join(ROOT, "resources.qrc")
if os.path.exists(qrc):
    t = load(qrc); out = REN.sub("FBTextMetrics", t)
    if out != t:
        if MODE == "apply": save(qrc, out)
        rec("rename TextMetrics", "resources.qrc", "APPLIED" if MODE == "apply" else "WOULD-APPLY", "")

# qmldir: also register IconButton and KitItem
rep("qmldir", "qml/Firebird/UIComponents/qmldir",
    "FileSelect 1.0 FileSelect.qml\n",
    "FileSelect 1.0 FileSelect.qml\nIconButton 1.0 IconButton.qml\nKitItem 1.0 KitItem.qml\n",
    required=False)

# ===========================================================================
# 5. C++
# ===========================================================================
rep("main.cpp", "main.cpp",
"""    #ifdef Q_OS_ANDROID
        QGuiApplication::setAttribute(Qt::AA_DisableHighDpiScaling);
    #else
        QGuiApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    #endif
    QGuiApplication::setAttribute(Qt::AA_UseHighDpiPixmaps);

""",
"""    // Qt 6 always enables High-DPI scaling and pixmaps, nothing to set up here.

""", required=False)

rep("main.cpp", "main.cpp",
"""    // Needed for settings migration
    qRegisterMetaTypeStreamOperators<KitModel>();
    qRegisterMetaType<KitModel>();
""",
"""    // Needed for settings migration. In Qt 6 the QDataStream operators of KitModel
    // are picked up automatically when the metatype is registered.
    qRegisterMetaType<KitModel>();
""", required=False)

rep("kitmodel.h", "kitmodel.h", "Q_ENUMS(Role)", "Q_ENUM(Role)", required=False)

rep("lcdwidget.cpp", "lcdwidget.cpp",
"""    the_qml_bridge->setTouchpadState((qreal)event->x() / width(), (qreal)event->y() / height(), true, event->button() == Qt::RightButton);""",
"""    const QPointF pos = event->position();
    the_qml_bridge->setTouchpadState(pos.x() / width(), pos.y() / height(), true, event->button() == Qt::RightButton);""",
    required=False)

rep("lcdwidget.cpp", "lcdwidget.cpp",
"""    the_qml_bridge->setTouchpadState((qreal)event->x() / width(), (qreal)event->y() / height(), keypad.touchpad_contact, keypad.touchpad_down);""",
"""    const QPointF pos = event->position();
    the_qml_bridge->setTouchpadState(pos.x() / width(), pos.y() / height(), keypad.touchpad_contact, keypad.touchpad_down);""",
    required=False)

rep("mainwindow.cpp", "mainwindow.cpp",
    "QMouseEvent ev(QMouseEvent::MouseMove, QPointF(0, 0), Qt::NoButton, Qt::NoButton, Qt::NoModifier);",
    "QMouseEvent ev(QEvent::MouseMove, QPointF(0, 0), QPointF(0, 0), Qt::NoButton, Qt::NoButton, Qt::NoModifier);",
    required=False)

# --- os-android.cpp: QtAndroid -> Qt 6 JNI ---------------------------------
OA = "core/os/os-android.cpp"
if os.path.exists(os.path.join(ROOT, OA)):
    rep("os-android", OA, "#include <QtAndroid>", "#include <QCoreApplication>", required=False)
    rep("os-android", OA, "QAndroidJniObject", "QJniObject", count=10**6, required=False)
    rep("os-android", OA, "QAndroidJniEnvironment", "QJniEnvironment", count=10**6, required=False)

    p = os.path.join(ROOT, OA)
    if "#include <QAndroidActivityResultReceiver>" in load(p):
        rep("os-android", OA, "#include <QAndroidActivityResultReceiver>\n", "", required=False)

    rep("os-android", OA,
"""static bool is_content_url(const char *path)""",
"""// The Android context (the activity, if there is one).
// Qt 6.2 returns a jobject, newer versions a QJniObject. Both work here.
static QJniObject androidContext()
{
    return QJniObject(QNativeInterface::QAndroidApplication::context());
}

static bool is_content_url(const char *path)""", required=False)

    rep("os-android", OA,
"""QtAndroid::androidActivity()
            .callObjectMethod("getContentResolver",""",
"""androidContext()
            .callObjectMethod("getContentResolver",""", count=10**6, required=False)

    rep("os-android", OA,
"""QtAndroid::androidActivity()
            .callObjectMethod("getWindow", "()Landroid/view/Window;");""",
"""androidContext()
            .callObjectMethod("getWindow", "()Landroid/view/Window;");""", required=False)

    rep("os-android", OA,
    "uri.object<jobject>(), proj.object<jobject>(), nullptr, nullptr);",
"""uri.object<jobject>(), proj.object<jobject>(),
                                                         static_cast<jobject>(nullptr), static_cast<jobject>(nullptr));""",
    required=False)

    rep("os-android", OA,
"""auto parts = pathStr.splitRef(QStringLiteral("%2F"), QString::SkipEmptyParts, Qt::CaseInsensitive);
            if(parts.length() > 1)
                ret = QUrl::fromPercentEncoding(parts.last().toString().toUtf8());""",
"""const auto parts = pathStr.split(QStringLiteral("%2F"), Qt::SkipEmptyParts, Qt::CaseInsensitive);
            if(parts.length() > 1)
                ret = QUrl::fromPercentEncoding(parts.last().toUtf8());""", required=False)

    rep("os-android", OA,
"""void androidVibrate()
{
    QJniEnvironment env;
""",
"""void androidVibrate()
{
    // The window is only available if the context is an activity.
    if(!QNativeInterface::QAndroidApplication::isActivityContext())
        return;

    QJniEnvironment env;
""", required=False)
else:
    rec("os-android", OA, "SKIP", "file missing")

# --- qmlbridge.cpp: save dialogs work on Android under Qt 6 ----------------
rep("qmlbridge", "qmlbridge.cpp",
"""    #ifdef Q_OS_ANDROID
        // Starting with Qt 5.13, the Android "File Picker" is used, but that doesn't allow creation of files.
        return QVersionNumber::fromString(QString::fromUtf8(qVersion())) < QVersionNumber(5, 13);
    #else
        return true;
    #endif""",
"""    // With Qt 5.13 - 5.15, the Android "File Picker" didn't allow creation of files.
    // Qt 6 uses ACTION_CREATE_DOCUMENT for save dialogs.
    return true;""", required=False)

# ===========================================================================
# 6. firebird.pro
# ===========================================================================
rep("firebird.pro", "firebird.pro",
"""lessThan(QT_MAJOR_VERSION, 5): error("You need at least Qt 5.9 to build Firebird!")
equals(QT_MAJOR_VERSION, 5):lessThan(QT_MINOR_VERSION, 9): error("You need at least Qt 5.9 to build Firebird!")
""",
"""# Qt 6.2 is the minimum because the Android build uses it (it is the last
# Qt version supporting Android 6-8). Desktop builds use newer versions.
lessThan(QT_MAJOR_VERSION, 6): error("You need at least Qt 6.2 to build Firebird!")
equals(QT_MAJOR_VERSION, 6):lessThan(QT_MINOR_VERSION, 2): error("You need at least Qt 6.2 to build Firebird!")
""", required=False)

rep("firebird.pro", "firebird.pro",
"""QT += core gui widgets quickwidgets
android: QT += androidextras
CONFIG += c++11
""",
"""QT += core gui widgets quickwidgets quickcontrols2
# Qt 6 requires C++17
CONFIG += c++17
""", required=False)

rep("firebird.pro", "firebird.pro",
"""macx: ICON = resources/logo.icns
macx: QMAKE_LIBS_OPENGL = -framework OpenGL
# MAP_JIT requires macOS 10.14. Qt 6 already requires a newer macOS version.
macx:!ios:lessThan(QT_MAJOR_VERSION, 6): QMAKE_MACOSX_DEPLOYMENT_TARGET = 10.14
""",
"""macx: ICON = resources/logo.icns
# MAP_JIT requires macOS 10.14. Qt 6 already requires a newer macOS version,
# so the default deployment target of Qt is used.
""", required=False)

rep("firebird.pro", "firebird.pro",
"""ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android
""",
"""ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android
# Qt 6.2 supports Android 6.0 (API 23) and newer.
ANDROID_MIN_SDK_VERSION = 23
ANDROID_TARGET_SDK_VERSION = 28
""", required=False)

# ===========================================================================
# 7. Android manifest
# ===========================================================================
write("Android manifest", "android/AndroidManifest.xml",
"""<?xml version="1.0"?>
<manifest package="org.firebird.emu" xmlns:android="http://schemas.android.com/apk/res/android" android:versionName="1.6" android:versionCode="10" android:installLocation="auto">
    <!-- The following comment will be replaced upon deployment with default permissions based on the dependencies of the application.
         Remove the comment if you do not require these default permissions. -->
    <!-- %%INSERT_PERMISSIONS -->

    <!-- The following comment will be replaced upon deployment with default features based on the dependencies of the application.
         Remove the comment if you do not require these default features. -->
    <!-- %%INSERT_FEATURES -->

    <supports-screens android:largeScreens="true" android:normalScreens="true" android:anyDensity="true" android:smallScreens="true"/>

    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>

    <!-- minSdkVersion and targetSdkVersion are set by ANDROID_MIN_SDK_VERSION
         and ANDROID_TARGET_SDK_VERSION in firebird.pro -->
    <application android:hardwareAccelerated="true"
                 android:name="org.qtproject.qt.android.bindings.QtApplication"
                 android:label="Firebird Emu"
                 android:icon="@drawable/icon"
                 android:extractNativeLibs="true"
                 android:requestLegacyExternalStorage="true"
                 android:allowNativeHeapPointerTagging="false">
        <activity android:name="org.qtproject.qt.android.bindings.QtActivity"
                  android:configChanges="orientation|uiMode|screenLayout|screenSize|smallestScreenSize|layoutDirection|locale|fontScale|keyboard|keyboardHidden|navigation|mcc|mnc|density"
                  android:label="-- %%INSERT_APP_NAME%% --"
                  android:screenOrientation="unspecified"
                  android:launchMode="singleTop"
                  android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <meta-data android:name="android.app.lib_name" android:value="-- %%INSERT_APP_LIB_NAME%% --"/>
            <meta-data android:name="android.app.arguments" android:value="-- %%INSERT_APP_ARGUMENTS%% --"/>
            <meta-data android:name="android.app.extract_android_style" android:value="minimal"/>

            <!-- Splash screen -->
            <meta-data android:name="android.app.splash_screen_drawable" android:resource="@drawable/splash"/>
            <!-- Splash screen -->

            <meta-data android:name="android.max_aspect" android:value="2.5"/>
        </activity>
    </application>
</manifest>
""")

# ===========================================================================
# 8. Verification
# ===========================================================================
def scan(pattern, where, label):
    rx = re.compile(pattern)
    hits = []
    base = os.path.join(ROOT, where)
    for dirpath, _d, files in os.walk(base):
        for fn in files:
            if not (fn.endswith(".qml") or fn == "qmldir"): continue
            p = os.path.join(dirpath, fn)
            for i, line in enumerate(load(p).splitlines(), 1):
                if rx.search(line):
                    hits.append("%s:%d" % (rel(p), i))
    if hits:
        rec(label, where, "MISSING", "%d hit(s), e.g. %s" % (len(hits), hits[0]))
    else:
        rec(label, where, "OK", "clean")

scan(r"^import QtQuick\.(Controls|Dialogs|Window|Layouts)\s+[0-9]", "qml", "verify QtQuick imports")
scan(r"^import QtQuick\s+[0-9]", "qml", "verify QtQuick core import")
scan(r"^import QtQuick\.Controls\.Styles", "qml", "verify Controls.Styles")
scan(r"(?<!FB)\bTextMetrics\b", "qml", "verify TextMetrics")

# ------------------------------------------------------------------ report --
order = {"APPLIED": 0, "WOULD-APPLY": 1, "OK": 2, "ALREADY": 3,
         "SKIP": 4, "MISSING": 5}
rows.sort(key=lambda r: (order.get(r[2], 9), r[0], r[1]))

counts = {}
for _s, _p, st, _d in rows:
    counts[st] = counts.get(st, 0) + 1

w = max([len(r[1]) for r in rows] + [10])
lines = ["Firebird Qt 6 port — replay report", "mode: %s" % MODE, ""]
for step, path, st, detail in rows:
    lines.append("%-11s %-22s %s  %s" % (st, step[:22], path.ljust(w), detail))
lines.append("")
lines.append("summary: " + ", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts)))
lines.append("")
lines.append("Not covered by this script: .github/workflows/*, and verification of the")
lines.append("Android, Windows and macOS builds (Linux/Qt 6.4 only).")

out = "\n".join(lines) + "\n"
with open(REPORT, "w", encoding="utf-8") as f:
    f.write(out)
sys.stdout.write(out)
sys.exit(1 if counts.get("MISSING", 0) else 0)
PY

PYRC=$?
echo

# ------------------------------------------------------------------ dialog ---
if [ "$NO_DIALOG" = 0 ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if   command -v zenity  >/dev/null 2>&1; then
        zenity --text-info --title "Firebird Qt 6 port — replay" \
               --filename "$REPORT" --width 1000 --height 700 2>/dev/null
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title "Firebird Qt 6 port — replay" --textbox "$REPORT" 1000 700 2>/dev/null
    elif command -v xmessage >/dev/null 2>&1; then
        xmessage -file "$REPORT" -center 2>/dev/null
    fi
fi

# ------------------------------------------------------------------- build ---
if [ "$DO_BUILD" = 1 ] && [ "$MODE" = apply ]; then
    QMAKE="$(command -v qmake6 || command -v qmake || true)"
    if [ -z "$QMAKE" ]; then
        echo "error: qmake6 not found" >&2; exit 2
    fi
    BD="$(dirname "$ROOT")/firebird-qt6-build"
    echo "--- build: $BD ---"
    rm -rf "$BD"; mkdir -p "$BD"; cd "$BD" || exit 2
    "$QMAKE" "$ROOT/firebird.pro" 2>&1 | tail -15 || exit 2
    make -j"$(nproc 2>/dev/null || echo 4)" 2>&1 \
        | grep -E "error|Error|warning: .*(deprec)|undefined" | head -40
    [ -x "$BD/firebird-emu" ] && echo "built: $BD/firebird-emu"
fi

[ "$MODE" = apply ] && [ "$GIT" = 1 ] && {
    echo "--- git status ---"
    git -C "$ROOT" status --short
}

exit "$PYRC"
