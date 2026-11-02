"""Party Game Item Kit -- review stage 3: Swap Ticket.

Builds on the v001 kit library (build_item_kit.py) and the v002 dice-family module
(build_dice_family_v002.py, which registers the v002 atlas cell layout). Neither is re-run.
Uses the existing v002 atlas maps unchanged -- no new atlas cells are needed.
Every v001 / v002 file is hash-checked before and after this build.

Run with the `bpy` module (pip install bpy) or Blender:
    python3 PartyGameItemKit/source/build_swap_ticket_v003.py
    KIT_STAGE=geo python3 ...        # geometry + export + validation, no renders

Outputs (relative to PartyGameItemKit/)
    source/PartyGameItemKit_SwapTicket_v003.blend
    export/SwapTicket_v003.fbx
    manifest_v003.json, validation/fbx_roundtrip_v003.json, renders/v003_swap_ticket/*.png
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
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_item_kit as K            # noqa: E402  v001 library
import build_dice_family_v002 as D2   # noqa: E402  v002 library (sets the v002 atlas class layout)

VERSION = "v003"
KIT = K.KIT
STUD = K.STUD
STAGE = os.environ.get("KIT_STAGE", "full")
RD = os.path.join(K.D["renders"], "v003_swap_ticket")
FRONT = K.FRONT                     # build plane XY, +Z toward viewer -> world XZ facing -Y
BACK = K.FRONT @ K.R("X", 180)      # back face, keeps "up" up

# ---------------------------------------------------------------- ticket dimensions (m)
W, H = 1.106, 0.69                  # 3.95 x 2.46 studs
RC = 0.075                          # corner radius
SAG = 0.030                         # concave top / bottom edges
WAVES = (-0.15, 0.0, 0.15)          # perforation scallops on each short side
WAVE_A, WAVE_W = 0.030, 0.050
BOW = 0.020                         # short ends lean back -> ticket bows toward the viewer
N_OUT = 136


def resample(P, n):
    P = np.asarray(P, float)
    Q = np.vstack([P, P[:1]])
    seg = np.linalg.norm(np.diff(Q, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    t = np.linspace(0, s[-1], n, endpoint=False)
    return np.stack([np.interp(t, s, Q[:, 0]), np.interp(t, s, Q[:, 1])], 1)


def ticket_outline():
    P = resample(K.rrect(W / 2, H / 2, RC, 12), N_OUT)
    x, y = P[:, 0].copy(), P[:, 1].copy()
    edge = np.clip((np.abs(y) - (H / 2 - RC)) / RC, 0, 1) ** 0.5     # 1 on top/bottom edges
    y -= np.sign(y) * SAG * (1 - (x / (W / 2)) ** 2) * edge
    side = np.clip((np.abs(x) - (W / 2 - RC)) / RC, 0, 1) ** 0.5     # 1 on the short sides
    dip = np.zeros_like(y)
    for yk in WAVES:
        u = np.clip((y - yk) / WAVE_W, -1, 1)
        dip += WAVE_A * np.cos(u * math.pi / 2) ** 2
    x -= np.sign(x) * dip * side
    return K.ccw(np.stack([x, y], 1))


def arrow_outline(cx, cy, r, a_tail, a_head, w=0.072, head_w=0.155, head_len=0.088, n=22):
    """Curved arrow travelling clockwise from a_tail to a_head (degrees) around (cx, cy)."""
    c = np.array([cx, cy])
    d = lambda a: np.array([math.cos(math.radians(a)), math.sin(math.radians(a))])  # noqa: E731
    outer, inner = [], []
    for k in range(n + 1):
        t = k / n
        a = a_tail + (a_head - a_tail) * t
        ww = w * (0.80 + 0.20 * t)
        outer.append(c + (r + ww / 2) * d(a))
        inner.append(c + (r - ww / 2) * d(a))
    ah = math.radians(a_head)
    tangent = np.array([math.sin(ah), -math.cos(ah)])
    tip = c + r * d(a_head) + tangent * head_len
    pts = outer + [c + (r + head_w / 2) * d(a_head), tip, c + (r - head_w / 2) * d(a_head)] + inner[::-1]
    # rounded tail end
    tail_c = c + r * d(a_tail)
    tw = w * 0.80 / 2
    ta = math.radians(a_tail)
    back = np.array([-math.sin(ta), math.cos(ta)])      # opposite to travel at the tail
    radial = d(a_tail)
    for k in range(1, 6):
        phi = math.pi * k / 6
        pts.append(tail_c - radial * tw * math.cos(phi) + back * tw * math.sin(phi))
    return K.ccw(pts)


def pawn_outline():
    base = [(-0.042, -0.056), (0.042, -0.056), (0.029, -0.034), (0.019, -0.008), (-0.019, -0.008), (-0.029, -0.034)]
    return K.chaikin(base, 2)


def dome(B, M, r, seg, z0, z1, h, cls, top=None):
    prof = [(0, z0), (0, z1)]
    for a in (40, 75):
        t = math.radians(a)
        prof.append((r * (1 - math.cos(t)), z1 + h * math.sin(t)))
    B.sweep(K.circle(r, seg), prof, [cls] * 3, M, cap0=cls, cap1=top or cls)


def build_ticket():
    B = K.Builder()
    P = ticket_outline()
    # body: gold rolled trim around both faces, cobalt contrast band, raised cream panels
    prof = [(0.090, -0.032), (0.078, -0.022), (0.052, -0.022), (0.040, -0.040), (0.012, -0.040),
            (0.0, -0.024), (0.0, 0.024), (0.012, 0.040), (0.040, 0.040), (0.052, 0.022),
            (0.078, 0.022), (0.090, 0.032)]
    cls = ["CREAM", "COBALT", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD", "GOLD", "COBALT", "CREAM"]
    B.sweep(P, prof, cls, FRONT, cap0="CREAM", cap1="CREAM", center=(0, 0))
    # gold rivets in the panel corners, both faces
    for side in (FRONT, BACK):
        for sx in (-1, 1):
            for sy in (-1, 1):
                dome(B, side @ K.tf((sx * 0.345, sy * 0.188, 0)), 0.024, 10, 0.020, 0.040, 0.016, "GOLD")
    # front: two player medallions (teal pawn left, coral pawn right) ...
    for sx, pawn_cls in ((-1, "TEAL"), (1, "CORAL_ENAMEL")):
        Mm = FRONT @ K.tf((sx * 0.330, 0.0, 0))
        B.sweep(K.circle(0.095, 22), [(0, 0.020), (0, 0.050), (0.010, 0.060), (0.022, 0.058), (0.026, 0.047)],
                ["GOLD", "GOLD", "GOLD", "GOLD_SATIN"], Mm, cap0="GOLD", cap1="COBALT")
        B.sweep(pawn_outline(), [(0, 0.040), (0, 0.060), (0.006, 0.066)], [pawn_cls, pawn_cls], Mm,
                cap0=pawn_cls, cap1=pawn_cls)
        B.sweep(K.circle(0.024, 12), [(0, 0.040), (0, 0.060), (0.006, 0.066)], [pawn_cls, pawn_cls],
                Mm @ K.tf((0, 0.024, 0)), cap0=pawn_cls, cap1=pawn_cls)
    # ... and the swap: teal arrow over the top heading right, coral arrow underneath heading left
    teal = arrow_outline(0.0, -0.035, 0.195, 152, 30)
    coral = -teal[::-1]                                         # point-symmetric twin
    for poly, c in ((teal, "TEAL"), (K.ccw(coral), "CORAL_ENAMEL")):
        B.sweep(poly, [(0, 0.020), (0, 0.054), (0.008, 0.064)], [c, c], FRONT, cap0=c, cap1=c, mode="miter")
    # back: simplified cream crossed-arrow emblem in low relief
    for poly in (teal * 0.82, K.ccw(coral * 0.82)):
        B.sweep(poly, [(0, 0.020), (0, 0.038), (0.006, 0.044)], ["CREAM", "CREAM"], BACK,
                cap0="CREAM", cap1="CREAM", mode="miter")
    # physical bow: the short ends lean back so the ticket curves toward the viewer
    for v in B.bm.verts:
        v.co.y += BOW * (v.co.x / (W / 2)) ** 2
    # root pivot = geometric (bounding-box) centre
    co = np.array([v.co[:] for v in B.bm.verts])
    centre = (co.min(0) + co.max(0)) / 2
    for v in B.bm.verts:
        v.co -= Vector(centre)
    return B, centre


# ---------------------------------------------------------------- main
def snapshot():
    out = {}
    for dp, _, fs in os.walk(KIT):
        for f in fs:
            p = os.path.relpath(os.path.join(dp, f), KIT)
            if p == "README.md" or "v003" in p or "__pycache__" in p or p.endswith(".blend1"):
                continue
            out[p] = hashlib.sha256(open(os.path.join(KIT, p), "rb").read()).hexdigest()
    return out


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

    coll = bpy.data.collections.new("PGK_SwapTicket")
    scene.collection.children.link(coll)
    root = D2.new_root(scene, "SwapTicket_Root", coll)
    B, shift = build_ticket()
    ob = K.finish_mesh("SwapTicket", B, coll, root, mat, 1.0)
    bpy.context.view_layer.update()

    me = ob.data
    cl = np.zeros(len(me.polygons), int)
    me.attributes["kit_class"].data.foreach_get("value", cl)
    co = np.array([v.co[:] for v in me.vertices])
    dims = co.max(0) - co.min(0)
    centre = (co.max(0) + co.min(0)) / 2
    checks = K.mesh_checks(ob)
    info = {
        "collection": coll.name, "root": root.name,
        "pivot": {"root_location_m": [0, 0, 0], "bbox_centre_offset_m": [round(x, 5) for x in centre],
                  "note": "root and mesh origin at the geometric (bounding-box) centre; spin about world Z, "
                          "hover along world Z; X-symmetric so a Z spin does not wobble"},
        "meshes": {ob.name: {"export_name": ob.name, "triangles": len(me.polygons), "vertices": len(me.vertices),
                             "material": me.materials[0].name, "material_slots": len(me.materials),
                             "atlas_cells": sorted({D2.CLASSES[c] for c in cl}), "uv_bounds": D2.uv_bounds(ob),
                             "origin_m": [0.0, 0.0, 0.0], "local_rotation_deg": [0, 0, 0], "local_scale": [1, 1, 1],
                             **checks}},
        "triangles_total": len(me.polygons), "mesh_count": 1,
        "bounds_m": [round(x, 4) for x in dims], "bounds_studs": [round(x / STUD, 2) for x in dims],
        "coplanar_overlap_pairs": D2.zfight_world([ob]),
        "mesh_intersections": {}, "shells": checks["shells"],
        "construction_note": "one production mesh; every decorative shell is seated 12 mm into the panel it "
                             "sits on (kit convention, no floating parts, no separate intersecting meshes)",
    }
    print("ITEM SwapTicket", info["triangles_total"], info["bounds_studs"], checks,
          "zf", info["coplanar_overlap_pairs"], "uv", info["meshes"]["SwapTicket"]["uv_bounds"])
    manifest = {"kit": "PartyGameItemKit", "version": VERSION, "stage": "review-3 (Swap Ticket)",
                "builds_on": {"scripts": ["source/build_item_kit.py", "source/build_dice_family_v002.py"],
                              "manifests": ["manifest.json", "manifest_v002.json"]},
                "units": {"blender": "metres", "stud_m": STUD},
                "atlas": {"maps": {k: os.path.relpath(p, KIT) for k, p in paths.items()},
                          "new_cells": [], "note": "uses the v002 atlas unchanged (cells CREAM, GOLD, GOLD_SATIN, "
                          "COBALT, TEAL, CORAL_ENAMEL); dark navy is not in the atlas, COBALT stands in"},
                "material": "PGK_KitAtlas (one material slot, v002 maps)",
                "items": {"SwapTicket": info}}

    # export
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = root
    fp = os.path.join(K.D["export"], f"SwapTicket_{VERSION}.fbx")
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
    peds = []
    for i in range(5):
        p, Hp = K.make_pedestal(helpers, ped_mats, (i - 2) * 1.9)
        peds.append((p, Hp))
    items = {"SwapTicket": {"root": root, "meshes": [ob]}, **refs}

    def park():
        for it in items.values():
            it["root"].location = (50, 50, -50)
            it["root"].rotation_euler = (0, 0, 0)
    park()
    root.location = (0, 0, peds[2][1] + dims[2] / 2 + 0.25)
    bpy.context.view_layer.update()
    blend = os.path.join(K.D["source"], f"PartyGameItemKit_SwapTicket_{VERSION}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["blend"] = os.path.relpath(blend, KIT)
    manifest["review_helpers"] = {"collections": ["Review_Helpers", "Reference_DiceFamily", "Review_Stage"],
                                  "excluded_from_exports": True}

    if STAGE == "full":
        render_reviews(scene, cam, floor, items, peds, r15, manifest, park)
        park()
        root.location = (0, 0, peds[2][1] + dims[2] / 2 + 0.25)
        for o in bpy.data.objects:
            o.hide_render = False
        bpy.ops.wm.save_as_mainfile(filepath=blend, relative_remap=True)
    manifest["renders"] = sorted(os.path.relpath(os.path.join(RD, f), KIT) for f in os.listdir(RD) if f.endswith(".png"))

    manifest["validation"] = roundtrip(fp, manifest)
    expected = [manifest["blend"], "source/build_swap_ticket_v003.py", info["fbx"],
                "validation/fbx_roundtrip_v003.json"] + list(manifest["atlas"]["maps"].values())
    manifest["missing_files"] = [f for f in expected if not os.path.exists(os.path.join(KIT, f))]
    manifest["renders_expected"] = 10
    manifest["renders_missing"] = 10 - len(manifest["renders"])
    after = snapshot()
    changed = sorted(f for f in before if after.get(f) != before[f])
    manifest["v001_v002_files_checked"] = len(before)
    manifest["v001_v002_files_unchanged"] = not changed
    manifest["v001_v002_files_changed"] = changed
    with open(os.path.join(KIT, f"manifest_{VERSION}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("PRIOR unchanged:", not changed, len(before), changed, "missing:", manifest["missing_files"],
          "renders:", len(manifest["renders"]))
    print("DONE in %.0fs" % (time.time() - t0))


def roundtrip(fp, manifest):
    exp = manifest["items"]["SwapTicket"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=fp)
    bpy.context.view_layer.update()
    obs = list(bpy.context.scene.objects)
    meshes = [o for o in obs if o.type == "MESH"]
    roots = [o for o in obs if o.parent is None]
    co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in meshes])
    dims = co.max(0) - co.min(0)
    centre_world = (co.max(0) + co.min(0)) / 2
    root_world = np.array(roots[0].matrix_world.translation) if roots else np.full(3, 9.0)
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
                       "local_transform_identity": bool(np.allclose(np.array(o.matrix_local), np.eye(4), atol=1e-4))}
    rec = {"file": os.path.relpath(fp, KIT), "bytes": os.path.getsize(fp),
           "importer": f"Blender {bpy.app.version_string} FBX importer",
           "hierarchy": {o.name: o.parent.name if o.parent else None for o in obs},
           "root_matches": len(roots) == 1 and roots[0].name == "SwapTicket_Root",
           "names_match": sorted(per) == sorted(exp["meshes"]), "mesh_count": len(meshes),
           "helpers_present": [o.name for o in obs if o.name.startswith(("R15", "ShopPedestal", "_", "Floor", "ref_"))],
           "meshes": per, "world_bounds_m": [round(x, 4) for x in dims], "source_bounds_m": exp["bounds_m"],
           "bounds_match_2mm": bool(np.allclose(sorted(dims), sorted(exp["bounds_m"]), atol=2e-3)),
           "root_to_geometric_centre_m": round(float(np.linalg.norm(centre_world - root_world)), 5),
           "embedded_images": sorted({i.name for i in bpy.data.images})}
    rec["root_pivot_within_2mm"] = rec["root_to_geometric_centre_m"] <= 2e-3
    rec["pass"] = bool(rec["root_matches"] and rec["names_match"] and rec["bounds_match_2mm"]
                       and rec["root_pivot_within_2mm"] and not rec["helpers_present"]
                       and all(p["triangles_match"] and p["uv_in_0_1"] and p["uv_layers"] == 1
                               and p["material_slots"] == 1 and p["local_transform_identity"]
                               and p["triangles"] < 8000 for p in per.values()))
    with open(os.path.join(K.D["validation"], f"fbx_roundtrip_{VERSION}.json"), "w") as f:
        json.dump({"version": VERSION, "items": {"SwapTicket": rec}}, f, indent=2)
    print("ROUNDTRIP SwapTicket", rec["pass"], rec["hierarchy"], rec["world_bounds_m"], rec["root_to_geometric_centre_m"])
    return {"SwapTicket": rec["pass"]}


# ---------------------------------------------------------------- renders
def render_reviews(scene, cam, floor, items, peds, r15, manifest, park):
    from bpy_extras.object_utils import world_to_camera_view
    tmp = os.path.join(RD, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    tp = lambda n: os.path.join(tmp, n + ".png")  # noqa: E731
    objs = lambda it: set(it["meshes"]) | {it["root"]}  # noqa: E731
    T = items["SwapTicket"]
    tick = objs(T)
    fam = ["PartyDiceBlock", "DoubleDice", "TripleDice", "LuckyDie"]
    famset = set().union(*[objs(items[n]) for n in fam])
    vis = K.set_render_vis
    views = {"front": (0, -1, 0.0), "back": (0, 1, 0.0), "side": (1, 0, 0.0),
             "three_quarter": (0.75, -1, 0.42), "back_three_quarter": (-0.75, 1, 0.42), "top": (0.0, -0.25, 1)}
    rad = max(manifest["items"]["SwapTicket"]["bounds_m"]) * 0.5 * 1.12
    dist = rad / math.tan(math.atan(18 / 85)) * 1.25

    def save(im, fn, title, sub):
        K.header(im, title, sub).save(os.path.join(RD, fn))

    def solo(z=1.0):
        park()
        T["root"].location = (0, 0, z)
        bpy.context.view_layer.update()
        vis(tick | {floor})

    def shot(k, size=640, d=None, z=1.0):
        K.aim(cam, (0, 0, z), views[k], d or dist)
        return K.label(K.do_render(scene, tp(k + str(size)), size, size), k.replace("_", " ").upper())

    # 1 turnaround
    solo()
    save(K.hstack([shot("front"), shot("back"), shot("side")]), "01_turnaround_front_back_side.png",
         "Swap Ticket", "Chunky cream ticket, rolled gold trim, cobalt band, teal + coral swap arrows, player medallions; cream crossed-arrow back")
    # 2 hero / 3 back 3/4
    for k, fn, title in (("three_quarter", "02_front_three_quarter_hero.png", "Front three-quarter hero"),
                         ("back_three_quarter", "03_back_three_quarter.png", "Back three-quarter")):
        K.aim(cam, (0, 0, 1.0), views[k], dist * 0.95)
        save(K.do_render(scene, tp(k), 1400, 1000), fn, f"Swap Ticket - {title.lower()}",
             "Bowed body (ends lean back 2 cm), scalloped perforated sides, layered enamel relief")
    # 4 shop pedestals beside the family
    park()
    order = ["PartyDiceBlock", "DoubleDice", "SwapTicket", "TripleDice", "LuckyDie"]
    for i, n in enumerate(order):
        ped, Hp = peds[i]
        b = 0.75 if n == "SwapTicket" else (1.3 if n in ("DoubleDice", "TripleDice") else 1.0)
        items[n]["root"].location = ((i - 2) * 1.9, 0, Hp + b * 0.5 + 0.2)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(tick | famset | {p for p, _ in peds} | {floor})
    K.aim(cam, (0, 0, 1.05), (0.15, -1, 0.40), 13.6, lens=50)
    save(K.do_render(scene, tp("pedestals"), 2000, 950), "04_shop_pedestals_with_dice_family.png",
         "Shop pedestals beside the dice family", "Party Dice | Double Dice | Swap Ticket | Triple Dice | Lucky Die")
    # 5 R15 scale
    park()
    r15.location = (0, 0, 0)
    T["root"].location = (1.45, 0, 1.05)
    items["PartyDiceBlock"]["root"].location = (-1.35, 0, 1.0)
    bpy.context.view_layer.update()
    vis(tick | objs(items["PartyDiceBlock"]) | {r15, floor})
    K.aim(cam, (0.05, 0, 0.85), (0, -1, 0.06), 7.4, lens=50)
    b = manifest["items"]["SwapTicket"]["bounds_studs"]
    save(K.do_render(scene, tp("scale"), 1600, 950), "05_r15_scale_comparison.png",
         "R15 scale comparison (5.2-stud blocky R15)",
         f"Swap Ticket {b[0]:.2f} W x {b[2]:.2f} H x {b[1]:.2f} D studs  |  Party Dice Block 3.56 studs for reference")
    r15.location = (-4.6, 0, 0)
    # 6 gameplay distance
    park()
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
        o = bpy.data.objects.new(f"_tile{k}", me)
        scene.collection.objects.link(o)
        board.append(o)
    for k, (x, y) in enumerate([tiles[3], tiles[7]]):
        f = K.make_r15(scene.collection, bpy.data.materials["R15_Clay"], name=f"_fig{k}")
        f.location = (x + 0.15, y + 0.9, 0.15)
        board.append(f)
    spots = {"PartyDiceBlock": tiles[1], "SwapTicket": tiles[4], "LuckyDie": tiles[6]}
    for n, (x, y) in spots.items():
        items[n]["root"].location = (x, y, 0.15 + 2.7 * STUD)
        items[n]["root"].rotation_euler = (0, 0, math.radians(-15))
    bpy.context.view_layer.update()
    vis(tick | objs(items["PartyDiceBlock"]) | objs(items["LuckyDie"]) | set(board) | {floor})
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
    save(K.hstack([full, K.vstack(crops[:2]), K.vstack(crops[2:])]), "06_gameplay_distance_comparison.png",
         "Gameplay-distance comparison", "Board camera ~15 m (54 studs), 35 mm; Party Dice | Swap Ticket | Lucky Die; right: 1:1 crops enlarged")
    for o in board:
        bpy.data.objects.remove(o, do_unlink=True)
    # 7 material / bevel close-up
    solo()
    ims = []
    for tgt, d, dd, t1, t2 in (((0.30, -0.10, 1.02), (0.45, -1, 0.35), 0.75, "ARROW + MEDALLION", "teal / coral enamel relief, gold bezel, cobalt inset"),
                               ((0.50, -0.02, 1.12), (0.9, -1, 0.5), 0.62, "TRIM + PERFORATION", "rolled gold trim, cobalt band, cream panel step, rivet"),
                               ((-0.05, 0.05, 1.0), (-0.4, 1, 0.3), 0.8, "BACK EMBLEM", "low-relief cream crossed arrows, rivets")):
        K.aim(cam, tgt, d, dd)
        ims.append(K.label(K.do_render(scene, tp("close" + t1[:4]), 700, 700), t1, t2, pos="bottom"))
    save(K.hstack(ims), "07_material_bevel_closeup.png", "Material and bevel close-up",
         "v002 atlas cells only: GOLD, GOLD_SATIN, CREAM, COBALT, TEAL, CORAL_ENAMEL")
    # 8 pivot
    solo()
    K.aim(cam, (0, 0, 1.0), views["three_quarter"], dist)
    bpy.context.view_layer.update()
    im = K.do_render(scene, tp("pivot"), 900, 900)
    im = Image.blend(im, Image.new("RGB", im.size, (240, 236, 228)), 0.35)
    dr = ImageDraw.Draw(im)
    px = lambda p: ((lambda q: (q.x * 900, (1 - q.y) * 900))(world_to_camera_view(scene, cam, p)))  # noqa: E731
    o = T["root"].matrix_world.translation.copy()
    rx, ry = px(o)
    for ax, col in ((Vector((0.3, 0, 0)), (220, 40, 40)), (Vector((0, 0.3, 0)), (40, 160, 40)), (Vector((0, 0, 0.3)), (40, 80, 230))):
        ex, ey = px(o + ax)
        dr.line((rx, ry, ex, ey), fill=col, width=5)
    ax0, ay0 = px(o + Vector((0, 0, -0.55)))
    ax1, ay1 = px(o + Vector((0, 0, 0.55)))
    for k in range(12):   # dashed spin axis
        t0_, t1_ = k / 12, (k + 0.5) / 12
        dr.line((ax0 + (ax1 - ax0) * t0_, ay0 + (ay1 - ay0) * t0_, ax0 + (ax1 - ax0) * t1_, ay0 + (ay1 - ay0) * t1_),
                fill=(120, 60, 160), width=3)
    dr.ellipse((rx - 12, ry - 12, rx + 12, ry + 12), outline=(20, 20, 20), width=4)
    dr.text((rx + 16, ry + 6), "SwapTicket_Root = mesh origin = bbox centre", fill=(20, 20, 20), font=K.font(18, True))
    dr.text((ax1 + 10, ay1), "spin / hover axis (world Z)", fill=(110, 50, 150), font=K.font(16, True))
    save(im, "08_pivot_visualisation.png", "Pivot",
         f"Root at the geometric centre (offset {max(abs(x) for x in manifest['items']['SwapTicket']['pivot']['bbox_centre_offset_m']) * 1000:.2f} mm); X-symmetric for wobble-free spin")
    # 9 wireframe
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
    for k in ("front", "three_quarter", "back"):
        K.aim(cam, (0, 0, 1.0), views[k], dist)
        vl.material_override = wire
        ims.append(K.do_render(scene, tp("wire" + k), 760, 760, samples=24))
        vl.material_override = None
    im = K.hstack(ims)
    info = manifest["items"]["SwapTicket"]
    dr = ImageDraw.Draw(im)
    dr.text((18, 14), "SwapTicket", fill=(30, 30, 60), font=K.font(30, True))
    dr.text((18, 56), f"{info['triangles_total']:,} tris  |  1 mesh  |  {info['shells']} closed shells  |  1 material", fill=(40, 40, 70), font=K.font(20))
    save(im, "09_wireframe_triangle_count.png", "Wireframe and triangle count", "Target 4,000-6,000, hard max 8,000")
    # 10 neutral contact sheet
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*K.BG_NEUTRAL, 1)
    fb = floor.data.materials[0].node_tree.nodes["Principled BSDF"]
    old = tuple(fb.inputs["Base Color"].default_value)
    fb.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    solo()
    row = K.hstack([shot(k, 400) for k in ("front", "three_quarter", "side", "back", "top")], bg=(205, 205, 205))
    fam_row = []
    for n in ["PartyDiceBlock", "DoubleDice", "TripleDice", "LuckyDie"]:
        park()
        items[n]["root"].location = (0, 0, 1.0)
        bpy.context.view_layer.update()
        vis(objs(items[n]) | {floor})
        dd = (1.6 if n in ("DoubleDice", "TripleDice") else 1.1) * 0.5 * 1.12 / math.tan(math.atan(18 / 85)) * 1.25
        K.aim(cam, (0, 0, 1.0), views["three_quarter"], dd)
        fam_row.append(K.label(K.do_render(scene, tp("fam" + n), 400, 400), n))
    solo()
    K.aim(cam, (0, 0, 1.0), views["three_quarter"], dist)
    fam_row.append(K.label(K.do_render(scene, tp("famticket"), 400, 400), "SwapTicket"))
    save(K.vstack([row, K.hstack(fam_row, bg=(205, 205, 205))], bg=(205, 205, 205)), "10_neutral_contact_sheet.png",
         "Neutral contact sheet", "top: front | three-quarter | side | back | top    bottom: three-quarter beside the dice family")
    bg.inputs["Color"].default_value = (*K.BG_WARM, 1)
    fb.inputs["Base Color"].default_value = old
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
