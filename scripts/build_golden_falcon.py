"""Build the faceted Golden Falcon guardian pet for Roblox as separate, rig-ready MeshParts.

Run with the `bpy` module (pip install bpy) or Blender:
    python3 scripts/build_golden_falcon.py                     # full build + export
    FALCON_STAGE=clay python3 scripts/build_golden_falcon.py   # gray-clay silhouette check only

Parts (each its own object, origin on its joint pivot, one shared UV atlas):
    Body, Head, Beak, WingL, WingR, Tail, LegL, LegR
Solid forms inside a part are boolean-unioned; feathers stay separate closed blades so
stacked feather layers never share (and overlap in) a UV island.

Outputs (in ./export):
    golden_falcon.fbx               all parts (texture embedded)
    golden_falcon_color.png         1024x1024 ColorMap
    golden_falcon_emissive.png      1024x1024 emissive mask
    golden_falcon_joints.json       hierarchy + joint pivots (studs) for Motor6Ds
    golden_falcon.blend             source scene
    golden_falcon_clay.png          gray-clay silhouette sheet (front / side / 3-4)
    golden_falcon_preview.png       textured verification sheet (front / side / 3-4)
"""
import json
import math
import os
import random

import bpy  # noqa: must precede bmesh when using the pip bpy module
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export")
TEX = 1024
SS = 2
STUD = 0.28
TARGET_H = 3.4 * STUD
STAGE = os.environ.get("FALCON_STAGE", "full")

COLORS = {
    "GOLD": (0.98, 0.72, 0.15), "GOLD2": (0.84, 0.54, 0.07), "CREAM": (0.97, 0.91, 0.80),
    "BLUE": (0.13, 0.18, 0.62), "LBLUE": (0.40, 0.85, 1.0), "NAVY": (0.06, 0.07, 0.24),
    "GEM": (0.22, 0.68, 1.0),
}
GLOW = {"GEM": 1.0, "LBLUE": 0.7}
CLASSES = list(COLORS) + ["HEADSHELL", "BODYSHELL"]
CID = {c: i for i, c in enumerate(CLASSES)}
rng = random.Random(5)


def V(*a):
    return Vector(a)


# ---------------------------------------------------------------- primitives
def ellipsoid(c, r, sd, jit=0.025, rx=0.0):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sd, radius=1.0)
    R = Matrix.Rotation(math.radians(rx), 3, "X")
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-jit, jit)
        v.co = R @ V(v.co.x * r[0], v.co.y * r[1], v.co.z * r[2]) + Vector(c)
    return bm


