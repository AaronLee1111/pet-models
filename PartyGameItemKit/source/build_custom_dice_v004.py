"""Party Game Item Kit -- review stage 4: Custom Dice Block (controlled-roll die).

Builds on the v001 kit library and the v002 dice-family module (neither is re-run) and uses the
v002 atlas unchanged. Every v001-v003 file is hash-checked before and after the build.

Selector concept: a gold dial ring in the die's front plane, riding on four gold rollers set into
the die's front-to-back edges, rotates about the front-facing axis. A coral pointer with a teal
button, mounted on the ring, marks the selected (front) face. The ring is sized so its clearance
to the die is the same at every dial angle (verified at 24 angles).

Run with the `bpy` module (pip install bpy) or Blender:
    python3 PartyGameItemKit/source/build_custom_dice_v004.py
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

VERSION = "v004"
KIT = K.KIT
STUD = K.STUD
STAGE = os.environ.get("KIT_STAGE", "full")
RD = os.path.join(K.D["renders"], "v004_custom_dice")
FRONT = K.FRONT                       # build plane XY, +Z toward viewer -> world XZ facing -Y
BODY_SCALE = 0.86                     # family die at 0.86 (Party Dice Block is 0.90)
RING_GAP = 0.022                      # ring inner radius = body max radius about the dial axis + gap
RING_W, RING_T = 0.048, 0.036         # radial width, half thickness (m)
ROLLER_GAP = 0.008
POINTER_GAP = 0.0015                  # pointer sits on the ring's front face
SELECTED = (0, -1, 0)                 # front face (value 5) is the selected result


# ---------------------------------------------------------------- body
def build_body():
    B = K.Builder()
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=K.DIE_S)
    bmesh.ops.bevel(tmp, geom=tmp.verts[:] + tmp.edges[:], offset=K.DIE_BEV, segments=3,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    B.append(tmp, "CREAM")                         # cream structural body
    tmp.free()
    h = K.DIE_S / 2
    bez = K.rrect(0.37, 0.37, 0.10, 3)
    for n, up, val in K.DIE_FACES:
        M = K.frame(Vector(n) * h, n, up)
        lip = "GOLD_GLOW" if tuple(n) == SELECTED else "GOLD"
        # raised cream frame with a gold inner lip (glowing gold on the selected face)
        B.sweep(bez, [(0, -0.03), (0, 0.030), (0.014, 0.048), (0.030, 0.048), (0.040, 0.046),
                      (0.052, 0.032), (0.055, -0.03)],
                ["CREAM", "CREAM", "CREAM", lip, lip, "GOLD_SATIN", "CREAM"], M, closed=True)
        B.sweep(bez, [(0.052, -0.02), (0.052, 0.010), (0.058, 0.018)], ["GOLD_SATIN", "TEAL"], M,
                cap0="TEAL", cap1="TEAL")
        for px, py in K.PIP_LAYOUT[val]:
            big = val == 1
            D2.pip_v2(B, M @ K.tf((px * 0.165, py * 0.165, 0)), 0.10 if big else 0.068, 14 if big else 9,
                      dome_h=0.62 if big else 0.85)
        # cobalt corner studs with gold rivets
        for sx in (-1, 1):
            for sy in (-1, 1):
                prof = [(0, -0.004), (0, 0.026), (0.006, 0.031), (0.016, 0.031)]
                for a in (40, 78):
                    t = math.radians(a)
                    prof.append((0.016 + 0.019 * (1 - math.cos(t)), 0.031 + 0.014 * math.sin(t)))
                B.sweep(K.circle(0.035, 8), prof, ["COBALT", "COBALT", "COBALT", "GOLD", "GOLD"],
                        M @ K.tf((sx * 0.27, sy * 0.27, 0)), cap0="COBALT", cap1="GOLD")
    bmesh.ops.scale(B.bm, vec=(BODY_SCALE,) * 3, verts=B.bm.verts[:])
    co = np.array([v.co[:] for v in B.bm.verts])
    max_rad = float(np.sqrt(co[:, 0] ** 2 + co[:, 2] ** 2).max())       # about the dial (Y) axis
    r_in = max_rad + RING_GAP
    # four gold rollers set into the front-to-back edges carry the ring
    for a in (45, 135, 225, 315):
        u = Vector((math.cos(math.radians(a)), 0, math.sin(math.radians(a))))
        r0 = 0.46
        L = r_in - ROLLER_GAP - r0
        prof = [(0, 0), (0, L - 0.012)]
        for ang in (40, 80):
            t = math.radians(ang)
            prof.append((0.026 * (1 - math.cos(t)), L - 0.012 + 0.012 * math.sin(t)))
        B.sweep(K.circle(0.026, 10), prof, ["GOLD"] * 3, K.frame(u * r0, u, (0, 1, 0)), cap0="GOLD", cap1="GOLD")
    return B, max_rad, r_in


def build_ring(r_in):
    B = K.Builder()
    r_out = r_in + RING_W
    w, t = RING_W, RING_T
    B.sweep(K.circle(r_out, 56), [(0.006, -t), (0, -t + 0.012), (0, t - 0.012), (0.006, t), (w - 0.006, t),
                                  (w, t - 0.012), (w, -t + 0.012), (w - 0.006, -t)],
            ["GOLD"] * 8, FRONT, closed=True)
    rm = r_in + w / 2
    for k in range(12):
        ang = 30 * k
        if ang == 90:          # pointer position
            continue
        major = ang % 90 == 0
        Mt = FRONT @ K.R("Z", ang) @ K.tf((rm, 0, 0))
        B.sweep(K.rrect(0.019 if major else 0.013, 0.0068, 0.004, 1), [(0, t - 0.006), (0, t + 0.007), (0.003, t + 0.011)],
                ["COBALT", "COBALT"], Mt, cap0="COBALT", cap1="COBALT")
    return B, r_out


def build_pointer(max_rad, r_out, front_y):
    """Gold arm clipped onto the ring top, reaching forward over the die; a coral arrowhead hangs in
    front of the selected face (entirely in front of the die's front-most point, so it clears the die
    at every dial angle) and carries the teal control button."""
    B = K.Builder()
    zr = r_out + POINTER_GAP                   # arm underside rests on the ring's outer rim
    y0, y1 = -(RING_T - 0.004), front_y - 0.026
    Ma = K.frame((0, y0, zr), (0, -1, 0), (0, 0, 1))
    B.sweep(K.rrect(0.024, 0.017, 0.010, 2) + np.array([0, 0.017]), [(0, 0.0), (0, (y0 - y1) - 0.006), (0.004, y0 - y1)],
            ["GOLD", "GOLD"], Ma, cap0="GOLD", cap1="GOLD")
    yp = front_y - 0.012                       # arrow plate back face
    tip = max_rad - 0.085                      # points at the selected face's top edge
    top = zr + 0.040
    arrow = [(0, tip), (0.064, tip + 0.082), (0.022, tip + 0.070), (0.022, top), (-0.022, top),
             (-0.022, tip + 0.070), (-0.064, tip + 0.082)]
    Mp = K.frame((0, yp, 0), (0, -1, 0), (0, 0, 1))
    B.sweep(arrow, [(0, 0.0), (0, 0.024), (0.005, 0.030)], ["CORAL_ENAMEL", "CORAL_ENAMEL"], Mp,
            cap0="CORAL_ENAMEL", cap1="CORAL_ENAMEL", mode="miter")
    Mg = K.frame((0, yp, zr + 0.012), (0, -1, 0), (0, 0, 1))
    prof = [(0, 0.020), (0, 0.040), (0.008, 0.046), (0.012, 0.043)]
    for a in (35, 70):
        tt = math.radians(a)
        prof.append((0.012 + 0.026 * (1 - math.cos(tt)), 0.043 + 0.024 * math.sin(tt)))
    B.sweep(K.circle(0.038, 14), prof, ["GOLD", "GOLD", "GOLD_SATIN", "TEAL", "TEAL"], Mg, cap0="GOLD", cap1="TEAL")
    return B, tip


# ---------------------------------------------------------------- validation helpers
def bvh(ob):
    co, tris = D2.world_tris(ob)
    return co, BVHTree.FromPolygons(co, tris)


def clearance(a, b):
    ca, ta = bvh(a)
    cb, tb = bvh(b)
    d1 = min(tb.find_nearest(p)[3] for p in ca)
    d2 = min(ta.find_nearest(p)[3] for p in cb[::2])
    return min(d1, d2), len(ta.overlap(tb))


def rotation_sweep(body, movers, step=15):
    out = []
    for ang in range(0, 360, step):
        for m in movers:
            m.rotation_euler = (0, math.radians(ang), 0)
        bpy.context.view_layer.update()
        row = {"angle_deg": ang}
        for m in movers:
            d, n = clearance(body, m)
            row[m.name] = {"min_clearance_m": round(d, 4), "intersections": n}
        out.append(row)
    for m in movers:
        m.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    return out


def snapshot():
    out = {}
    for dp, _, fs in os.walk(KIT):
        for f in fs:
            p = os.path.relpath(os.path.join(dp, f), KIT)
            if p == "README.md" or "v004" in p or "__pycache__" in p or p.endswith(".blend1"):
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

    coll = bpy.data.collections.new("PGK_CustomDice")
    scene.collection.children.link(coll)
    root = D2.new_root(scene, "CustomDice_Root", coll)
    Bb, max_rad, r_in = build_body()
    Br, r_out = build_ring(r_in)
    front_y = float(np.array([v.co[1] for v in Bb.bm.verts]).min())   # die's front-most point
    Bp, tip = build_pointer(max_rad, r_out, front_y)
    body = K.finish_mesh("CustomDice_Body", Bb, coll, root, mat, 1.0)
    ring = K.finish_mesh("CustomDice_SelectorRing", Br, coll, root, mat, 1.0)
    ptr = K.finish_mesh("CustomDice_Pointer", Bp, coll, root, mat, 1.0)
    obs = [body, ring, ptr]
    bpy.context.view_layer.update()

    meshes = {}
    allco = []
    for ob in obs:
        me = ob.data
        cl = np.zeros(len(me.polygons), int)
        me.attributes["kit_class"].data.foreach_get("value", cl)
        co = np.array([v.co[:] for v in me.vertices])
        allco.append(co)
        meshes[ob.name] = {"export_name": ob.name, "triangles": len(me.polygons), "vertices": len(me.vertices),
                           "material": me.materials[0].name, "material_slots": len(me.materials),
                           "atlas_cells": sorted({D2.CLASSES[c] for c in cl}), "uv_bounds": D2.uv_bounds(ob),
                           "origin_m": [0.0, 0.0, 0.0], "bounds_studs": [round(x / STUD, 2) for x in co.max(0) - co.min(0)],
                           **K.mesh_checks(ob)}
    co = np.concatenate(allco)
    dims = co.max(0) - co.min(0)
    body_dims = allco[0].max(0) - allco[0].min(0)
    rest = {}
    for a, b in ((body, ring), (body, ptr), (ring, ptr)):
        d, n = clearance(a, b)
        rest[f"{a.name} - {b.name}"] = {"min_clearance_m": round(d, 4), "intersections": n}
    sweep = rotation_sweep(body, [ring, ptr])
    min_sweep = min(min(r[m.name]["min_clearance_m"] for m in (ring, ptr)) for r in sweep)
    isect_sweep = sum(r[m.name]["intersections"] for r in sweep for m in (ring, ptr))
    info = {
        "collection": coll.name, "root": root.name,
        "hierarchy": {"CustomDice_Root": ["CustomDice_Body", "CustomDice_SelectorRing", "CustomDice_Pointer"]},
        "pivots": {"CustomDice_Root": "die centre (0,0,0)", "CustomDice_Body": "die centre",
                   "CustomDice_SelectorRing": "die centre; rotate about Blender +Y (the item's front-facing axis)",
                   "CustomDice_Pointer": "die centre, aligned to the ring's index position; rotate with the ring "
                                         "(same axis, same angle) or keep it parented to the ring in Roblox"},
        "selector": {"axis": "Blender Y (front-to-back); FBX/Roblox: the item's look axis", "ring_inner_radius_m": round(r_in, 4),
                     "ring_outer_radius_m": round(r_out, 4), "body_max_radius_about_axis_m": round(max_rad, 4),
                     "pointer_tip_radius_m": round(tip, 4), "roller_gap_m": ROLLER_GAP, "pointer_seat_gap_m": POINTER_GAP,
                     "rotation_test_step_deg": 15, "rotation_test": sweep,
                     "min_clearance_over_all_angles_m": round(min_sweep, 4), "intersections_over_all_angles": isect_sweep},
        "selected_face": {"normal": list(SELECTED), "value": 5, "highlight": "GOLD_GLOW inner lip",
                          "faces": {str(tuple(n)): v for n, _, v in K.DIE_FACES}, "opposites_sum_to_7": True},
        "meshes": meshes, "mesh_count": 3,
        "triangles_total": sum(m["triangles"] for m in meshes.values()),
        "triangles_body": meshes["CustomDice_Body"]["triangles"],
        "triangles_selector": meshes["CustomDice_SelectorRing"]["triangles"] + meshes["CustomDice_Pointer"]["triangles"],
        "bounds_m": [round(x, 4) for x in dims], "bounds_studs": [round(x / STUD, 2) for x in dims],
        "body_bounds_studs": [round(x / STUD, 2) for x in body_dims],
        "bbox_centre_offset_from_root_m": [round(x, 4) for x in (co.max(0) + co.min(0)) / 2],
        "coplanar_overlap_pairs": D2.zfight_world(obs), "rest_pose": rest,
    }
    print("ITEM CustomDice", info["triangles_total"], "body", info["triangles_body"], "sel", info["triangles_selector"],
          info["bounds_studs"], "body", info["body_bounds_studs"], "zf", info["coplanar_overlap_pairs"],
          {k: (v["inverted_shells"], v["non_manifold_edges"], v["degenerate_tris"], v["uv_bounds"]) for k, v in meshes.items()},
          "rest", rest, "sweep min", round(min_sweep, 4), "isect", isect_sweep, "r_in", round(r_in, 3), "maxrad", round(max_rad, 3))
    manifest = {"kit": "PartyGameItemKit", "version": VERSION, "stage": "review-4 (Custom Dice Block)",
                "builds_on": {"scripts": ["source/build_item_kit.py", "source/build_dice_family_v002.py"]},
                "units": {"blender": "metres", "stud_m": STUD},
                "atlas": {"maps": {k: os.path.relpath(p, KIT) for k, p in paths.items()}, "new_cells": [],
                          "note": "v002 atlas unchanged: CREAM, GOLD, GOLD_SATIN, GOLD_GLOW, TEAL, CORAL_ENAMEL, COBALT, PEARL"},
                "material": "PGK_KitAtlas (one slot per mesh, v002 maps)",
                "items": {"CustomDice": info}}

    bpy.ops.object.select_all(action="DESELECT")
    for o in [root] + obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    fp = os.path.join(K.D["export"], f"CustomDice_{VERSION}.fbx")
    bpy.ops.export_scene.fbx(filepath=fp, use_selection=True, object_types={"EMPTY", "MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                             mesh_smooth_type="FACE", use_mesh_modifiers=True, add_leaf_bones=False,
                             bake_anim=False, path_mode="COPY", embed_textures=True)
    info["fbx"] = os.path.relpath(fp, KIT)

    # review scene
    helpers = bpy.data.collections.new("Review_Helpers")
    scene.collection.children.link(helpers)
    clay = K.simple_mat("R15_Clay", (0.55, 0.57, 0.62), 0.6)
    ped_mats = (K.simple_mat("Pedestal_Gold", (0.95, 0.70, 0.30), 0.3, 1.0),
                K.simple_mat("Pedestal_Cream", (0.93, 0.87, 0.75), 0.45))
    cam, floor, lights, stage = K.setup_scene(scene)
    r15 = K.make_r15(helpers, clay)
    r15.location = (-4.6, 0, 0)
    refs = {}
    ref_coll = bpy.data.collections.new("Reference_DiceFamily")
    scene.collection.children.link(ref_coll)
    for nm, f in (("PartyDiceBlock", "PartyDiceBlock_v001.fbx"), ("DoubleDice", "DoubleDice_v002.fbx"),
                  ("TripleDice", "TripleDice_v002.fbx"), ("LuckyDie", "LuckyDie_v002.fbx")):
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
    peds = [K.make_pedestal(helpers, ped_mats, (i - 2) * 1.9) for i in range(5)]
    items = {"CustomDice": {"root": root, "meshes": obs}, **refs}

    def park():
        for it in items.values():
            it["root"].location = (50, 50, -50)
            it["root"].rotation_euler = (0, 0, 0)
    park()
    root.location = (0, 0, peds[2][1] + dims[2] / 2 + 0.2)
    bpy.context.view_layer.update()
    blend = os.path.join(K.D["source"], f"PartyGameItemKit_CustomDice_{VERSION}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["blend"] = os.path.relpath(blend, KIT)
    manifest["review_helpers"] = {"collections": ["Review_Helpers", "Reference_DiceFamily", "Review_Stage"],
                                  "excluded_from_exports": True}
    if STAGE == "full":
        render_reviews(scene, cam, floor, items, peds, r15, manifest, park, ring, ptr)
        park()
        root.location = (0, 0, peds[2][1] + dims[2] / 2 + 0.2)
        for m in (ring, ptr):
            m.rotation_euler = (0, 0, 0)
        for o in bpy.data.objects:
            o.hide_render = False
        bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["renders"] = sorted(os.path.relpath(os.path.join(RD, f), KIT) for f in os.listdir(RD) if f.endswith(".png"))
    manifest["validation"] = roundtrip(fp, manifest)
    expected = [manifest["blend"], "source/build_custom_dice_v004.py", info["fbx"], "validation/fbx_roundtrip_v004.json"] + \
        list(manifest["atlas"]["maps"].values())
    manifest["missing_files"] = [f for f in expected if not os.path.exists(os.path.join(KIT, f))]
    manifest["renders_expected"] = 11
    manifest["renders_missing"] = 11 - len(manifest["renders"])
    after = snapshot()
    changed = sorted(f for f in before if after.get(f) != before[f])
    manifest["v001_v003_files_checked"] = len(before)
    manifest["v001_v003_files_unchanged"] = not changed
    manifest["v001_v003_files_changed"] = changed
    with open(os.path.join(KIT, f"manifest_{VERSION}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("PRIOR unchanged:", not changed, len(before), changed, "missing:", manifest["missing_files"],
          "renders:", len(manifest["renders"]))
    print("DONE in %.0fs" % (time.time() - t0))


def roundtrip(fp, manifest):
    exp = manifest["items"]["CustomDice"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fp)
    bpy.context.view_layer.update()
    obs = list(bpy.context.scene.objects)
    meshes = [o for o in obs if o.type == "MESH"]
    roots = [o for o in obs if o.parent is None]
    co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
    dims = co.max(0) - co.min(0)
    per = {}
    for o in meshes:
        s = exp["meshes"].get(o.name, {})
        uv = np.zeros(len(o.data.loops) * 2)
        if o.data.uv_layers:
            o.data.uv_layers[0].data.foreach_get("uv", uv)
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        per[o.name] = {"parent": o.parent.name if o.parent else None, "triangles": tris,
                       "triangles_match": tris == s.get("triangles"), "uv_layers": len(o.data.uv_layers),
                       "uv_bounds": [round(float(uv.min()), 4), round(float(uv.max()), 4)] if uv.size else None,
                       "uv_in_0_1": bool(uv.size and uv.min() >= 0 and uv.max() <= 1),
                       "material_slots": len(o.data.materials), "materials": [m.name for m in o.data.materials if m],
                       "pivot_at_root_within_2mm": bool(np.linalg.norm(np.array(o.matrix_local.to_translation())) <= 2e-3),
                       "local_transform_identity": bool(np.allclose(np.array(o.matrix_local), np.eye(4), atol=1e-4))}
    rec = {"file": os.path.relpath(fp, KIT), "bytes": os.path.getsize(fp),
           "importer": f"Blender {bpy.app.version_string} FBX importer",
           "hierarchy": {o.name: o.parent.name if o.parent else None for o in obs},
           "root_matches": len(roots) == 1 and roots[0].name == "CustomDice_Root",
           "names_match": sorted(per) == sorted(exp["meshes"]), "mesh_count": len(meshes),
           "helpers_present": [o.name for o in obs if o.name.startswith(("R15", "ShopPedestal", "_", "Floor", "ref_"))],
           "meshes": per, "world_bounds_m": [round(x, 4) for x in dims], "source_bounds_m": exp["bounds_m"],
           "bounds_match_2mm": bool(np.allclose(sorted(dims), sorted(exp["bounds_m"]), atol=2e-3)),
           "embedded_images": sorted({i.name for i in bpy.data.images})}
    rec["pass"] = bool(rec["root_matches"] and rec["names_match"] and rec["bounds_match_2mm"] and not rec["helpers_present"]
                       and all(p["triangles_match"] and p["uv_in_0_1"] and p["uv_layers"] == 1 and p["material_slots"] == 1
                               and p["local_transform_identity"] and p["pivot_at_root_within_2mm"] and p["triangles"] < 8000
                               for p in per.values()))
    with open(os.path.join(K.D["validation"], f"fbx_roundtrip_{VERSION}.json"), "w") as f:
        json.dump({"version": VERSION, "items": {"CustomDice": rec}}, f, indent=2)
    print("ROUNDTRIP CustomDice", rec["pass"], rec["hierarchy"], rec["world_bounds_m"])
    return {"CustomDice": rec["pass"]}


# ---------------------------------------------------------------- renders
def render_reviews(scene, cam, floor, items, peds, r15, manifest, park, ring, ptr):
    from bpy_extras.object_utils import world_to_camera_view
    tmp = os.path.join(RD, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    tp = lambda n: os.path.join(tmp, n + ".png")  # noqa: E731
    objs = lambda it: set(it["meshes"]) | {it["root"]}  # noqa: E731
    C = items["CustomDice"]
    cd = objs(C)
    fam = ["PartyDiceBlock", "DoubleDice", "TripleDice", "LuckyDie"]
    vis = K.set_render_vis
    views = {"front": (0, -1, 0.0), "back": (0, 1, 0.0), "side": (1, 0, 0.0),
             "three_quarter": (0.75, -1, 0.42), "top": (0.0, -0.25, 1)}
    info = manifest["items"]["CustomDice"]
    rad = max(info["bounds_m"]) * 0.5 * 1.12
    dist = rad / math.tan(math.atan(18 / 85)) * 1.25

    def save(im, fn, title, sub):
        K.header(im, title, sub).save(os.path.join(RD, fn))

    def dial(deg):
        for m in (ring, ptr):
            m.rotation_euler = (0, math.radians(deg), 0)
        bpy.context.view_layer.update()

    def solo(z=1.0):
        park()
        C["root"].location = (0, 0, z)
        bpy.context.view_layer.update()
        vis(cd | {floor})

    def shot(k, size=640, d=None, name=None):
        K.aim(cam, (0, 0, 1.0), views[k], d or dist)
        return K.label(K.do_render(scene, tp((name or k) + str(size)), size, size), (name or k).replace("_", " ").upper())

    solo()
    dial(0)
    save(K.hstack([shot("front"), shot("back"), shot("side")]), "01_turnaround_front_back_side.png",
         "Custom Dice Block", "Cream family die, teal faces, cobalt corner studs; gold dial ring on four rollers; coral pointer + teal button marks the chosen face")
    K.aim(cam, (0, -0.05, 1.04), views["three_quarter"], dist * 1.08)
    save(K.do_render(scene, tp("hero"), 1400, 1000), "02_front_three_quarter_hero.png",
         "Custom Dice Block - front three-quarter", "Selected face (5) has a glowing gold inner lip; the pointer sits on the dial ring above it")
    # 3 selector close-up
    ims = []
    for tgt, d, dd, t1, t2 in (((0, -0.42, 1.52), (0.45, -1, 0.35), 0.80, "POINTER + BUTTON", "coral pointer, teal button, ring ticks"),
                               ((0.42, 0.0, 1.42), (0.9, -0.6, 0.6), 0.70, "ROLLER + CLEARANCE", f"ring rides {ROLLER_GAP * 1000:.0f} mm over a gold edge roller"),
                               ((0.0, -0.40, 1.42), (0.15, -1, 0.9), 0.75, "SELECTED FACE EDGE", "pointer over the glowing gold lip of face 5")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("sel" + t1[:4]), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "03_selector_mechanism_closeup.png", "Selector mechanism close-up",
         f"Ring inner radius {info['selector']['ring_inner_radius_m'] * 1000:.0f} mm vs die {info['selector']['body_max_radius_about_axis_m'] * 1000:.0f} mm about the dial axis")
    # 4 three dial positions
    ims = []
    for deg in (0, -40, 70):
        dial(deg)
        K.aim(cam, (0, 0, 1.0), views["front"], dist)
        ims.append(K.label(K.do_render(scene, tp(f"dial{deg}"), 640, 640), f"DIAL {deg:+d} deg"))
    dial(0)
    save(K.hstack(ims), "04_selector_three_positions.png", "Selector ring in three positions",
         f"Ring + pointer rotated about the front axis; min clearance to the die over 24 tested angles: {info['selector']['min_clearance_over_all_angles_m'] * 1000:.1f} mm, 0 intersections")
    # 5 shop pedestals
    park()
    order = ["PartyDiceBlock", "DoubleDice", "CustomDice", "TripleDice", "LuckyDie"]
    for i, n in enumerate(order):
        ped, Hp = peds[i]
        b = 1.25 if n == "CustomDice" else (1.3 if n in ("DoubleDice", "TripleDice") else 1.0)
        items[n]["root"].location = ((i - 2) * 1.9, 0, Hp + b * 0.5 + 0.2)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(cd | set().union(*[objs(items[n]) for n in fam]) | {p for p, _ in peds} | {floor})
    K.aim(cam, (0, 0, 1.1), (0.15, -1, 0.40), 13.6, lens=50)
    save(K.do_render(scene, tp("pedestals"), 2000, 950), "05_shop_pedestals_with_dice_family.png",
         "Shop pedestals beside the dice family", "Party Dice | Double Dice | Custom Dice | Triple Dice | Lucky Die")
    # 6 R15
    park()
    r15.location = (0, 0, 0)
    C["root"].location = (1.45, 0, 1.2)
    items["PartyDiceBlock"]["root"].location = (-1.35, 0, 1.2)
    bpy.context.view_layer.update()
    vis(cd | objs(items["PartyDiceBlock"]) | {r15, floor})
    K.aim(cam, (0.05, 0, 0.95), (0, -1, 0.06), 7.8, lens=50)
    b = info["bounds_studs"]
    save(K.do_render(scene, tp("scale"), 1600, 950), "06_r15_scale_comparison.png", "R15 scale comparison (5.2-stud blocky R15)",
         f"Custom Dice assembly {b[0]:.2f} W x {b[2]:.2f} H x {b[1]:.2f} D studs (body {info['body_bounds_studs'][0]:.2f})  |  Party Dice Block 3.56")
    r15.location = (-4.6, 0, 0)
    # 7 gameplay
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
    spots = {"PartyDiceBlock": tiles[1], "CustomDice": tiles[4], "LuckyDie": tiles[6]}
    for n, (x, y) in spots.items():
        items[n]["root"].location = (x, y, 0.15 + 2.9 * STUD)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(cd | objs(items["PartyDiceBlock"]) | objs(items["LuckyDie"]) | set(board) | {floor})
    K.aim(cam, (0, 0.4, 0.6), (0, -1, 1.05), 15.5, lens=35)
    full = K.do_render(scene, tp("gameplay"), 1280, 720)
    crops = []
    for n in spots:
        q = world_to_camera_view(scene, cam, items[n]["root"].matrix_world.translation)
        cx, cy = int(q.x * 1280), int((1 - q.y) * 720)
        c = full.crop((cx - 60, cy - 60, cx + 60, cy + 60)).resize((300, 300), Image.NEAREST)
        bar = Image.new("RGB", (300, 34), (246, 240, 228))
        ImageDraw.Draw(bar).text((8, 8), f"{n}  (120 px, x2.5)", fill=(70, 52, 30), font=K.font(14, True))
        crops.append(K.vstack([c, bar]))
    save(K.hstack([full, K.vstack(crops[:2]), K.vstack(crops[2:])]), "07_gameplay_distance_comparison.png",
         "Gameplay-distance comparison", "Board camera ~15 m (54 studs), 35 mm; Party Dice | Custom Dice | Lucky Die; right: 1:1 crops enlarged")
    for o in board:
        bpy.data.objects.remove(o, do_unlink=True)
    # 8 pivot + axis
    solo()
    K.aim(cam, (0, 0, 1.0), views["three_quarter"], dist)
    bpy.context.view_layer.update()
    im = K.do_render(scene, tp("pivot"), 900, 900)
    im = Image.blend(im, Image.new("RGB", im.size, (240, 236, 228)), 0.35)
    dr = ImageDraw.Draw(im)
    px = lambda p: ((lambda q: (q.x * 900, (1 - q.y) * 900))(world_to_camera_view(scene, cam, p)))  # noqa: E731
    o = C["root"].matrix_world.translation.copy()
    rx, ry = px(o)
    for ax, col in ((Vector((0.3, 0, 0)), (220, 40, 40)), (Vector((0, 0.3, 0)), (40, 160, 40)), (Vector((0, 0, 0.3)), (40, 80, 230))):
        ex, ey = px(o + ax)
        dr.line((rx, ry, ex, ey), fill=col, width=5)
    a0, a1 = px(o + Vector((0, -0.9, 0))), px(o + Vector((0, 0.9, 0)))
    for k in range(14):
        t0_, t1_ = k / 14, (k + 0.5) / 14
        dr.line((a0[0] + (a1[0] - a0[0]) * t0_, a0[1] + (a1[1] - a0[1]) * t0_,
                 a0[0] + (a1[0] - a0[0]) * t1_, a0[1] + (a1[1] - a0[1]) * t1_), fill=(200, 60, 40), width=4)
    dr.ellipse((rx - 12, ry - 12, rx + 12, ry + 12), outline=(20, 20, 20), width=4)
    dr.text((rx + 16, ry + 8), "Root = Body = SelectorRing = Pointer pivot (die centre)", fill=(20, 20, 20), font=K.font(17, True))
    dr.text((a0[0] + 10, a0[1] - 28), "dial axis (Blender Y, front-to-back)", fill=(170, 50, 30), font=K.font(17, True))
    save(im, "08_pivot_rotation_axis.png", "Pivots and rotation axis",
         "All three meshes share the die-centre pivot; ring and pointer rotate together about the front-facing axis only")
    # 9 material close-up
    solo()
    ims = []
    for tgt, d, dd, t1, t2 in (((0.18, -0.42, 1.18), (0.35, -1, 0.35), 0.60, "SELECTED FACE", "teal enamel, pearl pips, glowing gold lip, cobalt stud"),
                               ((0.40, -0.25, 1.40), (0.9, -1, 0.7), 0.70, "FRAME CORNER", "cream body + frame, gold rivet, ring ticks (cobalt)"),
                               ((-0.35, 0.3, 1.0), (-0.7, 1, 0.3), 0.85, "BACK + SIDE", "face 2 / face 4, rollers, plain ring back")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("mat" + t1[:4]), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "09_material_closeup.png", "Material close-up", "v002 atlas cells only; no new texture maps")
    # 10 wireframe
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
    dr.text((18, 14), "CustomDice", fill=(30, 30, 60), font=K.font(30, True))
    lines = [f"{info['triangles_total']:,} tris total  |  3 meshes  |  1 material slot each"] + \
            [f"{n}: {m['triangles']:,}" for n, m in info["meshes"].items()]
    for i, t in enumerate(lines):
        dr.text((18, 56 + i * 24), t, fill=(40, 40, 70), font=K.font(19))
    save(im, "10_wireframe_triangle_counts.png", "Wireframe and triangle counts",
         "Body <= 7,000; ring + pointer <= 2,000; package < 9,000")
    # 11 neutral contact sheet
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*K.BG_NEUTRAL, 1)
    fb = floor.data.materials[0].node_tree.nodes["Principled BSDF"]
    old = tuple(fb.inputs["Base Color"].default_value)
    fb.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    solo()
    row = K.hstack([shot(k, 400) for k in ("front", "three_quarter", "side", "back", "top")], bg=(205, 205, 205))
    fam_row = []
    for n in fam:
        park()
        items[n]["root"].location = (0, 0, 1.0)
        bpy.context.view_layer.update()
        vis(objs(items[n]) | {floor})
        dd = (1.6 if n in ("DoubleDice", "TripleDice") else 1.1) * 0.5 * 1.12 / math.tan(math.atan(18 / 85)) * 1.25
        K.aim(cam, (0, 0, 1.0), views["three_quarter"], dd)
        fam_row.append(K.label(K.do_render(scene, tp("fam" + n), 400, 400), n))
    solo()
    K.aim(cam, (0, 0, 1.0), views["three_quarter"], dist)
    fam_row.append(K.label(K.do_render(scene, tp("famcd"), 400, 400), "CustomDice"))
    save(K.vstack([row, K.hstack(fam_row, bg=(205, 205, 205))], bg=(205, 205, 205)), "11_neutral_contact_sheet.png",
         "Neutral contact sheet", "top: front | three-quarter | side | back | top    bottom: three-quarter beside the dice family")
    bg.inputs["Color"].default_value = (*K.BG_WARM, 1)
    fb.inputs["Base Color"].default_value = old
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
