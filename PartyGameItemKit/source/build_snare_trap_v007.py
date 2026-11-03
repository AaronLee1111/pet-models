"""Party Game Item Kit -- review stage 7: Snare Trap.

Reference: the turnaround supplied with the v007 brief (its banner reads "SPRING LOOP"): a rounded
gold-framed base on four feet, a scalloped cream panel with four gold chevrons and a cobalt pressure
plate, a thick padded teal loop folded around the panel whose ends meet a gold hinge barrel at the
front edge (pearl axle caps), a small coral indicator, and a raised pose where the loop swings up
to stand vertically over the front hinge.

Builds on the v001 kit library, the v002 module (atlas layout + validation helpers) and the v005
module (tube / dome / shell helpers); none is re-run. Uses the v002 atlas unchanged. Every
v001-v006 file is hash-checked before and after the build.

Animation (not rigged, documented only)
    SnareTrap_Loop     rotates +90 deg about its local X axis (the hinge axis) from armed to raised.
    SnareTrap_Trigger  translates -Z by TRIGGER_TRAVEL when activated.
    SnareTrap_Base     stays still.

Run with the `bpy` module (pip install bpy) or Blender:
    python3 PartyGameItemKit/source/build_snare_trap_v007.py
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

VERSION = "v007"
KIT = K.KIT
STUD = K.STUD
STAGE = os.environ.get("KIT_STAGE", "full")
RD = os.path.join(K.D["renders"], "v007_snare_trap")
HALF, CORNER = 0.42, 0.16              # base half-size and corner radius (3.0 studs square)
FRAME_TOP, DECK = 0.100, 0.104
RIM_TOP, PANEL_TOP = 0.124, 0.114
BEZEL_TOP = 0.148
PLATE_BOT, PLATE_TOP = 0.128, 0.158
TRIGGER_TRAVEL = 0.012
TUBE_R = 0.070
YH, ZH = -0.39, 0.202                  # hinge axis (parallel to X)
LX, LY_BACK, LOOP_RC = 0.35, 0.35, 0.12
ATTACH_X, ATTACH_DY, APPROACH_R = 0.08, 0.04, 0.10
BARREL_R, BARREL_X = 0.065, 0.155
PIN_X0, PIN_X1, PIN_R = 0.158, 0.210, 0.050
ACTIVATED_DEG = 90.0
TILE_R = 1.9 * STUD                    # review board-space radius used throughout the kit's renders
REST = {}


# ---------------------------------------------------------------- loop path
def loop_path():
    pts = []
    yf = YH + ATTACH_DY + APPROACH_R            # front run

    def arc(c, r, a0, a1, n):
        return [(c[0] + r * math.cos(math.radians(a)), c[1] + r * math.sin(math.radians(a)))
                for a in np.linspace(a0, a1, n)]
    # right half from the barrel to the back centre, then mirrored
    right = []
    right += [(ATTACH_X, YH + ATTACH_DY - 0.02)]
    right += arc((ATTACH_X + APPROACH_R, YH + ATTACH_DY), APPROACH_R, 180, 90, 10)
    right += arc((LX - LOOP_RC, yf + LOOP_RC), LOOP_RC, -90, 0, 10)
    right += arc((LX - LOOP_RC, LY_BACK - LOOP_RC), LOOP_RC, 0, 90, 10)
    right += [(0.0, LY_BACK)]
    left = [(-x, y) for x, y in reversed(right[:-1])]
    pts = right + left
    return np.array([(x, y, ZH) for x, y in pts]), yf


def build_loop():
    L = K.Builder()
    P, yf = loop_path()
    path = P5.Path(P, n=400)
    n = int(path.L / 0.016)
    pts = path.sub(0, path.L, n)
    s = np.linspace(0, path.L, n)
    seg = path.L / 12
    groove = np.array([1 - 0.05 * max(0.0, math.cos(2 * math.pi * (si - 0.5 * seg) / seg)) ** 8 for si in s])
    radii = P5.capsule_radii(s, TUBE_R, r_start=TUBE_R, r_end=TUBE_R, floor=0.3) * groove
    L.append(P5.tube(pts, radii, ring=14), "TEAL")
    # hinge barrel (part of the loop: it turns with it), gold with two satin grooves
    Mb = K.frame((-BARREL_X, YH, ZH), (1, 0, 0), (0, 0, 1))
    Lb = 2 * BARREL_X
    L.sweep(K.circle(BARREL_R, 24), [(0.010, 0.0), (0, 0.010), (0, 0.07), (0.006, 0.075), (0.006, 0.085), (0, 0.09),
                                     (0, Lb - 0.09), (0.006, Lb - 0.085), (0.006, Lb - 0.075), (0, Lb - 0.07),
                                     (0, Lb - 0.010), (0.010, Lb)],
            ["GOLD", "GOLD", "GOLD_SATIN", "GOLD_SATIN", "GOLD_SATIN", "GOLD", "GOLD_SATIN", "GOLD_SATIN", "GOLD_SATIN",
             "GOLD", "GOLD"], Mb, cap0="GOLD", cap1="GOLD")
    return L, yf


# ---------------------------------------------------------------- base
def scallop(rp, n=72, amp=0.12):
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    r = rp * (1 + amp * np.cos(4 * t))
    return K.ccw(np.stack([r * np.cos(t), r * np.sin(t)], 1))


def chevron():
    return K.ccw([(-0.060, -0.012), (0.0, 0.040), (0.060, -0.012), (0.044, -0.030), (0.0, 0.010), (-0.044, -0.030)])


def build_base():
    B = K.Builder()
    out = K.rrect(HALF, HALF, CORNER, 8)
    B.sweep(out, [(0.030, 0.025), (0.004, 0.028), (0, 0.045), (0, 0.085), (0.010, FRAME_TOP), (0.032, FRAME_TOP),
                  (0.040, 0.094), (0.046, 0.094), (0.050, DECK)],
            ["GOLD", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD_SATIN", "GOLD_SATIN", "CREAM"], K.tf(),
            cap0="GOLD_SATIN", cap1="CREAM", center=(0, 0))
    # four feet: the base rests on their apexes at z = 0
    for sx in (-1, 1):
        for sy in (-1, 1):
            P5.dome(B, K.frame((sx * 0.29, sy * 0.29, 0.035), (0, 0, -1), (0, 1, 0)), 0.045, 12, 0.0, 0.025, 0.010 / math.sin(math.radians(75)), "GOLD",
                    top="GOLD_SATIN")
    # scalloped cream panel with a gold rim
    sc = scallop(0.24)
    B.sweep(sc, [(0, 0.096), (0, 0.118), (0.006, RIM_TOP), (0.014, RIM_TOP), (0.020, 0.116), (0.020, 0.096)],
            ["GOLD"] * 6, K.tf(), closed=True, center=(0, 0))
    B.sweep(sc, [(0.016, 0.096), (0.016, PANEL_TOP)], ["CREAM"], K.tf(), cap0="CREAM", cap1="CREAM", center=(0, 0))
    # four gold chevrons pointing outward (the "step here" direction cue)
    for k in range(4):
        M = K.R("Z", 90 * k - 90) @ K.tf((0, 0.165, 0))
        B.sweep(chevron(), [(0, 0.108), (0, 0.124), (0.004, 0.128)], ["GOLD", "GOLD"], M, cap0="GOLD", cap1="GOLD",
                mode="miter")
    # gold bezel around the pressure plate (the plate itself is the Trigger mesh)
    B.sweep(K.rrect(0.128, 0.128, 0.040, 4), [(0, 0.108), (0, 0.142), (0.008, BEZEL_TOP), (0.020, BEZEL_TOP),
                                              (0.025, 0.140), (0.025, 0.108)], ["GOLD"] * 6, K.tf(), closed=True)
    # coral indicator on the deck, front-right corner
    B.sweep(K.rrect(0.036, 0.014, 0.012, 3), [(0, 0.098), (0, 0.116), (0.004, 0.120)], ["CORAL_ENAMEL", "CORAL_ENAMEL"],
            K.tf((0.335, -0.335, 0)) @ K.R("Z", 45), cap0="CORAL_ENAMEL", cap1="CORAL_ENAMEL")
    # hinge axle bosses with pearl caps, on stems rising from the frame
    for sx in (-1, 1):
        x0, x1 = sx * PIN_X0, sx * PIN_X1
        Mp = K.frame((x0, YH, ZH), (sx, 0, 0), (0, 0, 1))
        B.sweep(K.circle(PIN_R, 16), [(0, 0.0), (0, PIN_X1 - PIN_X0 - 0.008), (0.008, PIN_X1 - PIN_X0)],
                ["GOLD", "GOLD"], Mp, cap0="GOLD", cap1="GOLD_SATIN")
        P5.dome(B, K.frame((x1, YH, ZH), (sx, 0, 0), (0, 0, 1)), 0.034, 14, -0.006, 0.004, 0.024, "PEARL")
        B.sweep(K.rrect((PIN_X1 - PIN_X0) / 2 - 0.004, 0.026, 0.008, 2), [(0, 0.080), (0, ZH)], ["GOLD"],
                K.tf(((x0 + x1) / 2, YH, 0)), cap0="GOLD", cap1="GOLD")
    return B


def build_trigger():
    T = K.Builder()
    T.sweep(K.rrect(0.100, 0.100, 0.034, 4), [(0, PLATE_BOT), (0, PLATE_TOP - 0.008), (0.008, PLATE_TOP)],
            ["COBALT", "COBALT"], K.tf(), cap0="COBALT", cap1="COBALT")
    return T


# ---------------------------------------------------------------- validation helpers
def bvh_world(ob):
    co, tris = D2.world_tris(ob)
    return co, BVHTree.FromPolygons(co, tris)


def pair(a, b):
    ca, ta = bvh_world(a)
    cb, tb = bvh_world(b)
    d = min(min(tb.find_nearest(p)[3] for p in ca[::2]), min(ta.find_nearest(p)[3] for p in cb[::2]))
    return round(d, 4), len(ta.overlap(tb))


def snapshot():
    out = {}
    for dp, _, fs in os.walk(KIT):
        for f in fs:
            p = os.path.relpath(os.path.join(dp, f), KIT)
            if p == "README.md" or "v007" in p or "__pycache__" in p or p.endswith(".blend1"):
                continue
            out[p] = hashlib.sha256(open(os.path.join(KIT, p), "rb").read()).hexdigest()
    return out


def set_pose(loop, trig, deg, depress):
    loop.rotation_euler = (math.radians(deg), 0, 0)
    trig.location = REST["trigger"] - Vector((0, 0, TRIGGER_TRAVEL if depress else 0))
    bpy.context.view_layer.update()


def world_co(obs):
    return np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in obs])


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

    coll = bpy.data.collections.new("PGK_SnareTrap")
    scene.collection.children.link(coll)
    root = D2.new_root(scene, "SnareTrap_Root", coll)
    Bb = build_base()
    Bl, yf = build_loop()
    Bt = build_trigger()
    base = K.finish_mesh("SnareTrap_Base", Bb, coll, root, mat, 1.0)
    loop = K.finish_mesh("SnareTrap_Loop", Bl, coll, root, mat, 1.0)          # UVs projected in item space
    trig = K.finish_mesh("SnareTrap_Trigger", Bt, coll, root, mat, 1.0)
    hinge = Vector((0, YH, ZH))
    loop.data.transform(Matrix.Translation(-hinge))
    loop.location = hinge
    tpiv = Vector((0, 0, PLATE_TOP))
    trig.data.transform(Matrix.Translation(-tpiv))
    trig.location = tpiv
    REST["trigger"] = tpiv.copy()
    bpy.context.view_layer.update()
    obs = [base, loop, trig]

    # ---------------- checks, armed + activated
    meshes = {}
    for ob in obs:
        me = ob.data
        cl = np.zeros(len(me.polygons), int)
        me.attributes["kit_class"].data.foreach_get("value", cl)
        co = np.array([(ob.matrix_world @ v.co)[:] for v in me.vertices])
        meshes[ob.name] = {"export_name": ob.name, "triangles": len(me.polygons), "vertices": len(me.vertices),
                           "material": me.materials[0].name, "material_slots": len(me.materials),
                           "atlas_cells": sorted({D2.CLASSES[c] for c in cl}), "uv_bounds": D2.uv_bounds(ob),
                           "origin_m": [round(x, 5) for x in ob.location], "local_rotation_deg": [0, 0, 0],
                           "local_scale": [1, 1, 1], "bounds_m": [round(x, 4) for x in co.max(0) - co.min(0)],
                           **K.mesh_checks(ob)}
    armed_co = world_co(obs)
    armed_dims = armed_co.max(0) - armed_co.min(0)
    armed_pairs = {f"{a.name} - {b.name}": pair(a, b) for a, b in ((base, loop), (base, trig), (loop, trig))}
    radial = float(np.sqrt(armed_co[:, 0] ** 2 + armed_co[:, 1] ** 2).max())
    feet_min_z = float(armed_co[:, 2].min())
    set_pose(loop, trig, ACTIVATED_DEG, True)
    act_co = world_co(obs)
    act_dims = act_co.max(0) - act_co.min(0)
    act_pairs = {f"{a.name} - {b.name}": pair(a, b) for a, b in ((base, loop), (base, trig), (loop, trig))}
    # loop sweep envelope 0..90 deg
    sweep, env_lo, env_hi = [], np.full(3, 1e9), np.full(3, -1e9)
    for deg in range(0, int(ACTIVATED_DEG) + 1, 5):
        set_pose(loop, trig, deg, False)
        lco = world_co([loop])
        env_lo, env_hi = np.minimum(env_lo, lco.min(0)), np.maximum(env_hi, lco.max(0))
        d, n = pair(base, loop)
        sweep.append({"angle_deg": deg, "loop_min_z_m": round(float(lco[:, 2].min()), 4), "clearance_to_base_m": d,
                      "intersections": n})
    # R15 proxy on the pressure plate, activated pose
    set_pose(loop, trig, ACTIVATED_DEG, True)
    r15 = K.make_r15(coll, K.simple_mat("R15_Probe", (0.5, 0.5, 0.5)), name="_R15_probe")
    r15.location = (0, 0, PLATE_TOP - TRIGGER_TRAVEL)
    bpy.context.view_layer.update()
    r15_d, r15_n = pair(loop, r15)
    r15_trig_d, r15_trig_n = pair(base, r15)
    lco = world_co([loop])
    inner_w = 2 * (LX - TUBE_R)
    inner_h = (LY_BACK - TUBE_R) - (yf + TUBE_R)
    bpy.data.objects.remove(r15, do_unlink=True)
    set_pose(loop, trig, 0, False)
    n_float = sum(P5.floating_shells(o)[1] for o in obs if P5.floating_shells(o)[0] > 1)   # single-shell movers excluded
    info = {
        "reference": "Snare Trap turnaround attached to the v007 brief (banner reads 'SPRING LOOP')",
        "collection": coll.name, "root": root.name,
        "hierarchy": {"SnareTrap_Root": ["SnareTrap_Base", "SnareTrap_Loop", "SnareTrap_Trigger"]},
        "pivots": {
            "SnareTrap_Root": "footprint centre at floor level (feet apexes at z = 0)",
            "SnareTrap_Base": "aligned with the root (identity); stationary",
            "SnareTrap_Loop": {"location_m": [round(x, 4) for x in hinge], "pivot": "hinge-barrel axis centre",
                               "axis": "local +X (hinge axis, parallel to the front edge)",
                               "armed_rotation_deg": 0, "activated_rotation_deg": ACTIVATED_DEG,
                               "direction": "positive X rotation lifts the back of the loop up over the hinge"},
            "SnareTrap_Trigger": {"location_m": [round(x, 4) for x in tpiv], "pivot": "top centre of the pressure plate",
                                  "travel": f"-Z by {TRIGGER_TRAVEL} m when activated (top ends just below the bezel)"}},
        "poses": {"armed": {"loop_deg": 0, "trigger_dz_m": 0},
                  "activated": {"loop_deg": ACTIVATED_DEG, "trigger_dz_m": -TRIGGER_TRAVEL}},
        "meshes": meshes, "mesh_count": 3,
        "triangles_total": sum(m["triangles"] for m in meshes.values()),
        "armed_bounds_m": [round(x, 4) for x in armed_dims], "armed_bounds_studs": [round(x / STUD, 2) for x in armed_dims],
        "activated_bounds_m": [round(x, 4) for x in act_dims], "activated_bounds_studs": [round(x / STUD, 2) for x in act_dims],
        "activated_height_studs": round(float(act_co[:, 2].max()) / STUD, 2),
        "floor": {"min_z_m": round(feet_min_z, 5), "sits_on": "four gold feet"},
        "footprint": {"armed_max_radius_m": round(radial, 4), "armed_max_radius_studs": round(radial / STUD, 2),
                      "review_tile_radius_studs": round(TILE_R / STUD, 2), "fits_review_tile": radial <= TILE_R,
                      "recommended_collision": "one invisible, non-colliding Part sized to the armed footprint "
                                               "(3.0 x 3.0 x 1.0 studs) for touch detection; keep all meshes "
                                               "CanCollide = false (CollisionFidelity = Box)"},
        "armed_pairs": {k: {"min_clearance_m": v[0], "intersections": v[1]} for k, v in armed_pairs.items()},
        "activated_pairs": {k: {"min_clearance_m": v[0], "intersections": v[1]} for k, v in act_pairs.items()},
        "loop_sweep": {"step_deg": 5, "samples": sweep,
                       "min_clearance_to_base_m": min(s["clearance_to_base_m"] for s in sweep),
                       "intersections": sum(s["intersections"] for s in sweep),
                       "min_z_m": min(s["loop_min_z_m"] for s in sweep),
                       "envelope_min_m": [round(x, 4) for x in env_lo], "envelope_max_m": [round(x, 4) for x in env_hi],
                       "envelope_size_studs": [round(x / STUD, 2) for x in env_hi - env_lo]},
        "r15_activated": {"proxy": "5.2-stud blocky R15 standing on the depressed pressure plate",
                          "loop_to_r15_min_clearance_m": r15_d, "loop_r15_intersections": r15_n,
                          "base_r15_intersections": r15_trig_n,
                          "loop_inner_opening_m": [round(inner_w, 3), round(inner_h, 3)],
                          "loop_inner_opening_studs": [round(inner_w / STUD, 2), round(inner_h / STUD, 2)],
                          "r15_extent_studs": {"torso_width": 2.0, "arm_span": 4.0, "height": 5.2},
                          "encloses_r15": False,
                          "note": "the raised loop stands over the front hinge and frames the player from the front; "
                                  "within the 3.5-4.5-stud activated height it cannot enclose a 5.2-stud R15"},
        "floating_shells": n_float,
        "floating_note": "counted within multi-shell meshes; the one-shell Trigger is a moving part held in its bezel (see activated/armed pairs)",
        "coplanar_overlap_pairs": D2.zfight_world(obs),
    }
    print("ITEM SnareTrap", info["triangles_total"], {k: v["triangles"] for k, v in meshes.items()},
          "armed", info["armed_bounds_studs"], "act", info["activated_bounds_studs"], "zf", info["coplanar_overlap_pairs"],
          "float", n_float, {k: (v["inverted_shells"], v["non_manifold_edges"], v["degenerate_tris"], v["uv_bounds"]) for k, v in meshes.items()},
          "armedpairs", armed_pairs, "actpairs", act_pairs, "sweep", info["loop_sweep"]["min_clearance_to_base_m"],
          info["loop_sweep"]["intersections"], info["loop_sweep"]["min_z_m"], "r15", r15_d, r15_n, r15_trig_n,
          "radial", round(radial / STUD, 2), "floor", round(feet_min_z, 4))
    manifest = {"kit": "PartyGameItemKit", "version": VERSION, "stage": "review-7 (Snare Trap)",
                "builds_on": {"scripts": ["source/build_item_kit.py", "source/build_dice_family_v002.py",
                                          "source/build_pickpocket_v005.py"]},
                "units": {"blender": "metres", "stud_m": STUD},
                "atlas": {"maps": {k: os.path.relpath(p, KIT) for k, p in paths.items()}, "new_cells": [],
                          "note": "v002 atlas unchanged: CREAM, GOLD, GOLD_SATIN, COBALT, TEAL, CORAL_ENAMEL, PEARL"},
                "material": "PGK_KitAtlas (one slot per mesh, v002 maps)", "items": {"SnareTrap": info}}

    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    fp = os.path.join(K.D["export"], f"SnareTrap_{VERSION}.fbx")
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
    for nm, f in (("Pickpocket", "Pickpocket_v005.fbx"), ("CrownHeist", "CrownHeist_v006.fbx")):
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
    items = {"SnareTrap": {"root": root, "meshes": obs}, **refs}

    def park():
        for it in items.values():
            it["root"].location = (50, 50, -50)
            it["root"].rotation_euler = (0, 0, 0)
    park()
    root.location = (0, 0, peds[1][1])
    bpy.context.view_layer.update()
    blend = os.path.join(K.D["source"], f"PartyGameItemKit_SnareTrap_{VERSION}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["blend"] = os.path.relpath(blend, KIT)
    manifest["review_helpers"] = {"collections": ["Review_Helpers", "Reference_Items", "Review_Stage"],
                                  "excluded_from_exports": True}
    if STAGE == "full":
        render_reviews(scene, cam, floor, items, peds, r15, manifest, park, loop, trig)
        park()
        set_pose(loop, trig, 0, False)
        root.location = (0, 0, peds[1][1])
        for o in bpy.data.objects:
            o.hide_render = False
        bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["renders"] = sorted(os.path.relpath(os.path.join(RD, f), KIT) for f in os.listdir(RD) if f.endswith(".png"))
    manifest["validation"] = roundtrip(fp, manifest)
    expected = [manifest["blend"], "source/build_snare_trap_v007.py", info["fbx"], "validation/fbx_roundtrip_v007.json"] + \
        list(manifest["atlas"]["maps"].values())
    manifest["missing_files"] = [f for f in expected if not os.path.exists(os.path.join(KIT, f))]
    manifest["renders_expected"] = 17
    manifest["renders_missing"] = 17 - len(manifest["renders"])
    after = snapshot()
    changed = sorted(f for f in before if after.get(f) != before[f])
    manifest["v001_v006_files_checked"] = len(before)
    manifest["v001_v006_files_unchanged"] = not changed
    manifest["v001_v006_files_changed"] = changed
    with open(os.path.join(KIT, f"manifest_{VERSION}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("PRIOR unchanged:", not changed, len(before), changed, "missing:", manifest["missing_files"],
          "renders:", len(manifest["renders"]))
    print("DONE in %.0fs" % (time.time() - t0))


def roundtrip(fp, manifest):
    exp = manifest["items"]["SnareTrap"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fp)
    bpy.context.view_layer.update()
    obs = list(bpy.context.scene.objects)
    meshes = [o for o in obs if o.type == "MESH"]
    roots = [o for o in obs if o.parent is None]
    co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
    dims = co.max(0) - co.min(0)
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
    floor_z = float(co[:, 2].min() - root_w[2])
    rec = {"file": os.path.relpath(fp, KIT), "bytes": os.path.getsize(fp),
           "importer": f"Blender {bpy.app.version_string} FBX importer",
           "hierarchy": {o.name: o.parent.name if o.parent else None for o in obs},
           "root_matches": len(roots) == 1 and roots[0].name == "SnareTrap_Root",
           "names_match": sorted(per) == sorted(exp["meshes"]), "mesh_count": len(meshes),
           "helpers_present": [o.name for o in obs if o.name.startswith(("R15", "ShopPedestal", "_", "Floor", "ref_"))],
           "meshes": per, "world_bounds_m": [round(float(x), 4) for x in dims], "source_armed_bounds_m": exp["armed_bounds_m"],
           "bounds_match_2mm": bool(np.allclose(sorted(dims), sorted(exp["armed_bounds_m"]), atol=2e-3)),
           "floor_relative_to_root_m": round(floor_z, 5), "root_at_floor_2mm": abs(floor_z) <= 2e-3,
           "embedded_images": sorted({i.name for i in bpy.data.images})}
    rec["pass"] = bool(rec["root_matches"] and rec["names_match"] and rec["bounds_match_2mm"] and rec["root_at_floor_2mm"]
                       and not rec["helpers_present"]
                       and all(p["triangles_match"] and p["uv_in_0_1"] and p["uv_layers"] == 1 and p["material_slots"] == 1
                               and p["pivot_matches_source_2mm"] and p["bounds_match_2mm"] and p["local_rotation_scale_identity"]
                               and p["triangles"] < 6000 for p in per.values()))
    with open(os.path.join(K.D["validation"], f"fbx_roundtrip_{VERSION}.json"), "w") as f:
        json.dump({"version": VERSION, "items": {"SnareTrap": rec}}, f, indent=2)
    print("ROUNDTRIP SnareTrap", rec["pass"], rec["hierarchy"], rec["world_bounds_m"], rec["floor_relative_to_root_m"])
    return {"SnareTrap": rec["pass"]}


# ---------------------------------------------------------------- renders
def render_reviews(scene, cam, floor, items, peds, r15, manifest, park, loop, trig):
    from bpy_extras.object_utils import world_to_camera_view
    tmp = os.path.join(RD, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    tp = lambda n: os.path.join(tmp, n + ".png")  # noqa: E731
    objs = lambda it: set(it["meshes"]) | {it["root"]}  # noqa: E731
    S = items["SnareTrap"]
    st = objs(S)
    vis = K.set_render_vis
    info = manifest["items"]["SnareTrap"]
    views = {"front": (0, -1, 0.0), "back": (0, 1, 0.0), "left": (-1, 0, 0.0), "right": (1, 0, 0.0), "top": (0, -0.001, 1),
             "three_quarter": (0.75, -1, 0.75), "act_three_quarter": (0.9, -1, 0.45)}
    o_arm = 0.95 * 1.12
    o_act = 1.15 * 1.10

    def save(im, fn, title, sub):
        K.header(im, title, sub).save(os.path.join(RD, fn))

    def solo(deg=0, depress=False):
        park()
        S["root"].location = (0, 0, 0)
        set_pose(loop, trig, deg, depress)
        vis(st | {floor})

    def ortho(k, target_z, scale, size=(1000, 560), name=None):
        K.aim(cam, (0, 0, target_z), views[k], 6.0, ortho=scale)
        im = K.do_render(scene, tp((name or k) + str(scale)), *size)
        return K.label(im, (name or k).replace("_", " ").upper())

    solo()
    for i, (k, fn) in enumerate((("front", "01_front_ortho_armed.png"), ("back", "02_back_ortho_armed.png"),
                                 ("left", "03_left_side_armed.png"), ("right", "04_right_side_armed.png"))):
        save(ortho(k, 0.12, o_arm), fn, f"Snare Trap - {k} (armed, orthographic)",
             f"Armed {info['armed_bounds_studs'][0]:.2f} W x {info['armed_bounds_studs'][1]:.2f} D x {info['armed_bounds_studs'][2]:.2f} H studs; resting on four gold feet")
    K.aim(cam, (0, 0, 0.1), views["top"], 6.0, ortho=o_arm)
    save(K.label(K.do_render(scene, tp("top"), 900, 900), "TOP"), "05_top_armed.png", "Snare Trap - top (armed)",
         "Scalloped cream panel, four outward chevrons, cobalt pressure plate; teal loop folded around it; hinge at the front")
    K.aim(cam, (0, -0.02, 0.12), views["three_quarter"], 2.6, lens=50)
    save(K.do_render(scene, tp("hero"), 1400, 1000), "06_hero_three_quarter.png", "Snare Trap - hero three-quarter",
         "Padded teal loop folded over the gold-framed cream base; gold hinge barrel with pearl axle caps; coral indicator")
    solo(info["poses"]["activated"]["loop_deg"], True)
    K.aim(cam, (0, -0.15, 0.50), views["act_three_quarter"], 3.6, lens=50)
    save(K.do_render(scene, tp("activated"), 1400, 1000), "07_activated_pose.png", "Snare Trap - activated pose",
         f"Loop swung +{ACTIVATED_DEG:.0f} deg about the hinge to stand {info['activated_height_studs']:.2f} studs tall; plate depressed {TRIGGER_TRAVEL * 1000:.0f} mm")
    ims = []
    for deg, dep, lab in ((0, False, "ARMED"), (ACTIVATED_DEG, True, "ACTIVATED")):
        solo(deg, dep)
        K.aim(cam, (0, -0.1, 0.45), views["act_three_quarter"], 3.6, lens=50)
        ims.append(K.label(K.do_render(scene, tp("cmp" + lab), 800, 800), lab))
    save(K.hstack(ims), "08_armed_vs_activated.png", "Armed vs activated",
         f"Armed {info['armed_bounds_studs'][2]:.2f} studs tall  ->  activated {info['activated_height_studs']:.2f} studs tall")
    # envelope: side ortho, loop at 0/30/60/90 blended, hinge marker and envelope box
    frames = []
    for deg in (0, 30, 60, 90):
        solo(deg, False)
        K.aim(cam, (0, 0.0, 0.52), views["right"], 6.0, ortho=1.45)
        frames.append(K.do_render(scene, tp(f"env{deg}"), 1000, 1000))
    im = frames[0]
    for f in frames[1:]:
        im = Image.blend(im, f, 0.35)
    dr = ImageDraw.Draw(im)
    px = lambda p: ((lambda q: (q.x * 1000, (1 - q.y) * 1000))(world_to_camera_view(scene, cam, Vector(p))))  # noqa: E731
    lo, hi = info["loop_sweep"]["envelope_min_m"], info["loop_sweep"]["envelope_max_m"]
    corners = [px((hi[0], lo[1], lo[2])), px((hi[0], hi[1], lo[2])), px((hi[0], hi[1], hi[2])), px((hi[0], lo[1], hi[2]))]
    dr.polygon(corners, outline=(200, 60, 40))
    hx, hy = px(info["pivots"]["SnareTrap_Loop"]["location_m"])
    dr.ellipse((hx - 12, hy - 12, hx + 12, hy + 12), outline=(20, 20, 20), width=4)
    dr.text((hx + 14, hy - 4), "hinge axis (loop pivot, local X)", fill=(20, 20, 20), font=K.font(18, True))
    dr.text((corners[2][0] - 330, corners[2][1] + 6), "loop sweep envelope 0-90 deg", fill=(170, 50, 30), font=K.font(18, True))
    sw = info["loop_sweep"]
    save(im, "09_loop_pivot_envelope.png", "Loop pivot and movement envelope (right side, orthographic)",
         f"Loop at 0/30/60/90 deg; envelope {sw['envelope_size_studs'][0]:.2f} x {sw['envelope_size_studs'][1]:.2f} x {sw['envelope_size_studs'][2]:.2f} studs; "
         f"min clearance to base {sw['min_clearance_to_base_m'] * 1000:.1f} mm, {sw['intersections']} intersections")
    ims = []
    for dep, lab in ((False, "ARMED (plate up)"), (True, f"PRESSED (-{TRIGGER_TRAVEL * 1000:.0f} mm)")):
        solo(0, dep)
        K.aim(cam, (0.0, -0.02, 0.14), (0.55, -1, 0.55), 0.62, lens=85)
        ims.append(K.label(K.do_render(scene, tp("trig" + str(dep)), 760, 760), lab, pos="bottom"))
    save(K.hstack(ims), "10_trigger_closeup.png", "Trigger close-up",
         "Cobalt pressure plate in its gold bezel travels straight down; 2 mm floor gap and 3 mm side gap remain when pressed")
    # R15 clearance
    park()
    S["root"].location = (0, 0, 0)
    set_pose(loop, trig, ACTIVATED_DEG, True)
    r15.location = (0, 0, PLATE_TOP - TRIGGER_TRAVEL)
    bpy.context.view_layer.update()
    vis(st | {r15, floor})
    ims = []
    for k, d in (("front", (0, -1, 0.05)), ("side", (1, 0, 0.05))):
        K.aim(cam, (0, -0.05, 0.85), d, 6.0, ortho=1.95)
        ims.append(K.label(K.do_render(scene, tp("r15" + k), 800, 900), k.upper()))
    r = info["r15_activated"]
    save(K.hstack(ims), "11_r15_clearance.png", "R15 clearance (activated)",
         f"R15 on the pressed plate: loop clearance {r['loop_to_r15_min_clearance_m'] * 1000:.0f} mm, 0 intersections; loop opening "
         f"{r['loop_inner_opening_studs'][0]:.2f} x {r['loop_inner_opening_studs'][1]:.2f} studs frames, but cannot enclose, a 5.2-stud R15")
    r15.location = (-4.6, 0, 0)
    # board footprint
    park()
    board = []
    tm = [K.simple_mat("TileBlue", (0.15, 0.35, 0.90), 0.5), K.simple_mat("TileCream", (0.95, 0.88, 0.72), 0.5),
          K.simple_mat("TileRed", (0.92, 0.30, 0.25), 0.5)]

    def tile(x, y, k):
        tb = K.Builder()
        tb.sweep(K.circle(TILE_R, 48), [(0, 0.0), (0, 0.12), (0.03, 0.15)], ["CREAM", "CREAM"], K.tf((x, y, 0)),
                 cap0="CREAM", cap1="CREAM")
        me = bpy.data.meshes.new(f"_tile{k}")
        tb.bm.to_mesh(me)
        tb.bm.free()
        me.materials.append(tm[k % 3])
        o = bpy.data.objects.new(f"_tile{k}", me)
        scene.collection.objects.link(o)
        board.append(o)
    for k, x in enumerate((-5 * STUD, 0, 5 * STUD)):
        tile(x, 0, k)
    S["root"].location = (0, 0, 0.15)
    set_pose(loop, trig, 0, False)
    vis(st | set(board) | {floor})
    K.aim(cam, (0, 0, 0.15), views["top"], 6.0, ortho=3.4)
    im = K.do_render(scene, tp("foot"), 1400, 800)
    dr = ImageDraw.Draw(im)
    pf = lambda p: ((lambda q: (q.x * 1400, (1 - q.y) * 800))(world_to_camera_view(scene, cam, Vector(p))))  # noqa: E731
    c0 = pf((0, 0, 0.27))
    cr = pf((info["footprint"]["armed_max_radius_m"], 0, 0.27))
    rr = abs(cr[0] - c0[0])
    dr.ellipse((c0[0] - rr, c0[1] - rr, c0[0] + rr, c0[1] + rr), outline=(200, 60, 40), width=3)
    f = info["footprint"]
    save(im, "12_board_space_footprint.png", "Board-space footprint (top)",
         f"Armed trap reaches {f['armed_max_radius_studs']:.2f} studs from centre (red) on a {f['review_tile_radius_studs']:.1f}-stud-radius review space; neighbours 5 studs apart stay clear")
    for o in board:
        bpy.data.objects.remove(o, do_unlink=True)
    board.clear()
    # shop comparison
    park()
    order = ["Pickpocket", "SnareTrap", "CrownHeist"]
    for i, n in enumerate(order):
        ped, Hp = peds[i]
        z = {"Pickpocket": 1.0 / 2 + 0.02, "SnareTrap": 0.0, "CrownHeist": 1.306 / 2 + 0.15}[n]
        items[n]["root"].location = ((i - 1) * 1.9, 0, Hp + z)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    set_pose(loop, trig, 0, False)
    vis(st | objs(items["Pickpocket"]) | objs(items["CrownHeist"]) | {p for p, _ in peds} | {floor})
    K.aim(cam, (0, 0, 1.2), (0.15, -1, 0.42), 10.2, lens=50)
    save(K.do_render(scene, tp("shop"), 1800, 1050), "13_shop_scale_comparison.png", "Shop/item-scale comparison",
         "Pickpocket | Snare Trap (armed) | Crown Heist on standard 4.5-stud pedestals")
    # gameplay distance
    park()
    tiles = [((k - 4) * 5 * STUD, 2.0 * math.sin(k * 0.8) * STUD) for k in range(9)]
    for k, (x, y) in enumerate(tiles):
        tile(x, y, k)
    for k, (x, y) in enumerate([tiles[3], tiles[6]]):
        fg = K.make_r15(scene.collection, bpy.data.materials["R15_Clay"], name=f"_fig{k}")
        fg.location = (x + 0.15, y + 0.9, 0.15)
        board.append(fg)
    S["root"].location = (tiles[4][0], tiles[4][1], 0.15)
    S["root"].rotation_euler = (0, 0, 0)
    items["Pickpocket"]["root"].location = (tiles[1][0], tiles[1][1], 0.15 + 2.8 * STUD)
    items["CrownHeist"]["root"].location = (tiles[7][0], tiles[7][1], 0.15 + 3.0 * STUD)
    set_pose(loop, trig, 0, False)
    vis(st | objs(items["Pickpocket"]) | objs(items["CrownHeist"]) | set(board) | {floor})
    K.aim(cam, (0, 0.4, 0.6), (0, -1, 1.05), 15.5, lens=35)
    full = K.do_render(scene, tp("gameplay"), 1280, 720)
    q = world_to_camera_view(scene, cam, S["root"].matrix_world.translation + Vector((0, 0, 0.1)))
    cx, cy = int(q.x * 1280), int((1 - q.y) * 720)
    crop = full.crop((cx - 70, cy - 50, cx + 70, cy + 50)).resize((420, 300), Image.NEAREST)
    bar = Image.new("RGB", (420, 34), (246, 240, 228))
    ImageDraw.Draw(bar).text((8, 8), "Snare Trap on its space (140x100 px, x3)", fill=(70, 52, 30), font=K.font(14, True))
    save(K.hstack([full, K.vstack([crop, bar])]), "14_gameplay_distance.png", "Normal gameplay-distance view",
         "Board camera ~15 m (54 studs), 35 mm; armed trap sitting on a board space between other items and players")
    for o in board:
        bpy.data.objects.remove(o, do_unlink=True)
    # material close-up
    solo()
    ims = []
    for tgt, d, dd, t1, t2 in (((0.0, -0.39, 0.20), (0.35, -1, 0.35), 0.55, "HINGE", "gold barrel + satin grooves, pearl axle caps, padded teal"),
                               ((0.0, 0.0, 0.14), (0.2, -0.6, 1), 0.65, "PANEL", "cream enamel, gold rim + chevrons, cobalt plate, gold bezel"),
                               ((0.33, -0.33, 0.11), (0.6, -1, 0.6), 0.45, "CORNER", "coral indicator, brushed gold frame, foot")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("mat" + t1), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "15_material_closeup.png", "Material close-up", "v002 atlas cells only; no new texture maps")
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
    ims = []
    for deg, dep, lab in ((0, False, "ARMED"), (ACTIVATED_DEG, True, "ACTIVATED")):
        solo(deg, dep)
        K.aim(cam, (0, -0.1, 0.40 if deg else 0.12), views["act_three_quarter"], 3.4 if deg else 2.4, lens=50)
        bpy.context.view_layer.update()
        vl.material_override = wire
        im = K.do_render(scene, tp("wire" + lab), 860, 860, samples=24)
        vl.material_override = None
        dr = ImageDraw.Draw(im)
        pz = lambda p: ((lambda q: (q.x * 860, (1 - q.y) * 860))(world_to_camera_view(scene, cam, Vector(p))))  # noqa: E731
        rx, ry = pz((0, 0, 0))
        for ax, col in (((0.2, 0, 0), (220, 40, 40)), ((0, 0.2, 0), (40, 160, 40)), ((0, 0, 0.2), (40, 80, 230))):
            ex, ey = pz(ax)
            dr.line((rx, ry, ex, ey), fill=col, width=5)
        dr.ellipse((rx - 10, ry - 10, rx + 10, ry + 10), outline=(20, 20, 20), width=4)
        hx0, hy0 = pz((-0.3, YH, ZH))
        hx1, hy1 = pz((0.3, YH, ZH))
        dr.line((hx0, hy0, hx1, hy1), fill=(200, 60, 40), width=4)
        tx, ty = pz(tuple(trig.matrix_world.translation))
        dr.line((tx, ty - 14, tx, ty + 30), fill=(150, 20, 90), width=4)
        dr.text((rx + 12, ry + 6), "Root (floor centre)", fill=(20, 20, 20), font=K.font(15, True))
        dr.text((hx1 + 6, hy1 - 8), "Loop hinge axis", fill=(170, 50, 30), font=K.font(15, True))
        dr.text((tx + 8, ty - 30), "Trigger (-Z)", fill=(150, 20, 90), font=K.font(15, True))
        ims.append(K.label(im, lab, pos="bottom"))
    im = K.hstack(ims)
    dr = ImageDraw.Draw(im)
    dr.text((18, 14), "SnareTrap", fill=(30, 30, 60), font=K.font(30, True))
    for i, t in enumerate([f"{info['triangles_total']:,} tris total  |  3 meshes  |  1 material slot each"] +
                          [f"{n}: {m['triangles']:,}" for n, m in info["meshes"].items()]):
        dr.text((18, 56 + i * 24), t, fill=(40, 40, 70), font=K.font(19))
    save(im, "16_wireframe_pivots.png", "Wireframe and pivots", "Base stationary; loop rotates about the hinge axis; trigger travels -Z")
    # contact sheet
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*K.BG_NEUTRAL, 1)
    fbn = floor.data.materials[0].node_tree.nodes["Principled BSDF"]
    old = tuple(fbn.inputs["Base Color"].default_value)
    fbn.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    solo()
    row1 = []
    for k in ("front", "back", "left", "right"):
        K.aim(cam, (0, 0, 0.12), views[k], 6.0, ortho=o_arm)
        row1.append(K.label(K.do_render(scene, tp("cs" + k), 480, 300), k.upper()))
    row2 = []
    K.aim(cam, (0, 0, 0.1), views["top"], 6.0, ortho=o_arm)
    row2.append(K.label(K.do_render(scene, tp("cstop"), 480, 480), "TOP"))
    K.aim(cam, (0, -0.02, 0.12), views["three_quarter"], 2.6, lens=50)
    row2.append(K.label(K.do_render(scene, tp("cs34"), 480, 480), "THREE-QUARTER"))
    solo(ACTIVATED_DEG, True)
    K.aim(cam, (0, -0.15, 0.5), views["act_three_quarter"], 3.6, lens=50)
    row2.append(K.label(K.do_render(scene, tp("csact"), 480, 480), "ACTIVATED"))
    K.aim(cam, (0, -0.05, 0.5), views["front"], 6.0, ortho=o_act)
    row2.append(K.label(K.do_render(scene, tp("csactf"), 480, 480), "ACTIVATED FRONT"))
    save(K.vstack([K.hstack(row1, bg=(205, 205, 205)), K.hstack(row2, bg=(205, 205, 205))], bg=(205, 205, 205)),
         "17_contact_sheet.png", "Neutral contact sheet", "armed: front | back | left | right  -  top | three-quarter  -  activated: three-quarter | front")
    bg.inputs["Color"].default_value = (*K.BG_WARM, 1)
    fbn.inputs["Base Color"].default_value = old
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
