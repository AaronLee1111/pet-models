"""Party Game Item Kit -- review stage 2: the dice family (Double Dice, Triple Dice, Lucky Die).

Builds ON TOP of build_item_kit.py (v001), which is imported as a library and never re-run:
the v001 Party Dice Block / Coin Shield / Warp Token sources, exports, atlas maps, manifest,
round-trip report and renders are left byte-identical (checked at the end of this build).

Run with the `bpy` module (pip install bpy) or Blender:
    python3 PartyGameItemKit/source/build_dice_family_v002.py
    KIT_STAGE=geo python3 ...        # geometry + atlas + exports + validation, no renders

Outputs (relative to PartyGameItemKit/)
    source/PartyGameItemKit_DiceFamily_v002.blend
    export/DoubleDice_v002.fbx, TripleDice_v002.fbx, LuckyDie_v002.fbx
    textures/PGK_Atlas_v002_{Color,Roughness,Metalness,Emissive,Legend}.png
    manifest_v002.json, validation/fbx_roundtrip_v002.json, renders/v002_dice_family/*.png
"""
import hashlib
import json
import math
import os
import sys
import time

import bpy  # noqa: must precede bmesh when using the pip bpy module
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_item_kit as K  # noqa: E402  (v001 library: outlines, sweeps, atlas cells, render helpers)

VERSION = "v002"
KIT = K.KIT
STUD = K.STUD
STAGE = os.environ.get("KIT_STAGE", "full")
RD = os.path.join(K.D["renders"], "v002_dice_family")
os.makedirs(RD, exist_ok=True)

# ---------------------------------------------------------------- atlas v002
# Cells 0-11 and EMERALD (13) are regenerated with the v001 code + seeds -> byte-identical.
# The v001 reserved row is now spent on the dice family:
#   12 RUBY -> CORAL_ENAMEL, 13 EMERALD (kept), 14 SUN -> MINT gem, 15 ROSE -> GOLD_GLOW.
# v001 items never used row 3, so the v002 atlas is a drop-in superset for them.
V1_CLASSES = list(K.CLASSES)
CLASSES = V1_CLASSES[:12] + ["CORAL_ENAMEL", "EMERALD", "MINT", "GOLD_GLOW"]
K.CLASSES[:] = CLASSES
K.CID.clear()
K.CID.update({c: i for i, c in enumerate(CLASSES)})


def make_cell_v2(name, i):
    if i < 12 or name == "EMERALD":
        return K.make_cell(name, i)
    n1, n2 = K.noise(10 + i), K.noise(50 + i, scales=((24, 0.6), (70, 0.4)))
    one = np.ones((K.CELL, K.CELL))

    def mix(c0, c1, m):
        c0 = np.array(c0)
        return c0 + (np.array(c1) - c0) * m[..., None]
    if name == "CORAL_ENAMEL":      # same recipe as the v001 enamel cells
        m = np.clip(K.smooth(0.35, 0.85, n1) * 0.75 + 0.25 * n2, 0, 1)
        c = mix((0.88, 0.26, 0.14), (1.0, 0.50, 0.32), m)
        return c, 0.16 + 0.10 * (1 - n2), 0 * one, 0 * one
    if name == "MINT":              # faceted gem, like AQUA but green
        c = mix((0.24, 0.86, 0.56), (0.66, 1.0, 0.80), n1)
        return c, 0.06 + 0.04 * n2, 0 * one, 0.40 + 0.10 * n1
    if name == "GOLD_GLOW":         # warm gold that carries the Lucky Die's restrained glow
        c = mix((1.0, 0.76, 0.32), (1.0, 0.88, 0.52), n1 * 0.6 + n2 * 0.4)
        return c, 0.20 + 0.06 * n2, one, 0.35 * one
    raise KeyError(name)


