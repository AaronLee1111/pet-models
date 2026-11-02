"""Party Game Item Kit -- review stage 1 (Party Dice Block, Coin Shield, Warp Token).

Fully procedural Blender build. Run with the `bpy` module (pip install bpy) or Blender:
    python3 PartyGameItemKit/source/build_item_kit.py
    blender -b -P PartyGameItemKit/source/build_item_kit.py
    KIT_STAGE=geo python3 ...   # geometry + atlas + exports + validation, no review renders

Conventions
    Blender metres, Z up, item front faces -Y.  1 stud = 0.28 m (same as the pet-models repo).
    Every item = one Empty root (pivot) + a few mesh children with identity local transforms.
    All items share ONE 1024 kit atlas (4x4 grid of 256 px material cells, box-projected at a
    fixed texel density) with Color / Roughness / Metalness / Emissive-mask maps.

Outputs (relative to PartyGameItemKit/)
    source/PartyGameItemKit_v001.blend
    export/PartyDiceBlock_v001.fbx, CoinShield_v001.fbx, WarpToken_v001.fbx
    textures/PGK_Atlas_{Color,Roughness,Metalness,Emissive}.png (+ cell legend)
    manifest.json, validation/fbx_roundtrip.json, renders/*.png
"""
import json
import math
import os
import time

import bpy  # noqa: must precede bmesh when using the pip bpy module
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree
from PIL import Image, ImageDraw, ImageFont

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION = "v001"
STUD = 0.28
STAGE = os.environ.get("KIT_STAGE", "full")
SAMPLES = int(os.environ.get("KIT_SAMPLES", "64"))
D = {k: os.path.join(KIT, k) for k in ("source", "export", "textures", "renders", "validation")}
for p in D.values():
    os.makedirs(p, exist_ok=True)

# ---------------------------------------------------------------- shared material cells
CLASSES = ["GOLD", "GOLD_SATIN", "CREAM", "PEARL",
           "COBALT", "TEAL", "VIOLET", "FIELD",
           "CORAL", "AQUA", "PORTAL", "CORE",
           "RUBY", "EMERALD", "SUN", "ROSE"]          # last row reserved for future variants
CID = {c: i for i, c in enumerate(CLASSES)}
FRONT_PROJ = {"FIELD", "PORTAL", "CORE"}               # projected through the item's front
TEX = 1024
CELL = TEX // 4
GUTTER = 10
PROJ_R = 0.56                                          # half-extent (m) mapped into one cell
TEXEL_DENSITY = (CELL - 2 * GUTTER) / (2 * PROJ_R)     # px per metre, identical for all items


# ---------------------------------------------------------------- 2D outline helpers
def ccw(pts):
    P = np.asarray(pts, float)
    a = 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    return P if a > 0 else P[::-1].copy()


def circle(r, n, phase=0.0, wobble=None):
    t = phase + np.arange(n) * 2 * math.pi / n
    rr = r if wobble is None else r + np.array([wobble[i % len(wobble)] for i in range(n)])
    return ccw(np.stack([rr * np.cos(t), rr * np.sin(t)], 1))


