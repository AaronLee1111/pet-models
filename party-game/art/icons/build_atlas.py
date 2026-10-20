"""Builds the production utility atlas candidate v1 from art/vendor/kenney/selected (read-only).

    python3 build_atlas.py          (needs Pillow and resvg-py)

Writes (nothing outside art/icons):
  export/v1/ui_utility_v1.png   1024x256   tintable glyphs + touch prompts (white, tinted in game)
  export/v1/ui_keyboard_v1.png  1024x512   keyboard keys: filled (dark panels) + outline (light panels)
  export/v1/ui_gamepad_v1.png   1024x640   Xbox / PlayStation / neutral prompts, untinted
  export/v1/atlas_v1.json       semantic name -> atlas, cell rect, light-panel cell, tint, min px
  src/client/UI/Icons.luau      registry generated from the JSON + Icons.template.luau
  review/utility-atlas-candidate-v1.png   atlases on dark + light, every icon at its phone minimum

Cells are 128 px; every icon is fitted (never enlarged) into a centred 104 px box, so padding and
visual weight match. UI Pack icons are rendered from their SVGs at that size. Tintable icons are
flattened to white so Roblox ImageColor3 gives cream / gold / grey. Transparent pixels get the
neighbouring colour (edge bleed) so texture filtering and mipmaps never show dark fringes.
"""
import csv
import io
import json
import os
import re

import resvg_py
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ICONS = os.path.dirname(os.path.abspath(__file__))
SELECTED = os.path.join(os.path.dirname(ICONS), "vendor", "kenney", "selected")
EXPORT = os.path.join(ICONS, "export", "v1")
REVIEW = os.path.join(ICONS, "review", "utility-atlas-candidate-v1.png")
CELL, BOX, WIDTH = 128, 104, 1024
COLUMNS = WIDTH // CELL
ATLAS_ROWS = {"utility": 2, "keyboard": 4, "gamepad": 5}

CREAM, GOLD, GREY, DEEP = (255, 248, 228), (240, 198, 96), (150, 170, 165), (12, 54, 50)
DARK_PANEL, LIGHT_PANEL = (26, 92, 84), (255, 244, 220)
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"


def render_svg(path, box):
    text = open(path, encoding="utf-8").read()
    tag = re.search(r"<svg[^>]*>", text).group()
    w = float(re.search(r'width="([\d.]+)', tag).group(1))
    h = float(re.search(r'height="([\d.]+)', tag).group(1))
    k = box / max(w, h)
    new = re.sub(r'width="[\d.]+"', f'width="{w * k:.3f}"', tag, count=1)
    new = re.sub(r'height="[\d.]+"', f'height="{h * k:.3f}"', new, count=1)
    if "viewBox" not in new:
        new = new.replace("<svg", f'<svg viewBox="0 0 {w} {h}"', 1)
    return Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=text.replace(tag, new, 1))))).convert("RGBA")


