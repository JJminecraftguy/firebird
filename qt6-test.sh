#!/usr/bin/env bash
# fix-mobile-lightmode.sh — run from the firebird repo root
set -euo pipefail
ROOT="${1:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
[ -f "$ROOT/firebird.pro" ] || { echo "not a firebird checkout" >&2; exit 2; }

python3 - "$ROOT" <<'PY'
import re, os, sys
root = sys.argv[1]
def read(p): return open(p, encoding="utf-8").read()
def write(p, t): open(p, "w", encoding="utf-8").write(t)

# ── 1. main.cpp: force light palette on mobile ────────────────────────
p = os.path.join(root, "main.cpp")
t = read(p)

if "#include <QPalette>" not in t:
    t = t.replace("#include <QTranslator>\n",
                  "#include <QTranslator>\n#include <QPalette>\n", 1)

old = """    #ifdef MOBILE_UI
        QGuiApplication app(argc, argv);

        QTranslator appTranslator;
        loadAppTranslation(appTranslator, QLocale::system());
        app.installTranslator(&appTranslator);
"""
new = """    #ifdef MOBILE_UI
        // Force the Material style to light theme regardless of the
        // system's night-mode setting. Must be set before QGuiApplication.
        qputenv("QT_QUICK_CONTROLS_MATERIAL_THEME", "Light");

        QGuiApplication app(argc, argv);

        // Override the palette too, so light colors are used even if the
        // active style is Fusion rather than Material.
        {
            QPalette lightPalette;
            lightPalette.setColor(QPalette::Window,          QColor(0xef, 0xef, 0xef));
            lightPalette.setColor(QPalette::WindowText,      Qt::black);
            lightPalette.setColor(QPalette::Base,            Qt::white);
            lightPalette.setColor(QPalette::AlternateBase,   QColor(0xf7, 0xf7, 0xf7));
            lightPalette.setColor(QPalette::Text,            Qt::black);
            lightPalette.setColor(QPalette::Button,          QColor(0xef, 0xef, 0xef));
            lightPalette.setColor(QPalette::ButtonText,      Qt::black);
            lightPalette.setColor(QPalette::BrightText,      Qt::red);
            lightPalette.setColor(QPalette::Highlight,       QColor(0x30, 0x8c, 0xc6));
            lightPalette.setColor(QPalette::HighlightedText, Qt::white);
            lightPalette.setColor(QPalette::Disabled, QPalette::Text,       QColor(0xa0, 0xa0, 0xa0));
            lightPalette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(0xa0, 0xa0, 0xa0));
            QGuiApplication::setPalette(lightPalette);
        }

        QTranslator appTranslator;
        loadAppTranslation(appTranslator, QLocale::system());
        app.installTranslator(&appTranslator);
"""
if old in t:
    t = t.replace(old, new, 1)
    write(p, t)
    print("[main.cpp] light palette forced on mobile")
else:
    print("[main.cpp] pattern not found — check manually")

# ── 2. Undo the Emu.isMobile() forcing from the previous patch ────────
# The previous fix forced white text on all mobile; with a forced light
# palette that would produce white-on-white. Strip the forcing so the
# adaptive check does the right thing in both cases.
for rel in ["qml/Firebird/UIComponents/FileSelect.qml",
            "qml/ConfigPageKits.qml",
            "qml/Firebird/UIComponents/KitItem.qml",
            "qml/FlashDialog.qml"]:
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        print(f"[{rel}] not found, skipping")
        continue
    t = read(p)
    t2 = t.replace(
        "(Emu.isMobile() || paletteActive.window.hslLightness < 0.5)",
        "(paletteActive.window.hslLightness < 0.5)")
    if t2 != t:
        write(p, t2)
        print(f"[{rel}] reverted Emu.isMobile() forcing")
    else:
        print(f"[{rel}] no changes (not previously patched)")

# ── 3. MobileUIFront.qml: cap EmuScreen width to fit within height ────
p = os.path.join(root, "qml/MobileUIFront.qml")
t = read(p)

old = """    EmuScreen {
        id: screen
        implicitHeight: (mobileui.width - swipeBar.implicitWidth) / 320 * 240
        Layout.fillWidth: true
"""
new = """    EmuScreen {
        id: screen
        // Fit 4:3 inside the available area, so it doesn't overflow when
        // the container is wider than 4:3 (e.g. landscape on a 16:9 phone).
        readonly property real _aspect: 320.0 / 240.0
        readonly property real _availW: mobileui.width - swipeBar.implicitWidth
        readonly property real _availH: mobileui.height
        readonly property real _fitW: Math.min(_availW, _availH * _aspect)
        implicitWidth: _fitW
        implicitHeight: _fitW / _aspect
        Layout.fillWidth: true
        Layout.maximumWidth: _fitW
"""
if old in t:
    t = t.replace(old, new, 1)
    write(p, t)
    print("[MobileUIFront.qml] EmuScreen aspect-fit applied")
else:
    print("[MobileUIFront.qml] pattern not found — the file changed since last paste")
PY

echo
echo "=== DONE ==="
