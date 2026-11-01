#!/usr/bin/env bash
# fix-flash-boot1-tab.sh
#
# 1. FileSelect.qml: `iconSource:` on Button -> `icon.source:`  (root cause)
# 2. FlashDialog.qml: ensure `import QtQuick.Window` (Window moved from
#    QtQuick.Controls, which exported it, to QtQuick.Window in Qt 6)
# 3. ConfigPageEmulation.qml: stop binding a ComboBox's Layout.maximumWidth
#    to its own parent's width -> "Detected recursive rearrange"
#
# Usage:  cd firebird && ./fix-flash-boot1-tab.sh [--rebuild]

set -euo pipefail

ROOT=""
REBUILD=0
for arg in "$@"; do
    case "$arg" in
        --rebuild) REBUILD=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "unknown option: $arg" >&2; exit 2 ;;
        *)         ROOT="$arg" ;;
    esac
done

ROOT="${ROOT:-$PWD}"
[ -f "$ROOT/firebird.pro" ] || { echo "error: $ROOT is not a firebird checkout" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

python3 - "$ROOT" <<'PY'
import os, sys
root = sys.argv[1]

# 1. FileSelect.qml -- Button has icon.source, not iconSource
p = os.path.join(root, "qml/Firebird/UIComponents/FileSelect.qml")
t = open(p).read()
n = 0
for name in ("document-new", "document-edit"):
    old = f'iconSource: "qrc:/icons/resources/icons/{name}.png"'
    new = f'icon.source: "qrc:/icons/resources/icons/{name}.png"'
    if old in t:
        t = t.replace(old, new); n += 1
open(p, "w").write(t)
print(f"[FileSelect.qml] iconSource -> icon.source: {n} replacement(s)")

# 2. FlashDialog.qml -- Window lives in QtQuick.Window
p = os.path.join(root, "qml/FlashDialog.qml")
t = open(p).read()
if "import QtQuick.Window" in t:
    print("[FlashDialog.qml] already imports QtQuick.Window")
else:
    lines = t.split("\n")
    inserted = False
    for i, line in enumerate(lines):
        if line.strip() == "import QtQuick":
            lines.insert(i + 1, "import QtQuick.Window"); inserted = True; break
    if not inserted:
        for i, line in enumerate(lines):
            if line.startswith("import "):
                lines.insert(i + 1, "import QtQuick.Window"); inserted = True; break
    if not inserted:
        lines.insert(0, "import QtQuick.Window")
    open(p, "w").write("\n".join(lines))
    print("[FlashDialog.qml] added import QtQuick.Window")

# 3. ConfigPageEmulation.qml -- unbind Layout.maximumWidth from own parent width
p = os.path.join(root, "qml/ConfigPageEmulation.qml")
t = open(p).read(); before = t
t = t.replace("Layout.maximumWidth: parent.width * 0.4",
              "Layout.maximumWidth: parent.parent.width * 0.4")
t = t.replace("Layout.maximumWidth: root.width * 0.4",
              "Layout.maximumWidth: parent.parent.width * 0.4")
if t != before:
    open(p, "w").write(t)
    print("[ConfigPageEmulation.qml] anchored ComboBox width to outer ColumnLayout")
else:
    print("[ConfigPageEmulation.qml] no change needed")

# verify
p = os.path.join(root, "qml/Firebird/UIComponents/FileSelect.qml")
left = open(p).read().count("iconSource:")
if left:
    print(f"[warn] {left} iconSource: still present in FileSelect.qml")
else:
    print("[FileSelect.qml] clean")
PY

if [ "$REBUILD" = 1 ]; then
    BUILD="$(dirname "$ROOT")/firebird-build"
    echo
    echo "== rebuilding in $BUILD =="
    mkdir -p "$BUILD"; cd "$BUILD"
    qmake6 "$ROOT/firebird.pro" CONFIG+=release
    make -j"$(nproc)"
    echo
    echo "built: $BUILD/firebird-emu"
fi
