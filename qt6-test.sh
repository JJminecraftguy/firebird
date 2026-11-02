#!/usr/bin/env bash
# fix-qtframebuffer-scaling.sh — run from the firebird repo root
set -euo pipefail
ROOT="${1:-$PWD}"
ROOT="$(cd "$ROOT" && pwd)"
FILE="$ROOT/qtframebuffer.cpp"
[ -f "$FILE" ] || { echo "missing $FILE" >&2; exit 2; }
cp "$FILE" "$FILE.bak.$(date +%s)"

python3 - "$FILE" <<'PY'
import sys
p = sys.argv[1]
with open(p) as f:
    t = f.read()

# Refactor: extract the drawing into paintFramebufferInto(p, target, dpr)
# so both the widget path and the QML path can share it with the right rect.
old_widget = '''void paintFramebuffer(QPainter *p)
{
#ifdef IS_IOS_BUILD
    // Apparently, this is needed (will be 2 on retina screens)
    // TODO: actually make sure Android doesn't need that as well
    static const double devicePixelRatio = ((QGuiApplication*)QCoreApplication::instance())->primaryScreen()->devicePixelRatio();
#else
    // Has to be 1 on desktop, even on retina (tested on OS X 10.11 with one retina, one non-retina, and both ; same on Win VM)
    static const double devicePixelRatio = 1;
#endif

    QRect painterWindowScaled(p->window().topLeft(), p->window().size() / devicePixelRatio);

    if(hdq1w.lcd_contrast == 0)
    {
        p->fillRect(painterWindowScaled, emulate_cx ? Qt::black : Qt::white);
        p->setPen(emulate_cx ? Qt::white : Qt::black);
        p->drawText(painterWindowScaled, Qt::AlignCenter, QObject::tr("LCD turned off"));
    }
    else
    {
        QImage image = renderFramebuffer().scaled(p->window().size(), Qt::KeepAspectRatio, Qt::SmoothTransformation);
        image.setDevicePixelRatio(devicePixelRatio);
        p->drawImage((p->window().width() - image.width()) / 2, (p->window().height() - image.height()) / 2, image);
    }

    if(in_debugger)
    {
        p->setCompositionMode(QPainter::CompositionMode_SourceOver);
        p->fillRect(painterWindowScaled, QColor(30, 30, 30, 150));
        p->setPen(Qt::white);
        p->drawText(painterWindowScaled, Qt::AlignCenter, QObject::tr("In debugger"));
    }
}'''

new_widget = '''static void paintFramebufferInto(QPainter *p, const QRect &target, double imageDpr)
{
    if(hdq1w.lcd_contrast == 0)
    {
        p->fillRect(target, emulate_cx ? Qt::black : Qt::white);
        p->setPen(emulate_cx ? Qt::white : Qt::black);
        p->drawText(target, Qt::AlignCenter, QObject::tr("LCD turned off"));
    }
    else
    {
        QImage image = renderFramebuffer().scaled(target.size(), Qt::KeepAspectRatio, Qt::SmoothTransformation);
        image.setDevicePixelRatio(imageDpr);
        p->drawImage(target.x() + (target.width() - image.width()) / 2,
                     target.y() + (target.height() - image.height()) / 2,
                     image);
    }

    if(in_debugger)
    {
        p->setCompositionMode(QPainter::CompositionMode_SourceOver);
        p->fillRect(target, QColor(30, 30, 30, 150));
        p->setPen(Qt::white);
        p->drawText(target, Qt::AlignCenter, QObject::tr("In debugger"));
    }
}

void paintFramebuffer(QPainter *p)
{
#ifdef IS_IOS_BUILD
    // Apparently, this is needed (will be 2 on retina screens)
    // TODO: actually make sure Android doesn't need that as well
    static const double devicePixelRatio = ((QGuiApplication*)QCoreApplication::instance())->primaryScreen()->devicePixelRatio();
#else
    // Has to be 1 on desktop, even on retina (tested on OS X 10.11 with one retina, one non-retina, and both ; same on Win VM)
    static const double devicePixelRatio = 1;
#endif

    QRect painterWindowScaled(p->window().topLeft(), p->window().size() / devicePixelRatio);
    paintFramebufferInto(p, painterWindowScaled, devicePixelRatio);
}'''

if old_widget not in t:
    print("ERROR: paintFramebuffer block not found verbatim", file=sys.stderr)
    sys.exit(1)
t = t.replace(old_widget, new_widget, 1)

old_qml = '''void QMLFramebuffer::paint(QPainter *p)
{
    paintFramebuffer(p);
}'''

new_qml = '''void QMLFramebuffer::paint(QPainter *p)
{
    // Use the item's own bounds, not the top-level window. The painter is
    // already set up so (0,0) is the item's top-left. dpr = 1 because the
    // QQuickPaintedItem painter is already scaled by the scene graph; the
    // image should be laid out in item-local logical pixels.
    const QRect target(0, 0, int(width()), int(height()));
    paintFramebufferInto(p, target, 1.0);
}'''

if old_qml not in t:
    print("ERROR: QMLFramebuffer::paint not found verbatim", file=sys.stderr)
    sys.exit(1)
t = t.replace(old_qml, new_qml, 1)

with open(p, "w") as f:
    f.write(t)
print("Patched:", p)
PY

echo
echo "=== DONE ==="
