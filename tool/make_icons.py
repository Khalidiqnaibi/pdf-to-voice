"""Generates the launcher icons from the app's own wordmark.

The in-app mark is a rounded square carrying a warm amber gradient with the
Material `graphic_eq_rounded` glyph on top, in the dark accent ink. This script
redraws that at icon resolutions rather than screenshotting it, so the launcher
icon is identical to what the app shows about itself.

Outputs:
  android/app/src/main/res/mipmap-*/ic_launcher.png          legacy icon
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  adaptive layer
  windows/runner/resources/app_icon.ico                      multi-size icon

Run:  python tool/make_icons.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Straight from lib/theme/app_theme.dart.
ACCENT = (240, 180, 92)        # LumenPalette.accent
ACCENT_INK = (36, 24, 4)       # LumenPalette.accentInk
CANVAS = (13, 15, 19)          # LumenPalette.canvas

# The in-app mark fades the accent to 65% alpha over the canvas; flatten that
# to an opaque colour so the icon needs no transparency.
ACCENT_FADED = tuple(round(0.65 * a + 0.35 * c) for a, c in zip(ACCENT, CANVAS))

# Material `graphic_eq`, as (x, height) pairs on its 24x24 grid. Every bar is
# 2 units wide and centred on y=12, with fully rounded caps.
BARS = [(3, 4), (7, 12), (11, 20), (15, 12), (19, 4)]
BAR_W = 2
GRID = 24

# Supersample, then downscale: gives clean edges without any AA work.
SS = 8


def gradient_square(size: int, radius_ratio: float) -> Image.Image:
    """Rounded square with the accent gradient running top-left to bottom-right."""
    n = size * SS
    grad = Image.new('RGB', (n, n))
    px = grad.load()
    for y in range(n):
        for x in range(n):
            # Diagonal position, 0 at top-left and 1 at bottom-right.
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(ACCENT, ACCENT_FADED)
            )

    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, n - 1, n - 1), radius=int(n * radius_ratio), fill=255
    )

    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def glyph(size: int, scale: float, colour=ACCENT_INK) -> Image.Image:
    """The equaliser bars, centred, occupying `scale` of the canvas width."""
    n = size * SS
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    unit = n * scale / GRID
    offset = (n - GRID * unit) / 2

    for x, height in BARS:
        left = offset + x * unit
        right = left + BAR_W * unit
        top = offset + (GRID - height) / 2 * unit
        bottom = top + height * unit
        draw.rounded_rectangle(
            (left, top, right, bottom),
            radius=(right - left) / 2,
            fill=colour + (255,),
        )

    return img.resize((size, size), Image.LANCZOS)


def full_icon(size: int) -> Image.Image:
    """Legacy launcher icon: gradient tile with the glyph on it."""
    base = gradient_square(size, radius_ratio=0.22)
    base.alpha_composite(glyph(size, scale=0.52))
    return base


def write(path: str, image: Image.Image) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path)
    print('  %-58s %dx%d' % (os.path.relpath(path, ROOT), *image.size))


def main() -> None:
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')

    # Legacy icon, one per density bucket.
    print('android legacy icons:')
    for bucket, size in [
        ('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)
    ]:
        write(os.path.join(res, 'mipmap-%s' % bucket, 'ic_launcher.png'), full_icon(size))

    # Adaptive foreground. The canvas is 108dp but only the middle 72dp is
    # guaranteed visible, so the glyph is drawn well inside that safe zone.
    print('android adaptive foreground:')
    for bucket, size in [
        ('mdpi', 108), ('hdpi', 162), ('xhdpi', 216), ('xxhdpi', 324), ('xxxhdpi', 432)
    ]:
        write(
            os.path.join(res, 'mipmap-%s' % bucket, 'ic_launcher_foreground.png'),
            glyph(size, scale=0.40),
        )

    # Windows wants every size inside one .ico.
    print('windows icon:')
    ico = os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico')
    sizes = [16, 32, 48, 64, 128, 256]
    full_icon(256).save(ico, format='ICO', sizes=[(s, s) for s in sizes])
    print('  %-58s %s' % (os.path.relpath(ico, ROOT), sizes))


if __name__ == '__main__':
    main()
