#!/usr/bin/env python3
"""Erzeugt das App-Icon (1024x1024 PNG) für MonDial.

Aufruf: python3 tools/make_icon.py Resources/AppIcon.png
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # supersampling


def gradient(size, top, bottom):
    image = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        image.putpixel((0, y), color)
    return image.resize((size, size))


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "Resources/AppIcon.png"
    big = SIZE * SCALE

    # Hintergrund: Farbverlauf im Dropflow-Farbschema (dunkelblau -> türkis)
    background = gradient(big, (11, 37, 69), (0, 191, 200))

    # Sonne
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    center = big * 0.5
    radius = big * 0.155

    ray_inner = radius * 1.45
    ray_outer = radius * 2.05
    for i in range(12):
        angle = math.radians(i * 30)
        width = big * 0.022 if i % 2 == 0 else big * 0.015
        x0 = center + math.cos(angle) * ray_inner
        y0 = center + math.sin(angle) * ray_inner
        x1 = center + math.cos(angle) * ray_outer
        y1 = center + math.sin(angle) * ray_outer
        draw.line([(x0, y0), (x1, y1)], fill=(255, 255, 255, 235), width=int(width))

    draw.ellipse(
        [center - radius, center - radius, center + radius, center + radius],
        fill=(255, 255, 255, 250),
    )

    # Leichter innerer Verlauf in der Sonne
    shade = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    shade_draw = ImageDraw.Draw(shade)
    shade_draw.ellipse(
        [center - radius, center - radius * 0.2, center + radius, center + radius * 1.8],
        fill=(0, 140, 160, 45),
    )
    shade = shade.filter(ImageFilter.GaussianBlur(big * 0.02))
    layer = Image.alpha_composite(layer, shade)

    icon = background.convert("RGBA")
    icon = Image.alpha_composite(icon, layer)

    # Abgerundete Ecken + Schatten
    mask = rounded_mask(big, int(big * 0.225))
    icon.putalpha(mask)
    icon = icon.resize((SIZE, SIZE), Image.LANCZOS)
    icon.save(target)
    print(f"geschrieben: {target}")


if __name__ == "__main__":
    main()