def load(pack, rel):
    path = os.path.join(SELECTED, pack, rel)
    if pack == "input-prompts" and rel.endswith(".png"):
        # Prompt PNGs carry wide built-in padding; their SVGs render crisply at the full box.
        rel = rel.split("/")[0] + "/Vector/" + os.path.splitext(os.path.basename(rel))[0] + ".svg"
        path = os.path.join(SELECTED, pack, rel)
    if rel.endswith(".svg"):
        img = render_svg(path, BOX * 4)  # oversample: the drawing may fill only part of its canvas
    else:
        img = Image.open(path).convert("RGBA")
    img = img.crop(img.getbbox())
    k = min(1.0, BOX / max(img.size))  # fit, never enlarge a raster (SVGs are oversampled above)
    if k < 1:
        img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.alpha_composite(img, ((CELL - img.width) // 2, (CELL - img.height) // 2))
    return cell


def flatten_white(img):
    return Image.merge("RGBA", (*[Image.new("L", img.size, 255)] * 3, img.getchannel("A")))


def bleed(img):
    """Fill fully transparent pixels with nearby colour (alpha untouched), 8 px deep."""
    alpha = img.getchannel("A")
    solid = alpha.point(lambda v: 255 if v > 0 else 0)
    grown = Image.merge("RGBA", (*img.split()[:3], solid))
    for _ in range(8):
        spread = grown.filter(ImageFilter.MaxFilter(3))
        grown = Image.composite(grown, spread, grown.getchannel("A"))
    return Image.merge("RGBA", (*Image.composite(img, grown, solid).split()[:3], alpha))


def tint(img, colour, alpha=1.0):
    r, g, b, a = img.split()
    return Image.merge("RGBA", (
        r.point(lambda v: v * colour[0] // 255),
        g.point(lambda v: v * colour[1] // 255),
        b.point(lambda v: v * colour[2] // 255),
        a.point(lambda v: int(v * alpha)),
    ))


def main():
    os.makedirs(EXPORT, exist_ok=True)
    atlases = {name: Image.new("RGBA", (WIDTH, rows * CELL), (0, 0, 0, 0)) for name, rows in ATLAS_ROWS.items()}
    used = {name: 0 for name in atlases}
    entries, cells = {}, {}
    rows = [r for r in csv.reader(open(os.path.join(ICONS, "atlas_v1.tsv"), encoding="utf-8"), delimiter="\t")
            if r and not r[0].startswith("#")]

    def place(atlas, img):
        index = used[atlas]
        assert index < COLUMNS * ATLAS_ROWS[atlas], atlas + " is full"
        used[atlas] += 1
        x, y = (index % COLUMNS) * CELL, (index // COLUMNS) * CELL
        atlases[atlas].alpha_composite(img, (x, y))
        cells[(atlas, index)] = img
        return {"Offset": [x, y], "Size": [CELL, CELL], "Index": index}

    for atlas, name, pack, dark, light, tinted, min_px, note in rows:
        img = load(pack, dark)
        if tinted == "yes":
            img = flatten_white(img)
        entry = {"Atlas": atlas, "Tint": tinted == "yes", "MinPx": int(min_px), "Note": note}
        entry.update(place(atlas, bleed(img)))
        if light != "-":
            # Kenney outline prompts are white line art: tinted deep sea-green on light panels.
            entry["Light"] = place(atlas, bleed(flatten_white(load(pack, light))))
        entries[name] = entry

    files = {}
    for name, img in atlases.items():
        path = os.path.join(EXPORT, f"ui_{name}_v1.png")
        img.save(path, optimize=True)
        files[name] = os.path.basename(path)
    json.dump({"Cell": CELL, "Files": files, "Icons": entries}, open(os.path.join(EXPORT, "atlas_v1.json"), "w"), indent=1)
    write_registry(entries)
    review(entries, atlases, cells)


def write_registry(entries):
    lines = []
    for name, e in entries.items():
        light = f", Light = {{ {e['Light']['Offset'][0]}, {e['Light']['Offset'][1]} }}" if "Light" in e else ""
        lines.append(f"\t{name} = {{ Atlas = \"{e['Atlas']}\", Offset = {{ {e['Offset'][0]}, {e['Offset'][1]} }}{light}, Tint = {str(e['Tint']).lower()}, MinPx = {e['MinPx']} }},")
    template = open(os.path.join(ICONS, "Icons.template.luau"), encoding="utf-8").read()
    out = os.path.join(os.path.dirname(os.path.dirname(ICONS)), "src", "client", "UI", "Icons.luau")
    open(out, "w", encoding="utf-8").write(template.replace("--@REGISTRY", "\n".join(lines)))


def review(entries, atlases, cells):
    font, small = ImageFont.truetype(FONT, 18), ImageFont.truetype(FONT, 13)
    names = list(entries)
    row_h, label_w = 92, 210
    cols = [("normal", 1), ("selected", 1), ("disabled", 1), ("light panel", 1), ("iPhone px (x3)", 3)]
    col_w = 120
    grid_w = label_w + col_w * len(cols)
    per = (len(names) + 2) // 3
    atlas_h = sum(img.height for img in atlases.values()) // 2 + 3 * 40
    sheet = Image.new("RGBA", (40 + 3 * grid_w + 40, 80 + atlas_h + 50 + per * row_h + 30), (236, 232, 222, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 18), "Party Games - production utility atlas candidate v1 (Kenney CC0) - review only, not uploaded", font=font, fill=(40, 40, 40))
    draw.text((20, 46), "Top: the three atlases at half size, as the game shows them on dark (left) and light (right) panels. Below: every icon at its minimum UI size.", font=small, fill=(70, 70, 70))

    def shown(entry, light=False):
        if light and "Light" in entry:
            return tint(cells[(entry["Atlas"], entry["Light"]["Index"])], DEEP)
        img = cells[(entry["Atlas"], entry["Index"])]
        if entry["Tint"]:
            return tint(img, DEEP if light else CREAM)
        return img

    y = 80
    for name, img in atlases.items():
        draw.text((20, y), f"ui_{name}_v1.png  {img.width}x{img.height}", font=small, fill=(40, 40, 40))
        y += 18
        for side, bg in ((0, DARK_PANEL), (1, LIGHT_PANEL)):
            panel = Image.new("RGBA", (img.width // 2, img.height // 2), bg + (255,))
            for e in entries.values():
                if e["Atlas"] != name:
                    continue
                for key, light in (("Index", False), ("Light", True)):
                    if key == "Index" and side == 1 and "Light" in e:
                        continue  # light panels use the outline cell instead
                    if key == "Light" and "Light" not in e:
                        continue
                    index = e["Index"] if key == "Index" else e["Light"]["Index"]
                    cell = shown(e, light=side == 1) if key == "Index" else shown(e, light=True)
                    if key == "Light" and side == 0:
                        continue
                    half = cell.resize((CELL // 2, CELL // 2), Image.LANCZOS)
                    panel.alpha_composite(half, ((index % COLUMNS) * CELL // 2, (index // COLUMNS) * CELL // 2))
            sheet.alpha_composite(panel, (20 + side * (img.width // 2 + 30), y))
        y += img.height // 2 + 22

    y0 = y + 10
    for i, name in enumerate(names):
        e = entries[name]
        x = 20 + (i // per) * grid_w
        yy = y0 + (i % per) * row_h
        draw.rounded_rectangle((x, yy, x + grid_w - 12, yy + row_h - 8), 10, fill=(250, 248, 242, 255))
        draw.text((x + 10, yy + 10), name, font=font, fill=(30, 30, 30))
        draw.text((x + 10, yy + 36), f"min {e['MinPx']} px  " + ("tinted" if e["Tint"] else "source colours"), font=small, fill=(90, 90, 90))
        draw.text((x + 10, yy + 54), ("light: outline cell, tinted dark" if "Light" in e else ("light: tinted dark" if e["Tint"] else "light: same cell")), font=small, fill=(120, 80, 20))
        for c, (label, mult) in enumerate(cols):
            cx = x + label_w + c * col_w
            light = label == "light panel"
            draw.rounded_rectangle((cx, yy + 6, cx + col_w - 8, yy + row_h - 22), 8,
                                   fill=(LIGHT_PANEL if light else DARK_PANEL) + (255,), outline=GOLD if label == "selected" else None, width=2)
            base = shown(e, light)
            if label == "selected" and e["Tint"]:
                base = tint(cells[(e["Atlas"], e["Index"])], GOLD)
            elif label == "disabled":
                base = tint(cells[(e["Atlas"], e["Index"])], GREY, 0.5) if e["Tint"] else tint(base, (255, 255, 255), 0.45)
            px = min(e["MinPx"] * mult, 60)
            icon = base.resize((px, px), Image.LANCZOS)
            sheet.alpha_composite(icon, (cx + (col_w - 8 - px) // 2, yy + 6 + (row_h - 28 - px) // 2))
            draw.text((cx + 2, yy + row_h - 20), f"{label} {e['MinPx'] * mult}px" if mult > 1 else f"{label}", font=small, fill=(70, 70, 70))
    sheet.convert("RGB").save(REVIEW, optimize=True)
    print("wrote", REVIEW, sheet.size, "| atlas cells:", {k: v for k, v in zip(atlases, [sum(1 for e in cells if e[0] == a) for a in atlases])})


main()
