"""Generates large brand assets for social profiles and link previews.

Reuses the icon geometry from make_icons.py so everything stays identical to the
mark the app draws about itself, and pulls the real wordmark typeface (Fraunces,
SIL Open Font License) rather than approximating it with a system serif.

Outputs into brand/:
  lumen-icon-1024.png         rounded-square app icon, transparent corners
  lumen-icon-512.png          same, smaller
  lumen-avatar-1024.png       full-bleed, safe for a circular profile crop
  lumen-banner-1200x630.png   link preview / Open Graph card

Run:  python tool/make_social.py
"""

from __future__ import annotations

import io as _io
import os
import urllib.request

from PIL import Image, ImageDraw, ImageFont

from make_icons import ACCENT, ACCENT_INK, CANVAS, full_icon, glyph, gradient_square

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = os.path.join(ROOT, 'brand')

# Variable TTFs straight from Google Fonts; both are open licensed.
FRAUNCES = (
    'https://fonts.gstatic.com/s/fraunces/v38/6NUh8FyLNQOQZAnv9bYEvDiIdE9Ea92ue'
    'mAk_WBq8U_9v0c2Wa0K7iN7hzFUPJH58nib1603gg7S2nfgRYIcaRyjDg.ttf'
)
INTER = (
    'https://fonts.gstatic.com/s/inter/v20/'
    'UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZg.ttf'
)

_cache: dict[str, bytes] = {}


def download(url: str) -> bytes:
    if url not in _cache:
        request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(request, timeout=60) as response:
            _cache[url] = response.read()
    return _cache[url]


def font(url: str, size: int, **axes) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(_io.BytesIO(download(url)), size)
    if axes:
        try:
            # Variable fonts default to their lightest instance otherwise.
            names = [a.decode() if isinstance(a, bytes) else a for a in face.get_variation_axes__names()] \
                if hasattr(face, 'get_variation_axes__names') else None
            face.set_variation_by_axes(list(axes.values()))
        except Exception:
            pass  # Static fallback: the default instance still reads correctly.
    return face


def avatar(size: int) -> Image.Image:
    """Full-bleed tile: survives a circular crop without losing its corners."""
    base = gradient_square(size, radius_ratio=0.0).convert('RGBA')
    base.alpha_composite(glyph(size, scale=0.46))
    return base


def banner(width: int = 1200, height: int = 630) -> Image.Image:
    """Link-preview card: the mark, the wordmark and the one-line description."""
    card = Image.new('RGBA', (width, height), CANVAS + (255,))

    wordmark = font(FRAUNCES, 112, wght=600, opsz=144)
    body = font(INTER, 34, wght=400)

    measure = ImageDraw.Draw(card)
    title = 'Lumen'
    tagline = 'PDFs, read aloud by Kokoro'
    title_w = measure.textlength(title, font=wordmark)
    tagline_w = measure.textlength(tagline, font=body)

    # Lay the mark and the text out as one lockup, then centre the whole thing
    # rather than positioning each piece by eye.
    mark_size = 188
    gap = 44
    text_w = max(title_w, tagline_w)
    lockup_w = mark_size + gap + text_w
    left = (width - lockup_w) / 2
    mid = height / 2

    # Warm glow behind the mark, echoing the library screen's radial gradient.
    glow = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    cx, cy = left + mark_size / 2, mid
    for i in range(140, 0, -1):
        radius = i * 3.2
        alpha = int(20 * (1 - i / 140) ** 2)
        draw.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            fill=ACCENT + (alpha,),
        )
    card.alpha_composite(glow)
    card.alpha_composite(full_icon(mark_size), (int(left), int(mid - mark_size / 2)))

    draw = ImageDraw.Draw(card)
    text_x = left + mark_size + gap
    # Optical centring: the wordmark carries most of the visual weight.
    draw.text(
        (text_x, mid - 14),
        title,
        font=wordmark,
        fill=(242, 244, 248, 255),
        anchor='ls',
    )
    draw.text(
        (text_x + 3, mid + 58),
        tagline,
        font=body,
        fill=(168, 176, 191, 255),
        anchor='ls',
    )

    # Accent rule along the bottom edge.
    draw.rectangle((0, height - 8, width, height), fill=ACCENT + (255,))
    return card


def write(name: str, image: Image.Image) -> None:
    os.makedirs(BRAND, exist_ok=True)
    path = os.path.join(BRAND, name)
    image.save(path)
    print('  %-32s %sx%s  %6.0f KB' % (name, *image.size, os.path.getsize(path) / 1024))


def main() -> None:
    print('brand assets:')
    write('lumen-icon-1024.png', full_icon(1024))
    write('lumen-icon-512.png', full_icon(512))
    write('lumen-avatar-1024.png', avatar(1024))
    write('lumen-banner-1200x630.png', banner())
    print('\nwritten to %s' % os.path.relpath(BRAND, ROOT))


if __name__ == '__main__':
    main()