def make_atlas_v2():
    T, C = K.TEX, K.CELL
    maps = {"Color": np.zeros((T, T, 3)), "Roughness": np.zeros((T, T)),
            "Metalness": np.zeros((T, T)), "Emissive": np.zeros((T, T))}
    for i, name in enumerate(CLASSES):
        r0, c0 = (i // 4) * C, (i % 4) * C
        c, ro, me, em = make_cell_v2(name, i)
        maps["Color"][r0:r0 + C, c0:c0 + C] = np.clip(c, 0, 1)
        maps["Roughness"][r0:r0 + C, c0:c0 + C] = np.clip(ro, 0, 1)
        maps["Metalness"][r0:r0 + C, c0:c0 + C] = np.clip(me, 0, 1)
        maps["Emissive"][r0:r0 + C, c0:c0 + C] = np.clip(em, 0, 1)
    paths = {}
    for k, a in maps.items():
        p = os.path.join(K.D["textures"], f"PGK_Atlas_{VERSION}_{k}.png")
        Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(p)
        paths[k] = p
    leg = Image.open(paths["Color"]).convert("RGB")
    dr = ImageDraw.Draw(leg)
    f = K.font(20)
    for i, name in enumerate(CLASSES):
        x, y = (i % 4) * C + 8, (i // 4) * C + 6
        dr.rectangle((x - 4, y - 2, x + 12 * len(name) + 8, y + 24), fill=(20, 20, 30))
        dr.text((x, y), name + (" *" if i >= 12 and name != "EMERALD" else ""), fill=(255, 255, 255), font=f)
    leg.save(os.path.join(K.D["textures"], f"PGK_Atlas_{VERSION}_Legend.png"))
    return paths


def atlas_consistency(paths):
    """Cells v001 items depend on must be pixel-identical between the v001 and v002 atlases."""
    out = {}
    C = K.CELL
    for k in ("Color", "Roughness", "Metalness", "Emissive"):
        a = np.asarray(Image.open(os.path.join(K.D["textures"], f"PGK_Atlas_{k}.png")))
        b = np.asarray(Image.open(paths[k]))
        same = []
        for i in list(range(12)) + [13]:
            r0, c0 = (i // 4) * C, (i % 4) * C
            same.append(bool(np.array_equal(a[r0:r0 + C, c0:c0 + C], b[r0:r0 + C, c0:c0 + C])))
        out[k] = {"size": list(b.shape[:2]), "v001_cells_identical": all(same)}
    return out


# ---------------------------------------------------------------- family die (optimised v001 die)
DIE_S, DIE_BEV = K.DIE_S, K.DIE_BEV


def pip_v2(B, M, r, seg, dome_h=0.85, z0=-0.006, cls="PEARL"):
    rd = r - 0.018
    prof = [(0, z0), (0, 0.034), (0.009, 0.042), (0.018, 0.035)]
    cl = ["GOLD", "GOLD", "GOLD_SATIN"]
    for a in (42, 74):
        th = math.radians(a)
        prof.append((0.018 + rd * (1 - math.cos(th)), 0.034 + rd * dome_h * math.sin(th)))
        cl.append(cls)
    B.sweep(K.circle(r, seg), prof, cl, M, cap0="GOLD", cap1=cls)


def build_family_die(enamel="COBALT", star_cls="TEAL", edge_gem="CORAL", lucky=False, pip_seg=10):
    """Same construction as the v001 Party Dice Block (bevelled gold cube, gold bezel, cream rim,
    inset enamel, pearl pips in gold bezels, star under centre pips, edge gems, corner accents),
    with fewer segments on the repeated parts.  `lucky` adds the premium frame + fortune motif."""
    B = K.Builder()
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=DIE_S)
    bmesh.ops.bevel(tmp, geom=tmp.verts[:] + tmp.edges[:], offset=DIE_BEV, segments=3,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    B.append(tmp, "GOLD")
    tmp.free()
    h = DIE_S / 2
    bez = K.rrect(0.37, 0.37, 0.10, 3)
    if lucky:   # stronger, taller warm-gold frame
        bez_prof = [(0, -0.03), (0, 0.034), (0.016, 0.058), (0.050, 0.058), (0.068, 0.036), (0.068, -0.03)]
        base = 0.063
    else:       # v001 bezel profile
        bez_prof = [(0, -0.03), (0, 0.028), (0.014, 0.046), (0.040, 0.046), (0.055, 0.03), (0.055, -0.03)]
        base = 0.05
    for n, up, val in K.DIE_FACES:
        M = K.frame(Vector(n) * h, n, up)
        B.sweep(bez, bez_prof, ["GOLD"] * 6, M, closed=True)
        B.sweep(bez, [(base, -0.02), (base, 0.010), (base + 0.006, 0.018)], ["GOLD_SATIN", enamel], M,
                cap0=enamel, cap1=enamel)
        B.sweep(bez, [(base, 0.0), (base, 0.026), (base + 0.018, 0.035), (base + 0.046, 0.024),
                      (base + 0.046, 0.0)], ["CREAM"] * 5, M, closed=True)
        g = 0.165
        for px, py in K.PIP_LAYOUT[val]:
            Mp = M @ K.tf((px * g, py * g, 0))
            centre = (px, py) == (0, 0)
            if centre:
                ro = 0.16 if val == 1 else 0.125
                B.sweep(K.star(4, ro, 0.05), [(0, 0.0), (0, 0.024), (0.008, 0.031)], ["GOLD", "GOLD"], Mp,
                        cap0="GOLD", cap1=star_cls)
            big = centre and val == 1
            pip_v2(B, Mp, 0.10 if big else 0.068, 14 if big else pip_seg, dome_h=0.62 if big else 0.85)
        if lucky:
            # fortune medallion set into the bottom of the frame: gold coin with a four-leaf motif
            Mm = M @ K.tf((0, -0.292, 0))
            B.sweep(K.circle(0.070, 12), [(0, 0.0), (0, 0.050), (0.010, 0.062)], ["GOLD", "GOLD"], Mm,
                    cap0="GOLD", cap1="GOLD_GLOW")
            for k in range(4):
                a = math.radians(45 + 90 * k)
                Ml = Mm @ K.tf((0.034 * math.cos(a), 0.034 * math.sin(a), 0))
                B.sweep(K.circle(0.023, 7), [(0, 0.052), (0, 0.072), (0.005, 0.077)], ["GOLD", "GOLD"], Ml,
                        cap0="GOLD", cap1="EMERALD")
            # glowing gold flourishes sweeping out of the medallion along the cream rim
            for sx in (-1, 1):
                Mf = M @ K.tf((sx * 0.145, -0.287, 0)) @ K.R("Z", sx * -4)
                B.sweep(K.rrect(0.058, 0.0085, 0.006, 1), [(0, 0.018), (0, 0.042), (0.003, 0.046)],
                        ["GOLD", "GOLD"], Mf, cap0="GOLD", cap1="GOLD_GLOW")
    axes = [Vector(a) for a in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]
    for i in range(3):
        for j in range(i + 1, 3):
            for si in (-1, 1):
                for sj in (-1, 1):
                    n1, n2 = axes[i] * si, axes[j] * sj
                    b = (n1 + n2).normalized()
                    p = (n1 + n2) * (h - DIE_BEV) + b * DIE_BEV
                    M = K.frame(p, b, n1.cross(n2).cross(b))
                    K.gem_setting(B, M, 0.095, 0.058, edge_gem, h0=-0.035, h1=0.035)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                dvec = Vector((sx, sy, sz))
                p = dvec * (h - DIE_BEV) + dvec.normalized() * DIE_BEV
                M = K.frame(p, dvec, (1, 0, 0))
                if lucky:   # faceted mint corner gems replace the cream caps
                    K.gem_setting(B, M, 0.066, 0.066, "MINT", h0=-0.03, h1=0.03)
                else:
                    prof = [(0, -0.03), (0, 0.0)]
                    for a in (40, 78):
                        t = math.radians(a)
                        prof.append((0.062 * (1 - math.cos(t)), 0.040 * math.sin(t)))
                    B.sweep(K.circle(0.062, 10), prof, ["CREAM"] * 3, M, cap0="CREAM", cap1="CREAM")
    return B


# ---------------------------------------------------------------- connectors
def tube_arc(centre, u, v, radius, a0, a1, rw, rb, n=28, ring=8):
    """Closed tapered gold tube following a circular arc (angles in degrees) in the plane (u, v)."""
    bm = bmesh.new()
    C, U, Vv = Vector(centre), Vector(u), Vector(v)
    W = U.cross(Vv).normalized()
    rings = []
    for k in range(n + 1):
        t = k / n
        a = math.radians(a0 + (a1 - a0) * t)
        Nn = U * math.cos(a) + Vv * math.sin(a)
        p = C + Nn * radius
        taper = max(0.18, min(1.0, 5 * t, 5 * (1 - t))) ** 0.7
        rings.append([bm.verts.new(p + Nn * (rw * taper * math.cos(2 * math.pi * j / ring)) +
                                   W * (rb * taper * math.sin(2 * math.pi * j / ring))) for j in range(ring)])
    for k in range(n):
        for j in range(ring):
            jj = (j + 1) % ring
            bm.faces.new((rings[k][j], rings[k][jj], rings[k + 1][jj], rings[k + 1][j]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def arc_point(centre, u, v, radius, a):
    a = math.radians(a)
    return Vector(centre) + (Vector(u) * math.cos(a) + Vector(v) * math.sin(a)) * radius


def node_gem(B, p, gem, a=0.07, b=0.045):
    """Gem in a gold diamond setting, mounted on the connector, visible from front and back."""
    for z in ((0, -1, 0), (0, 1, 0)):
        K.gem_setting(B, K.frame(p, z, (0, 0, 1)), a, b, gem, h0=-0.012, h1=0.03)


DOUBLE = {"scale": 0.62, "dies": [
    # name, enamel, star, centre (m, root space), rest rotation (deg, applied XYZ-intrinsic as Rz@Rx@Rface)
    ("Die_A", "COBALT", "TEAL", (-0.25, 0.34, 0.25), {"z": 12, "x": -6, "face": 0}),
    ("Die_B", "TEAL", "COBALT", (0.25, -0.34, -0.25), {"z": -14, "x": 6, "face": -90})]}
TRIPLE = {"scale": 0.58, "dies": [
    ("Die_A", "COBALT", "TEAL", (0.0, 0.03, 0.50), {"z": 0, "x": -8, "face": 0}),
    ("Die_B", "CORAL_ENAMEL", "TEAL", (-0.38, 0.0, -0.25), {"z": 8, "x": -4, "face": -90}),
    ("Die_C", "TEAL", "COBALT", (0.38, 0.0, -0.25), {"z": -8, "x": -4, "face": 90})]}
LUCKY_SCALE = 0.90


def rest_matrix(r):
    return (Matrix.Rotation(math.radians(r["z"]), 3, "Z") @ Matrix.Rotation(math.radians(r["x"]), 3, "X")
            @ Matrix.Rotation(math.radians(r["face"]), 3, "Z"))


def free_runs(dice, c, u, v, radius, windows, margin=0.05):
    """Largest arc span inside each angular window whose points keep `margin` clearance from every die."""
    trees = []
    for ob in dice:
        co, tris = world_tris(ob)
        trees.append(BVHTree.FromPolygons(co, tris))

    def free(a):
        p = arc_point(c, u, v, radius, a)
        for t in trees:
            if t.find_nearest(p)[3] < margin:
                return False
            hit = t.ray_cast(p, Vector((0.577, 0.577, 0.577)))
            if hit[0] is not None and hit[1].dot(Vector((0.577, 0.577, 0.577))) > 0:
                return False   # inside a die
        return True
    out = []
    for w0, w1 in windows:
        angs = np.arange(w0, w1 + 0.01, 1.0)
        ok = [free(a) for a in angs]
        best, cur = (0, -1), None
        for i, f in enumerate(ok):
            if f and cur is None:
                cur = i
            if (not f or i == len(ok) - 1) and cur is not None:
                end = i if f else i - 1
                if end - cur > best[1] - best[0]:
                    best = (cur, end)
                cur = None
        a0, a1 = angs[best[0]] + 2, angs[best[1]] - 2
        out.append((float(a0), float(a1)))
    return out


def double_connector(dice):
    B = K.Builder()
    c, u, v = (0, 0, 0), (1, 0, 0), (0, 0, 1)
    for a0, a1 in free_runs(dice, c, u, v, 0.52, [(-10, 75), (170, 255)], margin=0.06):
        B.append(tube_arc(c, u, v, 0.52, a0, a1, 0.030, 0.024), "GOLD")
        node_gem(B, arc_point(c, u, v, 0.52, (a0 + a1) / 2), "AQUA")
    return B


def triple_connector(dice):
    B = K.Builder()
    c, u, v = (0, 0.40, 0), (1, 0, 0), (0, 0, 1)   # ring plane just behind the dice
    R = 0.47
    for a0, a1 in free_runs(dice, c, u, v, R, [(-33, 90), (90, 213), (213, 327)], margin=0.055):
        B.append(tube_arc(c, u, v, R, a0, a1, 0.026, 0.022), "GOLD")
        node_gem(B, arc_point(c, u, v, R, (a0 + a1) / 2), "CORAL", a=0.075, b=0.05)
    # central pearl node in a teal-and-gold star bezel, tied to the top die by a short gold bar
    Mf = K.frame((0, 0.40, 0), (0, -1, 0), (0, 0, 1))
    B.sweep(K.star(4, 0.095, 0.036), [(0, -0.03), (0, 0.022), (0.009, 0.032)], ["GOLD", "GOLD"], Mf,
            cap0="GOLD", cap1="TEAL")
    pip_v2(B, Mf @ K.tf((0, 0, 0.0)), 0.05, 14, dome_h=0.9, z0=0.012)
    # one bar up to the top of the ring (no three-spoke layout: that would read as a car logo)
    Mb = K.frame((0, 0.40, 0.27), (0, -1, 0), (0, 0, 1))
    B.sweep(K.rrect(0.016, 0.17, 0.010, 2), [(0, -0.018), (0, 0.016), (0.006, 0.022)], ["GOLD", "GOLD"], Mb,
            cap0="GOLD", cap1="GOLD")
    return B


# ---------------------------------------------------------------- assembly
def new_root(scene, name, coll):
    root = bpy.data.objects.new(name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.3
    coll.objects.link(root)
    return root


def build_assembly(scene, mat, name, spec, connector_fn, connector_name):
    coll = bpy.data.collections.new(f"PGK_{name}")
    scene.collection.children.link(coll)
    root = new_root(scene, f"{name}_Root", coll)
    meshes, pivots = [], {}
    for dname, enamel, star_cls, centre, rest in spec["dies"]:
        B = build_family_die(enamel, star_cls)
        bmesh.ops.rotate(B.bm, cent=(0, 0, 0), matrix=rest_matrix(rest), verts=B.bm.verts[:])
        ob = K.finish_mesh(f"{name}_{dname}", B, coll, root, mat, spec["scale"])
        ob.location = centre
        meshes.append(ob)
        pivots[dname] = {"location_m": list(centre), "location_studs": [round(x / STUD, 3) for x in centre],
                         "rest_rotation_deg": rest, "enamel": enamel,
                         "note": "object origin = die centre; rotation and scale applied to the mesh"}
    bpy.context.view_layer.update()
    con = K.finish_mesh(f"{name}_{connector_name}", connector_fn(meshes), coll, root, mat, 1.0)
    meshes.append(con)
    return {"root": root, "meshes": meshes, "coll": coll, "pivots": pivots,
            "export_names": {m.name: m.name[len(name) + 1:] for m in meshes}}


def build_lucky(scene, mat):
    coll = bpy.data.collections.new("PGK_LuckyDie")
    scene.collection.children.link(coll)
    root = new_root(scene, "LuckyDie_Root", coll)
    B = build_family_die("EMERALD", "MINT", "MINT", lucky=True, pip_seg=9)
    ob = K.finish_mesh("LuckyDie_Die", B, coll, root, mat, LUCKY_SCALE)
    return {"root": root, "meshes": [ob], "coll": coll,
            "pivots": {"Die": {"location_m": [0, 0, 0], "location_studs": [0, 0, 0],
                               "rest_rotation_deg": {"z": 0, "x": 0, "face": 0}, "enamel": "EMERALD",
                               "note": "single die, pivot at its centre (same as Party Dice Block)"}},
            "export_names": {"LuckyDie_Die": "LuckyDie"}}


# ---------------------------------------------------------------- validation helpers
def world_tris(ob):
    me = ob.data
    mw = ob.matrix_world
    co = [mw @ v.co for v in me.vertices]
    return co, [tuple(p.vertices) for p in me.polygons]


def zfight_world(obs):
    cents, norms, owner = [], [], []
    for oi, ob in enumerate(obs):
        sid = K.shell_ids(ob.data)
        mw = ob.matrix_world
        n3 = mw.to_3x3().inverted().transposed()
        for p in ob.data.polygons:
            cents.append(mw @ p.center)
            norms.append((n3 @ p.normal).normalized())
            owner.append((oi, sid[p.index]))
    kd = KDTree(len(cents))
    for i, c in enumerate(cents):
        kd.insert(c, i)
    kd.balance()
    hits = 0
    for i, c in enumerate(cents):
        for co, j, dist in kd.find_range(c, 0.004):
            if j > i and owner[i] != owner[j] and norms[i].dot(norms[j]) > 0.999 \
                    and abs((cents[j] - c).dot(norms[i])) < 2e-4:
                hits += 1
    return hits


def mesh_intersections(obs):
    """Triangle-pair intersections between DIFFERENT production meshes (dice must stay separable)."""
    trees = {}
    for ob in obs:
        co, tris = world_tris(ob)
        trees[ob.name] = BVHTree.FromPolygons(co, tris)
    out = {}
    names = list(trees)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            out[f"{names[i]} x {names[j]}"] = len(trees[names[i]].overlap(trees[names[j]]))
    return out


def min_gap(obs):
    """Smallest vertex-to-surface distance between different meshes (clearance for separate/reunite)."""
    trees = {}
    for ob in obs:
        co, tris = world_tris(ob)
        trees[ob.name] = (co, BVHTree.FromPolygons(co, tris))
    out = {}
    for a in trees:
        for b in trees:
            if a >= b:
                continue
            d = min(trees[b][1].find_nearest(p)[3] for p in trees[a][0][::3])
            out[f"{a} - {b}"] = round(d, 4)
    return out


def uv_bounds(ob):
    uv = np.zeros(len(ob.data.loops) * 2)
    ob.data.uv_layers[0].data.foreach_get("uv", uv)
    return [round(float(uv.min()), 4), round(float(uv.max()), 4)]


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


V001_FILES = ["source/build_item_kit.py", "source/PartyGameItemKit_v001.blend", "manifest.json",
              "validation/fbx_roundtrip.json", "README.md",
              "export/PartyDiceBlock_v001.fbx", "export/CoinShield_v001.fbx", "export/WarpToken_v001.fbx"] + \
    [f"textures/PGK_Atlas_{k}.png" for k in ("Color", "Roughness", "Metalness", "Emissive", "Legend")] + \
    [f"renders/{f}" for f in sorted(os.listdir(K.D["renders"])) if f.endswith(".png")]


# ---------------------------------------------------------------- main
def main():
    t0 = time.time()
    v1_hash = {f: sha(os.path.join(KIT, f)) for f in V001_FILES if f != "README.md"}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    paths = make_atlas_v2()
    mat = K.make_material(paths)
    for img in bpy.data.images:
        img.name = img.name.replace("PGK_Atlas_", f"PGK_Atlas_{VERSION}_")

    items = {
        "DoubleDice": build_assembly(scene, mat, "DoubleDice", DOUBLE, double_connector, "Connector"),
        "TripleDice": build_assembly(scene, mat, "TripleDice", TRIPLE, triple_connector, "Connectors"),
        "LuckyDie": build_lucky(scene, mat),
    }
    bpy.context.view_layer.update()

    manifest = {"kit": "PartyGameItemKit", "version": VERSION, "stage": "review-2 (dice family)",
                "builds_on": {"script": "source/build_item_kit.py", "manifest": "manifest.json"},
                "units": {"blender": "metres", "stud_m": STUD},
                "atlas": {"size": K.TEX, "cell_px": K.CELL, "gutter_px": K.GUTTER,
                          "projection_half_extent_m": K.PROJ_R,
                          "texel_density_px_per_m": round(K.TEXEL_DENSITY, 1),
                          "texel_density_px_per_stud": round(K.TEXEL_DENSITY * STUD, 1),
                          "cells": {c: {"index": i, "col": i % 4, "row": i // 4,
                                        "projection": "front" if c in K.FRONT_PROJ else "box",
                                        "new_in_v002": i >= 12 and c != "EMERALD"} for i, c in enumerate(CLASSES)},
                          "maps": {k: os.path.relpath(p, KIT) for k, p in paths.items()},
                          "consistency": atlas_consistency(paths)},
                "material": "PGK_KitAtlas (one material per mesh, v002 atlas maps)",
                "family_die": {"construction": "v001 Party Dice Block recipe",
                               "optimisation": "bevel 3 segs, bezel/rim corners 3 segs, pips 10 segs (centre-1 pip 14), corner caps 10 segs",
                               "v001_party_dice_tris": 7860},
                "items": {}}
    for name, it in items.items():
        info = {"collection": it["coll"].name, "root": it["root"].name, "pivots": it["pivots"],
                "export_names": it["export_names"], "meshes": {}}
        allco = []
        for ob in it["meshes"]:
            me = ob.data
            cls = np.zeros(len(me.polygons), int)
            me.attributes["kit_class"].data.foreach_get("value", cls)
            co = np.array([(ob.matrix_world @ v.co)[:] for v in me.vertices])
            allco.append(co)
            lo, hi = co.min(0), co.max(0)
            info["meshes"][ob.name] = {
                "export_name": it["export_names"][ob.name], "triangles": len(me.polygons),
                "vertices": len(me.vertices), "material": me.materials[0].name, "material_slots": len(me.materials),
                "atlas_cells": sorted({CLASSES[c] for c in cls}), "uv_bounds": uv_bounds(ob),
                "origin_m": [round(x, 4) for x in ob.location],
                "local_rotation_deg": [round(math.degrees(a), 3) for a in ob.rotation_euler],
                "local_scale": [round(s, 4) for s in ob.scale],
                "bounds_studs": [round(x / STUD, 2) for x in (hi - lo)], **K.mesh_checks(ob)}
        co = np.concatenate(allco)
        dims = co.max(0) - co.min(0)
        info.update({"triangles_total": sum(m["triangles"] for m in info["meshes"].values()),
                     "mesh_count": len(it["meshes"]),
                     "max_triangles_per_mesh": max(m["triangles"] for m in info["meshes"].values()),
                     "bounds_m": [round(x, 4) for x in dims], "bounds_studs": [round(x / STUD, 2) for x in dims],
                     "bbox_centre_offset_from_root_m": [round(x, 4) for x in (co.min(0) + co.max(0)) / 2],
                     "coplanar_overlap_pairs": zfight_world(it["meshes"]),
                     "mesh_intersections": mesh_intersections(it["meshes"]) if len(it["meshes"]) > 1 else {},
                     "min_clearance_m": min_gap(it["meshes"]) if len(it["meshes"]) > 1 else {}})
        manifest["items"][name] = info
        print("ITEM", name, info["triangles_total"], info["bounds_studs"],
              {m["export_name"]: m["triangles"] for m in info["meshes"].values()},
              "zf", info["coplanar_overlap_pairs"], "isect", sum(info["mesh_intersections"].values()),
              "inv", sum(m["inverted_shells"] for m in info["meshes"].values()),
              "open", sum(m["non_manifold_edges"] for m in info["meshes"].values()),
              "clear", info["min_clearance_m"])

    # ------------------------------------------------ export (roots at origin, export names applied)
    exports = {}
    for name, it in items.items():
        root = it["root"]
        root.location, root.rotation_euler = (0, 0, 0), (0, 0, 0)
        bpy.context.view_layer.update()
        orig = {ob: ob.name for ob in it["meshes"]}
        for ob in it["meshes"]:
            ob.name = it["export_names"][orig[ob]]
        bpy.ops.object.select_all(action="DESELECT")
        for ob in [root] + it["meshes"]:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = root
        fp = os.path.join(K.D["export"], f"{name}_{VERSION}.fbx")
        bpy.ops.export_scene.fbx(
            filepath=fp, use_selection=True, object_types={"EMPTY", "MESH"},
            apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
            mesh_smooth_type="FACE", use_mesh_modifiers=True, add_leaf_bones=False,
            bake_anim=False, path_mode="COPY", embed_textures=True)
        for ob in it["meshes"]:
            ob.name = orig[ob]
        exports[name] = fp
        manifest["items"][name]["fbx"] = os.path.relpath(fp, KIT)

    # ------------------------------------------------ review helpers + layout
    helpers = bpy.data.collections.new("Review_Helpers")
    scene.collection.children.link(helpers)
    clay = K.simple_mat("R15_Clay", (0.55, 0.57, 0.62), 0.6)
    ped_mats = (K.simple_mat("Pedestal_Gold", (0.95, 0.70, 0.30), 0.3, 1.0),
                K.simple_mat("Pedestal_Cream", (0.93, 0.87, 0.75), 0.45))
    cam, floor, lights, stage = K.setup_scene(scene)
    SP = 2.05
    peds = {}
    for i, name in enumerate(items):
        ped, H = K.make_pedestal(helpers, ped_mats, (i - 1) * SP)
        peds[name] = (ped, H)
    r15 = K.make_r15(helpers, clay)
    r15.location = (-4.6, 0, 0)

    # reference: the unchanged v001 Party Dice Block production FBX, re-skinned with the v002 atlas
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(K.D["export"], "PartyDiceBlock_v001.fbx"))
    ref_obs = [o for o in bpy.data.objects if o not in before]
    ref_coll = bpy.data.collections.new("Reference_PartyDiceBlock_v001")
    scene.collection.children.link(ref_coll)
    for o in ref_obs:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        ref_coll.objects.link(o)
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)
    ref_root = [o for o in ref_obs if o.parent is None][0]
    items_r = dict(items)
    items_r["PartyDiceBlock_v001"] = {"root": ref_root, "meshes": [o for o in ref_obs if o.type == "MESH"]}

    def lineup():
        for i, (name, it) in enumerate(items.items()):
            H = peds[name][1]
            it["root"].location = ((i - 1) * SP, 0, H + manifest["items"][name]["bounds_m"][2] / 2 + 0.2)
            it["root"].rotation_euler = (0, 0, math.radians(-15))
        ref_root.location = (50, 50, -50)
        bpy.context.view_layer.update()
    lineup()
    manifest["review_helpers"] = {"collections": ["Review_Helpers", "Reference_PartyDiceBlock_v001"],
                                  "excluded_from_exports": True}
    blend = os.path.join(K.D["source"], f"PartyGameItemKit_DiceFamily_{VERSION}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["blend"] = os.path.relpath(blend, KIT)

    if STAGE == "full":
        render_reviews(scene, cam, floor, items, items_r, peds, r15, helpers, manifest, ref_root)
        lineup()
        for ob in bpy.data.objects:
            ob.hide_render = False
        bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["renders"] = sorted(os.path.relpath(os.path.join(RD, f), KIT) for f in os.listdir(RD) if f.endswith(".png"))

    manifest["validation"] = roundtrip(exports, manifest)
    expected = [manifest["blend"], "source/build_dice_family_v002.py"] + list(manifest["atlas"]["maps"].values()) + \
        [f"textures/PGK_Atlas_{VERSION}_Legend.png"] + [it["fbx"] for it in manifest["items"].values()] + \
        ["validation/fbx_roundtrip_v002.json"] + (manifest["renders"] if STAGE == "full" else [])
    manifest["missing_files"] = [f for f in expected if not os.path.exists(os.path.join(KIT, f))]
    if STAGE == "full":
        manifest["missing_renders"] = 12 - len(manifest["renders"])
    changed = [f for f, hsh in v1_hash.items() if sha(os.path.join(KIT, f)) != hsh]
    manifest["v001_files_unchanged"] = not changed
    manifest["v001_files_changed"] = changed
    with open(os.path.join(KIT, f"manifest_{VERSION}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("V001 unchanged:", not changed, changed, "missing:", manifest["missing_files"])
    print("DONE in %.0fs" % (time.time() - t0))


# ---------------------------------------------------------------- FBX round trip
def roundtrip(exports, manifest):
    report = {"importer": f"Blender {bpy.app.version_string} FBX importer", "version": VERSION, "items": {}}
    for name, fp in exports.items():
        exp = manifest["items"][name]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=fp)
        bpy.context.view_layer.update()
        obs = list(bpy.context.scene.objects)
        meshes = [o for o in obs if o.type == "MESH"]
        roots = [o for o in obs if o.parent is None]
        co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
        dims = co.max(0) - co.min(0)
        src = {m["export_name"]: m for m in exp["meshes"].values()}
        per = {}
        for o in meshes:
            s = src.get(o.name, {})
            uv = np.zeros(len(o.data.loops) * 2)
            if o.data.uv_layers:
                o.data.uv_layers[0].data.foreach_get("uv", uv)
            loc = [round(x, 4) for x in o.matrix_local.to_translation()]
            per[o.name] = {
                "parent": o.parent.name if o.parent else None,
                "triangles": sum(len(p.vertices) - 2 for p in o.data.polygons),
                "triangles_match": sum(len(p.vertices) - 2 for p in o.data.polygons) == s.get("triangles"),
                "uv_layers": len(o.data.uv_layers), "uv_in_0_1": bool(uv.size and uv.min() >= 0 and uv.max() <= 1),
                "material_slots": len(o.data.materials),
                "materials": [m.name for m in o.data.materials if m],
                "local_translation_m": loc,
                "pivot_matches_source": bool(np.allclose(loc, s.get("origin_m", [9, 9, 9]), atol=2e-3)),
                "local_rotation_scale_identity": bool(np.allclose(np.array(o.matrix_local.to_3x3()), np.eye(3), atol=1e-4)),
            }
        rec = {"file": os.path.relpath(fp, KIT), "bytes": os.path.getsize(fp),
               "root": roots[0].name if len(roots) == 1 else [r.name for r in roots],
               "root_matches": len(roots) == 1 and roots[0].name == exp["root"],
               "meshes": per, "mesh_count": len(meshes), "mesh_count_matches": len(meshes) == exp["mesh_count"],
               "names_match": sorted(per) == sorted(src),
               "helpers_present": [o.name for o in obs if o.name.startswith(("R15", "ShopPedestal", "_", "Floor"))],
               "triangles_total": sum(p["triangles"] for p in per.values()),
               "world_bounds_m": [round(x, 4) for x in dims],
               "bounds_match": bool(np.allclose(sorted(dims), sorted(exp["bounds_m"]), atol=2e-3)),
               "embedded_images": sorted({i.name for i in bpy.data.images})}
        rec["pass"] = bool(rec["root_matches"] and rec["mesh_count_matches"] and rec["names_match"]
                           and rec["bounds_match"] and not rec["helpers_present"]
                           and all(p["triangles_match"] and p["uv_in_0_1"] and p["uv_layers"] == 1
                                   and p["material_slots"] == 1 and p["pivot_matches_source"]
                                   and p["local_rotation_scale_identity"] and p["triangles"] < 20000
                                   for p in per.values()))
        report["items"][name] = rec
        print("ROUNDTRIP", name, rec["pass"], rec["triangles_total"], rec["root"], sorted(per))
    with open(os.path.join(K.D["validation"], f"fbx_roundtrip_{VERSION}.json"), "w") as f:
        json.dump(report, f, indent=2)
    return {n: r["pass"] for n, r in report["items"].items()}


# ---------------------------------------------------------------- renders
def render_reviews(scene, cam, floor, items, items_r, peds, r15, helpers, manifest, ref_root):
    tmp = os.path.join(RD, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    tp = lambda n: os.path.join(tmp, n + ".png")  # noqa: E731
    names = list(items)
    objs = lambda it: set(it["meshes"]) | {it["root"]}  # noqa: E731
    allnew = set().union(*[objs(items[n]) for n in names])
    refset = objs(items_r["PartyDiceBlock_v001"])
    pedobs = {p[0] for p in peds.values()}
    vis = K.set_render_vis
    views = {"front": (0, -1, 0.0), "three_quarter": (0.75, -1, 0.42), "side": (1, 0, 0.0),
             "back": (0, 1, 0.0), "top": (0.0, -0.25, 1)}
    bnd = lambda n: max(manifest["items"][n]["bounds_m"]) if n in manifest["items"] else 1.0  # noqa: E731

    def park_all():
        for it in items_r.values():
            it["root"].location = (50, 50, -50)
            it["root"].rotation_euler = (0, 0, 0)

    def solo(name, z=1.0, rot=0.0):
        park_all()
        items_r[name]["root"].location = (0, 0, z)
        items_r[name]["root"].rotation_euler = (0, 0, math.radians(rot))
        bpy.context.view_layer.update()

    def turn(name, keys, size=640, z=1.0, floor_on=True):
        solo(name, z)
        vis(objs(items_r[name]) | ({floor} if floor_on else set()))
        rad = bnd(name) * 0.5 * 1.12
        dd = rad / math.tan(math.atan(18 / 85)) * 1.25
        return [K.label(K.do_render(scene, tp(f"{name}_{k}"), size, size), k.replace("_", " ").upper())
                for k in (aim(cam, (0, 0, z), views[k], dd) or k for k in keys)]

    def aim(c, t, d, dist, lens=85):
        K.aim(c, t, d, dist, lens=lens)

    def save(im, fn, title, sub):
        K.header(im, title, sub).save(os.path.join(RD, fn))

    # 1. all three together
    park_all()
    for i, n in enumerate(names):
        items[n]["root"].location = ((i - 1) * 1.95, 0, 1.0)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(allnew | {floor})
    aim(cam, (0, 0, 1.0), (0.2, -1, 0.35), 7.6, lens=50)
    save(K.do_render(scene, tp("together"), 1800, 950), "01_dice_family_together.png",
         "Dice family - review set 2", "Double Dice  |  Triple Dice  |  Lucky Die")

    # 2-4. turnarounds
    desc = {"DoubleDice": "Cobalt + turquoise family dice, offset in depth; twin gold orbit arcs with aqua nodes",
            "TripleDice": "Cobalt, coral and turquoise dice in a flat triangle; gold ring arcs with coral nodes and a pearl hub",
            "LuckyDie": "Emerald enamel, taller gold frame, four-leaf fortune medallions, glowing gold flourishes, mint corner gems"}
    for k, n in enumerate(names):
        im = K.hstack(turn(n, ["front", "back", "side", "three_quarter"]))
        save(im, f"0{k + 2}_{n.lower()}_front_back_side.png", n.replace("Dice", " Dice").replace("Die", " Die").strip(), desc[n])

    # 5. pivot visualisation
    from bpy_extras.object_utils import world_to_camera_view
    ims = []
    for n in names:
        solo(n)
        vis(objs(items[n]) | {floor})
        rad = bnd(n) * 0.5 * 1.12
        aim(cam, (0, 0, 1.0), views["three_quarter"], rad / math.tan(math.atan(18 / 85)) * 1.25)
        bpy.context.view_layer.update()
        im = K.do_render(scene, tp(f"pivot_{n}"), 640, 640)
        im = Image.blend(im, Image.new("RGB", im.size, (240, 236, 228)), 0.35)
        dr = ImageDraw.Draw(im)
        root = items[n]["root"]

        def px(p):
            q = world_to_camera_view(scene, cam, p)
            return q.x * 640, (1 - q.y) * 640
        rx, ry = px(root.matrix_world.translation)
        for ax, col in ((Vector((0.25, 0, 0)), (220, 40, 40)), (Vector((0, 0.25, 0)), (40, 160, 40)), (Vector((0, 0, 0.25)), (40, 80, 230))):
            ex, ey = px(root.matrix_world.translation + ax)
            dr.line((rx, ry, ex, ey), fill=col, width=4)
        dr.ellipse((rx - 11, ry - 11, rx + 11, ry + 11), outline=(20, 20, 20), width=4)
        dr.text((rx + 14, ry + 4), root.name, fill=(20, 20, 20), font=K.font(16, True))
        for ob in items[n]["meshes"]:
            if "Connector" in ob.name:
                continue
            x, y = px(ob.matrix_world.translation)
            dr.line((x - 12, y, x + 12, y), fill=(200, 30, 120), width=4)
            dr.line((x, y - 12, x, y + 12), fill=(200, 30, 120), width=4)
            nm = items[n]["export_names"][ob.name]
            dr.text((x + 10, y - 26), nm, fill=(150, 20, 90), font=K.font(16, True))
        ims.append(K.label(im, n, "o root pivot (XYZ = red/green/blue)   + die tumble pivots", pos="bottom"))
    save(K.hstack(ims), "05_pivot_visualisation.png", "Pivot structure",
         "One assembly root per item; every die mesh has its own centre pivot (rotation/scale applied, translation only)")

    # 6. shop pedestals
    park_all()
    for i, n in enumerate(names):
        H = peds[n][1]
        items[n]["root"].location = ((i - 1) * 2.05, 0, H + manifest["items"][n]["bounds_m"][2] / 2 + 0.2)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(allnew | pedobs | {floor})
    aim(cam, (0, 0, 1.05), (0.18, -1, 0.42), 9.4, lens=50)
    save(K.do_render(scene, tp("pedestals"), 1800, 1000), "06_shop_pedestal_comparison.png",
         "Shop pedestals", "Standard 4.5-stud pedestals; all dice of every assembly visible from the shop camera")

    # 7. R15 scale
    park_all()
    r15.location = (0, 0, 0)
    pos = {"DoubleDice": (-1.45, 1.25), "TripleDice": (1.55, 1.25), "LuckyDie": (3.25, 1.2), "PartyDiceBlock_v001": (-3.05, 1.2)}
    for n, (x, z) in pos.items():
        items_r[n]["root"].location = (x, 0, z)
        items_r[n]["root"].rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    vis(allnew | refset | {r15, floor})
    aim(cam, (0.1, 0, 0.95), (0, -1, 0.06), 10.2, lens=50)
    sb = manifest["items"]
    save(K.do_render(scene, tp("scale"), 1800, 950), "07_r15_scale_comparison.png",
         "R15 scale comparison (5.2-stud blocky R15)",
         f"Party Dice v001 3.56  |  Double {sb['DoubleDice']['bounds_studs'][0]:.1f} W x {sb['DoubleDice']['bounds_studs'][2]:.1f} H  |  "
         f"Triple {sb['TripleDice']['bounds_studs'][0]:.1f} W x {sb['TripleDice']['bounds_studs'][2]:.1f} H  |  Lucky {max(sb['LuckyDie']['bounds_studs']):.2f} studs")
    r15.location = (-4.6, 0, 0)

    # 8. gameplay distance
    park_all()
    board = []
    tiles = [((k - 4) * 5 * STUD, 2.0 * math.sin(k * 0.8) * STUD) for k in range(9)]
    tm = [K.simple_mat("TileBlue", (0.15, 0.35, 0.90), 0.5), K.simple_mat("TileCream", (0.95, 0.88, 0.72), 0.5),
          K.simple_mat("TileRed", (0.92, 0.30, 0.25), 0.5)]
    for k, (x, y) in enumerate(tiles):
        tb = K.Builder()
        tb.sweep(K.circle(1.9 * STUD, 32), [(0, 0.0), (0, 0.12), (0.03, 0.15)], ["CREAM", "CREAM"],
                 K.tf((x, y, 0)), cap0="CREAM", cap1="CREAM")
        me = bpy.data.meshes.new(f"_tile{k}")
        tb.bm.to_mesh(me)
        tb.bm.free()
        me.materials.append(tm[k % 3])
        ob = bpy.data.objects.new(f"_tile{k}", me)
        scene.collection.objects.link(ob)
        board.append(ob)
    for k, (x, y) in enumerate([tiles[3], tiles[7]]):
        f = K.make_r15(scene.collection, bpy.data.materials["R15_Clay"], name=f"_fig{k}")
        f.location = (x + 0.15, y + 0.9, 0.15)
        board.append(f)
    spots = {"PartyDiceBlock_v001": tiles[1], "DoubleDice": tiles[2], "TripleDice": tiles[4], "LuckyDie": tiles[6]}
    for n, (x, y) in spots.items():
        items_r[n]["root"].location = (x, y, 0.15 + 2.7 * STUD)
        items_r[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(allnew | refset | set(board) | {floor})
    aim(cam, (0, 0.4, 0.6), (0, -1, 1.05), 15.5, lens=35)
    full = K.do_render(scene, tp("gameplay"), 1280, 720)
    crops = []
    for n in spots:
        q = world_to_camera_view(scene, cam, items_r[n]["root"].matrix_world.translation)
        cx, cy = int(q.x * 1280), int((1 - q.y) * 720)
        c = full.crop((cx - 60, cy - 60, cx + 60, cy + 60)).resize((300, 300), Image.NEAREST)
        bar = Image.new("RGB", (300, 34), (246, 240, 228))
        ImageDraw.Draw(bar).text((8, 8), f"{n}  (120 px, x2.5)", fill=(70, 52, 30), font=K.font(14, True))
        crops.append(K.vstack([c, bar]))
    panel = K.hstack([K.vstack(crops[:2]), K.vstack(crops[2:])])
    save(K.hstack([full, panel]), "08_gameplay_distance_comparison.png", "Gameplay-distance comparison",
         "Board camera ~15 m (54 studs), 35 mm. Left to right: Party Dice v001, Double, Triple, Lucky; right: 1:1 crops enlarged")
    for ob in board:
        bpy.data.objects.remove(ob, do_unlink=True)

    # 9. material close-up
    ims = []
    shots = [("LuckyDie", (0.0, -0.46, 0.80), (0.25, -1, 0.15), 0.9, "LUCKY FRAME", "fortune medallion / glow flourish / emerald / mint gems"),
             ("TripleDice", (-0.15, -0.2, 0.86), (0.3, -1, 0.3), 1.25, "TRIPLE HUB", "coral enamel / pearl hub / coral nodes / turquoise"),
             ("DoubleDice", (0.38, -0.25, 1.15), (0.5, -1, 0.35), 1.2, "DOUBLE ORBIT", "orbit arc / aqua node / cobalt + turquoise")]
    for n, tgt, d, dist, t1, t2 in shots:
        solo(n, 1.0, rot=0)
        vis(objs(items[n]) | {floor})
        aim(cam, tgt, d, dist)
        ims.append(K.label(K.do_render(scene, tp(f"close_{n}"), 700, 700), t1, t2))
    save(K.hstack(ims), "09_material_closeup.png", "Material close-up",
         "Shared v002 atlas: gold, satin gold, cream, pearl, cobalt / turquoise / coral / emerald enamels, restrained mint + gold glow")

    # 10. wireframe
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
    ims = []
    for n in names:
        solo(n)
        vis(objs(items[n]) | {floor})
        rad = bnd(n) * 0.5 * 1.12
        aim(cam, (0, 0, 1.0), views["three_quarter"], rad / math.tan(math.atan(18 / 85)) * 1.25)
        vl.material_override = wire
        im = K.do_render(scene, tp(f"wire_{n}"), 760, 760, samples=24)
        vl.material_override = None
        info = manifest["items"][n]
        dr = ImageDraw.Draw(im)
        dr.text((18, 14), n, fill=(30, 30, 60), font=K.font(30, True))
        lines = [f"{info['triangles_total']:,} tris total  |  {info['mesh_count']} meshes"] + \
                [f"{m['export_name']}: {m['triangles']:,}" for m in info["meshes"].values()]
        for li, t in enumerate(lines):
            dr.text((18, 56 + li * 24), t, fill=(40, 40, 70), font=K.font(19))
        ims.append(im)
    save(K.hstack(ims), "10_wireframe_triangle_counts.png", "Wireframe and triangle counts",
         "Every die mesh < 8,000 tris; no mesh near the 20,000 limit; one material slot per mesh")

    # 11. existing Party Dice beside the family
    park_all()
    order = ["PartyDiceBlock_v001", "DoubleDice", "TripleDice", "LuckyDie"]
    for i, n in enumerate(order):
        items_r[n]["root"].location = ((i - 1.5) * 1.85, 0, 1.0)
        items_r[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(allnew | refset | {floor})
    aim(cam, (0, 0, 1.0), (0.18, -1, 0.35), 9.0, lens=50)
    save(K.do_render(scene, tp("family"), 1900, 900), "11_party_dice_beside_family.png",
         "Party Dice Block (v001, unchanged) beside the new family",
         "Party Dice Block  |  Double Dice  |  Triple Dice  |  Lucky Die  - same bevel, bezel, rim, pip and gem construction")

    # 12. neutral contact sheet
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*K.BG_NEUTRAL, 1)
    fb = floor.data.materials[0].node_tree.nodes["Principled BSDF"]
    old = tuple(fb.inputs["Base Color"].default_value)
    fb.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    rows = [K.hstack(turn(n, ["front", "three_quarter", "side", "back", "top"], size=400), bg=(205, 205, 205))
            for n in order]
    save(K.vstack(rows, bg=(205, 205, 205)), "12_neutral_contact_sheet.png", "Neutral contact sheet",
         "rows: Party Dice v001 | Double | Triple | Lucky    columns: front | three-quarter | side | back | top")
    bg.inputs["Color"].default_value = (*K.BG_WARM, 1)
    fb.inputs["Base Color"].default_value = old
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
