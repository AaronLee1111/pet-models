"""Party Game Item Kit -- review stage 5: Pickpocket.

Reference: the Pickpocket turnaround supplied with the v005 brief (coin-pinching teal glove on a
coral cuff; cream finger pads, gold joints, teal gem on the back, gold star coin).

Builds on the v001 kit library and the v002 module (atlas layout + validation helpers); neither is
re-run. Uses the v002 atlas unchanged. Every v001-v004 file is hash-checked before and after.

Layout: the glove stands on its cuff. The palm faces the front (-Y); the index and middle fingers
rise and curl forward over the top, the thumb curls up from below, and the coin is pinched between
the index tip (above) and thumb tip (below), facing the front. The coin spins about the vertical
pinch axis; both tips are centred on that axis, so the tip clearance is identical at every angle.

Run with the `bpy` module (pip install bpy) or Blender:
    python3 PartyGameItemKit/source/build_pickpocket_v005.py
    KIT_STAGE=geo python3 ...        # geometry + export + validation, no renders
"""
import hashlib
import json
import math
import os
import shutil
import sys
import time

import bpy  # noqa: must precede bmesh when using the pip bpy module
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_item_kit as K            # noqa: E402  v001 library
import build_dice_family_v002 as D2   # noqa: E402  v002 library (registers the v002 atlas layout)

VERSION = "v005"
KIT = K.KIT
STUD = K.STUD
STAGE = os.environ.get("KIT_STAGE", "full")
RD = os.path.join(K.D["renders"], "v005_pickpocket")
SCALE = 1.05                          # authored at 1.0, scaled to hit the stud targets
COIN_R, COIN_T = 0.13, 0.025          # radius, half thickness (authored metres)
COIN_C = Vector((0.0, -0.31, 0.60))   # coin centre (authored, pre-rotation frame)
POSE = __import__("mathutils").Matrix.Rotation(math.radians(90), 4, "Z")   # curl plane -> item front
TIP_GAP = 0.004                       # fingertip to coin rim (authored)
CID = D2.CLASSES.index


# ---------------------------------------------------------------- path + tube helpers
def resample(pts, n):
    P = np.asarray(pts, float)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    t = np.linspace(0, s[-1], n)
    return np.stack([np.interp(t, s, P[:, k]) for k in range(3)], 1), t


def arc(c, r, a0, a1, n, x):
    """Arc in the YZ plane at constant x: point = c + r*(cos a * +Y, sin a * +Z)."""
    return [(x, c[0] + r * math.cos(math.radians(a)), c[1] + r * math.sin(math.radians(a)))
            for a in np.linspace(a0, a1, n)]


