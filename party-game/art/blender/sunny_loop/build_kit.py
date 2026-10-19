"""Sunny Loop refined decoration kit (Blender source, non-destructive, reproducible).

Run headless:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P party-game/art/blender/sunny_loop/build_kit.py

Builds each asset in its own collection from scratch (nothing hand-edited), then writes:
    party-game/art/export/sunny_loop/<Asset>.fbx      one FBX per asset (Roblox: File > Import)
    party-game/art/export/sunny_loop/SunnyLoopKit.blend  editable source scene
    party-game/art/export/sunny_loop/kit_sheet.png      contact sheet render

Conventions (match docs/SunnyLoopV2.md and the Studio kit in src/server/Board/SkyGardenKit):
    * 1 stud = 0.28 m. Exports use FBX_SCALE_UNITS, axis_forward=-Z, axis_up=Y.
    * Transforms applied; origin at the bottom centre (props) or top-face centre (medallion,
      path pieces) so they drop straight onto the board grid.
    * Low-poly faceted shapes, flat shading, colour by material slot (2-4 slots per asset,
      shared material names across the kit so Studio can reuse SurfaceAppearances).
    * Names PG_<Kit>_<Asset>_<Variant>. Collision in Studio: decor = CanCollide off,
      CollisionFidelity Box; the medallion keeps its existing invisible collider.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

STUD = 0.28
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "export", "sunny_loop")
os.makedirs(OUT, exist_ok=True)

# Shared material palette (mid-tone, matches SkyGardenKit.Colors) --------------------------------
PALETTE = {
    "M_Bark": (0.48, 0.32, 0.22),
    "M_LeafShade": (0.30, 0.58, 0.20),
    "M_LeafMid": (0.41, 0.69, 0.23),
    "M_LeafLight": (0.54, 0.77, 0.27),
    "M_LeafRiver": (0.27, 0.62, 0.43),
    "M_Blossom": (0.88, 0.49, 0.65),
    "M_BlossomLight": (0.94, 0.65, 0.77),
    "M_Fruit": (0.86, 0.20, 0.20),
    "M_Petal": (0.96, 0.86, 0.30),
    "M_PetalPink": (0.94, 0.40, 0.62),
    "M_Soil": (0.59, 0.43, 0.30),
    "M_StoneLight": (0.91, 0.78, 0.63),
    "M_Stone": (0.84, 0.66, 0.47),
    "M_StoneDark": (0.69, 0.50, 0.38),
    "M_Moss": (0.38, 0.63, 0.25),
    "M_PathKerb": (0.77, 0.62, 0.43),
    "M_Path": (0.92, 0.84, 0.67),
    "M_Gold": (0.77, 0.57, 0.22),
    "M_Bevel": (0.96, 0.90, 0.77),
    "M_Field": (0.50, 0.50, 0.50),  # tinted per space type in Studio
}


def material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        r, g, b = PALETTE[name]
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
        bsdf.inputs["Roughness"].default_value = 0.8
        mat.diffuse_color = (r, g, b, 1)
    return mat


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_collection(name):
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    return coll


def add_object(coll, name, bm, mat_names):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mat_names:
        me.materials.append(material(m))
    for poly in me.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    coll.objects.link(obj)
    return obj


# Primitive builders into one bmesh (material index per part) -------------------------------------

def facet_blob(bm, centre, size, mat_index, rng, subdiv=1):
    """Faceted low-poly lump: an icosphere with jittered vertices and a squashed scale."""
    geom = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=0.5)
    verts = geom["verts"]
    for v in verts:
        v.co += Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08)))
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(centre)
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        f.material_index = mat_index


def prism(bm, base, top_centre, r_bottom, r_top, sides, mat_index):
    """Tapered n-sided column from base to top_centre."""
    geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=r_bottom, radius2=r_top,
                                 depth=(Vector(top_centre) - Vector(base)).length)
    verts = geom["verts"]
    axis = (Vector(top_centre) - Vector(base)).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(axis).to_matrix().to_4x4()
    mid = (Vector(base) + Vector(top_centre)) / 2
    bmesh.ops.transform(bm, matrix=Matrix.Translation(mid) @ rot, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_index


def box(bm, centre, size, mat_index, rot_z=0.0):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    m = Matrix.Translation(Vector(centre)) @ Matrix.Rotation(rot_z, 4, "Z") @ Matrix.Diagonal((*size, 1))
    bmesh.ops.transform(bm, matrix=m, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_index


def disc(bm, centre_z, radius, height, sides, mat_index, top_bevel=0.0):
    prism(bm, (0, 0, centre_z - height / 2), (0, 0, centre_z + height / 2), radius, radius - top_bevel, sides, mat_index)


# Assets (dimensions in studs, converted at the end) ---------------------------------------------

def tree(name, kind, seed):
    rng = random.Random(seed)
    bm = bmesh.new()
    mats = ["M_Bark", "M_LeafShade", "M_LeafMid", "M_LeafLight"]
    if kind == "Riverside":
        mats[1:] = ["M_LeafRiver", "M_LeafMid", "M_LeafLight"]
    if kind == "Fair":
        mats[1:] = ["M_Blossom", "M_BlossomLight", "M_BlossomLight"]
    h = {"Orchard": 5.0, "Riverside": 8.0, "Fair": 6.0}[kind]
    lean = Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0))
    top = Vector((0, 0, h)) + lean
    prism(bm, (0, 0, 0), top, 0.9, 0.45, 6, 0)               # tapered trunk
    prism(bm, (0, 0, 0), (0, 0, 0.6), 1.5, 1.0, 6, 0)       # root flare
    for k in range(2):                                     # two major branches
        a = rng.uniform(0, math.tau)
        start = top * rng.uniform(0.55, 0.75)
        end = start + Vector((math.cos(a) * 2.2, math.sin(a) * 2.2, 1.6))
        prism(bm, start, end, 0.3, 0.16, 5, 0)
    width = {"Orchard": 6.0, "Riverside": 4.4, "Fair": 5.4}[kind]
    count = rng.randint(3, 4)
    for k in range(count):
        a = rng.uniform(0, math.tau)
        r = 0 if k == 0 else width * rng.uniform(0.35, 0.55)
        y = width * (0.25 if k == 0 else rng.uniform(0.0, 0.55)) + (k * width * 0.35 if kind == "Riverside" else 0)
        s = width * (1.0 if k == 0 else rng.uniform(0.6, 0.8))
        c = top + Vector((math.cos(a) * r, math.sin(a) * r, y))
        facet_blob(bm, c, (s, s * 0.95, s * 0.7), 2 if k == 0 else 1, rng)
        facet_blob(bm, c + Vector((0, 0, s * 0.35)), (s * 0.7, s * 0.65, s * 0.45), 3, rng, subdiv=1)
    if kind == "Orchard":
        mats.append("M_Fruit")
        for k in range(3):
            a = rng.uniform(0, math.tau)
            c = top + Vector((math.cos(a) * width * 0.5, math.sin(a) * width * 0.5, width * 0.2))
            facet_blob(bm, c, (1.0, 1.0, 1.0), 4, rng, subdiv=1)
    return bm, mats


def flower_bed(name, long, seed):
    rng = random.Random(seed)
    bm = bmesh.new()
    mats = ["M_StoneLight", "M_Soil", "M_Moss", "M_Petal", "M_PetalPink"]
    if long:
        box(bm, (0, 0, 0.18), (7.5, 3.5, 0.36), 0)
        box(bm, (0, 0, 0.32), (7.0, 3.0, 0.3), 1)
    else:
        disc(bm, 0.18, 2.6, 0.36, 10, 0)
        disc(bm, 0.32, 2.3, 0.3, 10, 1)
    spots = [(-2.6 + k * 1.3, rng.uniform(-0.7, 0.7)) for k in range(5)] if long else \
        [(math.cos(k * 1.7) * 1.4, math.sin(k * 1.7) * 1.4) for k in range(4)]
    for k, (x, y) in enumerate(spots):
        stem_h = rng.uniform(1.2, 1.8)
        prism(bm, (x, y, 0.45), (x, y, 0.45 + stem_h), 0.09, 0.07, 4, 2)
        petal_mat = 3 if k % 3 else 4
        for p in range(5):
            a = p / 5 * math.tau
            box(bm, (x + math.cos(a) * 0.36, y + math.sin(a) * 0.36, 0.45 + stem_h), (0.6, 0.32, 0.12), petal_mat, rot_z=a)
        box(bm, (x, y, 0.5 + stem_h), (0.3, 0.3, 0.2), 3)
    return bm, mats


def bush(name, seed):
    rng = random.Random(seed)
    bm = bmesh.new()
    mats = ["M_LeafShade", "M_LeafMid", "M_LeafLight"]
    facet_blob(bm, (0, 0, 1.0), (3.6, 3.0, 2.2), 1, rng)
    facet_blob(bm, (1.2, 0.3, 1.6), (2.2, 2.0, 1.6), 2, rng)
    facet_blob(bm, (-1.3, -0.4, 0.8), (2.0, 1.8, 1.4), 0, rng)
    return bm, mats


def rock(name, seed, scale):
    rng = random.Random(seed)
    bm = bmesh.new()
    mats = ["M_StoneLight", "M_Stone", "M_StoneDark", "M_Moss"]
    geom = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.5)
    for v in geom["verts"]:
        v.co = Vector((v.co.x * scale[0] * rng.uniform(0.85, 1.15), v.co.y * scale[1] * rng.uniform(0.85, 1.15),
                       max(v.co.z, -0.15) * scale[2] * rng.uniform(0.8, 1.2) + scale[2] * 0.15))
    for f in geom["faces"] if "faces" in geom else {f for v in geom["verts"] for f in v.link_faces}:
        f.material_index = 0 if f.normal.z > 0.6 else (1 if f.normal.z > -0.2 else 2)
    facet_blob(bm, (scale[0] * 0.25, 0, scale[2] * 0.7), (scale[0] * 0.5, scale[1] * 0.4, 0.25), 3, rng)
    return bm, mats


def path_edge(name, length):
    """Kerb pair + seams for a 4.5-stud path, origin at the start-socket top centre."""
    bm = bmesh.new()
    mats = ["M_PathKerb", "M_StoneLight", "M_Path"]
    for s in (-1, 1):
        box(bm, (s * 2.45, length / 2, -0.05), (0.7, length, 0.55), 0)
        box(bm, (s * 2.45, length / 2, 0.25), (0.5, length, 0.12), 1)
    n = int(length // 3)
    for k in range(1, n + 1):
        box(bm, (0, k * length / (n + 1), 0.02), (4.1, 0.18, 0.06), 0)
    return bm, mats


def medallion(name):
    """Refined board space: foot, gold band, sandstone base, bevel, recess, field (tintable)."""
    bm = bmesh.new()
    mats = ["M_StoneDark", "M_Gold", "M_Stone", "M_Bevel", "M_Field"]
    disc(bm, -1.05, 6.0, 0.35, 32, 0)                 # foot (wider than the rim)
    disc(bm, -0.82, 5.7, 0.75, 32, 1)                 # gold band
    disc(bm, -0.7, 5.25, 1.0, 32, 2, top_bevel=0.12)  # sandstone base, bevelled top
    disc(bm, -0.12, 5.15, 0.16, 32, 3)                # bevel ring
    disc(bm, -0.02, 3.75, 0.1, 32, 4)                 # field (Studio tints this slot)
    return bm, mats


ASSETS = [
    ("PG_Tree_Orchard_A", lambda: tree("PG_Tree_Orchard_A", "Orchard", 11)),
    ("PG_Tree_Riverside_A", lambda: tree("PG_Tree_Riverside_A", "Riverside", 23)),
    ("PG_Tree_Fair_A", lambda: tree("PG_Tree_Fair_A", "Fair", 37)),
    ("PG_FlowerBed_Round", lambda: flower_bed("PG_FlowerBed_Round", False, 5)),
    ("PG_FlowerBed_Long", lambda: flower_bed("PG_FlowerBed_Long", True, 9)),
    ("PG_Bush_A", lambda: bush("PG_Bush_A", 3)),
    ("PG_Rock_A", lambda: rock("PG_Rock_A", 1, (3.2, 2.6, 2.2))),
    ("PG_Rock_B", lambda: rock("PG_Rock_B", 2, (2.2, 2.0, 2.8))),
    ("PG_Rock_C", lambda: rock("PG_Rock_C", 4, (4.2, 3.0, 1.6))),
    ("PG_Path_Edge_12", lambda: path_edge("PG_Path_Edge_12", 12.0)),
    ("PG_Space_Medallion", lambda: medallion("PG_Space_Medallion")),
]


def main():
    reset()
    coll = new_collection("SunnyLoopKit")
    stats = []
    for i, (name, build) in enumerate(ASSETS):
        bm, mats = build()
        bmesh.ops.scale(bm, vec=(STUD, STUD, STUD), verts=bm.verts)  # studs -> metres
        bmesh.ops.triangulate(bm, faces=bm.faces)
        obj = add_object(coll, name, bm, mats)
        obj.location = ((i % 6) * 3.4 - 8.5, (i // 6) * -4.2, 0)  # spread out for the sheet only
        stats.append((name, len(obj.data.polygons), len(mats)))
    # export each asset on its own at the origin
    for obj in list(coll.objects):
        saved = obj.location.copy()
        obj.location = (0, 0, 0)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, obj.name + ".fbx"), use_selection=True,
                                 object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
                                 axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE")
        obj.location = saved
    # contact sheet
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    coll.objects.link(cam)
    cam.location = (0, -17, 12)
    cam.rotation_euler = (math.radians(58), 0, 0)
    cam_data.lens = 30
    scene.camera = cam
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    coll.objects.link(sun)
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.75, 0.9, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    scene.world = world
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.filepath = os.path.join(OUT, "kit_sheet.png")
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "SunnyLoopKit.blend"))
    with open(os.path.join(OUT, "kit_stats.txt"), "w") as f:
        for name, tris, slots in stats:
            f.write(f"{name}\ttris={tris}\tmaterials={slots}\n")
    for name, tris, slots in stats:
        print(f"[kit] {name}: {tris} tris, {slots} material slots")


main()
