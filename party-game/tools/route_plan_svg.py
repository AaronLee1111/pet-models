"""Draws a labelled overhead route plan (SVG) from a board module.

    python3 tools/route_plan_svg.py src/server/Board/Boards/SunnyLoopV2.luau docs/sunny-loop-v2/route-plan.svg

Reads the Luau board data with simple patterns (Id, Type, At, Next, Paths, Area, Landmark,
Gates, CrownSpaces, Start), so the picture always matches the data. North is up; the board's
z axis is drawn upwards. Space colours follow Board/SpaceTypes; every type also gets a
letter, so the plan reads without colour.
"""
import math
import re
import sys

SRC, OUT = sys.argv[1], sys.argv[2]
text = open(SRC, encoding="utf-8").read()

TYPES = {  # colour, letter
    "Neutral": ("#c8c8d7", "·"), "Gain": ("#468cff", "+"), "Lose": ("#f04646", "−"),
    "Event": ("#50c86e", "?"), "Shop": ("#aa5ae6", "S"), "Item": ("#3cc8d2", "I"),
    "Duel": ("#ff8c28", "D"), "Chaos": ("#5a2878", "!"), "Switch": ("#f0f0ff", "W"),
    "Reward": ("#ffbe28", "G"),
}
AREA_FILL = {"Stream": "#d8f1ff", "Orchard": "#e4f6d4", "Fair": "#fff0d6", "Village": "#f2e6ff"}

spaces = {}
for block in re.findall(r"\{[^{}]*Id = \d+[^{}]*(?:\{[^{}]*\}[^{}]*)*\}", text):
    m = re.search(r"Id = (\d+)", block)
    if not m or "Type =" not in block:
        continue
    sid = int(m.group(1))
    at = [float(v) for v in re.search(r"At = \{([^}]*)\}", block).group(1).split(",")]
    nxt = [int(v) for v in re.search(r"Next = \{([^}]*)\}", block).group(1).split(",")]
    paths = re.search(r"Paths = \{([^}]*)\}", block)
    spaces[sid] = {
        "type": re.search(r'Type = "(\w+)"', block).group(1),
        "x": at[0], "z": at[1], "h": at[2] if len(at) > 2 else 0,
        "next": nxt,
        "paths": re.findall(r'"([^"]+)"', paths.group(1)) if paths else None,
        "area": (re.search(r'Area = "(\w+)"', block) or [None, ""])[1],
        "landmark": (re.search(r'Landmark = "(\w+)"', block) or [None, ""])[1],
    }
crowns = {int(v) for v in re.search(r"CrownSpaces = \{([^}]*)\}", text).group(1).split(",")}
start = int(re.search(r"Start = (\d+)", text).group(1))
gates = re.findall(r'\{ Id = "(\w+)", From = (\d+), To = (\d+)[^}]*Toll = (\d+)', text)

SCALE, PAD = 70, 150
xs = [s["x"] for s in spaces.values()]
zs = [s["z"] for s in spaces.values()]
W = (max(xs) - min(xs)) * SCALE + PAD * 2 + 300
H = max(W, (max(zs) - min(zs)) * SCALE + PAD * 2 + 40)  # square: previews crop to a square


def px(s):
    return (s["x"] - min(xs)) * SCALE + PAD, (max(zs) - s["z"]) * SCALE + PAD + 30


out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H:.0f}" font-family="Helvetica, Arial, sans-serif">',
       f'<rect width="100%" height="100%" fill="#fbfaf6"/>',
       '<defs><marker id="arrow" markerUnits="userSpaceOnUse" markerWidth="16" markerHeight="16" refX="13" refY="8" orient="auto">'
       '<path d="M0,0 L16,8 L0,16 z" fill="#7a6a55"/></marker></defs>',
       f'<text x="{PAD}" y="34" font-size="22" font-weight="bold" fill="#3b2f5c">Sunny Loop v2 · route plan (north up, clockwise)</text>']

# area halos
for sid, s in spaces.items():
    x, y = px(s)
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="46" fill="{AREA_FILL.get(s["area"], "#eee")}" opacity="0.8"/>')

# landmarks (drawn under the route)
LANDMARKS = {
    "SundialPavilion": (0.0, -1.0, 62, "Sundial Pavilion"),
    "OrchardMarket": (-6.25, -1.9, 34, "Orchard Market (shop)"),
    "CrownPavilion": (1.0, 6.25, 34, "Crown Pavilion"),
    "EventStage": (0.6, 2.55, 30, "Event Stage"),
    "Waterwheel": (6.25, 0.6, 30, "Waterwheel"),
    "BellSwitch": (3.55, 5.0, 22, "Bell Switch"),
    "FairKiosk": (2.6, 5.95, 20, "Fair Kiosk (shop)"),
    "SunGate": (0.0, -5.6, 22, "Sun Gate (start)"),
    "OrchardGrove": (-2.75, -1.0, 26, "Orchard Grove"),
}
for key, (lx, lz, r, label) in LANDMARKS.items():
    x, y = px({"x": lx, "z": lz})
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#ffffff" stroke="#b9a37a" stroke-width="2" stroke-dasharray="6 4"/>')
    out.append(f'<text x="{x:.1f}" y="{y + r + 14:.1f}" font-size="12" text-anchor="middle" fill="#6b5a3a">{label}</text>')