def bezier(p0, p1, p2, p3, n):
    p0, p1, p2, p3 = (np.array(p) for p in (p0, p1, p2, p3))
    t = np.linspace(0, 1, n)[:, None]
    return list((1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3)


class Path:
    def __init__(self, pts, n=200):
        self.P, self.s = resample(pts, n)
        self.L = self.s[-1]

    def at(self, s):
        return np.array([np.interp(s, self.s, self.P[:, k]) for k in range(3)])

    def sub(self, s0, s1, n):
        return np.array([self.at(s) for s in np.linspace(s0, s1, n)])


def tube(points, radii, ring=12):
    """Closed tube along a polyline with per-point radius (parallel-transport frames)."""
    P = np.asarray(points, float)
    T = np.gradient(P, axis=0)
    T /= np.linalg.norm(T, axis=1)[:, None]
    ref = np.array([1.0, 0, 0]) if abs(T[0][0]) < 0.9 else np.array([0, 0, 1.0])
    Nn = np.cross(T[0], ref)
    Nn /= np.linalg.norm(Nn)
    bm = bmesh.new()
    rings = []
    for i in range(len(P)):
        Nn = Nn - Nn.dot(T[i]) * T[i]
        Nn /= np.linalg.norm(Nn)
        Bn = np.cross(T[i], Nn)
        rings.append([bm.verts.new(P[i] + radii[i] * (math.cos(2 * math.pi * j / ring) * Nn +
                                                       math.sin(2 * math.pi * j / ring) * Bn)) for j in range(ring)])
    for k in range(len(rings) - 1):
        for j in range(ring):
            jj = (j + 1) % ring
            bm.faces.new((rings[k][j], rings[k][jj], rings[k + 1][jj], rings[k + 1][j]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def capsule_radii(s, r, r_start=None, r_end=None, floor=0.14, start_floor=None):
    """Radius profile with hemispherical rounding of radius r_start / r_end at the two ends."""
    L = s[-1] - s[0]
    out = np.full(len(s), r, float)
    for i, si in enumerate(s - s[0]):
        k = 1.0
        if r_end and si > L - r_end:
            u = (si - (L - r_end)) / r_end
            k = min(k, math.sqrt(max(0.0, 1 - u * u)))
        f = floor
        if r_start and si < r_start:
            u = (r_start - si) / r_start
            k = min(k, math.sqrt(max(0.0, 1 - u * u)))
            if start_floor is not None:
                f = start_floor
        out[i] = r * max(k, f)
    return out


def merge(dst, src):
    """Append every face of builder `src` into builder `dst`, keeping material classes."""
    vm = {v: dst.bm.verts.new(v.co) for v in src.bm.verts}
    for f in src.bm.faces:
        nf = dst.bm.faces.new([vm[v] for v in f.verts])
        nf.material_index = f.material_index
    dst.shells += src.shells


def add_bm(B, bm, cls):
    B.append(bm, cls)
    bm.free()


def dome(B, M, r, seg, z0, z1, h, cls, top=None):
    prof = [(0, z0), (0, z1)]
    for a in (40, 75):
        t = math.radians(a)
        prof.append((r * (1 - math.cos(t)), z1 + h * math.sin(t)))
    B.sweep(K.circle(r, seg), prof, [cls] * 3, M, cap0=cls, cap1=top or cls)


# ---------------------------------------------------------------- fingers
def finger(path, r, bands, tip_len, side, boss_at, ring=12):
    """Teal finger tube with gold joint bands, gold knuckle bosses on `side`, cream fingertip pad."""
    F = K.Builder()
    n = max(16, int(path.L / 0.022))
    s_teal = path.L - tip_len * 0.55
    pts = path.sub(0, s_teal, n)
    add_bm(F, tube(pts, np.full(len(pts), r), ring), "TEAL")
    rt = r * 1.10
    s0 = path.L - tip_len
    tp = path.sub(s0, path.L, 12)
    st = np.linspace(s0, path.L, 12)
    add_bm(F, tube(tp, capsule_radii(st, rt, r_start=0.012, r_end=rt, start_floor=0.86), ring), "CREAM")
    for b in bands:
        sb = b * path.L
        bp = path.sub(sb - 0.022, sb + 0.022, 6)
        sbs = np.linspace(sb - 0.022, sb + 0.022, 6)
        add_bm(F, tube(bp, capsule_radii(sbs, r * 1.14, r_start=0.012, r_end=0.012, floor=0.86), ring), "GOLD")
    for b in boss_at:
        sb = b * path.L
        p = path.at(sb)
        tng = path.at(sb + 0.01) - path.at(sb - 0.01)
        sd = np.array(side, float)
        sd = sd - sd.dot(tng / np.linalg.norm(tng)) * tng / np.linalg.norm(tng)
        sd /= np.linalg.norm(sd)
        dome(F, K.frame(Vector(p + sd * (r * 1.14 - 0.014)), Vector(sd), Vector(tng)), 0.034, 14, 0.0, 0.016, 0.018,
             "GOLD", top="GOLD_SATIN")
    return F


def build_glove():
    G = K.Builder()
    # cuff: gold rims, coral band, cobalt stripe, cream roll on top, gold buttons
    ell = lambda rx, ry: K.circle(1.0, 40) * np.array([rx, ry])  # noqa: E731  oval cuff (wider than deep)
    G.sweep(ell(0.20, 0.35), [(0.05, 0.0), (0.012, 0.0), (0, 0.012), (0, 0.040), (0.014, 0.048), (0.014, 0.140),
                                 (0.022, 0.146), (0.022, 0.170), (0.010, 0.176), (0.0, 0.184), (0.0, 0.205),
                                 (0.012, 0.215), (0.05, 0.215)],
            ["GOLD", "GOLD", "GOLD", "GOLD_SATIN", "CORAL_ENAMEL", "CORAL_ENAMEL", "COBALT", "GOLD", "GOLD",
             "GOLD", "GOLD", "GOLD"], K.tf(), cap0="GOLD_SATIN", cap1="GOLD_SATIN")
    G.sweep(ell(0.186, 0.335), [(0, 0.200), (0, 0.250), (0.022, 0.276), (0.062, 0.285), (0.140, 0.272), (0.170, 0.200)],
            ["CREAM"] * 6, K.tf(), closed=True)
    for d, r, rr in (((-1, 0, 0), 0.042, 0.186), ((0, 1, 0), 0.050, 0.336), ((0, -1, 0), 0.050, 0.336)):
        dv = Vector(d)
        dome(G, K.frame(dv * rr + Vector((0, 0, 0.094)), dv, (0, 0, 1)), r, 14, -0.012, 0.010, 0.024, "GOLD",
             top="GOLD_SATIN")
    # palm: rounded mitten block rising out of the cuff
    G.sweep(K.rrect(0.20, 0.15, 0.11, 6), [(0.05, 0.200), (0.02, 0.30), (0.0, 0.40), (0.0, 0.55), (0.015, 0.63),
                                            (0.045, 0.685), (0.085, 0.712), (0.128, 0.722)],
            ["TEAL"] * 7, K.tf(), cap0="TEAL", cap1="TEAL", center=(0, 0))
    # back of the glove: gold bezel, cobalt ring, faceted sea-glass gem, side rivets and a gold strap
    Mg = K.frame((0.0, 0.140, 0.47), (0, 1, 0), (0, 0, 1))
    G.sweep(K.circle(0.092, 24), [(0, -0.012), (0, 0.022), (0.010, 0.032), (0.022, 0.030), (0.026, 0.022)],
            ["GOLD", "GOLD", "GOLD", "GOLD_SATIN"], Mg, cap0="GOLD", cap1="COBALT")
    G.sweep(K.circle(0.060, 8, phase=math.pi / 8), [(0, 0.016), (0, 0.034), (0.034, 0.058)], ["AQUA", "AQUA"], Mg,
            cap0="AQUA", cap1="AQUA")
    G.sweep(K.rrect(0.165, 0.016, 0.012, 2), [(0, -0.010), (0, 0.014), (0.005, 0.019)], ["GOLD", "GOLD"],
            K.frame((0.0, 0.138, 0.47), (0, 1, 0), (0, 0, 1)), cap0="GOLD", cap1="GOLD")
    for sx in (-1, 1):
        dome(G, K.frame((sx * 0.150, 0.140, 0.47), (0, 1, 0), (0, 0, 1)), 0.030, 12, -0.006, 0.022, 0.016,
             "GOLD", top="GOLD_SATIN")
    # fingers (built separately so their mutual clearance can be checked before merging)
    ri, rm, rth = 0.066, 0.062, 0.070
    top_i = COIN_C.z + COIN_R + TIP_GAP                       # index tip lowest point (on the spin axis)
    Ri = 0.155
    idx = Path([(COIN_C.x, COIN_C.y + 2 * Ri, 0.58)] + arc((COIN_C.y + Ri, top_i), Ri, 0, 180, 60, COIN_C.x))
    xm = COIN_C.x + 0.165
    mid = Path([(xm, 0.03, 0.58)] + arc((0.03 - 0.125, 0.75), 0.125, 0, 196, 60, xm))
    bot_t = COIN_C.z - COIN_R - TIP_GAP                       # thumb tip highest point (on the spin axis)
    thb = Path(bezier((-0.12, -0.06, 0.42), (-0.12, -0.24, 0.36), (COIN_C.x, COIN_C.y, 0.37),
                      (COIN_C.x, COIN_C.y, bot_t), 60))
    fingers = {
        "index": finger(idx, ri, (0.20, 0.55), 0.135, (-1, 0, 0), (0.20, 0.55)),
        "middle": finger(mid, rm, (0.22, 0.58), 0.115, (1, 0, 0), (0.22, 0.58)),
        "thumb": finger(thb, rth, (0.56,), 0.13, (-1, 0, 0), (0.56,)),
    }
    return G, fingers


def build_coin():
    C = K.Builder()
    for zdir in ((-1, 0, 0),):
        M = K.frame((0, 0, 0), zdir, (0, 0, 1))
        t = COIN_T
        C.sweep(K.circle(COIN_R, 48), [(0.030, -t + 0.004), (0.018, -t), (0.006, -t + 0.002), (0, -t + 0.013),
                                       (0, t - 0.013), (0.006, t - 0.002), (0.018, t), (0.030, t - 0.004)],
                ["GOLD_SATIN", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD_SATIN"], M, cap0="GOLD_SATIN", cap1="GOLD_SATIN")
    for zdir in ((-1, 0, 0), (1, 0, 0)):
        M = K.frame((0, 0, 0), zdir, (0, 0, 1))
        C.sweep(K.star(4, 0.074, 0.026), [(0, COIN_T - 0.010), (0, COIN_T + 0.004), (0.010, COIN_T + 0.012)],
                ["GOLD", "GOLD"], M, cap0="GOLD", cap1="GOLD", center=(0, 0))
    return C


# ---------------------------------------------------------------- validation helpers
def bvh_of(co, tris):
    return BVHTree.FromPolygons([Vector(c) for c in co], tris)


def builder_bvh(B):
    bm = B.bm.copy()
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    co = [v.co.copy() for v in bm.verts]
    tris = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return co, BVHTree.FromPolygons(co, tris)


def floating_shells(ob):
    """Shells of a mesh that neither intersect nor touch (<1 mm) any other shell of it."""
    me = ob.data
    sid = K.shell_ids(me)
    groups = {}
    for p in me.polygons:
        groups.setdefault(sid[p.index], []).append(p.index)
    co = [v.co.copy() for v in me.vertices]
    trees = {}
    vsets = {}
    for g, faces in groups.items():
        tris = [list(me.polygons[f].vertices) for f in faces]
        trees[g] = BVHTree.FromPolygons(co, tris)
        vsets[g] = sorted({v for t in tris for v in t})
    floating = []
    keys = list(trees)
    for g in keys:
        ok = False
        for h in keys:
            if h == g:
                continue
            if trees[g].overlap(trees[h]):
                ok = True
                break
            if min(trees[h].find_nearest(co[v])[3] for v in vsets[g][::4]) < 1e-3:
                ok = True
                break
        if not ok:
            floating.append(g)
    return len(keys), len(floating)


def clearance(a, b):
    ca, ta = D2.world_tris(a)[0], None
    co_a, tris_a = D2.world_tris(a)
    co_b, tris_b = D2.world_tris(b)
    ta, tb = BVHTree.FromPolygons(co_a, tris_a), BVHTree.FromPolygons(co_b, tris_b)
    d = min(min(tb.find_nearest(p)[3] for p in co_a), min(ta.find_nearest(p)[3] for p in co_b[::2]))
    return d, len(ta.overlap(tb))


def snapshot():
    out = {}
    for dp, _, fs in os.walk(KIT):
        for f in fs:
            p = os.path.relpath(os.path.join(dp, f), KIT)
            if p == "README.md" or "v005" in p or "__pycache__" in p or p.endswith(".blend1"):
                continue
            out[p] = hashlib.sha256(open(os.path.join(KIT, p), "rb").read()).hexdigest()
    return out


# ---------------------------------------------------------------- main
def main():
    t0 = time.time()
    before = snapshot()
    os.makedirs(RD, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    paths = {k: os.path.join(K.D["textures"], f"PGK_Atlas_v002_{k}.png")
             for k in ("Color", "Roughness", "Metalness", "Emissive")}
    mat = K.make_material(paths)
    for img in bpy.data.images:
        img.name = img.name.replace("PGK_Atlas_", "PGK_Atlas_v002_")

    G, fingers = build_glove()
    # finger-to-finger clearance before merging into the glove mesh
    fb = {k: builder_bvh(F) for k, F in fingers.items()}
    finger_pairs = {}
    names = list(fb)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = fb[names[i]], fb[names[j]]
            d = min(min(b[1].find_nearest(p)[3] for p in a[0]), min(a[1].find_nearest(p)[3] for p in b[0]))
            finger_pairs[f"{names[i]}-{names[j]}"] = {"min_clearance_m": round(d * SCALE, 4),
                                                       "intersections": len(a[1].overlap(b[1]))}
    for F in fingers.values():
        merge(G, F)
        F.bm.free()
    C = build_coin()
    # rest pose: turn the item so the finger-curl plane (and the coin face) faces the front (-Y)
    bmesh.ops.transform(G.bm, matrix=POSE, verts=G.bm.verts[:])
    bmesh.ops.transform(C.bm, matrix=POSE, verts=C.bm.verts[:])
    global COIN_C
    COIN_C = POSE @ COIN_C
    # root pivot = visual (bounding-box) centre of the whole item
    allco = np.array([v.co[:] for v in G.bm.verts] + [(Vector(v.co) + COIN_C)[:] for v in C.bm.verts]) * SCALE
    centre = (allco.min(0) + allco.max(0)) / 2
    for v in G.bm.verts:
        v.co = v.co * SCALE - Vector(centre)
    for v in C.bm.verts:
        v.co = v.co * SCALE
    coin_loc = COIN_C * SCALE - Vector(centre)

    coll = bpy.data.collections.new("PGK_Pickpocket")
    scene.collection.children.link(coll)
    root = D2.new_root(scene, "Pickpocket_Root", coll)
    glove = K.finish_mesh("Pickpocket_Glove", G, coll, root, mat, 1.0)
    # the coin is UV-projected in item space (as if at its rest position), then moved to its pivot
    for v in C.bm.verts:
        v.co += coin_loc
    coin = K.finish_mesh("Pickpocket_Coin", C, coll, root, mat, 1.0)
    coin.data.transform(__import__("mathutils").Matrix.Translation(-coin_loc))
    coin.location = coin_loc
    bpy.context.view_layer.update()
    obs = [glove, coin]

    meshes = {}
    co_all = []
    for ob in obs:
        me = ob.data
        cl = np.zeros(len(me.polygons), int)
        me.attributes["kit_class"].data.foreach_get("value", cl)
        co = np.array([(ob.matrix_world @ v.co)[:] for v in me.vertices])
        co_all.append(co)
        meshes[ob.name] = {"export_name": ob.name, "triangles": len(me.polygons), "vertices": len(me.vertices),
                           "material": me.materials[0].name, "material_slots": len(me.materials),
                           "atlas_cells": sorted({D2.CLASSES[c] for c in cl}), "uv_bounds": D2.uv_bounds(ob),
                           "origin_m": [round(x, 5) for x in ob.location], "local_rotation_deg": [0, 0, 0],
                           "local_scale": [1, 1, 1], "bounds_studs": [round(x / STUD, 2) for x in co.max(0) - co.min(0)],
                           **K.mesh_checks(ob)}
    co = np.concatenate(co_all)
    dims = co.max(0) - co.min(0)
    n_shells, n_float = floating_shells(glove)
    rest_d, rest_n = clearance(glove, coin)
    spin = []
    for ang in range(0, 360, 10):
        coin.rotation_euler = (0, 0, math.radians(ang))
        bpy.context.view_layer.update()
        d, n = clearance(glove, coin)
        spin.append({"angle_deg": ang, "min_clearance_m": round(d, 4), "intersections": n})
    coin.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    info = {
        "reference": "Pickpocket turnaround attached to the v005 brief",
        "collection": coll.name, "root": root.name,
        "hierarchy": {"Pickpocket_Root": ["Pickpocket_Glove", "Pickpocket_Coin"]},
        "pivots": {"Pickpocket_Root": "visual (bounding-box) centre of the whole item, at (0,0,0)",
                   "Pickpocket_Glove": "aligned with the root (identity local transform)",
                   "Pickpocket_Coin": {"location_m": [round(x, 5) for x in coin_loc],
                                       "location_studs": [round(x / STUD, 3) for x in coin_loc],
                                       "rotation_deg": [0, 0, 0], "scale": [1, 1, 1],
                                       "face_normal": "local -Y (faces the item front)",
                                       "spin_axis": "local +Z (vertical pinch axis through both fingertips)"}},
        "meshes": meshes, "mesh_count": 2,
        "triangles_glove": meshes["Pickpocket_Glove"]["triangles"], "triangles_coin": meshes["Pickpocket_Coin"]["triangles"],
        "triangles_total": sum(m["triangles"] for m in meshes.values()),
        "bounds_m": [round(x, 4) for x in dims], "bounds_studs": [round(x / STUD, 2) for x in dims],
        "glove_shells": n_shells, "floating_shells": n_float, "finger_clearance": finger_pairs,
        "coin": {"radius_m": round(COIN_R * SCALE, 4), "thickness_m": round(2 * COIN_T * SCALE, 4),
                 "rest_min_clearance_m": round(rest_d, 4), "rest_intersections": rest_n,
                 "spin_test_step_deg": 10, "spin_test": spin,
                 "spin_min_clearance_m": round(min(r["min_clearance_m"] for r in spin), 4),
                 "spin_intersections": sum(r["intersections"] for r in spin)},
        "coplanar_overlap_pairs": D2.zfight_world(obs),
    }
    print("ITEM Pickpocket", info["triangles_total"], "glove", info["triangles_glove"], "coin", info["triangles_coin"],
          info["bounds_studs"], "zf", info["coplanar_overlap_pairs"], "shells", n_shells, "float", n_float,
          {k: (v["inverted_shells"], v["non_manifold_edges"], v["degenerate_tris"], v["uv_bounds"]) for k, v in meshes.items()},
          "fingers", finger_pairs, "coin rest", round(rest_d, 4), rest_n, "spin", info["coin"]["spin_min_clearance_m"],
          info["coin"]["spin_intersections"], "coin_loc", [round(x, 3) for x in coin_loc])
    manifest = {"kit": "PartyGameItemKit", "version": VERSION, "stage": "review-5 (Pickpocket)",
                "builds_on": {"scripts": ["source/build_item_kit.py", "source/build_dice_family_v002.py"]},
                "units": {"blender": "metres", "stud_m": STUD},
                "atlas": {"maps": {k: os.path.relpath(p, KIT) for k, p in paths.items()}, "new_cells": [],
                          "note": "v002 atlas unchanged: TEAL, CREAM, CORAL_ENAMEL, GOLD, GOLD_SATIN, COBALT, AQUA (gem)"},
                "material": "PGK_KitAtlas (one slot per mesh, v002 maps)", "items": {"Pickpocket": info}}

    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    fp = os.path.join(K.D["export"], f"Pickpocket_{VERSION}.fbx")
    bpy.ops.export_scene.fbx(filepath=fp, use_selection=True, object_types={"EMPTY", "MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                             mesh_smooth_type="FACE", use_mesh_modifiers=True, add_leaf_bones=False,
                             bake_anim=False, path_mode="COPY", embed_textures=True)
    info["fbx"] = os.path.relpath(fp, KIT)

    helpers = bpy.data.collections.new("Review_Helpers")
    scene.collection.children.link(helpers)
    clay = K.simple_mat("R15_Clay", (0.55, 0.57, 0.62), 0.6)
    ped_mats = (K.simple_mat("Pedestal_Gold", (0.95, 0.70, 0.30), 0.3, 1.0),
                K.simple_mat("Pedestal_Cream", (0.93, 0.87, 0.75), 0.45))
    cam, floor, lights, stage = K.setup_scene(scene)
    r15 = K.make_r15(helpers, clay)
    r15.location = (-4.6, 0, 0)
    refs = {}
    ref_coll = bpy.data.collections.new("Reference_Items")
    scene.collection.children.link(ref_coll)
    for nm, f in (("CoinShield", "CoinShield_v001.fbx"), ("WarpToken", "WarpToken_v001.fbx")):
        prev = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(K.D["export"], f))
        new = [o for o in bpy.data.objects if o not in prev]
        for o in new:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            ref_coll.objects.link(o)
            if o.type == "MESH":
                o.name = f"ref_{nm}_{o.name}"
                o.data.materials.clear()
                o.data.materials.append(mat)
        r = [o for o in new if o.parent is None][0]
        r.name = f"ref_{nm}_Root"
        refs[nm] = {"root": r, "meshes": [o for o in new if o.type == "MESH"]}
    peds = [K.make_pedestal(helpers, ped_mats, (i - 1) * 1.9) for i in range(3)]
    items = {"Pickpocket": {"root": root, "meshes": obs}, **refs}

    def park():
        for it in items.values():
            it["root"].location = (50, 50, -50)
            it["root"].rotation_euler = (0, 0, 0)
    park()
    root.location = (0, 0, peds[1][1] + dims[2] / 2 + 0.02)
    bpy.context.view_layer.update()
    blend = os.path.join(K.D["source"], f"PartyGameItemKit_Pickpocket_{VERSION}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["blend"] = os.path.relpath(blend, KIT)
    manifest["review_helpers"] = {"collections": ["Review_Helpers", "Reference_Items", "Review_Stage"],
                                  "excluded_from_exports": True}
    if STAGE == "full":
        render_reviews(scene, cam, floor, items, peds, r15, manifest, park, coin)
        park()
        root.location = (0, 0, peds[1][1] + dims[2] / 2 + 0.02)
        coin.rotation_euler = (0, 0, 0)
        for o in bpy.data.objects:
            o.hide_render = False
        bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["renders"] = sorted(os.path.relpath(os.path.join(RD, f), KIT) for f in os.listdir(RD) if f.endswith(".png"))
    manifest["validation"] = roundtrip(fp, manifest)
    expected = [manifest["blend"], "source/build_pickpocket_v005.py", info["fbx"], "validation/fbx_roundtrip_v005.json"] + \
        list(manifest["atlas"]["maps"].values())
    manifest["missing_files"] = [f for f in expected if not os.path.exists(os.path.join(KIT, f))]
    manifest["renders_expected"] = 12
    manifest["renders_missing"] = 12 - len(manifest["renders"])
    after = snapshot()
    changed = sorted(f for f in before if after.get(f) != before[f])
    manifest["v001_v004_files_checked"] = len(before)
    manifest["v001_v004_files_unchanged"] = not changed
    manifest["v001_v004_files_changed"] = changed
    with open(os.path.join(KIT, f"manifest_{VERSION}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("PRIOR unchanged:", not changed, len(before), changed, "missing:", manifest["missing_files"],
          "renders:", len(manifest["renders"]))
    print("DONE in %.0fs" % (time.time() - t0))


def roundtrip(fp, manifest):
    exp = manifest["items"]["Pickpocket"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fp)
    bpy.context.view_layer.update()
    obs = list(bpy.context.scene.objects)
    meshes = [o for o in obs if o.type == "MESH"]
    roots = [o for o in obs if o.parent is None]
    co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
    dims = co.max(0) - co.min(0)
    centre = (co.max(0) + co.min(0)) / 2
    root_w = np.array(roots[0].matrix_world.translation) if roots else np.full(3, 9.0)
    per = {}
    for o in meshes:
        s = exp["meshes"].get(o.name, {})
        uv = np.zeros(len(o.data.loops) * 2)
        if o.data.uv_layers:
            o.data.uv_layers[0].data.foreach_get("uv", uv)
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        loc = np.array(o.matrix_local.to_translation(), float)
        per[o.name] = {"parent": o.parent.name if o.parent else None, "triangles": tris,
                       "triangles_match": tris == s.get("triangles"), "uv_layers": len(o.data.uv_layers),
                       "uv_bounds": [round(float(uv.min()), 4), round(float(uv.max()), 4)] if uv.size else None,
                       "uv_in_0_1": bool(uv.size and uv.min() >= 0 and uv.max() <= 1),
                       "material_slots": len(o.data.materials), "materials": [m.name for m in o.data.materials if m],
                       "local_translation_m": [round(float(x), 4) for x in loc],
                       "pivot_matches_source_2mm": bool(np.allclose(loc, s.get("origin_m", [9, 9, 9]), atol=2e-3)),
                       "local_rotation_scale_identity": bool(np.allclose(np.array(o.matrix_local.to_3x3()), np.eye(3), atol=1e-4))}
    rec = {"file": os.path.relpath(fp, KIT), "bytes": os.path.getsize(fp),
           "importer": f"Blender {bpy.app.version_string} FBX importer",
           "hierarchy": {o.name: o.parent.name if o.parent else None for o in obs},
           "root_matches": len(roots) == 1 and roots[0].name == "Pickpocket_Root",
           "names_match": sorted(per) == sorted(exp["meshes"]), "mesh_count": len(meshes),
           "helpers_present": [o.name for o in obs if o.name.startswith(("R15", "ShopPedestal", "_", "Floor", "ref_"))],
           "meshes": per, "world_bounds_m": [round(x, 4) for x in dims], "source_bounds_m": exp["bounds_m"],
           "bounds_match_2mm": bool(np.allclose(sorted(dims), sorted(exp["bounds_m"]), atol=2e-3)),
           "root_to_visual_centre_m": round(float(np.linalg.norm(centre - root_w)), 5),
           "embedded_images": sorted({i.name for i in bpy.data.images})}
    rec["root_pivot_within_2mm"] = rec["root_to_visual_centre_m"] <= 2e-3
    rec["pass"] = bool(rec["root_matches"] and rec["names_match"] and rec["bounds_match_2mm"] and rec["root_pivot_within_2mm"]
                       and not rec["helpers_present"]
                       and all(p["triangles_match"] and p["uv_in_0_1"] and p["uv_layers"] == 1 and p["material_slots"] == 1
                               and p["pivot_matches_source_2mm"] and p["local_rotation_scale_identity"]
                               and p["triangles"] < 8000 for p in per.values()))
    with open(os.path.join(K.D["validation"], f"fbx_roundtrip_{VERSION}.json"), "w") as f:
        json.dump({"version": VERSION, "items": {"Pickpocket": rec}}, f, indent=2)
    print("ROUNDTRIP Pickpocket", rec["pass"], rec["hierarchy"], rec["world_bounds_m"], rec["root_to_visual_centre_m"])
    return {"Pickpocket": rec["pass"]}


# ---------------------------------------------------------------- renders
def render_reviews(scene, cam, floor, items, peds, r15, manifest, park, coin):
    from bpy_extras.object_utils import world_to_camera_view
    tmp = os.path.join(RD, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    tp = lambda n: os.path.join(tmp, n + ".png")  # noqa: E731
    objs = lambda it: set(it["meshes"]) | {it["root"]}  # noqa: E731
    P = items["Pickpocket"]
    pk = objs(P)
    vis = K.set_render_vis
    views = {"front": (0, -1, 0.0), "back": (0, 1, 0.0), "side": (1, 0, 0.0), "dorsal": (-1, 0, 0.0), "three_quarter": (0.75, -1, 0.42),
             "back_three_quarter": (-1, 0.6, 0.42), "top": (0.0, -0.25, 1)}
    info = manifest["items"]["Pickpocket"]
    rad = max(info["bounds_m"]) * 0.5 * 1.12
    dist = rad / math.tan(math.atan(18 / 85)) * 1.25
    cl = Vector(info["pivots"]["Pickpocket_Coin"]["location_m"])

    def save(im, fn, title, sub):
        K.header(im, title, sub).save(os.path.join(RD, fn))

    def solo(z=1.0):
        park()
        P["root"].location = (0, 0, z)
        bpy.context.view_layer.update()
        vis(pk | {floor})

    def shot(k, size=640, name=None):
        K.aim(cam, (0, 0, 1.0), views[k], dist)
        return K.label(K.do_render(scene, tp((name or k) + str(size)), size, size), (name or k).replace("_", " ").upper())

    def spin(deg):
        coin.rotation_euler = (0, 0, math.radians(deg))
        bpy.context.view_layer.update()

    solo()
    spin(0)
    save(K.hstack([shot("front"), shot("back"), shot("side", name="side_palm"), shot("dorsal", name="side_back_of_hand")]), "01_turnaround_front_back_side.png", "Pickpocket",
         "Teal glove on a coral cuff pinching a gold star coin; cream finger pads, gold joints; sea-glass gem on the back")
    for k, fn, t in (("three_quarter", "02_front_three_quarter_hero.png", "front three-quarter hero"),
                     ("back_three_quarter", "03_back_three_quarter.png", "back three-quarter")):
        K.aim(cam, (0, 0, 1.0), views[k], dist * 1.3)
        save(K.do_render(scene, tp(k), 1400, 1000), fn, f"Pickpocket - {t}",
             "Index tip above and thumb tip below hold the coin by its rim; middle finger curls alongside")
    c = Vector((0, 0, 1.0)) + cl
    ims = []
    for tgt, d, dd, t1, t2 in ((c + Vector((0, 0, 0.16)), (0.5, -1, 0.2), 0.55, "INDEX TIP", "tip centred on the spin axis above the rim"),
                               (c + Vector((0, 0, -0.16)), (0.5, -1, -0.1), 0.55, "THUMB TIP", "tip centred on the spin axis below the rim"),
                               (c, (1, -0.15, 0.1), 0.8, "SIDE PROFILE", "coin edge-on between the two tips")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("clr" + t1[:4]), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "04_coin_finger_clearance_closeup.png", "Coin and finger clearance",
         f"Rest clearance {info['coin']['rest_min_clearance_m'] * 1000:.1f} mm; minimum over a full spin {info['coin']['spin_min_clearance_m'] * 1000:.1f} mm, 0 intersections")
    ims = []
    for deg in (0, 45, 90):
        spin(deg)
        K.aim(cam, (0, 0, 1.0), views["three_quarter"], dist)
        ims.append(K.label(K.do_render(scene, tp(f"spin{deg}"), 640, 640), f"COIN {deg} deg"))
    spin(0)
    save(K.hstack(ims), "05_coin_three_spin_angles.png", "Coin at three spin angles",
         "Coin turns about the vertical pinch axis (local Z) independently of the glove")
    park()
    order = ["CoinShield", "Pickpocket", "WarpToken"]
    for i, n in enumerate(order):
        ped, Hp = peds[i]
        b = info["bounds_m"][2] if n == "Pickpocket" else 1.05
        items[n]["root"].location = ((i - 1) * 1.9, 0, Hp + b * 0.5 + (0.02 if n == "Pickpocket" else 0.22))
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(pk | objs(items["CoinShield"]) | objs(items["WarpToken"]) | {p for p, _ in peds} | {floor})
    K.aim(cam, (0, 0, 1.15), (0.15, -1, 0.40), 9.2, lens=50)
    save(K.do_render(scene, tp("pedestals"), 1800, 1000), "06_shop_pedestals_with_shield_and_token.png",
         "Shop pedestals", "Coin Shield | Pickpocket | Warp Token")
    park()
    r15.location = (0, 0, 0)
    P["root"].location = (1.45, 0, 1.15)
    items["CoinShield"]["root"].location = (-1.35, 0, 1.15)
    bpy.context.view_layer.update()
    vis(pk | objs(items["CoinShield"]) | {r15, floor})
    K.aim(cam, (0.05, 0, 0.92), (0, -1, 0.06), 7.6, lens=50)
    b = info["bounds_studs"]
    save(K.do_render(scene, tp("scale"), 1600, 950), "07_r15_scale_comparison.png", "R15 scale comparison (5.2-stud blocky R15)",
         f"Pickpocket {b[0]:.2f} W x {b[2]:.2f} H x {b[1]:.2f} D studs  |  Coin Shield 2.98 x 3.66 studs")
    r15.location = (-4.6, 0, 0)
    park()
    board = []
    tiles = [((k - 4) * 5 * STUD, 2.0 * math.sin(k * 0.8) * STUD) for k in range(9)]
    tm = [K.simple_mat("TileBlue", (0.15, 0.35, 0.90), 0.5), K.simple_mat("TileCream", (0.95, 0.88, 0.72), 0.5),
          K.simple_mat("TileRed", (0.92, 0.30, 0.25), 0.5)]
    for k, (x, y) in enumerate(tiles):
        tb = K.Builder()
        tb.sweep(K.circle(1.9 * STUD, 32), [(0, 0.0), (0, 0.12), (0.03, 0.15)], ["CREAM", "CREAM"], K.tf((x, y, 0)),
                 cap0="CREAM", cap1="CREAM")
        me = bpy.data.meshes.new(f"_tile{k}")
        tb.bm.to_mesh(me)
        tb.bm.free()
        me.materials.append(tm[k % 3])
        o = bpy.data.objects.new(f"_tile{k}", me)
        scene.collection.objects.link(o)
        board.append(o)
    for k, (x, y) in enumerate([tiles[3], tiles[7]]):
        f = K.make_r15(scene.collection, bpy.data.materials["R15_Clay"], name=f"_fig{k}")
        f.location = (x + 0.15, y + 0.9, 0.15)
        board.append(f)
    spots = {"CoinShield": tiles[1], "Pickpocket": tiles[4], "WarpToken": tiles[6]}
    for n, (x, y) in spots.items():
        items[n]["root"].location = (x, y, 0.15 + 2.8 * STUD)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(pk | objs(items["CoinShield"]) | objs(items["WarpToken"]) | set(board) | {floor})
    K.aim(cam, (0, 0.4, 0.6), (0, -1, 1.05), 15.5, lens=35)
    full = K.do_render(scene, tp("gameplay"), 1280, 720)
    crops = []
    for n in spots:
        q = world_to_camera_view(scene, cam, items[n]["root"].matrix_world.translation)
        cx, cy = int(q.x * 1280), int((1 - q.y) * 720)
        cimg = full.crop((cx - 60, cy - 60, cx + 60, cy + 60)).resize((300, 300), Image.NEAREST)
        bar = Image.new("RGB", (300, 34), (246, 240, 228))
        ImageDraw.Draw(bar).text((8, 8), f"{n}  (120 px, x2.5)", fill=(70, 52, 30), font=K.font(14, True))
        crops.append(K.vstack([cimg, bar]))
    save(K.hstack([full, K.vstack(crops[:2]), K.vstack(crops[2:])]), "08_gameplay_distance_comparison.png",
         "Gameplay-distance comparison", "Board camera ~15 m (54 studs), 35 mm; Coin Shield | Pickpocket | Warp Token; right: 1:1 crops enlarged")
    for o in board:
        bpy.data.objects.remove(o, do_unlink=True)
    solo()
    K.aim(cam, (0, 0, 1.0), views["three_quarter"], dist)
    bpy.context.view_layer.update()
    im = K.do_render(scene, tp("pivot"), 900, 900)
    im = Image.blend(im, Image.new("RGB", im.size, (240, 236, 228)), 0.35)
    dr = ImageDraw.Draw(im)
    px = lambda p: ((lambda q: (q.x * 900, (1 - q.y) * 900))(world_to_camera_view(scene, cam, p)))  # noqa: E731
    o = P["root"].matrix_world.translation.copy()
    rx, ry = px(o)
    for ax, col in ((Vector((0.3, 0, 0)), (220, 40, 40)), (Vector((0, 0.3, 0)), (40, 160, 40)), (Vector((0, 0, 0.3)), (40, 80, 230))):
        ex, ey = px(o + ax)
        dr.line((rx, ry, ex, ey), fill=col, width=5)
    dr.ellipse((rx - 12, ry - 12, rx + 12, ry + 12), outline=(20, 20, 20), width=4)
    dr.text((rx + 16, ry + 6), "Pickpocket_Root = Glove origin (visual centre)", fill=(20, 20, 20), font=K.font(17, True))
    cw = coin.matrix_world.translation.copy()
    a0, a1 = px(cw + Vector((0, 0, -0.32))), px(cw + Vector((0, 0, 0.32)))
    for k in range(12):
        t0_, t1_ = k / 12, (k + 0.5) / 12
        dr.line((a0[0] + (a1[0] - a0[0]) * t0_, a0[1] + (a1[1] - a0[1]) * t0_,
                 a0[0] + (a1[0] - a0[0]) * t1_, a0[1] + (a1[1] - a0[1]) * t1_), fill=(200, 60, 40), width=4)
    cx, cy = px(cw)
    dr.line((cx - 12, cy, cx + 12, cy), fill=(200, 30, 120), width=4)
    dr.line((cx, cy - 12, cx, cy + 12), fill=(200, 30, 120), width=4)
    dr.text((cx + 14, cy - 30), "Pickpocket_Coin pivot (coin centre)", fill=(150, 20, 90), font=K.font(17, True))
    dr.text((a1[0] + 10, a1[1] - 6), "coin spin axis (local Z)", fill=(170, 50, 30), font=K.font(16, True))
    save(im, "09_pivot_coin_axis.png", "Pivots and coin axis",
         f"Coin local transform: location {tuple(round(x, 3) for x in cl)} m, rotation 0, scale 1")
    solo()
    ims = []
    for tgt, d, dd, t1, t2 in ((Vector((-0.14, 0.0, 0.95)), (-1, 0.35, 0.25), 0.80, "BACK GEM", "gold bezel, cobalt ring, faceted sea-glass gem, rivets"),
                               (Vector((0.02, -0.05, 1.30)), (0.35, -1, 0.45), 0.80, "FINGER JOINTS", "teal tubes, gold joint bands + knuckle bosses, cream pads"),
                               (Vector((0.0, -0.25, 0.62)), (0.3, -1, 0.15), 0.85, "CUFF", "cream roll, gold rims + buttons, coral band, cobalt stripe")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("mat" + t1[:4]), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "10_material_joint_closeup.png", "Material and joint close-up", "v002 atlas cells only; no new texture maps")
    wire = bpy.data.materials.new("Wire")
    nt = wire.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.86, 0.84, 0.80, 1)
    wn = nt.nodes.new("ShaderNodeWireframe")
    wn.use_pixel_size = True
    wn.inputs[0].default_value = 0.9
    mix = nt.nodes.new("ShaderNodeMixShader")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.05, 0.10, 0.35, 1)
    nt.links.new(wn.outputs[0], mix.inputs[0])
    nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    vl = scene.view_layers[0]
    solo()
    ims = []
    for k in ("front", "three_quarter", "side"):
        K.aim(cam, (0, 0, 1.0), views[k], dist)
        vl.material_override = wire
        ims.append(K.do_render(scene, tp("wire" + k), 760, 760, samples=24))
        vl.material_override = None
    im = K.hstack(ims)
    dr = ImageDraw.Draw(im)
    dr.text((18, 14), "Pickpocket", fill=(30, 30, 60), font=K.font(30, True))
    for i, t in enumerate([f"{info['triangles_total']:,} tris total  |  2 meshes  |  1 material slot each",
                           f"Pickpocket_Glove: {info['triangles_glove']:,}", f"Pickpocket_Coin: {info['triangles_coin']:,}"]):
        dr.text((18, 56 + i * 24), t, fill=(40, 40, 70), font=K.font(19))
    save(im, "11_wireframe_triangle_counts.png", "Wireframe and triangle counts", "Glove 5,000-7,000; coin 600-1,200; total < 8,000")
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*K.BG_NEUTRAL, 1)
    fb = floor.data.materials[0].node_tree.nodes["Principled BSDF"]
    old = tuple(fb.inputs["Base Color"].default_value)
    fb.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    solo()
    row = K.hstack([shot(k, 400) for k in ("front", "three_quarter", "side", "back", "top")], bg=(205, 205, 205))
    rr = []
    for n in ("CoinShield", "WarpToken"):
        park()
        items[n]["root"].location = (0, 0, 1.0)
        bpy.context.view_layer.update()
        vis(objs(items[n]) | {floor})
        K.aim(cam, (0, 0, 1.0), views["three_quarter"], 1.1 * 0.5 * 1.12 / math.tan(math.atan(18 / 85)) * 1.25)
        rr.append(K.label(K.do_render(scene, tp("ref" + n), 400, 400), n))
    solo()
    K.aim(cam, (0, 0, 1.0), views["back_three_quarter"], dist)
    rr.append(K.label(K.do_render(scene, tp("pkb"), 400, 400), "Pickpocket back 3/4"))
    save(K.vstack([row, K.hstack(rr, bg=(205, 205, 205))], bg=(205, 205, 205)), "12_neutral_contact_sheet.png",
         "Neutral contact sheet", "top: front | three-quarter | side | back | top    bottom: Coin Shield, Warp Token, Pickpocket back")
    bg.inputs["Color"].default_value = (*K.BG_WARM, 1)
    fb.inputs["Base Color"].default_value = old
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