def hull(points):
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in points]
    res = bmesh.ops.convex_hull(bm, input=vs)
    drop = {g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)}
    bmesh.ops.delete(bm, geom=list(drop), context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def blade(b, t, w, th, s=None):
    """Chunky feather blade: wide base, widest near the root third, pointed tip."""
    b, t = Vector(b), Vector(t)
    a = t - b
    an = a.normalized()
    if s is None:
        s = an.cross(V(0, 1, 0))
        if s.length < 0.3:
            s = V(0, 0, 1)
    s = Vector(s)
    s = (s - an * s.dot(an)).normalized()
    n = an.cross(s).normalized()
    m, m2 = b + a * 0.3, b + a * 0.66
    return hull([b + s * w * 0.65, b - s * w * 0.65, b + n * th * 0.6, b - n * th * 0.6, t,
                 m + s * w, m - s * w, m + n * th, m - n * th, m2 + s * w * 0.62, m2 - s * w * 0.62])


def limb(p0, r0, p1, r1, k=6):
    pts = []
    for c, r in ((p0, r0), (p1, r1)):
        pts += [(c[0] + r * math.cos(a), c[1] + r * math.sin(a), c[2])
                for a in np.linspace(0, 2 * math.pi, k, endpoint=False) + 0.3]
    return hull(pts)


# ---------------------------------------------------------------- anatomy (design units, facing -Y)
# each part returns (solid prims to union, separate feather blades, joint pivot)
def part_body():
    solid = [(ellipsoid((0, -0.10, 0.62), (0.28, 0.24, 0.30), 4, rx=40), "BODYSHELL"),   # broad chest
             (ellipsoid((0, 0.18, 0.46), (0.18, 0.25, 0.17), 3, rx=62), "BODYSHELL")]    # narrow waist
    for s in (1, -1):
        solid.append((ellipsoid((0.14 * s, 0.08, 0.33), (0.12, 0.13, 0.12), 3), "CREAM"))
    solid.append((hull([(0, -0.29, 0.86), (0, -0.37, 0.50), (0.10, -0.36, 0.68), (-0.10, -0.36, 0.68),
                        (0, -0.43, 0.68), (0, -0.22, 0.68)]), "GEM"))
    return solid, [], (0, 0.02, 0.52)


def part_head():
    solid = [(ellipsoid((0, -0.20, 1.04), (0.25, 0.31, 0.22), 4, 0.02, rx=-12), "HEADSHELL"),  # long skull
             (ellipsoid((0, -0.40, 0.98), (0.17, 0.15, 0.15), 3, 0.02), "HEADSHELL")]           # tapered face
    # gold brow visor: slopes forward over the eyes into a V
    solid.append((hull([(0, -0.53, 1.08), (0, -0.50, 1.15), (0.21, -0.38, 1.10), (-0.21, -0.38, 1.10),
                        (0.22, -0.36, 1.17), (-0.22, -0.36, 1.17), (0.16, -0.20, 1.23), (-0.16, -0.20, 1.23),
                        (0, -0.26, 1.27)]), "GOLD"))
    solid.append((hull([(0, -0.44, 1.27), (0, -0.51, 1.14), (0.04, -0.49, 1.20), (-0.04, -0.49, 1.20),
                        (0, -0.535, 1.20), (0, -0.42, 1.20)]), "GEM"))
    crest = [((0, -0.32, 1.22), (0, 0.06, 1.52), 0.10),
             ((0.09, -0.28, 1.20), (0.22, 0.12, 1.42), 0.09), ((-0.09, -0.28, 1.20), (-0.22, 0.12, 1.42), 0.09),
             ((0.16, -0.20, 1.15), (0.30, 0.18, 1.26), 0.075), ((-0.16, -0.20, 1.15), (-0.30, 0.18, 1.26), 0.075)]
    blades = [(blade(b, t, w, 0.04), "GOLD") for b, t, w in crest]
    return solid, blades, (0, -0.16, 0.86)


def part_beak():
    upper = [(0.09, -0.45, 1.03), (-0.09, -0.45, 1.03), (0.08, -0.45, 0.93), (-0.08, -0.45, 0.93),
             (0, -0.46, 1.08), (0, -0.63, 1.03), (0.045, -0.62, 0.97), (-0.045, -0.62, 0.97), (0, -0.68, 0.97)]
    hook = [(0, -0.64, 1.01), (0.035, -0.63, 0.95), (-0.035, -0.63, 0.95), (0, -0.72, 0.95),
            (0, -0.70, 0.85), (0, -0.63, 0.91)]
    lower = [(0.06, -0.46, 0.93), (-0.06, -0.46, 0.93), (0, -0.46, 0.88), (0, -0.60, 0.92),
             (0.03, -0.58, 0.93), (-0.03, -0.58, 0.93)]
    return [(hull(upper), "GOLD"), (hull(hook), "NAVY"), (hull(lower), "GOLD2")], [], (0, -0.46, 0.98)


def part_wing(side=1):
    root = V(0.19 * side, 0.02, 0.80)
    e1 = V(1.0 * side, 0.3, 0.95).normalized()
    nw = e1.cross(V(0, 0.3, -1)).normalized()
    if nw.y > 0:
        nw = -nw
    e2 = nw.cross(e1).normalized()
    if e2.z > 0:
        e2 = -e2
    L = 0.62
    solid = [(blade(root - e1 * 0.06, root + e1 * (L + 0.06), 0.085, 0.07, e2), "GOLD2"),
             (ellipsoid(root + e1 * 0.05 + nw * 0.02, (0.14, 0.13, 0.11), 2, 0.04), "GOLD")]   # shoulder armor
    blades = []

    def fan(n, t0, t1, a0, a1, l0, l1, w, depth, classes):
        for i in range(n):
            f = i / max(n - 1, 1)
            t = t0 + (t1 - t0) * f
            phi = math.radians(a0 + (a1 - a0) * f)
            d = (e1 * math.cos(phi) + e2 * math.sin(phi)).normalized()
            base = root + e1 * (L * t) + nw * depth - e2 * 0.02
            blades.append((blade(base, base + d * (l0 + (l1 - l0) * f), w, 0.03, nw.cross(d)),
                           classes[i % len(classes)]))

    fan(7, 0.50, 1.00, 62, -8, 0.58, 0.86, 0.16, -0.05, ["GOLD"])            # 1: large primaries
    fan(3, 0.36, 0.74, 74, 46, 0.56, 0.60, 0.045, 0.012, ["LBLUE"])          # cyan accents
    fan(5, 0.16, 0.62, 84, 60, 0.58, 0.66, 0.15, 0.0, ["BLUE"])              # 2: royal-blue secondaries
    fan(4, 0.08, 0.50, 92, 70, 0.26, 0.32, 0.17, 0.045, ["CREAM", "GOLD"])   # 3: broad inner plates
    return solid, blades, tuple(root)


def part_tail():
    b = V(0, 0.40, 0.44)
    blades = []
    spec = [(-54, "GOLD", 0.52, 0.0), (54, "GOLD", 0.52, 0.0), (-36, "GOLD", 0.64, 0.01), (36, "GOLD", 0.64, 0.01),
            (-18, "GOLD", 0.72, 0.02), (18, "GOLD", 0.72, 0.02), (-9, "LBLUE", 0.66, 0.035),
            (9, "LBLUE", 0.66, 0.035), (0, "BLUE", 0.80, 0.045)]
    for ang, cls, ln, dz in spec:
        d = Matrix.Rotation(math.radians(ang), 3, "Z") @ V(0, 1, 0)
        d = V(d.x, d.y, -0.32).normalized()
        w = 0.05 if cls == "LBLUE" else 0.13
        bb = b + V(0, 0, dz)
        blades.append((blade(bb, bb + d * ln, w, 0.03, d.cross(V(0, 0, 1))), cls))
    return [], blades, tuple(b)


def part_leg(side=1):
    hip, ankle = V(0.13 * side, 0.08, 0.30), V(0.17 * side, 0.0, 0.075)
    solid = [(limb(hip, 0.055, ankle, 0.045), "GOLD2"),
             (limb(ankle + V(0, 0, 0.13), 0.068, ankle + V(0, 0, 0.05), 0.066), "GOLD"),
             (ellipsoid(ankle, (0.065, 0.065, 0.045), 2, 0.0), "GOLD")]
    for ang, ln in ((-30, 0.12), (0, 0.135), (30, 0.12), (180, 0.08)):
        d = Matrix.Rotation(math.radians(ang * side), 3, "Z") @ V(0, -1, 0)
        tip = ankle + d * ln + V(0, 0, -0.025)
        s = d.cross(V(0, 0, 1))
        solid.append((blade(ankle, tip, 0.045, 0.04, s), "GOLD"))
        solid.append((blade(tip - d * 0.03, tip + d * 0.06 + V(0, 0, -0.05), 0.032, 0.03, s), "NAVY"))
    return solid, [], tuple(hip)


NECK = Vector((0, -0.16, 0.86))
HEAD_XFORM = Matrix.Translation(NECK + Vector((0, -0.06, -0.02))) @ Matrix.Scale(1.22, 4) @ Matrix.Translation(-NECK)

PARTS = [("Body", part_body, None), ("Head", part_head, "Body"), ("Beak", part_beak, "Head"),
         ("WingL", part_wing, "Body"), ("WingR", "WingL", "Body"), ("Tail", part_tail, "Body"),
         ("LegL", part_leg, "Body"), ("LegR", "LegL", "Body")]   # string = exact X-mirror of that part


# ---------------------------------------------------------------- build helpers
MATS = {}


def cls_mat(cls):
    if cls not in MATS:
        MATS[cls] = bpy.data.materials.new("cls_" + cls)
    return MATS[cls]


def to_obj(name, bm, cls):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(cls_mat(cls))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_part(name, solid, blades):
    """Union the solid prims; append feather blades as separate closed shells."""
    if solid:
        objs = [to_obj(f"{name}_{i}", bm, cls) for i, (bm, cls) in enumerate(solid)]
        base = objs[0]
        coll = None
        if len(objs) > 1:
            coll = bpy.data.collections.new(name + "_ops")
            for ob in objs[1:]:
                bpy.context.scene.collection.objects.unlink(ob)
                coll.objects.link(ob)
            mod = base.modifiers.new("union", "BOOLEAN")
            mod.operation, mod.operand_type, mod.collection = "UNION", "COLLECTION", coll
            mod.solver, mod.material_mode = "EXACT", "TRANSFER"
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
        for ob in objs:
            bpy.data.objects.remove(ob)
        if coll:
            bpy.data.collections.remove(coll)
    else:
        me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bm.from_mesh(me)
    mats = [m.name for m in me.materials]
    for bbm, cls in blades:
        tmp = bpy.data.meshes.new("tmp")
        bbm.to_mesh(tmp)
        bbm.free()
        nf = len(bm.faces)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        mname = cls_mat(cls).name
        if mname not in mats:
            mats.append(mname)
            me.materials.append(cls_mat(cls))
        bm.faces.ensure_lookup_table()
        for f in bm.faces[nf:]:
            f.material_index = mats.index(mname)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.name = name
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for poly in me.polygons:
        poly.use_smooth = False
    return ob


def mirror_part(name, src):
    me = src.data.copy()
    me.name = name
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=bm.verts)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ---------------------------------------------------------------- color function (design coords)
def shade(P, N, C, cls, trand):
    n = len(P)
    col = np.zeros((n, 3))
    glow = np.zeros(n)
    for c, rgb in COLORS.items():
        m = cls == CID[c]
        col[m] = rgb
        glow[m] = GLOW.get(c, 0.0)
    x, y, z = P.T
    ax = np.abs(x)
    side = np.where(x >= 0, 1.0, -1.0)
    gold, cream, navy = (np.array(COLORS[k]) for k in ("GOLD", "CREAM", "NAVY"))
    keep = np.zeros(n, bool)

    # ---- body: ivory with a gold V chest plate framing the gem (navy keyline)
    bm_ = cls == CID["BODYSHELL"]
    col[bm_] = cream
    fr = bm_ & (N[:, 1] < -0.15)
    dia = ax / 0.17 + np.abs(z - 0.68) / 0.27
    vz = np.abs(z - (0.66 + 0.95 * ax))
    plate = fr & ((dia < 1.0) | (vz < 0.055) & (ax < 0.25))
    edge = fr & ((dia < 1.08) | (vz < 0.068) & (ax < 0.26)) & ~plate
    col[edge] = navy
    col[plate] = gold

    # ---- head: ivory with sharp almond eyes, inner corners angled down toward the beak
    hm = cls == CID["HEADSHELL"]
    col[hm] = cream
    ne = np.stack([side * 0.55, -np.ones(n), np.zeros(n)], 1)
    ne /= np.linalg.norm(ne, axis=1, keepdims=True)
    U = np.stack([-ne[:, 1], ne[:, 0], np.zeros(n)], 1) * side[:, None]      # horizontal, outward
    E = np.stack([side * 0.15, np.full(n, -0.44), np.full(n, 1.03)], 1)
    du = np.einsum("ij,ij->i", P - E, U)
    dv = z - 1.03
    th = math.radians(14)
    a = du * math.cos(th) + dv * math.sin(th)
    b = -du * math.sin(th) + dv * math.cos(th)
    w = 0.108
    q = np.clip(1 - (a / w) ** 2, 0, None)
    face = hm & (np.einsum("ij,ij->i", N, ne) > 0.2)
    eye = face & (np.abs(a) < w) & (b < 0.046 * q) & (b > -0.072 * q)
    q2 = np.clip(1 - (a / (w * 1.12)) ** 2, 0, None)
    rim = face & (np.abs(a) < w * 1.12) & (b >= 0.046 * q) & (b < 0.046 * q2 + 0.017) & ~eye
    di = np.hypot(a + 0.008, b + 0.004)
    t = np.clip((0.0 - b) / 0.06 * 0.5 + 0.5, 0, 1)[:, None]
    iris = (1 - t) * np.array([0.07, 0.11, 0.48]) + t * np.array([0.30, 0.58, 1.0])
    ec = np.where((di < 0.066)[:, None], iris, np.array([0.05, 0.06, 0.20]))
    ec = np.where((di < 0.028)[:, None], np.array([0.03, 0.04, 0.18]), ec)
    star = np.sqrt(np.abs(a + 0.01)) + np.sqrt(np.abs(b - 0.008)) < math.sqrt(0.024)
    ec = np.where(star[:, None], np.array([1.0, 1.0, 1.0]), ec)
    col[eye] = ec[eye]
    glow[eye & star] = 1.0
    col[rim] = navy
    keep |= eye | rim

    # ---- gems: faceted sparkle
    gm = cls == CID["GEM"]
    col[gm] = np.clip(col[gm] * (1.0 + 0.30 * trand[gm, None]) + 0.15 * (trand[gm, None] > 0.5), 0, 1)
    keep |= gm

    amp = np.where(np.isin(cls, [CID["GOLD"], CID["GOLD2"]]), 0.10, 0.04)
    var = ~keep
    col[var] = np.clip(col[var] * (1.0 + amp[var, None] * trand[var, None]), 0, 1)
    return col, glow


