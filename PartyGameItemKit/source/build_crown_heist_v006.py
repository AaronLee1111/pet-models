"""Party Game Item Kit -- review stage 6: Crown Heist.

Reference: the Crown Heist turnaround supplied with the v006 brief (cream-and-gold handle, gold
hoop with an asymmetric cream crest and gold horn, a bulging cage of two cobalt and two teal
ribbons, a gold crown caught inside, small coral trigger).

Builds on the v001 kit library, the v002 module (atlas layout + validation helpers) and the v005
module (tube / dome / shell helpers); none of them is re-run. Uses the v002 atlas unchanged.
Every v001-v005 file is hash-checked before and after the build.

Construction
    The net is an ellipsoidal cage centred on the hoop: two cobalt loops in the planes x = +-c and
    two teal loops in the planes z = +-h, all meeting the hoop at its centre line. The teal loops
    weave radially in and out (+-6 %) so that they pass alternately over and under the cobalt loops
    without ever touching them. The crown sits in the cage's central front window on a small gold
    perch (4 mm gap) and is removed straight out of that window toward the front (-Y).

Run with the `bpy` module (pip install bpy) or Blender:
    python3 PartyGameItemKit/source/build_crown_heist_v006.py
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
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_item_kit as K            # noqa: E402  v001 library
import build_dice_family_v002 as D2   # noqa: E402  v002 library (registers the v002 atlas layout)
import build_pickpocket_v005 as P5    # noqa: E402  v005 helpers (tube, dome, shells, clearance)

VERSION = "v006"
KIT = K.KIT
STUD = K.STUD
STAGE = os.environ.get("KIT_STAGE", "full")
RD = os.path.join(K.D["renders"], "v006_crown_heist")
FRONT = K.FRONT                       # build plane XY, +Z toward viewer -> world XZ facing -Y
SCALE = 1.0
R = 0.45                              # hoop centre-line radius
HOOP_T = 0.036                        # hoop tube radius
DEPTH = 0.50                          # cage depth semi-axis = DEPTH * R
CX = 0.40 * R                         # cobalt loop planes x = +-CX
HZ = 0.38 * R                         # teal loop planes z = +-HZ
RIB_W, RIB_T = 0.062, 0.018           # ribbon width, thickness
WEAVE = 0.021                         # over/under offset along the cage normal (m)
CROWN_R = 0.122                       # crown band radius
PERCH_GAP = 0.004
HANDLE_TOP = -R - 0.08
HANDLE_LEN = 0.29


# ---------------------------------------------------------------- ribbons
def ellipsoid_normal(p):
    nrm = np.array([p[0] / R ** 2, p[1] / (DEPTH * R) ** 2, p[2] / R ** 2])
    return nrm / np.linalg.norm(nrm)


def ribbon_loop(fn, off, n=64):
    """Closed flat ribbon following fn(t) -> point on the cage ellipsoid (t in [0, 2pi)), displaced
    along the ellipsoid normal by off(p) (checkerboard over/under weave, zero at the hoop)."""
    ts = np.linspace(0, 2 * math.pi, n, endpoint=False)
    P = np.array([fn(t) for t in ts])
    P = np.array([p + ellipsoid_normal(p) * off(p) for p in P])
    bm = bmesh.new()
    sec = K.rrect(RIB_W / 2, RIB_T / 2, RIB_T / 2 * 0.9, 1)          # 8-point rounded flat section
    rings = []
    for i in range(n):
        T = P[(i + 1) % n] - P[i - 1]
        T /= np.linalg.norm(T)
        p = P[i]
        nrm = ellipsoid_normal(p)
        nrm = nrm - nrm.dot(T) * T
        nrm /= np.linalg.norm(nrm)
        B = np.cross(T, nrm)
        rings.append([bm.verts.new(p + B * u + nrm * v) for u, v in sec])
    m = len(sec)
    for i in range(n):
        a, b = rings[i], rings[(i + 1) % n]
        for j in range(m):
            jj = (j + 1) % m
            bm.faces.new((a[j], a[jj], b[jj], b[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def cobalt_fn(sx):
    rho = math.sqrt(R * R - CX * CX)
    return lambda t: np.array([sx * CX, DEPTH * rho * math.cos(t), rho * math.sin(t)])


def teal_fn(sz):
    rho = math.sqrt(R * R - HZ * HZ)
    return lambda t: np.array([rho * math.cos(t), DEPTH * rho * math.sin(t), sz * HZ])


SOFT = 0.06
teal_off = lambda p: WEAVE * math.tanh(p[0] / SOFT) * math.tanh(p[1] / SOFT) * math.tanh(p[2] / SOFT)    # noqa: E731
cobalt_off = lambda p: -WEAVE * math.tanh(p[0] / SOFT) * math.tanh(p[1] / SOFT) * math.tanh(p[2] / SOFT)  # noqa: E731


# ---------------------------------------------------------------- crown
def build_crown():
    C = K.Builder()
    n = 60
    zb, zt0, hp = -0.075, 0.020, 0.058
    th = 0.014
    bm = bmesh.new()
    rows = []
    for row in range(4):
        ring = []
        for i in range(n):
            a = -math.pi / 2 + 2 * math.pi * i / n                    # i = 0 faces the front (-Y)
            u = ((i / n) * 5 + 0.5) % 1.0
            peak = 1 - abs(u * 2 - 1)                                 # 1 at the points (i = 0, 12, 24 ...; front first)
            ztop = zt0 + hp * peak ** 1.6
            z = zb if row in (0, 3) else ztop
            flare = 1 + 0.10 * (z - zb) / (zt0 + hp - zb)
            r = (CROWN_R if row in (0, 1) else CROWN_R - th) * flare
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rows.append(ring)
    for k in range(4):
        A, Bv = rows[k], rows[(k + 1) % 4]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((A[i], A[j], Bv[j], Bv[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    C.append(bm, "GOLD")
    bm.free()
    # gold balls on the five points
    for k in range(5):
        a = -math.pi / 2 + 2 * math.pi * k / 5
        r = CROWN_R * 1.10 - th / 2
        s = bmesh.new()
        bmesh.ops.create_icosphere(s, subdivisions=2, radius=0.019)
        for v in s.verts:
            v.co += Vector((r * math.cos(a), r * math.sin(a), zt0 + hp + 0.010))
        C.append(s, "GOLD")
        s.free()
    # cream band with gold rims, pearl studs and a front pearl diamond
    C.sweep(K.circle(CROWN_R + 0.010, 40), [(0, zb + 0.004), (0, zb + 0.016), (0.004, zb + 0.020), (0.004, zb + 0.040),
                                            (0, zb + 0.044), (0, zb + 0.054), (0.018, zb + 0.054), (0.018, zb + 0.004)],
            ["GOLD", "GOLD_SATIN", "CREAM", "GOLD_SATIN", "GOLD", "GOLD", "GOLD", "GOLD"], K.tf(), closed=True)
    for k in (1, 2, 3, 4):
        a = -math.pi / 2 + 2 * math.pi * k / 5
        d = Vector((math.cos(a), math.sin(a), 0))
        P5.dome(C, K.frame(d * (CROWN_R + 0.010) + Vector((0, 0, zb + 0.030)), d, (0, 0, 1)), 0.011, 8, -0.004, 0.003,
                0.008, "PEARL")
    K.gem_setting(C, K.frame(Vector((0, -(CROWN_R + 0.008), zb + 0.032)), (0, -1, 0), (0, 0, 1)), 0.030, 0.024, "PEARL",
                  h0=-0.004, h1=0.010)
    co = np.array([v.co[:] for v in C.bm.verts])
    centre = (co.min(0) + co.max(0)) / 2
    for v in C.bm.verts:
        v.co -= Vector(centre)
    return C, co.max(0) - co.min(0)


# ---------------------------------------------------------------- net assembly
def lathe(B, outline_r, prof, cls, z_shift=0.0, seg=18, cap0=None, cap1=None):
    B.sweep(K.circle(outline_r, seg), [(d, z + z_shift) for d, z in prof], cls, K.tf(), cap0=cap0, cap1=cap1)


def build_net(crown_dims):
    N = K.Builder()
    # hoop (round gold tube in the item's front plane)
    N.sweep(K.circle(R + HOOP_T, 72), [(HOOP_T * (1 - math.cos(a)), HOOP_T * math.sin(a))
                                       for a in np.radians(np.arange(0, 360, 45))], ["GOLD"] * 8, FRONT, closed=True)
    # asymmetric crest: cream wing with a pearl (upper left), gold horn (upper right)
    wing = [(math.cos(math.radians(a)) * rr, math.sin(math.radians(a)) * rr)
            for a, rr in [(102, R - 0.012), (112, R + 0.085), (124, R + 0.100), (138, R + 0.086), (150, R + 0.036), (156, R - 0.012),
                          (140, R - 0.016), (122, R - 0.016)]]
    wing = K.chaikin(wing, 2)
    N.sweep(wing, [(0.010, -0.032), (0, -0.022), (0, 0.022), (0.010, 0.032)], ["GOLD", "GOLD", "GOLD"], FRONT,
            cap0="CREAM", cap1="CREAM", mode="miter")
    a = math.radians(127)
    pw = FRONT @ Vector(((R + 0.052) * math.cos(a), (R + 0.052) * math.sin(a), 0))
    for zdir in ((0, -1, 0), (0, 1, 0)):                       # same spot on the front and the back
        Mw = K.frame(pw, zdir, (0, 0, 1))
        P5.dome(N, Mw, 0.034, 14, 0.020, 0.034, 0.020, "GOLD", top="GOLD_SATIN")
        P5.dome(N, Mw @ K.tf((0, 0, 0.010)), 0.024, 14, 0.036, 0.048, 0.016, "PEARL")
    horn = [(math.cos(math.radians(a)) * rr, math.sin(math.radians(a)) * rr)
            for a, rr in [(48, R - 0.014), (74, R - 0.014), (70, R + 0.050), (58, R + 0.095), (47, R + 0.122), (50, R + 0.055)]]
    horn = K.chaikin(horn, 1)
    N.sweep(horn, [(0.008, -0.028), (0, -0.020), (0, 0.020), (0.008, 0.028)], ["GOLD", "GOLD", "GOLD"], FRONT,
            cap0="GOLD_SATIN", cap1="GOLD_SATIN", mode="miter")
    # gold side clamps on the hoop
    for a in (0, 180):
        Mc = FRONT @ K.R("Z", a) @ K.tf((R, 0, 0))
        N.sweep(K.diamond(0.062, 0.040), [(0, -0.046), (0, 0.040), (0.012, 0.050)], ["GOLD", "GOLD"], Mc,
                cap0="GOLD", cap1="GOLD_SATIN")
    # cage ribbons (built separately so the weave clearance can be checked)
    ribbons = {}
    for sx in (-1, 1):
        B = K.Builder()
        B.append(ribbon_loop(cobalt_fn(sx), cobalt_off), "COBALT")
        ribbons[f"cobalt_{'L' if sx < 0 else 'R'}"] = B
    for sz in (-1, 1):
        B = K.Builder()
        B.append(ribbon_loop(teal_fn(sz), teal_off), "TEAL")
        ribbons[f"teal_{'low' if sz < 0 else 'up'}"] = B
    # collar under the hoop with a front pearl
    lathe(N, 0.075, [(0.020, -R - 0.105), (0.004, -R - 0.098), (0, -R - 0.088), (0, -R - 0.060), (0.010, -R - 0.052),
                     (0.010, -R - 0.020), (0.022, -R + 0.010)],
          ["GOLD", "GOLD", "GOLD", "GOLD_SATIN", "CREAM", "CREAM"], cap0="GOLD", cap1="CREAM")
    Mp = K.frame((0, -0.068, -R - 0.034), (0, -1, 0), (0, 0, 1))
    N.sweep(K.circle(0.028, 14), [(0, -0.012), (0, 0.012), (0.006, 0.018)], ["GOLD", "GOLD"], Mp, cap0="GOLD", cap1="GOLD_SATIN")
    P5.dome(N, Mp, 0.020, 12, 0.004, 0.016, 0.014, "PEARL")
    # handle: cream shaft, gold bands, gold pommel with a pearl
    zt, zb = HANDLE_TOP, HANDLE_TOP - HANDLE_LEN
    zm = (zt + zb) / 2 + 0.03
    lathe(N, 0.080, [(0.070, zb), (0.035, zb + 0.004), (0.010, zb + 0.022), (0, zb + 0.045), (0, zb + 0.072),
                     (0.010, zb + 0.090), (0.026, zb + 0.100), (0.030, zb + 0.110), (0.030, zm - 0.020),
                     (0.020, zm - 0.012), (0.020, zm + 0.012), (0.030, zm + 0.020), (0.030, zt - 0.070),
                     (0.016, zt - 0.062), (0.016, zt - 0.030), (0.030, zt - 0.022), (0.030, zt + 0.010)],
          ["GOLD", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD_SATIN", "CREAM", "CREAM", "GOLD", "GOLD", "GOLD", "CREAM",
           "GOLD", "GOLD", "GOLD", "CREAM"], cap0="GOLD", cap1="CREAM")
    Mq = K.frame((0, -0.080, zb + 0.058), (0, -1, 0), (0, 0, 1))
    N.sweep(K.circle(0.030, 14), [(0, -0.014), (0, 0.010), (0.006, 0.016)], ["GOLD", "GOLD"], Mq, cap0="GOLD", cap1="GOLD_SATIN")
    P5.dome(N, Mq, 0.022, 12, 0.002, 0.014, 0.014, "PEARL")
    # coral trigger tab on the left of the grip
    tab = K.chaikin([(0.0, 0.03), (-0.075, 0.020), (-0.090, -0.060), (-0.060, -0.075), (-0.045, -0.025), (0.0, -0.020)], 1)
    N.sweep(tab + np.array([-0.035, 0.0]), [(0, -0.018), (0, 0.014), (0.005, 0.019)], ["CORAL_ENAMEL", "CORAL_ENAMEL"],
            FRONT @ K.tf((0, zt - 0.10, 0)), cap0="CORAL_ENAMEL", cap1="CORAL_ENAMEL", mode="miter")
    # gold perch the crown rests on (crown base sits PERCH_GAP above the dish)
    crown_base = -crown_dims[2] / 2
    top = crown_base - PERCH_GAP
    lathe(N, 0.034, [(0, -R - 0.010), (0, top - 0.030)], ["GOLD"], seg=14, cap0="GOLD", cap1="GOLD")
    zmid = (-R + top) / 2
    lathe(N, 0.050, [(0.016, zmid - 0.030), (0.004, zmid - 0.020), (0, zmid - 0.008), (0, zmid + 0.008),
                     (0.004, zmid + 0.020), (0.016, zmid + 0.030)], ["CREAM"] * 5, seg=16, cap0="CREAM", cap1="CREAM")
    lathe(N, 0.072, [(0.050, top - 0.034), (0.030, top - 0.024), (0.006, top - 0.010), (0, top - 0.004), (0.006, top)],
          ["GOLD", "GOLD", "GOLD", "GOLD"], seg=24, cap0="GOLD", cap1="CREAM")
    return N, ribbons


# ---------------------------------------------------------------- validation
def bvh_world(ob):
    co, tris = D2.world_tris(ob)
    return co, BVHTree.FromPolygons(co, tris)


def removal_test(net, crown, step=0.01):
    """Slide the crown straight out of the front window (-Y) until it is clear of the cage."""
    start = crown.location.copy()
    nco, ntree = bvh_world(net)
    net_front = min(c.y for c in nco)
    out, minc, hits, travel = [], 1e9, 0, 0.0
    while True:
        crown.location = start + Vector((0, -travel, 0))
        bpy.context.view_layer.update()
        cco, ctree = bvh_world(crown)
        d = min(ntree.find_nearest(p)[3] for p in cco)
        n = len(ctree.overlap(ntree))
        out.append({"travel_m": round(travel, 3), "min_clearance_m": round(d, 4), "intersections": n})
        minc, hits = min(minc, d), hits + n
        if max(c.y for c in cco) < net_front - 0.01:
            break
        travel += step
    crown.location = start
    bpy.context.view_layer.update()
    return {"direction": "-Y (out through the front window)", "step_m": step, "travel_m": round(travel, 3),
            "min_clearance_m": round(minc, 4), "intersections": hits, "samples": out}


def snapshot():
    out = {}
    for dp, _, fs in os.walk(KIT):
        for f in fs:
            p = os.path.relpath(os.path.join(dp, f), KIT)
            if p == "README.md" or "v006" in p or "__pycache__" in p or p.endswith(".blend1"):
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

    C, crown_dims = build_crown()
    N, ribbons = build_net(crown_dims)
    rb = {k: P5.builder_bvh(B) for k, B in ribbons.items()}
    weave = {}
    ks = list(rb)
    for i in range(len(ks)):
        for j in range(i + 1, len(ks)):
            a, b = rb[ks[i]], rb[ks[j]]
            d = min(min(b[1].find_nearest(p)[3] for p in a[0]), min(a[1].find_nearest(p)[3] for p in b[0]))
            weave[f"{ks[i]} - {ks[j]}"] = {"min_clearance_m": round(d, 4), "intersections": len(a[1].overlap(b[1]))}
    for B in ribbons.values():
        P5.merge(N, B)
        B.bm.free()
    crown_c = Vector((0, 0, 0))                                    # crown centre = cage centre (authored)
    allco = np.array([v.co[:] for v in N.bm.verts] + [(v.co + crown_c)[:] for v in C.bm.verts]) * SCALE
    centre = (allco.min(0) + allco.max(0)) / 2
    for v in N.bm.verts:
        v.co = v.co * SCALE - Vector(centre)
    crown_loc = crown_c * SCALE - Vector(centre)
    for v in C.bm.verts:
        v.co = v.co * SCALE + crown_loc                            # UV-project at rest, then re-centre below

    coll = bpy.data.collections.new("PGK_CrownHeist")
    scene.collection.children.link(coll)
    root = D2.new_root(scene, "CrownHeist_Root", coll)
    net = K.finish_mesh("CrownHeist_Net", N, coll, root, mat, 1.0)
    crown = K.finish_mesh("CrownHeist_Crown", C, coll, root, mat, 1.0)
    crown.data.transform(Matrix.Translation(-crown_loc))
    crown.location = crown_loc
    bpy.context.view_layer.update()
    obs = [net, crown]

    meshes, co_all = {}, []
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
                           "local_scale": [1, 1, 1], "bounds_m": [round(x, 4) for x in co.max(0) - co.min(0)],
                           "bounds_studs": [round(x / STUD, 2) for x in co.max(0) - co.min(0)], **K.mesh_checks(ob)}
    co = np.concatenate(co_all)
    dims = co.max(0) - co.min(0)
    n_shells, n_float = P5.floating_shells(net)
    rest_d, rest_n = P5.clearance(net, crown)
    removal = removal_test(net, crown)
    info = {
        "reference": "Crown Heist turnaround attached to the v006 brief (front / back / left / right / 3-4 / crown detail)",
        "collection": coll.name, "root": root.name,
        "hierarchy": {"CrownHeist_Root": ["CrownHeist_Net", "CrownHeist_Crown"]},
        "pivots": {"CrownHeist_Root": "presentation (bounding-box) centre of the whole item, at (0,0,0)",
                   "CrownHeist_Net": "aligned with the root (identity local transform)",
                   "CrownHeist_Crown": {"location_m": [round(x, 5) for x in crown_loc],
                                        "location_studs": [round(x / STUD, 3) for x in crown_loc],
                                        "rotation_deg": [0, 0, 0], "scale": [1, 1, 1],
                                        "pivot": "crown bounding-box centre", "front": "-Y (pearl diamond)",
                                        "removal_direction": "-Y, straight out through the cage's central front window"}},
        "meshes": meshes, "mesh_count": 2,
        "triangles_net": meshes["CrownHeist_Net"]["triangles"], "triangles_crown": meshes["CrownHeist_Crown"]["triangles"],
        "triangles_total": sum(m["triangles"] for m in meshes.values()),
        "bounds_m": [round(x, 4) for x in dims], "bounds_studs": [round(x / STUD, 2) for x in dims],
        "crown_dims_m": [round(x * SCALE, 4) for x in crown_dims], "crown_dims_studs": [round(x * SCALE / STUD, 2) for x in crown_dims],
        "cage": {"hoop_radius_m": R * SCALE, "depth_semi_axis_m": round(DEPTH * R * SCALE, 4),
                 "cobalt_planes_x_m": round(CX * SCALE, 4), "teal_planes_z_m": round(HZ * SCALE, 4),
                 "front_window_m": [round((2 * CX - RIB_W) * SCALE, 4), round((2 * HZ - RIB_W) * SCALE, 4)],
                 "weave_offset_m": WEAVE, "ribbon_clearance": weave},
        "net_shells": n_shells, "floating_shells": n_float,
        "crown_rest": {"min_clearance_m": round(rest_d, 4), "intersections": rest_n, "perch_gap_m": PERCH_GAP * SCALE},
        "crown_removal": removal,
        "coplanar_overlap_pairs": D2.zfight_world(obs),
    }
    print("ITEM CrownHeist", info["triangles_total"], "net", info["triangles_net"], "crown", info["triangles_crown"],
          info["bounds_studs"], "crown", info["crown_dims_studs"], "zf", info["coplanar_overlap_pairs"], "shells", n_shells,
          "float", n_float, {k: (v["inverted_shells"], v["non_manifold_edges"], v["degenerate_tris"], v["uv_bounds"]) for k, v in meshes.items()},
          "weave", {k: (v["min_clearance_m"], v["intersections"]) for k, v in weave.items()},
          "rest", round(rest_d, 4), rest_n, "removal", removal["min_clearance_m"], removal["intersections"], removal["travel_m"],
          "crown_loc", [round(x, 3) for x in crown_loc])
    manifest = {"kit": "PartyGameItemKit", "version": VERSION, "stage": "review-6 (Crown Heist)",
                "builds_on": {"scripts": ["source/build_item_kit.py", "source/build_dice_family_v002.py",
                                          "source/build_pickpocket_v005.py"]},
                "units": {"blender": "metres", "stud_m": STUD},
                "atlas": {"maps": {k: os.path.relpath(p, KIT) for k, p in paths.items()}, "new_cells": [],
                          "note": "v002 atlas unchanged: GOLD, GOLD_SATIN, CREAM, TEAL, COBALT, CORAL_ENAMEL, PEARL"},
                "material": "PGK_KitAtlas (one slot per mesh, v002 maps)", "items": {"CrownHeist": info}}

    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    fp = os.path.join(K.D["export"], f"CrownHeist_{VERSION}.fbx")
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
    for nm, f in (("CoinShield", "CoinShield_v001.fbx"), ("Pickpocket", "Pickpocket_v005.fbx")):
        prev = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(K.D["export"], f))
        new = [o for o in bpy.data.objects if o not in prev]
        for o in new:
            for cc in list(o.users_collection):
                cc.objects.unlink(o)
            ref_coll.objects.link(o)
            if o.type == "MESH":
                o.name = f"ref_{nm}_{o.name}"
                o.data.materials.clear()
                o.data.materials.append(mat)
        r = [o for o in new if o.parent is None][0]
        r.name = f"ref_{nm}_Root"
        refs[nm] = {"root": r, "meshes": [o for o in new if o.type == "MESH"]}
    peds = [K.make_pedestal(helpers, ped_mats, (i - 1) * 1.9) for i in range(3)]
    items = {"CrownHeist": {"root": root, "meshes": obs}, **refs}

    def park():
        for it in items.values():
            it["root"].location = (50, 50, -50)
            it["root"].rotation_euler = (0, 0, 0)
    park()
    root.location = (0, 0, peds[1][1] + dims[2] / 2 + 0.15)
    bpy.context.view_layer.update()
    blend = os.path.join(K.D["source"], f"PartyGameItemKit_CrownHeist_{VERSION}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["blend"] = os.path.relpath(blend, KIT)
    manifest["review_helpers"] = {"collections": ["Review_Helpers", "Reference_Items", "Review_Stage"],
                                  "excluded_from_exports": True}
    if STAGE == "full":
        render_reviews(scene, cam, floor, items, peds, r15, manifest, park, crown)
        park()
        root.location = (0, 0, peds[1][1] + dims[2] / 2 + 0.15)
        crown.location = crown_loc
        for o in bpy.data.objects:
            o.hide_render = False
        bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["renders"] = sorted(os.path.relpath(os.path.join(RD, f), KIT) for f in os.listdir(RD) if f.endswith(".png"))
    manifest["validation"] = roundtrip(fp, manifest)
    expected = [manifest["blend"], "source/build_crown_heist_v006.py", info["fbx"], "validation/fbx_roundtrip_v006.json"] + \
        list(manifest["atlas"]["maps"].values())
    manifest["missing_files"] = [f for f in expected if not os.path.exists(os.path.join(KIT, f))]
    manifest["renders_expected"] = 13
    manifest["renders_missing"] = 13 - len(manifest["renders"])
    after = snapshot()
    changed = sorted(f for f in before if after.get(f) != before[f])
    manifest["v001_v005_files_checked"] = len(before)
    manifest["v001_v005_files_unchanged"] = not changed
    manifest["v001_v005_files_changed"] = changed
    with open(os.path.join(KIT, f"manifest_{VERSION}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("PRIOR unchanged:", not changed, len(before), changed, "missing:", manifest["missing_files"],
          "renders:", len(manifest["renders"]))
    print("DONE in %.0fs" % (time.time() - t0))


def roundtrip(fp, manifest):
    exp = manifest["items"]["CrownHeist"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fp)
    bpy.context.view_layer.update()
    obs = list(bpy.context.scene.objects)
    meshes = [o for o in obs if o.type == "MESH"]
    roots = [o for o in obs if o.parent is None]
    co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
    dims = co.max(0) - co.min(0)
    centre = (co.max(0) + co.min(0)) / 2
    root_w = np.array(roots[0].matrix_world.translation, float) if roots else np.full(3, 9.0)
    per = {}
    for o in meshes:
        s = exp["meshes"].get(o.name, {})
        uv = np.zeros(len(o.data.loops) * 2)
        if o.data.uv_layers:
            o.data.uv_layers[0].data.foreach_get("uv", uv)
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        loc = np.array(o.matrix_local.to_translation(), float)
        mco = np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices])
        per[o.name] = {"parent": o.parent.name if o.parent else None, "triangles": tris,
                       "triangles_match": tris == s.get("triangles"), "uv_layers": len(o.data.uv_layers),
                       "uv_bounds": [round(float(uv.min()), 4), round(float(uv.max()), 4)] if uv.size else None,
                       "uv_in_0_1": bool(uv.size and uv.min() >= 0 and uv.max() <= 1),
                       "material_slots": len(o.data.materials), "materials": [m.name for m in o.data.materials if m],
                       "local_translation_m": [round(float(x), 4) for x in loc],
                       "pivot_matches_source_2mm": bool(np.allclose(loc, s.get("origin_m", [9, 9, 9]), atol=2e-3)),
                       "bounds_match_2mm": bool(np.allclose(sorted(mco.max(0) - mco.min(0)), sorted(s.get("bounds_m", [0, 0, 0])), atol=2e-3)),
                       "local_rotation_scale_identity": bool(np.allclose(np.array(o.matrix_local.to_3x3()), np.eye(3), atol=1e-4))}
    rec = {"file": os.path.relpath(fp, KIT), "bytes": os.path.getsize(fp),
           "importer": f"Blender {bpy.app.version_string} FBX importer",
           "hierarchy": {o.name: o.parent.name if o.parent else None for o in obs},
           "root_matches": len(roots) == 1 and roots[0].name == "CrownHeist_Root",
           "names_match": sorted(per) == sorted(exp["meshes"]), "mesh_count": len(meshes),
           "helpers_present": [o.name for o in obs if o.name.startswith(("R15", "ShopPedestal", "_", "Floor", "ref_"))],
           "meshes": per, "world_bounds_m": [round(float(x), 4) for x in dims], "source_bounds_m": exp["bounds_m"],
           "bounds_match_2mm": bool(np.allclose(sorted(dims), sorted(exp["bounds_m"]), atol=2e-3)),
           "root_to_presentation_centre_m": round(float(np.linalg.norm(centre - root_w)), 5),
           "embedded_images": sorted({i.name for i in bpy.data.images})}
    rec["root_pivot_within_2mm"] = rec["root_to_presentation_centre_m"] <= 2e-3
    rec["pass"] = bool(rec["root_matches"] and rec["names_match"] and rec["bounds_match_2mm"] and rec["root_pivot_within_2mm"]
                       and not rec["helpers_present"]
                       and all(p["triangles_match"] and p["uv_in_0_1"] and p["uv_layers"] == 1 and p["material_slots"] == 1
                               and p["pivot_matches_source_2mm"] and p["bounds_match_2mm"] and p["local_rotation_scale_identity"]
                               and p["triangles"] < 8000 for p in per.values()))
    with open(os.path.join(K.D["validation"], f"fbx_roundtrip_{VERSION}.json"), "w") as f:
        json.dump({"version": VERSION, "items": {"CrownHeist": rec}}, f, indent=2)
    print("ROUNDTRIP CrownHeist", rec["pass"], rec["hierarchy"], rec["world_bounds_m"], rec["root_to_presentation_centre_m"])
    return {"CrownHeist": rec["pass"]}


# ---------------------------------------------------------------- renders
def render_reviews(scene, cam, floor, items, peds, r15, manifest, park, crown):
    from bpy_extras.object_utils import world_to_camera_view
    tmp = os.path.join(RD, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    tp = lambda n: os.path.join(tmp, n + ".png")  # noqa: E731
    objs = lambda it: set(it["meshes"]) | {it["root"]}  # noqa: E731
    CH = items["CrownHeist"]
    ch = objs(CH)
    vis = K.set_render_vis
    info = manifest["items"]["CrownHeist"]
    cl = Vector(info["pivots"]["CrownHeist_Crown"]["location_m"])
    H = max(info["bounds_m"])
    ortho = H * 1.15
    views = {"front": (0, -1, 0.0), "back": (0, 1, 0.0), "left": (-1, 0, 0.0), "right": (1, 0, 0.0),
             "three_quarter": (0.75, -1, 0.42), "back_three_quarter": (-0.75, 1, 0.42)}
    dist = H * 0.5 * 1.12 / math.tan(math.atan(18 / 85)) * 1.25

    def save(im, fn, title, sub):
        K.header(im, title, sub).save(os.path.join(RD, fn))

    def solo(z=1.0):
        park()
        CH["root"].location = (0, 0, z)
        crown.location = cl
        bpy.context.view_layer.update()
        vis(ch | {floor})

    def ortho_shot(k, size=720):
        K.aim(cam, (0, 0, 1.0), views[k], 6.0, ortho=ortho)
        return K.label(K.do_render(scene, tp("o" + k), size, size), f"{k.upper()} (ORTHO)")

    solo()
    ims = [ortho_shot(k) for k in ("front", "back", "left", "right")]
    ims[0].save(os.path.join(tmp, "front.png"))
    save(ims[0], "01_front_ortho.png", "Crown Heist - front (orthographic)",
         "Gold hoop with cream crest + gold horn; cobalt/teal woven cage; gold crown on a perch; cream handle, coral trigger")
    save(ims[1], "02_back_ortho.png", "Crown Heist - back (orthographic)", "Back of the cage, crest and horn mirrored, pommel pearl")
    save(K.hstack(ims[2:]), "03_left_right_ortho.png", "Crown Heist - left and right (orthographic)",
         f"Cage bulges {info['cage']['depth_semi_axis_m'] * 1000:.0f} mm front and back of the hoop; coral trigger on the left")
    K.aim(cam, (0, 0, 1.0), views["three_quarter"], dist * 1.05)
    save(K.do_render(scene, tp("hero"), 1400, 1000), "04_hero_three_quarter.png", "Crown Heist - hero three-quarter",
         "The captured crown reads through the cage's central front window")
    ims = []
    c = Vector((0, 0, 1.0)) + cl
    for tgt, d, dd, t1, t2 in ((c, (0.35, -1, 0.25), 0.95, "CROWN IN THE NET", "pearl diamond front, five gold points"),
                               (c + Vector((0, 0, -0.10)), (0.6, -1, 0.1), 0.75, "PERCH + GAP", f"crown rests {PERCH_GAP * 1000:.0f} mm above the gold perch"),
                               (c + Vector((0.12, 0.0, 0.10)), (1, -0.5, 0.8), 0.95, "WEAVE", "teal passes over / under cobalt, never touching")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("cn" + t1[:4]), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "05_crown_net_closeup.png", "Crown and net close-up",
         f"Crown rest clearance {info['crown_rest']['min_clearance_m'] * 1000:.1f} mm, 0 intersections; ribbon weave min {min(v['min_clearance_m'] for v in info['cage']['ribbon_clearance'].values()) * 1000:.1f} mm")
    solo()
    crown.location = cl + Vector((0.95, 0, -0.05))
    bpy.context.view_layer.update()
    K.aim(cam, (0.45, 0, 1.0), (0.35, -1, 0.25), dist * 1.15)
    save(K.do_render(scene, tp("separate"), 1500, 1000), "06_crown_separate.png", "Crown shown separately",
         f"CrownHeist_Crown {info['crown_dims_studs'][0]:.2f} x {info['crown_dims_studs'][1]:.2f} x {info['crown_dims_studs'][2]:.2f} studs, own centre pivot")
    # removal path: blend the crown at three positions along -Y, side view
    solo()
    travel = info["crown_removal"]["travel_m"]
    frames = []
    for f in (0.0, 0.5, 1.0):
        crown.location = cl + Vector((0, -travel * f, 0))
        bpy.context.view_layer.update()
        K.aim(cam, (0, -travel * 0.35, 1.0 + cl.z), (1, -0.25, 0.12), 6.0, ortho=ortho * 0.8)
        frames.append(K.do_render(scene, tp(f"rm{f}"), 1100, 900))
    im = Image.blend(Image.blend(frames[0], frames[1], 0.4), frames[2], 0.4)
    dr = ImageDraw.Draw(im)
    p0 = world_to_camera_view(scene, cam, Vector((0, 0, 1.0)) + cl)
    p1 = world_to_camera_view(scene, cam, Vector((0, -travel, 1.0)) + cl)
    a0, a1 = (p0.x * 1100, (1 - p0.y) * 900), (p1.x * 1100, (1 - p1.y) * 900)
    dr.line((a0, a1), fill=(200, 60, 40), width=6)
    dr.polygon([a1, (a1[0] + 20, a1[1] - 14), (a1[0] + 20, a1[1] + 14)], fill=(200, 60, 40))
    rm = info["crown_removal"]
    save(im, "07_crown_removal_path.png", "Crown removal path",
         f"Straight out of the front window (-Y), {travel * 1000:.0f} mm travel: min clearance {rm['min_clearance_m'] * 1000:.1f} mm, {rm['intersections']} intersections")
    crown.location = cl
    # R15
    park()
    r15.location = (0, 0, 0)
    CH["root"].location = (1.55, 0, info["bounds_m"][2] / 2 + 0.25)
    items["Pickpocket"]["root"].location = (-1.35, 0, 1.0)
    bpy.context.view_layer.update()
    vis(ch | objs(items["Pickpocket"]) | {r15, floor})
    K.aim(cam, (0.1, 0, 0.95), (0, -1, 0.06), 8.4, lens=50)
    b = info["bounds_studs"]
    save(K.do_render(scene, tp("scale"), 1600, 950), "08_r15_scale_comparison.png", "R15 scale comparison (5.2-stud blocky R15)",
         f"Crown Heist {b[0]:.2f} W x {b[2]:.2f} H x {b[1]:.2f} D studs  |  Pickpocket 3.03 x 3.59")
    r15.location = (-4.6, 0, 0)
    # shop
    park()
    order = ["CoinShield", "CrownHeist", "Pickpocket"]
    for i, n in enumerate(order):
        ped, Hp = peds[i]
        z = {"CoinShield": 1.05 / 2 + 0.22, "CrownHeist": info["bounds_m"][2] / 2 + 0.15, "Pickpocket": 1.0 / 2 + 0.02}[n]
        items[n]["root"].location = ((i - 1) * 1.9, 0, Hp + z)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(ch | objs(items["CoinShield"]) | objs(items["Pickpocket"]) | {p for p, _ in peds} | {floor})
    K.aim(cam, (0, 0, 1.3), (0.15, -1, 0.35), 10.2, lens=50)
    save(K.do_render(scene, tp("shop"), 1800, 1050), "09_shop_scale_comparison.png", "Shop-scale comparison",
         "Coin Shield | Crown Heist | Pickpocket on standard 4.5-stud pedestals")
    # gameplay
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
    spots = {"CoinShield": tiles[1], "CrownHeist": tiles[4], "Pickpocket": tiles[6]}
    for n, (x, y) in spots.items():
        items[n]["root"].location = (x, y, 0.15 + 3.0 * STUD)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(ch | objs(items["CoinShield"]) | objs(items["Pickpocket"]) | set(board) | {floor})
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
    save(K.hstack([full, K.vstack(crops[:2]), K.vstack(crops[2:])]), "10_gameplay_distance.png",
         "Gameplay-distance view", "Board camera ~15 m (54 studs), 35 mm; Coin Shield | Crown Heist | Pickpocket; right: 1:1 crops enlarged")
    for o in board:
        bpy.data.objects.remove(o, do_unlink=True)
    # material close-up
    solo()
    ims = []
    for tgt, d, dd, t1, t2 in ((Vector((-0.32, 0, 1.0 + R * 0.78)), (-0.3, -1, 0.3), 0.70, "CREST + HORN", "cream wing, gold bezel + pearl, gold horn"),
                               (Vector((0.0, 0.0, 1.0 + cl.z)), (0.2, -1, 0.15), 0.70, "RIBBONS + CROWN", "teal + cobalt ribbons, gold crown, cream band"),
                               (Vector((0.0, 0.0, 1.0 + HANDLE_TOP - 0.12 + cl.z - 0.0)), (0.5, -1, 0.2), 0.65, "GRIP", "cream shaft, gold bands, coral trigger, pearl collar")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("mat" + t1[:4]), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "11_material_closeup.png", "Material close-up", "v002 atlas cells only; no new texture maps")
    # wireframe + pivots
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
    for k in ("front", "three_quarter"):
        if k == "front":
            K.aim(cam, (0, 0, 1.0), views[k], 6.0, ortho=ortho)
        else:
            K.aim(cam, (0, 0, 1.0), views[k], dist)
        bpy.context.view_layer.update()
        vl.material_override = wire
        im = K.do_render(scene, tp("wire" + k), 860, 860, samples=24)
        vl.material_override = None
        dr = ImageDraw.Draw(im)
        px = lambda p: ((lambda q: (q.x * 860, (1 - q.y) * 860))(world_to_camera_view(scene, cam, p)))  # noqa: E731
        o = CH["root"].matrix_world.translation.copy()
        rx, ry = px(o)
        for ax, col in ((Vector((0.25, 0, 0)), (220, 40, 40)), (Vector((0, 0.25, 0)), (40, 160, 40)), (Vector((0, 0, 0.25)), (40, 80, 230))):
            ex, ey = px(o + ax)
            dr.line((rx, ry, ex, ey), fill=col, width=5)
        dr.ellipse((rx - 11, ry - 11, rx + 11, ry + 11), outline=(20, 20, 20), width=4)
        cw = crown.matrix_world.translation.copy()
        cx, cy = px(cw)
        dr.line((cx - 12, cy, cx + 12, cy), fill=(200, 30, 120), width=4)
        dr.line((cx, cy - 12, cx, cy + 12), fill=(200, 30, 120), width=4)
        ex, ey = px(cw + Vector((0, -0.4, 0)))
        dr.line((cx, cy, ex, ey), fill=(200, 60, 40), width=3)
        dr.text((rx + 14, ry + 6), "Root (presentation centre)", fill=(20, 20, 20), font=K.font(16, True))
        dr.text((cx + 14, cy - 28), "Crown pivot", fill=(150, 20, 90), font=K.font(16, True))
        ims.append(im)
    im = K.hstack(ims)
    dr = ImageDraw.Draw(im)
    dr.text((18, 14), "CrownHeist", fill=(30, 30, 60), font=K.font(30, True))
    for i, t in enumerate([f"{info['triangles_total']:,} tris total  |  2 meshes  |  1 material slot each",
                           f"CrownHeist_Net: {info['triangles_net']:,}", f"CrownHeist_Crown: {info['triangles_crown']:,}"]):
        dr.text((18, 56 + i * 24), t, fill=(40, 40, 70), font=K.font(19))
    save(im, "12_wireframe_pivots.png", "Wireframe and pivots",
         "Root at the presentation centre (axes); crown pivot at the crown centre (+), removal direction -Y (red line)")
    # contact sheet
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*K.BG_NEUTRAL, 1)
    fb = floor.data.materials[0].node_tree.nodes["Principled BSDF"]
    old = tuple(fb.inputs["Base Color"].default_value)
    fb.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    solo()
    row = []
    for k in ("front", "back", "left", "right"):
        K.aim(cam, (0, 0, 1.0), views[k], 6.0, ortho=ortho)
        row.append(K.label(K.do_render(scene, tp("cs" + k), 420, 420), k.upper()))
    for k in ("three_quarter", "back_three_quarter"):
        K.aim(cam, (0, 0, 1.0), views[k], dist)
        row.append(K.label(K.do_render(scene, tp("cs" + k), 420, 420), k.replace("_", " ").upper()))
    rr = []
    for n in ("CoinShield", "Pickpocket"):
        park()
        items[n]["root"].location = (0, 0, 1.0)
        bpy.context.view_layer.update()
        vis(objs(items[n]) | {floor})
        K.aim(cam, (0, 0, 1.0), views["three_quarter"], 1.1 * 0.5 * 1.12 / math.tan(math.atan(18 / 85)) * 1.25)
        rr.append(K.label(K.do_render(scene, tp("ref" + n), 420, 420), n))
    solo()
    crown.location = Vector((0, 0, 0))
    bpy.context.view_layer.update()
    vis({crown, CH["root"], floor})
    K.aim(cam, (0, 0, 1.0), views["three_quarter"], 0.9)
    rr.append(K.label(K.do_render(scene, tp("crownonly"), 420, 420), "CROWN"))
    crown.location = cl
    save(K.vstack([K.hstack(row[:3], bg=(205, 205, 205)), K.hstack(row[3:], bg=(205, 205, 205)), K.hstack(rr, bg=(205, 205, 205))],
                  bg=(205, 205, 205)), "13_contact_sheet.png", "Neutral contact sheet",
         "rows: front | back | left  -  right | three-quarter | back three-quarter  -  Coin Shield | Pickpocket | crown alone")
    bg.inputs["Color"].default_value = (*K.BG_WARM, 1)
    fb.inputs["Base Color"].default_value = old
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
