#!/usr/bin/env bash
# fix-fileselect-icons.sh
#
# Fix FileSelect.qml's two buttons rendering as solid white on Qt 6.12.
#
# Cause: the port replaced the Qt 5 `Image`-inside-`Button` pattern with
# QQC2's `icon.source`, which is rendered by the active style. Under
# Fusion, `icon.source` is tinted with palette.buttonText, so a light
# palette turns every icon white.
#
# Fix: draw the PNG through `contentItem: Image`, which bypasses the
# style's icon rendering entirely, as it did before the port.
#
#   ./fix-fileselect-icons.sh [path]          # apply
#   ./fix-fileselect-icons.sh [path] --dry    # show what would change

set -euo pipefail

ROOT="${1:-$PWD}"
DRY=0
[ "${2:-}" = "--dry" ] && DRY=1
[ -f "$ROOT/firebird.pro" ] || { echo "error: not a firebird checkout" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

FS="$ROOT/qml/Firebird/UIComponents/FileSelect.qml"
[ -f "$FS" ] || { echo "error: $FS not found" >&2; exit 2; }

if [ "$DRY" = 1 ]; then
    echo "would patch: $FS"
else
    cp "$FS" "$FS.bak.$(date +%Y%m%d-%H%M%S)"
fi

FS="$FS" DRY="$DRY" python3 - <<'PY'
import os, re, sys
p   = os.environ["FS"]
dry = os.environ["DRY"] == "1"
t   = open(p).read()
before = t

def replace_icon(text, name):
    """Turn a Button's `icon.source`/`iconSource` property into contentItem: Image."""
    img = (
        "        contentItem: Image {\n"
        f'            source: "qrc:/icons/resources/icons/{name}.png"\n'
        "            sourceSize.width: Math.round(FBTextMetrics.normalSize * 1.5)\n"
        "            sourceSize.height: Math.round(FBTextMetrics.normalSize * 1.5)\n"
        "            fillMode: Image.PreserveAspectFit\n"
        "            smooth: true\n"
        "        }\n"
    )
    for key in (f'        icon.source: "qrc:/icons/resources/icons/{name}.png"\n',
                f'        iconSource:  "qrc:/icons/resources/icons/{name}.png"\n',
                f'        iconSource: "qrc:/icons/resources/icons/{name}.png"\n'):
        if key in text:
            return text.replace(key, img), True
    return text, False

t, n1 = replace_icon(t, "document-new")
t, n2 = replace_icon(t, "document-edit")
print(f"document-new : {'patched' if n1 else 'already fixed / not found'}")
print(f"document-edit: {'patched' if n2 else 'already fixed / not found'}")

if t == before:
    print("no changes needed", file=sys.stderr)
    sys.exit(0)

if dry:
    print("\n--- would write ---")
    print(t[t.find("    Button {", t.find("document-new")-200):][:600] if False else "(dry run, nothing written)")
else:
    open(p, "w").write(t)
    print(f"wrote: {p}")
PY

cat <<'EOM'

== next ==
  Rebuild the binary (not the CI artifact — that has the old code):
    cd firebird
    mkdir -p build && cd build
    qmake6 ../firebird.pro CONFIG+=release
    make -j"$(nproc)"
    ./firebird-emu

  Or commit and let CI rebuild.

  If icons are STILL white after this, the fallback one-liner is to add
    icon.color: "transparent"
  to each Button that has icon.source — this disables the tint but still
  uses the style's icon path. The contentItem: Image above is the more
  reliable fix; the one-liner exists only in case something about the
  layout changes unexpectedly.
EOM