# ---------------------------------------------------------------- UV atlas + texel bake
def shared_unwrap(objs, scene):
    """Unwrap all parts as one temporary mesh so they share one non-overlapping atlas."""
    comb = bmesh.new()
    for ob in objs:
        comb.from_mesh(ob.data)
    tmp_me = bpy.data.meshes.new("atlas_tmp")
    comb.to_mesh(tmp_me)
    comb.free()
    tmp = bpy.data.objects.new("atlas_tmp", tmp_me)
    scene.collection.objects.link(tmp)
    tmp_me.uv_layers.new(name="UVMap")
    bpy.context.view_layer.objects.active = tmp
    tmp.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    tuv = np.zeros(len(tmp_me.loops) * 2)
    tmp_me.uv_layers.active.data.foreach_get("uv", tuv)
    tuv = tuv.reshape(-1, 2)
    tls = np.zeros(len(tmp_me.polygons), int)
    tmp_me.polygons.foreach_get("loop_start", tls)
    f0 = 0
    for ob in objs:
        me = ob.data
        nf = len(me.polygons)
        ls = np.zeros(nf, int)
        me.polygons.foreach_get("loop_start", ls)
        uv = np.zeros((len(me.loops), 2))
        for j in range(3):
            uv[ls + j] = tuv[tls[f0:f0 + nf] + j]
        me.uv_layers.new(name="UVMap").data.foreach_set("uv", uv.ravel())
        f0 += nf
    bpy.data.objects.remove(tmp)


