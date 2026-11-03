#!/usr/bin/env python3
"""Draws a schematic of the menu bar panel for the README (docs/panel.png).

It is intentionally a clean redraw, not a screenshot: the real panel uses the
system's translucent material and the live values of the connected display.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont

S = 4                      # supersampling factor
W, H = 340, 214            # panel size in points
ACCENT = (0, 184, 194, 255)
ACCENT_SOFT = (0, 184, 194, 40)
TEXT = (26, 30, 34, 255)
SECONDARY = (118, 128, 136, 255)
CARD = (255, 255, 255, 255)
CARD_BORDER = (226, 231, 234, 255)
TRACK = (227, 232, 235, 255)
PANEL = (246, 248, 249, 255)
PANEL_BORDER = (214, 220, 224, 255)

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
FONT_REG = os.path.join(FONT_DIR, "DejaVuSans.ttf")
FONT_BOLD = os.path.join(FONT_DIR, "DejaVuSans-Bold.ttf")


def font(size, bold=False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT_REG, int(size * S))


def px(value):
    return int(round(value * S))


img = Image.new("RGBA", (px(W), px(H)), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# Panel
d.rounded_rectangle([px(0.5), px(0.5), px(W - 0.5), px(H - 0.5)], radius=px(13),
                    fill=PANEL, outline=PANEL_BORDER, width=px(0.8))

# Title row
cx, cy, r = 22, 22, 6
d.ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=ACCENT)
for angle in range(0, 360, 45):
    rad = math.radians(angle)
    x1 = cx + math.cos(rad) * (r + 1.6)
    y1 = cy + math.sin(rad) * (r + 1.6)
    x2 = cx + math.cos(rad) * (r + 3.4)
    y2 = cy + math.sin(rad) * (r + 3.4)
    d.line([px(x1), px(y1), px(x2), px(y2)], fill=ACCENT, width=px(1))

d.text((px(34), px(14)), "MonDial", font=font(12.5, bold=True), fill=TEXT)

# Gear (simple)
gx, gy, gr = 318, 21, 5.6
d.ellipse([px(gx - gr), px(gy - gr), px(gx + gr), px(gy + gr)], outline=ACCENT, width=px(1.3))
d.ellipse([px(gx - 1.8), px(gy - 1.8), px(gx + 1.8), px(gy + 1.8)], outline=ACCENT, width=px(1.1))
for angle in range(0, 360, 45):
    rad = math.radians(angle)
    d.line([px(gx + math.cos(rad) * gr), px(gy + math.sin(rad) * gr),
            px(gx + math.cos(rad) * (gr + 2.2)), px(gy + math.sin(rad) * (gr + 2.2))],
           fill=ACCENT, width=px(1.1))

# Display card
d.rounded_rectangle([px(12), px(40), px(328), px(126)], radius=px(9),
                    fill=CARD, outline=CARD_BORDER, width=px(0.8))

d.text((px(24), px(50)), "S34C650", font=font(10.5, bold=True), fill=TEXT)
status = "DDC · 62 %"
sw = d.textlength(status, font=font(8.5))
d.text((px(316) - sw, px(52)), status, font=font(8.5), fill=SECONDARY)


def slider(y, ratio, label):
    # sun / speaker glyph
    if label == "bright":
        d.ellipse([px(24.6), px(y - 2.0), px(28.8), px(y + 2.0)], outline=SECONDARY, width=px(1.0))
        for angle in range(0, 360, 45):
            rad = math.radians(angle)
            d.line([px(26.7 + math.cos(rad) * 3.4), px(y + math.sin(rad) * 3.4),
                    px(26.7 + math.cos(rad) * 5.2), px(y + math.sin(rad) * 5.2)],
                   fill=SECONDARY, width=px(0.8))
    else:
        d.polygon([(px(24), px(y - 1.6)), (px(26.4), px(y - 1.6)), (px(29.4), px(y - 4)),
                   (px(29.4), px(y + 4)), (px(26.4), px(y + 1.6)), (px(24), px(y + 1.6))],
                  fill=SECONDARY)
        d.arc([px(29), px(y - 4.4), px(35.4), px(y + 4.4)], start=-55, end=55,
              fill=SECONDARY, width=px(0.9))

    left, right = 40, 262
    d.rounded_rectangle([px(left), px(y - 3), px(right), px(y + 3)], radius=px(3), fill=TRACK)
    knob = left + (right - left) * ratio
    d.rounded_rectangle([px(left), px(y - 3), px(knob), px(y + 3)], radius=px(3), fill=ACCENT)
    shadow = [px(knob - 5.4), px(y - 6.4), px(knob + 5.4), px(y + 6.4)]
    d.ellipse([shadow[0], shadow[1] + px(0.6), shadow[2], shadow[3] + px(0.6)], fill=(0, 0, 0, 18))
    d.ellipse([px(knob - 5.4), px(y - 6.4), px(knob + 5.4), px(y + 6.4)], fill=CARD,
              outline=(203, 210, 214, 255), width=px(0.6))

    text = f"{int(round(ratio * 100))} %"
    tw = d.textlength(text, font=font(8.5))
    d.text((px(316) - tw, px(y - 5.5)), text, font=font(8.5), fill=SECONDARY)


slider(72, 0.62, "bright")
slider(104, 0.40, "volume")


# Output row
d.polygon([(px(24), px(147)), (px(26.4), px(147)), (px(29.4), px(143.4)),
           (px(29.4), px(151.4)), (px(26.4), px(148.6)), (px(24), px(148.6))], fill=SECONDARY)
d.arc([px(29), px(143), px(35.4), px(151.8)], start=-55, end=55, fill=SECONDARY, width=px(0.9))
d.text((px(40), px(142)), "Ausgabe", font=font(8.5), fill=SECONDARY)
value = "S34C650 (DisplayPort)  ⌄"
vw = d.textlength(value, font=font(8.5))
d.text((px(316) - vw, px(142)), value, font=font(8.5), fill=TEXT)

# Divider
d.line([px(12), px(166), px(328), px(166)], fill=(228, 233, 236, 255), width=px(0.8))

# Footer
d.text((px(16), px(176)), "⟳  Neu scannen", font=font(8.5), fill=ACCENT)
quit_text = "Beenden"
qw = d.textlength(quit_text, font=font(8.5))
d.text((px(328) - qw, px(176)), quit_text, font=font(8.5), fill=ACCENT)

os.makedirs("docs", exist_ok=True)
img = img.resize((px(2 * W) // 2, px(2 * H) // 2), Image.LANCZOS)
canvas = Image.new("RGB", img.size, (255, 255, 255))
canvas.paste(img, (0, 0), img)
canvas.save("docs/panel.png", optimize=True)
print("docs/panel.png", canvas.size)