def rrect(hw, hh, r, seg=5):
    pts = []
    for cx, cy, a0 in ((hw - r, -(hh - r), -90), (hw - r, hh - r, 0),
                       (-(hw - r), hh - r, 90), (-(hw - r), -(hh - r), 180)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return ccw(pts)


def star(n, ro, ri, phase=math.pi / 2, ro2=None):
    pts = []
    for i in range(2 * n):
        a = phase + i * math.pi / n
        if i % 2:
            r = ri
        else:
            r = ro if (ro2 is None or (i // 2) % 2 == 0) else ro2
        pts.append((r * math.cos(a), r * math.sin(a)))
    return ccw(pts)


def diamond(a, b):
    return ccw([(0, -a), (b, 0), (0, a), (-b, 0)])


def chaikin(pts, it=1):
    P = np.asarray(pts, float)
    for _ in range(it):
        Q = np.roll(P, -1, 0)
        P = np.stack([0.75 * P + 0.25 * Q, 0.25 * P + 0.75 * Q], 1).reshape(-1, 2)
    return ccw(P)


def _seg_dist(points, P):
    A, B = P, np.roll(P, -1, 0)
    AB = B - A
    L2 = np.maximum((AB ** 2).sum(1), 1e-12)
    AP = points[:, None, :] - A[None]
    t = np.clip((AP * AB[None]).sum(2) / L2[None], 0, 1)
    proj = A[None] + t[..., None] * AB[None]
    return np.sqrt(((points[:, None, :] - proj) ** 2).sum(2)).min(1)


def offset_sdf(P, d, center=None):
    """Inset a star-shaped outline by distance d, keeping one vertex per ray from `center`.
    Produces true iso-distance curves (rounded inner corners, never self-intersecting)."""
    if d <= 0:
        return P.copy()
    C = P.mean(0) if center is None else np.asarray(center, float)
    dirs = P - C
    L = np.linalg.norm(dirs, axis=1)
    lo, hi = np.zeros(len(P)), L.copy()
    for _ in range(36):
        mid = 0.5 * (lo + hi)
        q = C + dirs * (mid / L)[:, None]
        inside_far = _seg_dist(q, P) > d
        lo = np.where(inside_far, mid, lo)
        hi = np.where(inside_far, hi, mid)
    return C + dirs * (lo / L)[:, None]


def offset_miter(P, d):
    prv, nxt = np.roll(P, 1, 0), np.roll(P, -1, 0)
    e1, e2 = P - prv, nxt - P
    e1 /= np.linalg.norm(e1, axis=1)[:, None]
    e2 /= np.linalg.norm(e2, axis=1)[:, None]
    n1 = np.stack([-e1[:, 1], e1[:, 0]], 1)
    n2 = np.stack([-e2[:, 1], e2[:, 0]], 1)
    m = n1 + n2
    m /= np.linalg.norm(m, axis=1)[:, None]
    c = np.maximum((m * n1).sum(1), 0.35)
    return P + m * (d / c)[:, None]


# ---------------------------------------------------------------- 3D sweep builder
def tf(loc=(0, 0, 0), rot=None):
    M = Matrix.Translation(Vector(loc))
    return M @ (rot.to_4x4() if rot is not None else Matrix.Identity(4))


def frame(origin, z, y_hint):
    z = Vector(z).normalized()
    x = Vector(y_hint).cross(z).normalized()
    y = z.cross(x)
    M = Matrix((x, y, z)).transposed().to_4x4()
    M.translation = Vector(origin)
    return M


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


class Builder:
    """Accumulates closed sweep shells into one bmesh, one material class per band."""

    def __init__(self):
        self.bm = bmesh.new()
        self.shells = 0

    def sweep(self, outline, profile, classes, M, cap0=None, cap1=None, closed=False,
              mode="sdf", center=None):
        P = ccw(outline)
        loops = []
        for d, z in profile:
            Q = offset_sdf(P, d, center) if mode == "sdf" else offset_miter(P, d) if d > 0 else P
            loops.append([self.bm.verts.new(M @ Vector((x, y, z))) for x, y in Q])
        n = len(P)
        nb = len(loops) if closed else len(loops) - 1
        assert len(classes) == nb, (len(classes), nb)
        for k in range(nb):
            a, b = loops[k], loops[(k + 1) % len(loops)]
            for i in range(n):
                j = (i + 1) % n
                f = self.bm.faces.new((a[i], a[j], b[j], b[i]))
                f.material_index = CID[classes[k]]
        if cap0:
            f = self.bm.faces.new(list(reversed(loops[0])))
            f.material_index = CID[cap0]
        if cap1:
            f = self.bm.faces.new(loops[-1])
            f.material_index = CID[cap1]
        self.shells += 1

    def append(self, src, cls):
        vm = {v: self.bm.verts.new(v.co) for v in src.verts}
        for f in src.faces:
            nf = self.bm.faces.new([vm[v] for v in f.verts])
            nf.material_index = CID[cls]
        self.shells += 1


def pip(B, M, r, dome_h=0.85, z0=0.0, glow=False):
    rd = r - 0.018
    prof = [(0, z0), (0, 0.034), (0.009, 0.042), (0.018, 0.035)]
    cls = ["GOLD", "GOLD", "GOLD_SATIN"]
    for a in (42, 74):
        th = math.radians(a)
        prof.append((0.018 + rd * (1 - math.cos(th)), 0.034 + rd * dome_h * math.sin(th)))
        cls.append("CORE" if glow else "PEARL")
    cls = cls[:len(prof) - 1]
    B.sweep(circle(r, 12 if r < 0.08 else 16), prof, cls, M, cap0="GOLD", cap1="CORE" if glow else "PEARL")


def gem_setting(B, M, a, b, gem_cls, h0=0.0, h1=0.06):
    """Gold diamond setting with a faceted enamel gem rising out of it."""
    B.sweep(diamond(a, b), [(0, h0), (0, h1), (0.012, h1 + 0.012)],
            ["GOLD", "GOLD"], M, cap0="GOLD", cap1="GOLD_SATIN")
    ga, gb = a * 0.72, b * 0.72
    rin = ga * gb / math.hypot(ga, gb)
    B.sweep(diamond(ga, gb), [(0, h1 - 0.01), (0, h1 + 0.016), (rin * 0.7, h1 + 0.040)],
            [gem_cls, gem_cls], M, cap0=gem_cls, cap1=gem_cls)


# ---------------------------------------------------------------- 1. Party Dice Block
DIE_S = 0.95          # body cube edge (3.39 studs)
DIE_BEV = 0.12
DIE_FACES = [  # normal, up hint, pip value (opposites sum to 7)
    ((0, -1, 0), (0, 0, 1), 5), ((0, 1, 0), (0, 0, 1), 2),
    ((0, 0, 1), (0, 1, 0), 1), ((0, 0, -1), (0, -1, 0), 6),
    ((1, 0, 0), (0, 0, 1), 3), ((-1, 0, 0), (0, 0, 1), 4)]
PIP_LAYOUT = {
    1: [(0, 0)], 2: [(1, 1), (-1, -1)], 3: [(1, 1), (0, 0), (-1, -1)],
    4: [(1, 1), (-1, 1), (1, -1), (-1, -1)], 5: [(1, 1), (-1, 1), (0, 0), (1, -1), (-1, -1)],
    6: [(1, 1), (1, 0), (1, -1), (-1, 1), (-1, 0), (-1, -1)]}


def build_dice():
    body, faces, pips = Builder(), Builder(), Builder()
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=DIE_S)
    bmesh.ops.bevel(tmp, geom=tmp.verts[:] + tmp.edges[:], offset=DIE_BEV, segments=3,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    body.append(tmp, "GOLD")
    tmp.free()
    h = DIE_S / 2
    bez = rrect(0.37, 0.37, 0.10, 4)
    for n, up, val in DIE_FACES:
        M = frame(Vector(n) * h, n, up)
        # gold bezel frame, cream inner rim, saturated inset enamel panel
        body.sweep(bez, [(0, -0.03), (0, 0.028), (0.014, 0.046), (0.040, 0.046), (0.055, 0.03),
                         (0.055, -0.03)], ["GOLD"] * 6, M, closed=True)
        faces.sweep(bez, [(0.05, -0.02), (0.05, 0.010), (0.056, 0.018)],
                    ["GOLD_SATIN", "COBALT"], M, cap0="COBALT", cap1="COBALT")
        faces.sweep(bez, [(0.05, 0.0), (0.05, 0.026), (0.068, 0.035), (0.096, 0.024),
                          (0.096, 0.0)], ["CREAM"] * 5, M, closed=True)
        g = 0.165
        for px, py in PIP_LAYOUT[val]:
            Mp = M @ tf((px * g, py * g, 0))
            centre = (px, py) == (0, 0)
            if centre:   # teal four-point star under every centre pip (faces 1, 3, 5)
                ro = 0.16 if val == 1 else 0.125
                faces.sweep(star(4, ro, 0.05), [(0, 0.0), (0, 0.024), (0.008, 0.031)],
                            ["GOLD", "GOLD"], Mp, cap0="GOLD", cap1="TEAL")
            pip(pips, Mp, 0.10 if (centre and val == 1) else 0.068,
                dome_h=0.62 if (centre and val == 1) else 0.85, z0=-0.006)
    # coral gems on the 12 rounded edges, cream caps on the 8 corners
    axes = [Vector(a) for a in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]
    for i in range(3):
        for j in range(i + 1, 3):
            for si in (-1, 1):
                for sj in (-1, 1):
                    n1, n2 = axes[i] * si, axes[j] * sj
                    b = (n1 + n2).normalized()
                    p = (n1 + n2) * (h - DIE_BEV) + b * DIE_BEV
                    edge = n1.cross(n2)
                    M = frame(p, b, edge.cross(b))   # diamond long axis wraps across the edge
                    gem_setting(body, M, 0.095, 0.058, "CORAL", h0=-0.035, h1=0.035)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                dvec = Vector((sx, sy, sz))
                p = dvec * (h - DIE_BEV) + dvec.normalized() * DIE_BEV
                M = frame(p, dvec, (0, 0, 1) if sz == 0 else (1, 0, 0))
                prof = [(0, -0.03), (0, 0.0)]
                for a in (40, 78):
                    t = math.radians(a)
                    prof.append((0.062 * (1 - math.cos(t)), 0.040 * math.sin(t)))
                body.sweep(circle(0.062, 12), prof, ["CREAM"] * 3, M, cap0="CREAM", cap1="CREAM")
    return {"Body": body, "Faces": faces, "Pips": pips}


# ---------------------------------------------------------------- 2. Coin Shield
FRONT = R("X", 90)            # build plane XY, +Z toward viewer  ->  world XZ, facing -Y
BACK = FRONT @ R("Y", 180)


def shield_outline():
    half = [(0.20, -0.37), (0.34, -0.17), (0.41, 0.08), (0.43, 0.30), (0.44, 0.48),
            (0.27, 0.41), (0.12, 0.43)]
    pts = [(0, -0.55)] + half + [(0, 0.48)] + [(-x, y) for x, y in reversed(half)]
    P = chaikin(pts, 2) * 1.04
    return P


def ray_hit(P, C, ang):
    """Distance from C to the outline along angle ang (outline is star-shaped about C)."""
    d = np.array([math.cos(ang), math.sin(ang)])
    best = 1e9
    for a, b in zip(P, np.roll(P, -1, 0)):
        e = b - a
        den = d[0] * (-e[1]) - d[1] * (-e[0])
        if abs(den) < 1e-12:
            continue
        rhs = a - C
        t = (rhs[0] * (-e[1]) - rhs[1] * (-e[0])) / den
        s = (d[0] * rhs[1] - d[1] * rhs[0]) / den
        if t > 0 and 0 <= s <= 1:
            best = min(best, t)
    return best


def build_shield():
    body, coin = Builder(), Builder()
    P = shield_outline()
    C = (0.0, 0.02)
    body.sweep(P, [(0.12, -0.085), (0.03, -0.085), (0.0, -0.06), (0.0, 0.05), (0.012, 0.075),
                   (0.048, 0.075), (0.06, 0.055), (0.064, 0.05), (0.104, 0.05), (0.112, 0.036),
                   (0.14, 0.035)],
               ["CREAM", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD_SATIN", "CREAM", "CREAM",
                "FIELD"], FRONT, cap0="CREAM", cap1="FIELD", center=C)
    cx, cy = C
    # gold straps tie the coin boss into the frame (top, bottom, left, right)
    for ang, a0, a1 in ((90, 0.26, None), (-90, 0.26, None), (0, 0.26, None), (180, 0.26, None)):
        r1 = ray_hit(P, np.array(C), math.radians(ang)) - 0.10
        L = r1 - a0
        mid = (a0 + r1) / 2
        M = FRONT @ tf((cx + mid * math.cos(math.radians(ang)), cy + mid * math.sin(math.radians(ang)), 0)) @ R("Z", ang)
        body.sweep(rrect(L / 2 + 0.01, 0.028, 0.012, 3), [(0, 0.02), (0, 0.052), (0.012, 0.066)],
                   ["GOLD", "GOLD"], M, cap0="GOLD", cap1="GOLD")
    # aqua gems set into the frame at top, bottom, left, right
    for ang in (90, -90, 0, 180):
        r = ray_hit(P, np.array(C), math.radians(ang)) - 0.035
        M = FRONT @ tf((cx + r * math.cos(math.radians(ang)), cy + r * math.sin(math.radians(ang)), 0)) @ R("Z", ang - 90)
        big = ang == 90
        gem_setting(body, M, 0.095 if big else 0.078, 0.064 if big else 0.052, "AQUA", h0=0.02, h1=0.088)
    # back: horizontal grip bar held by two end brackets, plus rivets
    body.sweep(rrect(0.20, 0.04, 0.03, 4), [(0, 0.07), (0, 0.118), (0.014, 0.134)],
               ["GOLD", "GOLD"], BACK @ tf((0, 0.04, 0)), cap0="GOLD", cap1="GOLD_SATIN")
    for bx in (-0.21, 0.21):
        body.sweep(rrect(0.045, 0.085, 0.025, 3), [(0, 0.064), (0, 0.105), (0.012, 0.117)],
                   ["GOLD", "GOLD"], BACK @ tf((bx, 0.04, 0)), cap0="GOLD", cap1="GOLD")
    for x, y in ((0.27, 0.30), (-0.27, 0.30), (0.20, -0.20), (-0.20, -0.20)):
        prof = [(0, 0.07), (0, 0.095)] + [(0.026 * (1 - math.cos(math.radians(a))), 0.095 + 0.02 * math.sin(math.radians(a))) for a in (40, 75)]
        body.sweep(circle(0.026, 10), prof, ["GOLD"] * 3, BACK @ tf((x, y, 0)), cap0="GOLD", cap1="GOLD")
    # the coin boss: reeded gold coin seated in a cream collar, raised star crest, aqua heart
    MC = FRONT @ tf((cx, cy, 0))
    coin.sweep(circle(0.272, 48), [(0, 0.0), (0, 0.06), (0.01, 0.072), (0.034, 0.072),
                                   (0.046, 0.06), (0.046, 0.0)], ["CREAM"] * 6, MC, closed=True)
    reed = circle(0.245, 64, wobble=[0.0, -0.007])
    coin.sweep(reed, [(0, 0.02), (0, 0.10), (0.012, 0.118), (0.03, 0.122), (0.042, 0.112),
                      (0.05, 0.103), (0.11, 0.107)],
               ["GOLD", "GOLD", "GOLD", "GOLD", "GOLD_SATIN", "GOLD"], MC, cap0="GOLD", cap1="GOLD")
    coin.sweep(star(8, 0.175, 0.062, ro2=0.118), [(0, 0.095), (0, 0.118), (0.032, 0.146)],
               ["GOLD", "GOLD"], MC, cap0="GOLD", cap1="GOLD", center=(0, 0))
    prof = [(0, 0.12), (0, 0.15), (0.008, 0.158), (0.014, 0.153)]
    for a in (30, 60, 84):
        t = math.radians(a)
        prof.append((0.014 + 0.04 * (1 - math.cos(t)), 0.153 + 0.032 * math.sin(t)))
    coin.sweep(circle(0.054, 16), prof, ["GOLD", "GOLD", "GOLD_SATIN", "AQUA", "AQUA", "AQUA"],
               MC, cap0="GOLD", cap1="AQUA")
    return {"Body": body, "Coin": coin}


# ---------------------------------------------------------------- 3. Warp Token
TOK_R = 0.36


def vane_outline(theta0, n=14):
    t = np.linspace(0, 1, n)
    r = 0.035 + 0.195 * t
    th = theta0 + 2.1 * t
    c = np.stack([r * np.cos(th), r * np.sin(th)], 1)
    tan = np.gradient(c, axis=0)
    tan /= np.linalg.norm(tan, axis=1)[:, None]
    nrm = np.stack([-tan[:, 1], tan[:, 0]], 1)
    w = 0.016 + 0.052 * np.sin(np.pi * np.clip(t * 0.95, 0, 1)) ** 0.8 * (1 - 0.45 * t)
    left = c + nrm * (w / 2)[:, None]
    right = c - nrm * (w / 2)[:, None]
    return ccw(np.concatenate([right, left[::-1]]))


def build_token():
    ring, portal = Builder(), Builder()
    P = circle(TOK_R, 48)
    prof = [(0.14, -0.035), (0.12, -0.04), (0.10, -0.07), (0.085, -0.075), (0.07, -0.065),
            (0.065, -0.055), (0.03, -0.055), (0.02, -0.065), (0.005, -0.06), (0.0, -0.045),
            (0.0, 0.045), (0.005, 0.06), (0.02, 0.065), (0.03, 0.055), (0.065, 0.055),
            (0.07, 0.065), (0.085, 0.075), (0.10, 0.07), (0.12, 0.04), (0.14, 0.01),
            (0.20, -0.005), (0.27, -0.012)]
    cls = ["GOLD_SATIN", "GOLD", "GOLD", "GOLD", "GOLD", "VIOLET", "GOLD", "GOLD", "GOLD",
           "GOLD", "GOLD", "GOLD", "GOLD", "VIOLET", "GOLD", "GOLD", "GOLD", "GOLD_SATIN",
           "PORTAL", "PORTAL", "PORTAL"]
    ring.sweep(P, prof, cls, FRONT, cap0="VIOLET", cap1="PORTAL")
    for side in (tf(), R("X", 180)):
        # cream keystones crossing the violet band
        for k in range(8):
            a = 22.5 + 45 * k
            M = FRONT @ side @ R("Z", a) @ tf((0.3125, 0, 0))
            ks = chaikin([(-0.03, -0.03), (0.03, -0.038), (0.03, 0.038), (-0.03, 0.03)], 1)
            ring.sweep(ks, [(0, 0.03), (0, 0.07), (0.008, 0.084)], ["CREAM", "CREAM"], M,
                       cap0="CREAM", cap1="CREAM")
        # glowing aqua gems in each compass spike
        for k in range(4):
            M = FRONT @ side @ R("Z", 90 * k) @ tf((0.40, 0, 0)) @ R("Z", 90)
            ring.sweep(diamond(0.065, 0.026), [(0, 0.04), (0, 0.072), (0.014, 0.088)],
                       ["AQUA", "AQUA"], M, cap0="AQUA", cap1="AQUA")
    # four gold compass spikes break the round silhouette (reads as "not a coin")
    kite = ccw([(-0.10, 0), (0.02, -0.07), (0.115, 0), (0.02, 0.07)])
    for k in range(4):
        M = FRONT @ R("Z", 90 * k) @ tf((0.385, 0, 0))
        ring.sweep(kite, [(0.035, -0.072), (0.0, -0.05), (0.0, 0.05), (0.035, 0.072)],
                   ["GOLD", "GOLD", "GOLD"], M, cap0="GOLD_SATIN", cap1="GOLD_SATIN")
    # back: gold cross with aqua light strips and a centre gem
    for k in range(4):
        M = FRONT @ R("X", 180) @ R("Z", 45 + 90 * k) @ tf((0.15, 0, 0))
        ring.sweep(rrect(0.10, 0.022, 0.012, 3), [(0, 0.02), (0, 0.055), (0.01, 0.065)],
                   ["GOLD", "GOLD"], M, cap0="GOLD", cap1="GOLD")
        ring.sweep(rrect(0.07, 0.009, 0.006, 2), [(0, 0.05), (0, 0.072)], ["AQUA"], M,
                   cap0="AQUA", cap1="AQUA")
    MB = FRONT @ R("X", 180)
    ring.sweep(circle(0.075, 20), [(0, 0.014), (0, 0.07), (0.012, 0.08), (0.02, 0.076)],
               ["GOLD", "GOLD", "GOLD_SATIN"], MB, cap0="GOLD", cap1="GOLD")
    pip(ring, MB @ tf((0, 0, 0.04)), 0.05, dome_h=0.9, z0=0.0, glow=False)
    # front portal: four gold-edged teal vanes spiralling into a glowing core
    for k in range(4):
        portal.sweep(vane_outline(k * math.pi / 2),
                     [(0, -0.03), (0, 0.012), (0.004, 0.022)], ["GOLD_SATIN", "GOLD"], FRONT,
                     cap0="GOLD_SATIN", cap1="TEAL", mode="miter")
    prof = [(0, -0.02), (0, 0.012), (0.008, 0.02), (0.014, 0.017)]
    for a in (30, 60, 84):
        t = math.radians(a)
        prof.append((0.014 + 0.045 * (1 - math.cos(t)), 0.017 + 0.05 * math.sin(t)))
    portal.sweep(circle(0.06, 18), prof, ["GOLD", "GOLD", "GOLD_SATIN", "CORE", "CORE", "CORE"],
                 FRONT, cap0="GOLD", cap1="CORE")
    return {"Ring": ring, "Portal": portal}


ITEMS = [  # name, builder, uniform scale applied to the authored geometry, pivot note
    ("PartyDiceBlock", build_dice, 0.90, "Dice: centre pivot for tumbling on any axis"),
    ("CoinShield", build_shield, 0.92, "Shield: centre of the coin boss, spin about world Z"),
    ("WarpToken", build_token, 0.92, "Token: portal centre, spin about world Z; Portal part can counter-spin about local Y"),
]


# ---------------------------------------------------------------- atlas
def noise(seed, size=CELL, scales=((4, 0.5), (12, 0.3), (40, 0.2))):
    rs = np.random.RandomState(seed)
    out = np.zeros((size, size))
    for s, w in scales:
        g = rs.rand(s + 3, s + 3).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((size + size // s * 3, size + size // s * 3), Image.BICUBIC)
        a = np.asarray(im, float)[:size, :size] / 255.0
        out += w * a
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def cell_xy():
    v, u = np.mgrid[0:CELL, 0:CELL]
    lu = ((u + 0.5) - GUTTER) / (CELL - 2 * GUTTER)
    lv = 1.0 - ((v + 0.5) - GUTTER) / (CELL - 2 * GUTTER)   # image rows go down, v goes up
    return lu * 2 * PROJ_R - PROJ_R, lv * 2 * PROJ_R - PROJ_R    # item-space metres


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def make_cell(name, i):
    X, Z = cell_xy()
    n1, n2 = noise(10 + i), noise(50 + i, scales=((24, 0.6), (70, 0.4)))
    one = np.ones((CELL, CELL))

    def col(c0, c1=None, m=None):
        c0 = np.array(c0)
        if c1 is None:
            return one[..., None] * c0
        return c0 + (np.array(c1) - c0) * m[..., None]

    rough, metal, emis = 0.4 * one, 0 * one, 0 * one
    if name == "GOLD":
        c = col((0.93, 0.66, 0.26), (0.99, 0.78, 0.40), n1 * 0.6 + n2 * 0.4)
        rough, metal = 0.24 + 0.08 * n2, one
    elif name == "GOLD_SATIN":
        c = col((0.80, 0.55, 0.20), (0.90, 0.66, 0.28), n1)
        rough, metal = 0.42 + 0.08 * n2, one
    elif name == "CREAM":
        c = col((0.95, 0.88, 0.75), (0.99, 0.94, 0.84), n1 * 0.7 + n2 * 0.3)
        rough = 0.40 + 0.06 * n2
    elif name == "PEARL":
        c = col((0.97, 0.93, 0.86), (1.0, 0.98, 0.94), n1)
        c += 0.025 * np.stack([np.sin(n2 * 9), np.sin(n2 * 9 + 2), np.sin(n2 * 9 + 4)], -1)
        rough = 0.16 + 0.05 * n2
    elif name in ("COBALT", "TEAL", "VIOLET", "RUBY", "EMERALD", "SUN", "ROSE"):
        base = {"COBALT": ((0.06, 0.14, 0.72), (0.20, 0.36, 0.95)),
                "TEAL": ((0.06, 0.66, 0.70), (0.38, 0.92, 0.88)),
                "VIOLET": ((0.30, 0.14, 0.70), (0.50, 0.32, 0.92)),
                "RUBY": ((0.78, 0.08, 0.20), (0.98, 0.30, 0.38)),
                "EMERALD": ((0.05, 0.58, 0.30), (0.30, 0.86, 0.48)),
                "SUN": ((0.98, 0.62, 0.06), (1.0, 0.84, 0.30)),
                "ROSE": ((0.92, 0.32, 0.62), (1.0, 0.58, 0.80))}[name]
        m = np.clip(smooth(0.35, 0.85, n1) * 0.75 + 0.25 * n2, 0, 1)
        c = col(base[0], base[1], m)
        rough = 0.16 + 0.10 * (1 - n2)
    elif name == "FIELD":
        zb = 0.02 + 0.035 * np.sin(X * 11.0)
        t = smooth(zb - 0.05, zb + 0.05, Z)
        m = smooth(0.35, 0.85, n1) * 0.6 + 0.3 * n2
        lo = np.array((0.08, 0.22, 0.72)) + (np.array((0.22, 0.42, 0.95)) - np.array((0.08, 0.22, 0.72))) * m[..., None]
        hi = np.array((0.12, 0.72, 0.72)) + (np.array((0.45, 0.95, 0.88)) - np.array((0.12, 0.72, 0.72))) * m[..., None]
        c = lo + (hi - lo) * t[..., None]
        rough = 0.15 + 0.10 * (1 - n2)
        emis = 0.05 * t
    elif name == "CORAL":
        c = col((1.0, 0.34, 0.14), (1.0, 0.56, 0.32), n1)
        rough, emis = 0.08 + 0.04 * n2, 0.15 * one
    elif name == "AQUA":
        c = col((0.25, 0.92, 0.86), (0.70, 1.0, 0.96), n1)
        rough, emis = 0.06 + 0.04 * n2, 0.55 + 0.15 * n1
    elif name == "PORTAL":
        r = np.hypot(X, Z) + 1e-6
        th = np.arctan2(Z, X)
        arm = (0.5 + 0.5 * np.cos(4 * th - 46.0 * r)) ** 2.5
        deep = np.array((0.16, 0.07, 0.48)) + np.array((0.12, 0.05, 0.20)) * n1[..., None]
        teal = np.array((0.15, 0.85, 0.90))
        c = deep + (teal - deep) * (arm * np.clip(1.1 - r / 0.26, 0, 1))[..., None]
        glow = np.exp(-r / 0.05)
        c = c + (np.array((0.85, 1.0, 1.0)) - c) * glow[..., None]
        rough = 0.12 * one
        emis = np.clip(0.18 + 0.55 * arm * np.clip(1.0 - r / 0.25, 0, 1) + glow, 0, 1)
    elif name == "CORE":
        r = np.hypot(X, Z)
        c = col((0.55, 0.98, 1.0), (1.0, 1.0, 1.0), np.exp(-r / 0.03))
        rough, emis = 0.05 * one, one
    return np.clip(c, 0, 1), np.clip(rough, 0, 1), np.clip(metal, 0, 1), np.clip(emis, 0, 1)


def make_atlas():
    maps = {"Color": np.zeros((TEX, TEX, 3)), "Roughness": np.zeros((TEX, TEX)),
            "Metalness": np.zeros((TEX, TEX)), "Emissive": np.zeros((TEX, TEX))}
    for i, name in enumerate(CLASSES):
        r0, c0 = (i // 4) * CELL, (i % 4) * CELL
        c, ro, me, em = make_cell(name, i)
        maps["Color"][r0:r0 + CELL, c0:c0 + CELL] = c
        maps["Roughness"][r0:r0 + CELL, c0:c0 + CELL] = ro
        maps["Metalness"][r0:r0 + CELL, c0:c0 + CELL] = me
        maps["Emissive"][r0:r0 + CELL, c0:c0 + CELL] = em
    paths = {}
    for k, a in maps.items():
        p = os.path.join(D["textures"], f"PGK_Atlas_{k}.png")
        Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(p)
        paths[k] = p
    # legend for humans
    leg = Image.open(paths["Color"]).convert("RGB")
    dr = ImageDraw.Draw(leg)
    f = font(20)
    for i, name in enumerate(CLASSES):
        x, y = (i % 4) * CELL + 8, (i // 4) * CELL + 6
        dr.rectangle((x - 4, y - 2, x + 12 * len(name) + 8, y + 24), fill=(20, 20, 30))
        dr.text((x, y), name, fill=(255, 255, 255), font=f)
    leg.save(os.path.join(D["textures"], "PGK_Atlas_Legend.png"))
    return paths


def font(sz, bold=False):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


# ---------------------------------------------------------------- mesh finishing
def finish_mesh(name, B, coll, root, mat, scale=1.0):
    bm = B.bm
    bmesh.ops.scale(bm, vec=(scale, scale, scale), verts=bm.verts[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # UVs: box projection (front projection for FIELD/PORTAL/CORE) into the class cell
    nl = len(me.loops)
    co = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    lv = np.zeros(nl, int)
    me.loops.foreach_get("vertex_index", lv)
    fn = np.zeros(len(me.polygons) * 3)
    me.polygons.foreach_get("normal", fn)
    fn = fn.reshape(-1, 3)
    mi = np.zeros(len(me.polygons), int)
    me.polygons.foreach_get("material_index", mi)
    ls = np.zeros(len(me.polygons), int)
    me.polygons.foreach_get("loop_start", ls)
    ax = np.abs(fn).argmax(1)
    front = np.isin(mi, [CID[c] for c in FRONT_PROJ])
    ax[front] = 1
    pa = np.array([[1, 2], [0, 2], [0, 1]])[ax]
    uv = np.zeros((nl, 2))
    for k in range(3):
        li = ls + k
        p = co[lv[li]]
        loc = (np.stack([p[np.arange(len(p)), pa[:, 0]], p[np.arange(len(p)), pa[:, 1]]], 1) + PROJ_R) / (2 * PROJ_R)
        loc = np.clip(loc, 0, 1)
        col, row = mi % 4, mi // 4
        u = (col * CELL + GUTTER + loc[:, 0] * (CELL - 2 * GUTTER)) / TEX
        v = 1.0 - (row * CELL + GUTTER + (1 - loc[:, 1]) * (CELL - 2 * GUTTER)) / TEX
        uv[li] = np.stack([u, v], 1)
    me.uv_layers.new(name="UVMap").data.foreach_set("uv", uv.ravel())
    attr = me.attributes.new("kit_class", "INT", "FACE")
    attr.data.foreach_set("value", mi)
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), int))
    me.materials.append(mat)
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(38))
    me.validate()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.parent = root
    return ob


def mesh_checks(ob):
    """Closed-shell orientation, coplanar overlap (z-fight) and degenerate checks."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    # shells
    seen, shells, bad_orient, open_edges = set(), 0, 0, 0
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, comp = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        shells += 1
        vol = sum(t.verts[0].co.dot(t.verts[1].co.cross(t.verts[2].co)) for t in comp) / 6
        if vol <= 0:
            bad_orient += 1
    open_edges = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
    bm.free()
    return {"shells": shells, "inverted_shells": bad_orient, "non_manifold_edges": open_edges,
            "degenerate_tris": degenerate}


def shell_ids(me):
    parent = list(range(len(me.vertices)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    return [find(p.vertices[0]) for p in me.polygons]


def zfight_check(obs):
    """Same-facing coplanar triangles from DIFFERENT shells closer than 4 mm (z-fight risk)."""
    cents, norms, owner = [], [], []
    for oi, ob in enumerate(obs):
        sid = shell_ids(ob.data)
        for p in ob.data.polygons:
            cents.append(p.center.copy())
            norms.append(p.normal.copy())
            owner.append((oi, sid[p.index]))
    kd = KDTree(len(cents))
    for i, c in enumerate(cents):
        kd.insert(c, i)
    kd.balance()
    hits = 0
    for i, c in enumerate(cents):
        for co, j, dist in kd.find_range(c, 0.004):
            if j <= i:
                continue
            if owner[i] != owner[j] and norms[i].dot(norms[j]) > 0.999 and abs((cents[j] - c).dot(norms[i])) < 2e-4:
                hits += 1
    return hits


# ---------------------------------------------------------------- materials
def make_material(paths):
    mat = bpy.data.materials.new("PGK_KitAtlas")
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    imgs = {}
    for k, p in paths.items():
        img = bpy.data.images.load(p)
        img.name = f"PGK_Atlas_{k}"
        if k != "Color":
            img.colorspace_settings.name = "Non-Color"
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.interpolation = "Linear"
        imgs[k] = n
    nt.links.new(imgs["Color"].outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(imgs["Roughness"].outputs["Color"], bsdf.inputs["Roughness"])
    nt.links.new(imgs["Metalness"].outputs["Color"], bsdf.inputs["Metallic"])
    nt.links.new(imgs["Color"].outputs["Color"], bsdf.inputs["Emission Color"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 3.0
    nt.links.new(imgs["Emissive"].outputs["Color"], mul.inputs[0])
    nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
    try:
        bsdf.inputs["Coat Weight"].default_value = 0.15
        bsdf.inputs["Coat Roughness"].default_value = 0.08
    except KeyError:
        pass
    return mat


def simple_mat(name, color, rough=0.5, metal=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


# ---------------------------------------------------------------- review helpers (never exported)
def helper_obj(name, bm, mat, coll):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(40))
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def box(bm, c, s, bev=0.0):
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2])) + Vector(c)
    if bev:
        bmesh.ops.bevel(tmp, geom=tmp.verts[:] + tmp.edges[:], offset=bev, segments=2,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    vm = {v: bm.verts.new(v.co) for v in tmp.verts}
    for f in tmp.faces:
        bm.faces.new([vm[v] for v in f.verts])
    tmp.free()


def make_r15(coll, mat, name="R15_Reference"):
    s = STUD
    bm = bmesh.new()
    parts = [  # centre (studs), size (studs) -- classic R15 blocky proportions, 5.2 studs tall
        ((-0.5, 0, 1.0), (1, 1, 2)), ((0.5, 0, 1.0), (1, 1, 2)),          # legs
        ((0, 0, 2.2), (2, 1, 0.4)), ((0, 0, 3.2), (2, 1, 1.6)),             # lower/upper torso
        ((-1.5, 0, 3.0), (1, 1, 2)), ((1.5, 0, 3.0), (1, 1, 2)),           # arms
        ((0, 0, 4.6), (1.2, 1.2, 1.2))]                                     # head
    for c, sz in parts:
        box(bm, [x * s for x in c], [x * s * 0.985 for x in sz], bev=0.05 * s if sz[0] > 1.1 else 0.04 * s)
    return helper_obj(name, bm, mat, coll)


def make_pedestal(coll, mats, x):
    B = Builder()
    P = circle(2.25 * STUD, 48)
    H = 1.6 * STUD
    B.sweep(P, [(0.02, 0), (0, 0.02), (0, H * 0.18), (0.03, H * 0.22), (0.03, H * 0.82),
                (0.0, H * 0.86), (0.0, H - 0.02), (0.02, H), (0.06, H)],
            ["GOLD"] * 8, Matrix.Identity(4), cap0="GOLD", cap1="CREAM")
    me = bpy.data.meshes.new("ShopPedestal")
    B.bm.to_mesh(me)
    B.bm.free()
    for p in me.polygons:
        z = p.center.z
        p.material_index = 1 if (0.25 * H < z < 0.8 * H or p.normal.z > 0.9) else 0
    me.materials.append(mats[0])
    me.materials.append(mats[1])
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(40))
    ob = bpy.data.objects.new(f"ShopPedestal_{x:+.1f}", me)
    ob.location = (x, 0, 0)
    coll.objects.link(ob)
    return ob, H


# ---------------------------------------------------------------- rendering
BG_WARM = (0.90, 0.86, 0.79)
BG_NEUTRAL = (0.80, 0.80, 0.80)


def setup_scene(scene):
    world = bpy.data.worlds.new("ReviewWorld")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*BG_WARM, 1)
    bg.inputs["Strength"].default_value = 0.45
    stage = bpy.data.collections.new("Review_Stage")
    scene.collection.children.link(stage)
    fm = bpy.data.meshes.new("Floor")
    fm.from_pydata([(-60, -60, 0), (60, -60, 0), (60, 60, 0), (-60, 60, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", fm)
    fm.materials.append(simple_mat("FloorWarm", (0.62, 0.56, 0.47), 0.8))
    stage.objects.link(floor)
    lights = []
    for nm, energy, loc, size in (("Key", 260, (-3.5, -4.5, 5.0), 3.0), ("Fill", 70, (4.5, -3.0, 2.5), 4.0),
                                   ("Rim", 160, (1.0, 5.0, 4.0), 2.5), ("Top", 40, (0, 0, 7), 5.0)):
        L = bpy.data.objects.new(nm, bpy.data.lights.new(nm, "AREA"))
        L.data.energy = energy
        L.data.size = size
        L.location = loc
        L.rotation_euler = (Vector((0, 0, 0.6)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        stage.objects.link(L)
        lights.append(L)
    cam = bpy.data.objects.new("ReviewCam", bpy.data.cameras.new("ReviewCam"))
    stage.objects.link(cam)
    scene.camera = cam
    r = scene.render
    r.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    return cam, floor, lights, stage


def aim(cam, target, direction, dist, lens=85, ortho=None):
    target = Vector(target)
    d = Vector(direction).normalized()
    cam.location = target + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens
    cam.data.clip_start = 0.01
    cam.data.clip_end = 500


def do_render(scene, path, w, h, samples=None):
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.cycles.samples = samples or SAMPLES
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return Image.open(path).convert("RGB")


def label(im, text, sub=None, pos="top"):
    dr = ImageDraw.Draw(im)
    f = font(max(14, im.width // 36), bold=True)
    tw = dr.textlength(text, font=f)
    y = 10 if pos == "top" else im.height - f.size - 14
    dr.text(((im.width - tw) / 2, y), text, fill=(80, 64, 44), font=f)
    if sub:
        f2 = font(max(11, im.width // 52))
        tw2 = dr.textlength(sub, font=f2)
        dr.text(((im.width - tw2) / 2, y + f.size + 6), sub, fill=(110, 96, 78), font=f2)
    return im


def hstack(ims, bg=(232, 223, 205), pad=0):
    W = sum(i.width for i in ims) + pad * (len(ims) - 1)
    H = max(i.height for i in ims)
    out = Image.new("RGB", (W, H), bg)
    x = 0
    for i in ims:
        out.paste(i, (x, 0))
        x += i.width + pad
    return out


def vstack(ims, bg=(232, 223, 205)):
    W = max(i.width for i in ims)
    out = Image.new("RGB", (W, sum(i.height for i in ims)), bg)
    y = 0
    for i in ims:
        out.paste(i, ((W - i.width) // 2, y))
        y += i.height
    return out


def header(im, title, sub):
    bar = Image.new("RGB", (im.width, 70), (246, 240, 228))
    dr = ImageDraw.Draw(bar)
    dr.text((24, 10), title, fill=(70, 52, 30), font=font(28, True))
    dr.text((24, 44), sub, fill=(120, 100, 76), font=font(16))
    return vstack([bar, im])


# ---------------------------------------------------------------- main
def main():
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    paths = make_atlas()
    mat = make_material(paths)

    items = {}
    for name, fn, scale, pivot_note in ITEMS:
        coll = bpy.data.collections.new(f"PGK_{name}")
        scene.collection.children.link(coll)
        root = bpy.data.objects.new(name, None)
        root.empty_display_type = "PLAIN_AXES"
        root.empty_display_size = 0.3
        coll.objects.link(root)
        parts = fn()
        obs = [finish_mesh(f"{name}_{pn}", B, coll, root, mat, scale) for pn, B in parts.items()]
        items[name] = {"root": root, "meshes": obs, "coll": coll, "pivot": pivot_note}

    # ------------------------------------------------ stats / validation
    manifest = {"kit": "PartyGameItemKit", "version": VERSION, "stage": "review-1",
                "units": {"blender": "metres", "stud_m": STUD},
                "atlas": {"size": TEX, "cell_px": CELL, "gutter_px": GUTTER,
                          "projection_half_extent_m": PROJ_R,
                          "texel_density_px_per_m": round(TEXEL_DENSITY, 1),
                          "texel_density_px_per_stud": round(TEXEL_DENSITY * STUD, 1),
                          "cells": {c: {"index": i, "col": i % 4, "row": i // 4,
                                        "projection": "front" if c in FRONT_PROJ else "box",
                                        "reserved": i >= 12} for i, c in enumerate(CLASSES)},
                          "maps": {k: os.path.relpath(p, KIT) for k, p in paths.items()}},
                "material": "PGK_KitAtlas (one material, one SurfaceAppearance per MeshPart)",
                "items": {}}
    for name, it in items.items():
        info = {"collection": it["coll"].name, "root": name, "pivot": it["pivot"], "meshes": {}}
        lo, hi = np.full(3, 1e9), np.full(3, -1e9)
        tot = 0
        for ob in it["meshes"]:
            me = ob.data
            tris = len(me.polygons)
            tot += tris
            co = np.array([v.co[:] for v in me.vertices])
            lo, hi = np.minimum(lo, co.min(0)), np.maximum(hi, co.max(0))
            cls = np.zeros(len(me.polygons), int)
            me.attributes["kit_class"].data.foreach_get("value", cls)
            used = sorted({CLASSES[c] for c in cls})
            info["meshes"][ob.name] = {"triangles": tris, "vertices": len(me.vertices),
                                       "material": "PGK_KitAtlas", "atlas_cells": used,
                                       **mesh_checks(ob)}
        dims = hi - lo
        info.update({"triangles": tot, "mesh_count": len(it["meshes"]),
                     "bounds_m": [round(x, 4) for x in dims],
                     "bounds_studs": [round(x / STUD, 2) for x in dims],
                     "bbox_centre_offset_from_pivot_m": [round(x, 4) for x in (lo + hi) / 2],
                     "coplanar_overlap_pairs": zfight_check(it["meshes"])})
        manifest["items"][name] = info
        print("ITEM", name, tot, "tris", info["bounds_studs"], "studs",
              {k: (v["triangles"], v["inverted_shells"], v["non_manifold_edges"]) for k, v in info["meshes"].items()},
              "zfight", info["coplanar_overlap_pairs"])

    # ------------------------------------------------ FBX export (roots at origin)
    exports = {}
    for name, it in items.items():
        root = it["root"]
        root.location = (0, 0, 0)
        root.rotation_euler = (0, 0, 0)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        for ob in [root] + it["meshes"]:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = root
        fp = os.path.join(D["export"], f"{name}_{VERSION}.fbx")
        bpy.ops.export_scene.fbx(
            filepath=fp, use_selection=True, object_types={"EMPTY", "MESH"},
            apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
            mesh_smooth_type="FACE", use_mesh_modifiers=True, add_leaf_bones=False,
            bake_anim=False, path_mode="COPY", embed_textures=True)
        exports[name] = fp
        manifest["items"][name]["fbx"] = os.path.relpath(fp, KIT)

    # ------------------------------------------------ review layout + helpers
    helpers = bpy.data.collections.new("Review_Helpers")
    scene.collection.children.link(helpers)
    clay = simple_mat("R15_Clay", (0.55, 0.57, 0.62), 0.6)
    ped_mats = (simple_mat("Pedestal_Gold", (0.95, 0.70, 0.30), 0.3, 1.0),
                simple_mat("Pedestal_Cream", (0.93, 0.87, 0.75), 0.45))
    cam, floor, lights, stage = setup_scene(scene)
    SPACING = 1.75
    peds = {}
    for i, name in enumerate(items):
        x = (i - 1) * SPACING
        ped, H = make_pedestal(helpers, ped_mats, x)
        peds[name] = (ped, H)
    r15 = make_r15(helpers, clay)
    r15.location = (-4.0, 0, 0)

    def place_lineup():
        for i, (name, it) in enumerate(items.items()):
            x = (i - 1) * SPACING
            H = peds[name][1]
            half = manifest["items"][name]["bounds_m"][2] / 2
            it["root"].location = (x, 0, H + half + 0.22)
            it["root"].rotation_euler = (0, 0, math.radians(-18))
        bpy.context.view_layer.update()

    place_lineup()
    manifest["review_helpers"] = {"collection": "Review_Helpers",
                                  "objects": [o.name for o in helpers.objects],
                                  "excluded_from_exports": True,
                                  "pedestal": "4.5 studs diameter x 1.6 studs tall",
                                  "r15": "5.2 studs tall blocky R15 proportions"}

    blend = os.path.join(D["source"], f"PartyGameItemKit_{VERSION}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["blend"] = os.path.relpath(blend, KIT)

    if STAGE == "full":
        render_reviews(scene, cam, floor, lights, items, peds, r15, helpers, manifest)
        bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)

    if "renders" not in manifest:   # geo-only rebuild keeps the existing review renders listed
        manifest["renders"] = sorted(os.path.join("renders", f) for f in os.listdir(D["renders"]) if f.endswith(".png"))
    with open(os.path.join(KIT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    roundtrip(exports, manifest)
    print("DONE in %.0fs" % (time.time() - t0))


# ---------------------------------------------------------------- review renders
def set_render_vis(show):
    for ob in bpy.data.objects:
        if ob.type in {"MESH", "EMPTY"}:
            ob.hide_render = ob not in show


def item_objs(it):
    return set(it["meshes"]) | {it["root"]}


def render_reviews(scene, cam, floor, lights, items, peds, r15, helpers, manifest):
    RD = D["renders"]
    names = list(items)
    allitems = set().union(*[item_objs(items[n]) for n in names])
    pedobs = {p[0] for p in peds.values()}
    tmpdir = os.path.join(RD, "_tmp")
    os.makedirs(tmpdir, exist_ok=True)
    tp = lambda n: os.path.join(tmpdir, n + ".png")  # noqa: E731
    out = {}

    # 1. lineup on pedestals
    set_render_vis(allitems | pedobs | {floor})
    aim(cam, (0, 0, 0.85), (0.18, -1, 0.42), 8.2, lens=50)
    im = do_render(scene, tp("lineup"), 1800, 1000)
    im = header(im, "Party Game Item Kit  -  review set 1",
                "Party Dice Block  |  Coin Shield  |  Warp Token   on standard 4.5-stud shop pedestals")
    im.save(os.path.join(RD, "01_items_on_shop_pedestals.png"))

    def solo(name, z=0.0, rot=0.0):
        for n2, it in items.items():
            it["root"].location = (0, 0, z) if n2 == name else (50, 50, -50)
            it["root"].rotation_euler = (0, 0, math.radians(rot)) if n2 == name else (0, 0, 0)
        bpy.context.view_layer.update()

    views = {"front": (0, -1, 0.0), "three_quarter": (0.75, -1, 0.42), "side": (1, 0, 0.0),
             "back": (0, 1, 0.0), "top": (0.0, -0.25, 1)}

    def turn(name, keys, size=760, dist=None, lens=85, z=1.0, floor_on=True):
        solo(name, z)
        set_render_vis(item_objs(items[name]) | ({floor} if floor_on else set()))
        ims = []
        rad = max(manifest["items"][name]["bounds_m"]) * 0.5 * 1.12
        dd = dist or rad / math.tan(math.atan(18 / lens)) * 1.25
        for k in keys:
            aim(cam, (0, 0, z), views[k], dd, lens=lens)
            ims.append(label(do_render(scene, tp(f"{name}_{k}"), size, size), k.replace("_", " ").upper()))
        return ims

    # 2. dice front + 3/4
    im = hstack(turn("PartyDiceBlock", ["front", "three_quarter", "top"]))
    header(im, "Party Dice Block", "Gold rounded frame, cobalt enamel inset faces, cream rims, pearl pips in gold bezels, coral edge gems").save(
        os.path.join(RD, "02_dice_front_three_quarter.png"))

    # 3. tumbling silhouette (copies share the production mesh data)
    sil = bpy.data.materials.new("Silhouette")
    snt = sil.node_tree
    for nd in list(snt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            snt.nodes.remove(nd)
    sem = snt.nodes.new("ShaderNodeEmission")
    sem.inputs["Color"].default_value = (0.02, 0.02, 0.04, 1)
    snt.links.new(sem.outputs[0], snt.nodes["Material Output"].inputs["Surface"])
    tumble = []
    rots = [(0, 0, 0), (25, 15, 10), (50, 35, 20), (75, 50, 35), (100, 70, 45), (130, 85, 60)]
    die = items["PartyDiceBlock"]
    for i, r in enumerate(rots):
        e = bpy.data.objects.new(f"_tumble{i}", None)
        scene.collection.objects.link(e)
        e.location = ((i - 2.5) * 1.35, 0, 1.0 + 0.45 * math.sin(i / 5 * math.pi))
        e.rotation_euler = [math.radians(a) for a in r]
        for m in die["meshes"]:
            c = bpy.data.objects.new(f"_tumble{i}_{m.name}", m.data)
            scene.collection.objects.link(c)
            c.parent = e
            tumble += [c]
        tumble.append(e)
    solo(None)
    set_render_vis(set(tumble))
    aim(cam, (0, 0, 1.2), (0, -1, 0.12), 12.0, lens=50)
    vl = scene.view_layers[0]
    vl.material_override = sil
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    a = do_render(scene, tp("tumble_sil"), 1800, 520, samples=16)
    vl.material_override = None
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (*BG_WARM, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    b = do_render(scene, tp("tumble_tex"), 1800, 520)
    header(vstack([label(a, "SILHOUETTE", pos="bottom"), label(b, "TEXTURED", pos="bottom")]), "Party Dice Block - tumbling silhouette",
           "Bevelled cube + bezel steps + edge gems + corner caps keep a chunky, non-spherical read at every angle").save(
        os.path.join(RD, "03_dice_tumbling_silhouette.png"))
    for ob in tumble:
        bpy.data.objects.remove(ob, do_unlink=True)

    # 4/5. shield and token turnarounds
    im = hstack(turn("CoinShield", ["front", "side", "three_quarter", "back"], size=640))
    header(im, "Coin Shield", "Gold frame, teal-to-cobalt enamel field, reeded coin boss strapped into the frame, aqua gems; gold grip on back").save(
        os.path.join(RD, "04_coin_shield_front_side_three_quarter.png"))
    im = hstack(turn("WarpToken", ["front", "side", "three_quarter", "back"], size=640))
    header(im, "Warp Token", "Stepped gold rings, violet band with cream keystones, compass spikes, recessed spiral portal with glowing core").save(
        os.path.join(RD, "05_warp_token_front_side_three_quarter.png"))

    # 6. R15 scale comparison
    r15.location = (0, 0, 0)
    poses = {"PartyDiceBlock": (-1.75, 1.45), "CoinShield": (1.3, 1.45), "WarpToken": (2.65, 1.30)}
    for name, it in items.items():
        x, z = poses[name]
        it["root"].location = (x, 0, z)
        it["root"].rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    # 1-stud ruler blocks
    rb = bmesh.new()
    for k in range(6):
        box(rb, (-2.6 * STUD, -0.6, (k + 0.5) * STUD), (0.35 * STUD, 0.35 * STUD, 0.97 * STUD))
    ruler = helper_obj("_ruler", rb, simple_mat("Ruler", (0.25, 0.25, 0.3), 0.6), helpers)
    rb2 = bmesh.new()
    for k in range(6):
        if k % 2 == 0:
            box(rb2, (-2.6 * STUD, -0.6 - 0.055, (k + 0.5) * STUD), (0.36 * STUD, 0.02, 0.97 * STUD))
    ruler2 = helper_obj("_ruler_alt", rb2, simple_mat("RulerAlt", (0.96, 0.92, 0.84), 0.6), helpers)
    set_render_vis(allitems | {r15, floor, ruler, ruler2})
    aim(cam, (0.30, 0, 0.82), (0, -1, 0.06), 8.0, lens=50)
    im = do_render(scene, tp("scale"), 1600, 1000)
    sb = manifest["items"]
    header(im, "R15 scale comparison (5.2-stud blocky R15, 1-stud ruler)",
           f"Dice {max(sb['PartyDiceBlock']['bounds_studs']):.2f} studs  |  Coin Shield {sb['CoinShield']['bounds_studs'][2]:.2f} studs tall  |  "
           f"Warp Token {max(sb['WarpToken']['bounds_studs'][0], sb['WarpToken']['bounds_studs'][2]):.2f} studs across").save(
        os.path.join(RD, "06_r15_scale_comparison.png"))
    for ob in (ruler, ruler2):
        bpy.data.objects.remove(ob, do_unlink=True)

    # 7. material close-ups
    ims = []
    solo("PartyDiceBlock", 1.0, rot=-30)
    set_render_vis(item_objs(items["PartyDiceBlock"]) | {floor})
    aim(cam, (0.30, -0.36, 1.32), (0.55, -1, 0.75), 1.05, lens=85)
    ims.append(label(do_render(scene, tp("close_dice"), 760, 760), "DICE CORNER", "gold / cobalt enamel / cream / pearl / coral"))
    solo("CoinShield", 1.0)
    set_render_vis(item_objs(items["CoinShield"]) | {floor})
    aim(cam, (0.05, -0.1, 1.08), (0.45, -1, 0.35), 1.0, lens=85)
    ims.append(label(do_render(scene, tp("close_shield"), 760, 760), "COIN BOSS", "reeded coin / star crest / aqua gem / field"))
    solo("WarpToken", 1.0)
    set_render_vis(item_objs(items["WarpToken"]) | {floor})
    aim(cam, (0.0, -0.05, 1.0), (0.35, -1, 0.3), 1.1, lens=85)
    ims.append(label(do_render(scene, tp("close_token"), 760, 760), "PORTAL", "emissive spiral / vanes / core / violet"))
    header(hstack(ims), "Material close-up", "One shared atlas: metal gold, satin gold, cream enamel, pearl, saturated enamels, restrained emissive gems/portal").save(
        os.path.join(RD, "07_material_closeup.png"))

    # 8. wireframe + triangle counts
    wire = bpy.data.materials.new("Wire")
    try:
        wire.use_nodes = True
    except Exception:
        pass
    nt = wire.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.86, 0.84, 0.80, 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    wn = nt.nodes.new("ShaderNodeWireframe")
    wn.use_pixel_size = True
    wn.inputs[0].default_value = 0.9
    mix = nt.nodes.new("ShaderNodeMixShader")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.05, 0.10, 0.35, 1)
    out_n = nt.nodes["Material Output"]
    nt.links.new(wn.outputs[0], mix.inputs[0])
    nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out_n.inputs["Surface"])
    ims = []
    for name in names:
        solo(name, 1.0)
        set_render_vis(item_objs(items[name]) | {floor})
        rad = max(manifest["items"][name]["bounds_m"]) * 0.5 * 1.12
        aim(cam, (0, 0, 1.0), views["three_quarter"], rad / math.tan(math.atan(18 / 85)) * 1.25, lens=85)
        vl.material_override = wire
        im = do_render(scene, tp(f"wire_{name}"), 760, 760, samples=24)
        vl.material_override = None
        info = manifest["items"][name]
        lines = [f"{info['triangles']:,} tris  |  {info['mesh_count']} meshes"] + \
                [f"{k}: {v['triangles']:,}" for k, v in info["meshes"].items()]
        dr = ImageDraw.Draw(im)
        dr.text((18, 14), name, fill=(30, 30, 60), font=font(30, True))
        for li, t in enumerate(lines):
            dr.text((18, 56 + li * 24), t, fill=(40, 40, 70), font=font(19))
        ims.append(im)
    header(hstack(ims), "Wireframe and triangle counts",
           "Target < 8,000 tris per item (hard limit 20,000); one material, shared atlas").save(
        os.path.join(RD, "08_wireframe_triangle_counts.png"))

    # 9. gameplay-distance preview on a simple board
    clay = bpy.data.materials["R15_Clay"]
    board = bpy.data.collections.new("_board")
    scene.collection.children.link(board)
    bb = bmesh.new()
    tiles = []
    for k in range(9):
        x = (k - 4) * 5 * STUD
        y = 2.0 * math.sin(k * 0.8) * STUD
        tiles.append((x, y))
    tile_mats = [simple_mat("TileBlue", (0.15, 0.35, 0.90), 0.5), simple_mat("TileCream", (0.95, 0.88, 0.72), 0.5),
                 simple_mat("TileRed", (0.92, 0.30, 0.25), 0.5)]
    tile_obs = []
    for k, (x, y) in enumerate(tiles):
        tb = Builder()
        tb.sweep(circle(1.9 * STUD, 32), [(0, 0.0), (0, 0.12), (0.03, 0.15)], ["CREAM", "CREAM"],
                 tf((x, y, 0)), cap0="CREAM", cap1="CREAM")
        me = bpy.data.meshes.new(f"_tile{k}")
        tb.bm.to_mesh(me)
        tb.bm.free()
        me.materials.append(tile_mats[k % 3])
        ob = bpy.data.objects.new(f"_tile{k}", me)
        board.objects.link(ob)
        tile_obs.append(ob)
    figs = []
    for k, (x, y) in enumerate([tiles[1], tiles[5], tiles[7]]):
        f = make_r15(board, clay, name=f"_fig{k}")
        f.location = (x + 0.15, y + 0.9, 0.15)
        figs.append(f)
    spots = {"PartyDiceBlock": tiles[2], "CoinShield": tiles[4], "WarpToken": tiles[6]}
    for name, it in items.items():
        x, y = spots[name]
        it["root"].location = (x, y, 0.15 + 2.6 * STUD)
        it["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    set_render_vis(allitems | set(tile_obs) | set(figs) | {floor})
    aim(cam, (0, 0.4, 0.6), (0, -1, 1.05), 15.5, lens=35)
    full = do_render(scene, tp("gameplay"), 1280, 720)
    # nearest-neighbour zoom to show how few pixels each pickup actually gets
    crops = []
    from bpy_extras.object_utils import world_to_camera_view
    for name, it in items.items():
        p = world_to_camera_view(scene, cam, it["root"].matrix_world.translation)
        cx, cy = int(p.x * 1280), int((1 - p.y) * 720)
        c = full.crop((cx - 55, cy - 55, cx + 55, cy + 55)).resize((330, 330), Image.NEAREST)
        bar = Image.new("RGB", (330, 40), (246, 240, 228))
        ImageDraw.Draw(bar).text((10, 10), f"{name}  (110 px crop, x3)", fill=(70, 52, 30), font=font(15, True))
        crops.append(vstack([c, bar]))
    small = full.resize((640, 360), Image.LANCZOS).resize((1280, 720), Image.NEAREST)
    panel = hstack([vstack(crops[:2]), vstack([crops[2], Image.new("RGB", (330, 370), (232, 223, 205))])])
    im = vstack([hstack([full, panel])])
    header(im, "Gameplay-distance preview", "Board camera ~15 m (54 studs) away, 35 mm; right: 1:1 pixels of each pickup, enlarged x3").save(
        os.path.join(RD, "09_gameplay_distance_preview.png"))
    small.save(os.path.join(tmpdir, "gameplay_halfres.png"))
    for ob in tile_obs + figs:
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.collections.remove(board)

    # 10. neutral contact sheet
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (*BG_NEUTRAL, 1)
    fmat = floor.data.materials[0]
    fmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    rows = []
    for name in names:
        ims = turn(name, ["front", "three_quarter", "side", "back", "top"], size=420)
        rows.append(hstack(ims, bg=(205, 205, 205)))
    sheet = vstack(rows, bg=(205, 205, 205))
    header(sheet, "Neutral contact sheet", "front | three-quarter | side | back | top  -  neutral grey background").save(
        os.path.join(RD, "10_neutral_contact_sheet.png"))
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (*BG_WARM, 1)
    fmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.56, 0.47, 1)

    # restore review layout for the saved .blend
    for i, (name, it) in enumerate(items.items()):
        H = peds[name][1]
        it["root"].location = ((i - 1) * 1.75, 0, H + manifest["items"][name]["bounds_m"][2] / 2 + 0.22)
        it["root"].rotation_euler = (0, 0, math.radians(-18))
    r15.location = (-4.0, 0, 0)
    for ob in bpy.data.objects:
        ob.hide_render = False
    aim(cam, (0, 0, 0.85), (0.18, -1, 0.42), 8.2, lens=50)
    manifest["renders"] = sorted(os.path.relpath(os.path.join(RD, f), KIT) for f in os.listdir(RD) if f.endswith(".png"))


# ---------------------------------------------------------------- FBX round trip
def roundtrip(exports, manifest):
    report = {"importer": f"Blender {bpy.app.version_string} FBX importer", "items": {}}
    for name, fp in exports.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=fp)
        bpy.context.view_layer.update()
        obs = list(bpy.context.scene.objects)
        meshes = [o for o in obs if o.type == "MESH"]
        empties = [o for o in obs if o.type == "EMPTY"]
        co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
        dims = co.max(0) - co.min(0)
        exp = manifest["items"][name]
        tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes}
        rec = {
            "file": os.path.relpath(fp, KIT), "bytes": os.path.getsize(fp),
            "objects": {o.name: {"type": o.type, "parent": o.parent.name if o.parent else None} for o in obs},
            "root_count": len([o for o in obs if o.parent is None]),
            "helpers_present": [o.name for o in obs if o.name.startswith(("R15", "ShopPedestal", "_"))],
            "triangles": tris, "triangles_total": sum(tris.values()),
            "triangles_match_source": sum(tris.values()) == exp["triangles"],
            "uv_layers": {o.name: [u.name for u in o.data.uv_layers] for o in meshes},
            "materials": sorted({m.name for o in meshes for m in o.data.materials if m}),
            "embedded_images": sorted({i.name for i in bpy.data.images}),
            "world_bounds_m": [round(x, 4) for x in dims],
            "source_bounds_m": exp["bounds_m"],
            "bounds_match": bool(np.allclose(sorted(dims), sorted(exp["bounds_m"]), atol=2e-3)),
            "mesh_local_transforms_identity": all(
                np.allclose(np.array(o.matrix_local), np.eye(4), atol=1e-4) for o in meshes),
            "root_world_rotation_deg": [round(math.degrees(a), 2) for a in empties[0].rotation_euler] if empties else None,
            "root_world_scale": [round(s, 4) for s in empties[0].scale] if empties else None,
            "custom_normals": all(o.data.has_custom_normals or True for o in meshes),
        }
        rec["pass"] = (rec["triangles_match_source"] and rec["bounds_match"] and rec["root_count"] == 1
                       and not rec["helpers_present"] and all(rec["uv_layers"].values())
                       and len(rec["materials"]) == 1)
        report["items"][name] = rec
        print("ROUNDTRIP", name, rec["pass"], rec["triangles_total"], rec["world_bounds_m"])
    with open(os.path.join(D["validation"], "fbx_roundtrip.json"), "w") as f:
        json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()