def mesh_tris(me):
    T = len(me.polygons)
    ls = np.zeros(T, int)
    me.polygons.foreach_get("loop_start", ls)
    lv = np.zeros(len(me.loops), int)
    me.loops.foreach_get("vertex_index", lv)
    co = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    uvs = np.zeros(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uvs)
    mi = np.zeros(T, int)
    me.polygons.foreach_get("material_index", mi)
    li = ls[:, None] + np.arange(3)
    mat_cls = np.array([CID[m.name[4:].split(".")[0]] for m in me.materials])
    return co.reshape(-1, 3)[lv[li]], uvs.reshape(-1, 2)[li], mat_cls[mi]


def bake(objs):
    data = [mesh_tris(o.data) for o in objs]
    tri_p = np.concatenate([d[0] for d in data])
    tri_uv = np.concatenate([d[1] for d in data]) * (TEX * SS) - 0.5
    tcls = np.concatenate([d[2] for d in data])
    T = len(tri_p)
    nrm = np.cross(tri_p[:, 1] - tri_p[:, 0], tri_p[:, 2] - tri_p[:, 0])
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
    cent = tri_p.mean(axis=1)
    trand = np.random.default_rng(3).uniform(-1, 1, T)

    W = TEX * SS
    pix, tid, bar, dist_in = [], [], [], []
    for t in range(T):
        a, b, c = tri_uv[t]
        area2 = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if abs(area2) < 1e-9:
            continue
        x0 = max(int(math.floor(min(a[0], b[0], c[0]) - 1)), 0)
        x1 = min(int(math.ceil(max(a[0], b[0], c[0]) + 1)), W - 1)
        y0 = max(int(math.floor(min(a[1], b[1], c[1]) - 1)), 0)
        y1 = min(int(math.ceil(max(a[1], b[1], c[1]) + 1)), W - 1)
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        xs, ys = xs.ravel(), ys.ravel()
        w0 = ((b[0] - xs) * (c[1] - ys) - (b[1] - ys) * (c[0] - xs)) / area2
        w1 = ((c[0] - xs) * (a[1] - ys) - (c[1] - ys) * (a[0] - xs)) / area2
        Wb = np.stack([w0, w1, 1.0 - w0 - w1], 1)
        L = np.array([np.linalg.norm(c - b), np.linalg.norm(a - c), np.linalg.norm(b - a)])
        dist = (Wb * (abs(area2) / np.maximum(L, 1e-9))).min(axis=1)
        keep = dist > -1.5
        if not keep.any():
            continue
        Wk = np.clip(Wb[keep], 0, None)
        Wk /= Wk.sum(1, keepdims=True)
        pix.append(ys[keep] * W + xs[keep])
        tid.append(np.full(keep.sum(), t))
        bar.append(Wk)
        dist_in.append(dist[keep])
    pix, tid, bar, dist_in = map(np.concatenate, (pix, tid, bar, dist_in))
    P = np.einsum("nk,nkj->nj", bar, tri_p[tid])
    col, glow = shade(P, nrm[tid], cent[tid], tcls[tid], trand[tid])

    _, cnt = np.unique(pix[dist_in > 0.3], return_counts=True)
    overlap = int((cnt > 1).sum()) // (SS * SS)      # in final-texture pixels

    img = np.zeros((W * W, 4))
    order = np.argsort(dist_in >= 0, kind="stable")
    img[pix[order], :3] = col[order]
    img[pix[order], 3] = glow[order]
    filled = np.zeros(W * W, bool)
    filled[pix] = True
    img = img.reshape(W, W, 4)
    filled = filled.reshape(W, W)
    for _ in range(12):
        acc = np.zeros_like(img)
        cnt2 = np.zeros((W, W))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(img * filled[..., None], dx, 1), dy, 0)
            cnt2 += np.roll(np.roll(filled, dx, 1), dy, 0)
        grow = ~filled & (cnt2 > 0)
        img[grow] = acc[grow] / cnt2[grow][:, None]
        filled |= grow
    return img.reshape(TEX, SS, TEX, SS, 4).mean(axis=(1, 3)), overlap