gate_edges = {(int(f), int(t)): (gid, toll) for gid, f, t, toll in gates}
# edges
for sid, s in spaces.items():
    x1, y1 = px(s)
    for n in s["next"]:
        t = spaces[n]
        x2, y2 = px(t)
        d = math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / d, (y2 - y1) / d
        sx, sy, ex, ey = x1 + ux * 22, y1 + uy * 22, x2 - ux * 24, y2 - uy * 24
        elevated = s["h"] >= 6 and t["h"] >= 6
        colour = "#c2873b" if (sid, n) in gate_edges else ("#8c6bbf" if elevated else "#7a6a55")
        dash = ' stroke-dasharray="10 6"' if (sid, n) in gate_edges else ""
        out.append(f'<line x1="{sx:.1f}" y1="{sy:.1f}" x2="{ex:.1f}" y2="{ey:.1f}" stroke="{colour}" stroke-width="5"{dash} marker-end="url(#arrow)"/>')
        if (sid, n) in gate_edges:
            gid, toll = gate_edges[(sid, n)]
            out.append(f'<text x="{(sx + ex) / 2 + 14:.1f}" y="{(sy + ey) / 2 + 22:.1f}" font-size="12" fill="#c2873b" font-weight="bold">GATE {gid} · toll {toll} · Switch 19 closes</text>')

# spaces
for sid, s in spaces.items():
    x, y = px(s)
    colour, letter = TYPES[s["type"]]
    ring = "#e0a800" if sid in crowns else "#3b2f5c"
    width = 5 if sid in crowns else 2
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="20" fill="{colour}" stroke="{ring}" stroke-width="{width}"/>')
    dark = s["type"] in ("Chaos",)
    out.append(f'<text x="{x:.1f}" y="{y + 5:.1f}" font-size="15" font-weight="bold" text-anchor="middle" fill="{"#fff" if dark else "#1d1630"}">{letter}</text>')
    out.append(f'<text x="{x + 17:.1f}" y="{y - 17:.1f}" font-size="12" font-weight="bold" fill="#1d1630">{sid}</text>')
    if s["h"]:
        out.append(f'<text x="{x - 30:.1f}" y="{y + 32:.1f}" font-size="10" fill="#6b6b8a">h{s["h"]:g}</text>')
    if s["paths"]:
        # fork labels: in a box beside the fork, away from the routes
        lines = [f"FORK {sid}"] + [f"{i + 1}→{n} {label}" for i, (n, label) in enumerate(zip(s["next"], s["paths"]))]
        bx = x - 250 if s["x"] < 0 else x + 30
        by = y - 70 if s["z"] > 0 else y + 26
        out.append(f'<rect x="{bx:.1f}" y="{by:.1f}" width="215" height="{14 * len(lines) + 8}" rx="6" fill="#ffffff" stroke="#3b2f5c" opacity="0.92"/>')
        for i, line in enumerate(lines):
            weight = "bold" if i == 0 else "normal"
            out.append(f'<text x="{bx + 8:.1f}" y="{by + 17 + i * 14:.1f}" font-size="12" font-weight="{weight}" fill="#3b2f5c">{line}</text>')
    if sid == start:
        out.append(f'<text x="{x:.1f}" y="{y + 40:.1f}" font-size="13" font-weight="bold" text-anchor="middle" fill="#3b2f5c">START</text>')

# legend
lx = W - 270
out.append(f'<text x="{lx}" y="70" font-size="15" font-weight="bold" fill="#3b2f5c">Legend</text>')
row = 92
for name, (colour, letter) in TYPES.items():
    out.append(f'<circle cx="{lx + 10}" cy="{row - 5}" r="9" fill="{colour}" stroke="#3b2f5c"/>')
    out.append(f'<text x="{lx + 10}" y="{row - 1}" font-size="10" text-anchor="middle" fill="{"#fff" if name == "Chaos" else "#1d1630"}">{letter}</text>')
    out.append(f'<text x="{lx + 26}" y="{row}" font-size="13" fill="#1d1630">{"Gift (Reward)" if name == "Reward" else name}</text>')
    row += 22
for colour, label in (("#7a6a55", "path (arrow = movement)"), ("#8c6bbf", "elevated path"), ("#c2873b", "gated toll edge")):
    out.append(f'<line x1="{lx}" y1="{row - 5}" x2="{lx + 22}" y2="{row - 5}" stroke="{colour}" stroke-width="5"/>')
    out.append(f'<text x="{lx + 30}" y="{row}" font-size="13" fill="#1d1630">{label}</text>')
    row += 22
out.append(f'<circle cx="{lx + 10}" cy="{row - 5}" r="9" fill="#fff" stroke="#e0a800" stroke-width="4"/>')
out.append(f'<text x="{lx + 26}" y="{row}" font-size="13" fill="#1d1630">Crown space</text>')
row += 22
for area, fill in AREA_FILL.items():
    out.append(f'<rect x="{lx}" y="{row - 14}" width="20" height="16" fill="{fill}" stroke="#ccc"/>')
    out.append(f'<text x="{lx + 30}" y="{row}" font-size="13" fill="#1d1630">{ {"Fair": "Hilltop Fairground", "Village": "Waterwheel Village"}.get(area, area)}</text>')
    row += 22
out.append(f'<text x="{lx}" y="{row + 10}" font-size="12" fill="#6b6b8a">h = height in studs · {len(spaces)} spaces</text>')
out.append("</svg>")
open(OUT, "w", encoding="utf-8").write("\n".join(out))
print(f"wrote {OUT}: {len(spaces)} spaces")
