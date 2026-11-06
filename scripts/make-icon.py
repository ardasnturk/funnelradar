#!/usr/bin/env python3
"""Draws FunnelRadar's icon: three bars that narrow like a funnel, on a deep violet tile, with a
gold point where the funnel lets out. Same recipe as MRRadar's icon.

    python3 scripts/make-icon.py

Writes the sizes of the app icon and docs/icon.png.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "FunnelRadar", "Resources", "Assets.xcassets", "AppIcon.appiconset")
S = 2048
TOP, BOTTOM = (37, 24, 84), (14, 16, 42)
GLOW = (116, 84, 240)
VIOLET, BLUE = (150, 112, 255), (84, 160, 255)
GOLD = (248, 184, 62)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw():
    inset = int(S * 0.098)
    box = [inset, inset, S - inset, S - inset]
    radius = int((S - 2 * inset) * 0.225)

    tile = Image.new("RGB", (S, S))
    pixels = tile.load()
    for y in range(S):
        for x in range(S):
            pixels[x, y] = lerp(TOP, BOTTOM, (x * 0.4 + y * 0.6) / S)
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([S * 0.1, S * 0.05, S * 0.75, S * 0.7], fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.13))
    tile = Image.composite(Image.new("RGB", (S, S), GLOW), tile, glow)

    # Bars, each narrower than the one above, brighter towards the outlet.
    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    height = int(S * 0.098)
    gap = int(S * 0.044)
    y = int(S * 0.27)
    centre = S / 2
    for index, half in enumerate((0.31, 0.215, 0.125)):
        left, right = centre - S * half, centre + S * half
        t = index / 2
        bar = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        fill = lerp(VIOLET, BLUE, t) + (round(170 + 85 * t),)
        ImageDraw.Draw(bar).rounded_rectangle([left, y, right, y + height], radius=height * 0.42, fill=fill)
        art = Image.alpha_composite(art, bar)
        y += height + gap

    # The point that gets through.
    d = ImageDraw.Draw(art)
    r = S * 0.052
    cy = y + r * 0.75
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([centre - r * 2, cy - r * 2, centre + r * 2, cy + r * 2], fill=GOLD + (70,))
    art = Image.alpha_composite(art, halo.filter(ImageFilter.GaussianBlur(S * 0.018)))
    ImageDraw.Draw(art).ellipse([centre - r, cy - r, centre + r, cy + r], fill=GOLD + (255,))

    tile = Image.alpha_composite(tile.convert("RGBA"), art)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(tile, (0, 0), mask)
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 34), width=max(2, S // 340))
    return Image.alpha_composite(out, edge)


icon = draw()
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        icon.resize((size * scale, size * scale), Image.LANCZOS).save(os.path.join(ICONSET, f"icon_{size}x{size}@{scale}x.png"))
icon.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "docs", "icon.png"))
print("icon written")