def save_png(arr_rgb, name, colorspace="sRGB"):
    im = bpy.data.images.new(name, TEX, TEX, alpha=False)
    px = np.ones((TEX, TEX, 4))
    px[..., :3] = arr_rgb
    im.pixels.foreach_set(px.ravel().astype(np.float32))
    im.filepath_raw = os.path.join(OUT, name)
    im.file_format = "PNG"
    im.save()
    im.colorspace_settings.name = colorspace
    return im


# ---------------------------------------------------------------- render sheet
def setup_stage(scene):
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.08, 0.08, 0.10, 1)
    fm = bpy.data.meshes.new("floor")
    fm.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("floor", fm)
    fmat = bpy.data.materials.new("floor")
    fmat.use_nodes = True
    fmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.04, 0.04, 0.05, 1)
    fm.materials.append(fmat)
    scene.collection.objects.link(floor)
    for nm, energy, rx, rz in (("key", 3.5, 45, -35), ("rim", 2.0, 60, 160)):
        L = bpy.data.objects.new(nm, bpy.data.lights.new(nm, "SUN"))
        L.data.energy = energy
        L.data.angle = math.radians(20)
        L.rotation_euler = (math.radians(rx), 0, math.radians(rz))
        scene.collection.objects.link(L)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 560
    scene.view_settings.view_transform = "Standard"
    return cam


