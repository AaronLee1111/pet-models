"""Builds utility-icons-candidate-v1.png from the selected Kenney source files (read-only).

    python3 make_candidate_sheet.py      (needs Pillow; run from any directory)

Each row: label | source scale | 64 px | 32 px | smallest phone size, all cream on the dark
sea-green glass | 64 px selected gold | 64 px disabled grey | 64 px cream on a light panel.
Tints multiply the source like Roblox's ImageColor3 does, so the preview matches the game.
Source files are never written; previews are generated in memory.
"""
import csv
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ICONS = os.path.dirname(HERE)
SELECTED = os.path.join(os.path.dirname(ICONS), "vendor", "kenney", "selected")
OUT = os.path.join(HERE, "utility-icons-candidate-v1.png")

CREAM = (255, 248, 228)
GOLD = (240, 198, 96)
GREY = (150, 170, 165)
DARK = (18, 70, 64)  # Theme.Glass.Deep-ish sea-green
LIGHT = (255, 244, 220)
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", 15)
SMALL = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", 12)

ROW_H = 150
COLS = [("source", None), ("64", 64), ("32", 32), ("phone min", "min"), ("selected", 64), ("disabled", 64), ("light bg", 64)]
LABEL_W, CELL_W = 230, 150
COLUMN_W = LABEL_W + CELL_W * len(COLS)


def tinted(img, colour, alpha=1.0):
    """Multiply RGB by colour (Roblox ImageColor3) and scale alpha (ImageTransparency)."""
    r, g, b, a = img.split()
    r = r.point(lambda v: v * colour[0] // 255)
    g = g.point(lambda v: v * colour[1] // 255)
    b = b.point(lambda v: v * colour[2] // 255)
    a = a.point(lambda v: int(v * alpha))
    return Image.merge("RGBA", (r, g, b, a))


def main():
    rows = [r for r in csv.reader(open(os.path.join(ICONS, "selection.tsv"), encoding="utf-8"), delimiter="\t")
            if r and not r[0].startswith("#")]
    per_column = (len(rows) + 1) // 2
    sheet = Image.new("RGBA", (COLUMN_W * 2 + 40, 70 + per_column * ROW_H + 20), (236, 232, 222, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 18), "Party Games - utility icon candidates v1 - Kenney CC0 (Board Game Icons 1.1, Input Prompts 1.5A, UI Pack 2.0) - review only, not a Roblox atlas",
              font=FONT, fill=(40, 40, 40))
    for index, row in enumerate(rows):
        label, pack, png, _svg, _screen, min_px, modification = row
        tint = "tint" in modification and "no tint" not in modification
        x0 = 20 + (index // per_column) * (COLUMN_W + 0)
        y0 = 60 + (index % per_column) * ROW_H
        src = Image.open(os.path.join(SELECTED, pack, png)).convert("RGBA")
        draw.rounded_rectangle((x0, y0, x0 + COLUMN_W - 10, y0 + ROW_H - 10), 14, fill=(250, 248, 242, 255))
        draw.text((x0 + 12, y0 + 12), label, font=FONT, fill=(30, 30, 30))
        draw.text((x0 + 12, y0 + 36), f"{pack}", font=SMALL, fill=(90, 90, 90))
        draw.text((x0 + 12, y0 + 54), os.path.basename(png), font=SMALL, fill=(90, 90, 90))
        draw.text((x0 + 12, y0 + 72), f"source {src.width}x{src.height} - min {min_px}px", font=SMALL, fill=(90, 90, 90))
        draw.text((x0 + 12, y0 + 90), "tinted in game" if tint else "kept in source colours", font=SMALL, fill=(120, 80, 20))
        for c, (name, size) in enumerate(COLS):
            cx = x0 + LABEL_W + c * CELL_W
            bg = LIGHT if name == "light bg" else DARK
            draw.rounded_rectangle((cx, y0 + 8, cx + CELL_W - 10, y0 + ROW_H - 30), 12, fill=bg + (255,),
                                   outline=GOLD if name == "selected" else None, width=3)
            px = src.height if size is None else (int(min_px) if size == "min" else size)
            scale = px / max(src.width, src.height)
            icon = src.resize((max(1, round(src.width * scale)), max(1, round(src.height * scale))), Image.LANCZOS)
            if name == "selected":
                icon = tinted(icon, GOLD) if tint else icon
            elif name == "disabled":
                icon = tinted(icon.convert("LA").convert("RGBA"), GREY if tint else (255, 255, 255), 0.45)
            elif name == "light bg":
                icon = tinted(icon, DARK) if tint else icon  # on light panels the game tints dark
            elif tint:
                icon = tinted(icon, CREAM)
            box_w, box_h = CELL_W - 10, ROW_H - 38
            sheet.alpha_composite(icon, (cx + (box_w - icon.width) // 2, y0 + 8 + (box_h - icon.height) // 2))
            draw.text((cx + 4, y0 + ROW_H - 26), f"{name} {px}px", font=SMALL, fill=(70, 70, 70))
    sheet.convert("RGB").save(OUT, optimize=True)
    print("wrote", OUT, sheet.size)


main()