def render_sheet(scene, cam, objs, path):
    co = np.concatenate([np.array([(o.matrix_world @ v.co)[:] for v in o.data.vertices]) for o in objs])
    lo, hi = co.min(0), co.max(0)
    target = Vector(((lo + hi) / 2).tolist())
    size = float(max(hi - lo))
    tiles = []
    for d in ((0, -1, 0.12), (-1, 0, 0.10), (-0.62, -0.76, 0.22)):      # front, side, 3/4
        dv = Vector(d).normalized()
        cam.location = target + dv * size * 1.75
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        tmp = path + ".tile.png"
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(tmp)
        tiles.append(np.array(im.pixels[:]).reshape(im.size[1], im.size[0], 4))
        bpy.data.images.remove(im)
        os.remove(tmp)
    sheet = np.concatenate(tiles, axis=1)
    out = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=False)
    out.pixels.foreach_set(sheet.ravel().astype(np.float32))
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()


# ---------------------------------------------------------------- main
def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    objs, pivots, parents = [], {}, {}
    for name, fn, parent in PARTS:
        if isinstance(fn, str):
            src = next(o for o in objs if o.name == fn)
            objs.append(mirror_part(name, src))
            pv = pivots[fn]
            pivots[name], parents[name] = Vector((-pv.x, pv.y, pv.z)), parent
            continue
        solid, blades, pivot = fn()
        if name in ("Head", "Beak"):
            for bm_, _ in solid + blades:
                bmesh.ops.transform(bm_, matrix=HEAD_XFORM, verts=bm_.verts)
            pivot = HEAD_XFORM @ Vector(pivot)
        objs.append(build_part(name, solid, blades))
        pivots[name], parents[name] = Vector(pivot), parent

    # global scale, ground at z=0, centred between the feet, origins on joint pivots
    allco = np.concatenate([np.array([v.co[:] for v in o.data.vertices]) for o in objs])
    s = TARGET_H / (allco[:, 2].max() - allco[:, 2].min())
    feet = np.concatenate([np.array([v.co[:] for v in o.data.vertices]) for o in objs if o.name.startswith("Leg")])
    off = Vector((-0.5 * (feet[:, 0].min() + feet[:, 0].max()),
                  -0.5 * (feet[:, 1].min() + feet[:, 1].max()), -allco[:, 2].min()))
    G = Matrix.Scale(s, 4) @ Matrix.Translation(off)
    for ob in objs:
        piv = G @ pivots[ob.name]
        ob.data.transform(Matrix.Translation(-piv) @ G)
        ob.location = piv
    bpy.context.view_layer.update()

    cam = setup_stage(scene)
    clay = bpy.data.materials.new("clay")
    clay.use_nodes = True
    clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.6, 0.6, 0.62, 1)
    scene.view_layers[0].material_override = clay
    render_sheet(scene, cam, objs, os.path.join(OUT, "golden_falcon_clay.png"))
    scene.view_layers[0].material_override = None
    if STAGE == "clay":
        print("CLAY DONE")
        return

    # bake in design space (shade() works in design coordinates), then restore placement
    Ginv = G.inverted()
    for ob in objs:
        ob.data.transform(Ginv @ Matrix.Translation(ob.location))
    shared_unwrap(objs, scene)
    img, overlap = bake(objs)
    for ob in objs:
        ob.data.transform(Matrix.Translation(-ob.location) @ G)
    col_img = save_png(img[..., :3], "golden_falcon_color.png")
    msk_img = save_png(np.repeat(img[..., 3:4], 3, axis=2), "golden_falcon_emissive.png", "Non-Color")

    mat = bpy.data.materials.new("GoldenFalcon")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = col_img
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.4

    joints, total, nonman, ngons = {}, 0, 0, 0
    for ob in objs:
        me = ob.data
        me.materials.clear()
        me.materials.append(mat)
        bm = bmesh.new()
        bm.from_mesh(me)
        nonman += sum(1 for e in bm.edges if not e.is_manifold)
        ngons += sum(1 for f in bm.faces if len(f.verts) != 3)
        bm.free()
        total += len(me.polygons)
        joints[ob.name] = {"parent": parents[ob.name], "tris": len(me.polygons),
                           "pivot_blender_studs": [round(c / STUD, 3) for c in ob.location]}
    bpy.context.view_layer.update()
    allco = np.concatenate([np.array([(ob.matrix_world @ v.co)[:] for v in ob.data.vertices]) for ob in objs])
    dims = allco.max(0) - allco.min(0)
    with open(os.path.join(OUT, "golden_falcon_joints.json"), "w") as f:
        json.dump({"note": "Pivots are part origins in Blender axes (X = model's left, Y = back, Z = up), "
                           "in studs, ground at Z=0; model faces -Y. Connect each part to its parent "
                           "with a Motor6D placed at the part's pivot.",
                   "parts": joints}, f, indent=2)
    stats = (f"tris={total} parts={len(objs)} nonmanifold_edges={nonman} ngons={ngons} "
             f"uv_overlap_px={overlap} studs=({dims[0]/STUD:.2f},{dims[1]/STUD:.2f},{dims[2]/STUD:.2f}) "
             + " ".join(f"{k}:{v['tris']}" for k, v in joints.items()))
    print("STATS", stats)

    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "golden_falcon.fbx"), use_selection=True,
        object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True,
        axis_forward="-Z", axis_up="Y")

    # textured verification sheet (glow previewed via emission)
    tm = nt.nodes.new("ShaderNodeTexImage")
    tm.image = msk_img
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Emission Color"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 4.0
    nt.links.new(tm.outputs["Color"], mul.inputs[0])
    nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
    bsdf.inputs["Metallic"].default_value = 0.25
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "golden_falcon.blend"), relative_remap=True)
    render_sheet(scene, cam, objs, os.path.join(OUT, "golden_falcon_preview.png"))
    print("DONE", stats)


if __name__ == "__main__":
    main()
