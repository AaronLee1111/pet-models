"""Build the chibi Robo-Manager pet for Roblox (MeshPart + SurfaceAppearance).

Run with the `bpy` module (pip install bpy) or Blender:
    python3 scripts/build_robo_manager.py
    blender -b -P scripts/build_robo_manager.py

Outputs (in ./export):
    robo_manager.fbx              one triangulated, flat-shaded mesh (texture embedded)
    robo_manager_color.png        1024x1024 ColorMap
    robo_manager_emissive.png     1024x1024 emissive mask (white = glow)
    robo_manager_roughness.png    optional RoughnessMap (glossy visor)
    robo_manager.blend            source scene
    robo_manager_preview.png      verification render (front 3/4)
"""
import math
import os

import bpy  # noqa: must precede bmesh when using the pip bpy module
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "export")
TEX = 1024
SS = 2                       # supersampling for the texel bake
TARGET_H = 3.5 * 0.28        # 3.5 studs tall, in metres
RENDER = os.environ.get("ROBO_RENDER", "1") == "1"

WHITE = np.array([0.90, 0.91, 0.95])
NAVY = np.array([0.075, 0.085, 0.16])
DARK = np.array([0.04, 0.045, 0.085])
VISOR = np.array([0.02, 0.02, 0.04])
CYAN = np.array([0.18, 0.86, 1.0])
MAGENTA = np.array([1.0, 0.16, 0.76])
SHIRT = np.array([0.96, 0.96, 0.98])
BADGE = np.array([0.80, 0.82, 0.87])
HOLO = np.array([0.05, 0.25, 0.48])


def rot(deg):
    m = Matrix.Identity(3)
    for axis, a in zip("XYZ", deg):
        m = Matrix.Rotation(math.radians(a), 3, axis) @ m
    return m


# ---------------------------------------------------------------- parts
# Superquadric: ((|u|^e1 + |v|^e1)^(e2/e1) + |w|^e2) = 1, w along `axis`.
# name, center, radii(x,y,z), e1, e2, grid n, axis, rotation(deg), mirrored
SQ_PARTS = [
    ("head",     (0.0, 0.0, 1.40),     (0.56, 0.46, 0.46),  3.4, 3.4, 10, "Z", (0, 0, 0), False),
    ("visor",    (0.0, -0.27, 1.37),   (0.43, 0.23, 0.30),  3.4, 3.4, 8,  "Z", (0, 0, 0), False),
    ("toppanel", (0.0, -0.02, 1.86),   (0.15, 0.13, 0.05),  4.0, 4.0, 4,  "Z", (0, 0, 0), False),
    ("headset",  (0.55, 0.0, 1.36),    (0.11, 0.25, 0.25),  2.0, 5.0, 7,  "X", (0, 0, 0), True),
    ("neck",     (0.0, 0.0, 0.93),     (0.14, 0.14, 0.08),  2.0, 3.0, 4,  "Z", (0, 0, 0), False),
    ("torso",    (0.0, 0.0, 0.66),     (0.30, 0.24, 0.26),  2.6, 3.5, 8,  "Z", (0, 0, 0), False),
    ("badge",    (0.15, -0.205, 0.70), (0.045, 0.03, 0.06), 5.0, 6.0, 3,  "Y", (-12, 0, 0), False),
    ("sleeve",   (0.36, -0.01, 0.70),  (0.10, 0.10, 0.13),  2.4, 2.4, 5,  "Z", (0, 0, 0), True),
    ("wrist",    (0.41, -0.03, 0.60),  (0.085, 0.085, 0.04), 2.0, 4.0, 4, "Z", (0, 0, 0), True),
    ("hand",     (0.45, -0.05, 0.52),  (0.125, 0.12, 0.11),  2.0, 2.0, 4,  "Z", (0, 0, 0), True),
    ("pod",      (0.0, 0.0, 0.42),     (0.24, 0.21, 0.18),  2.5, 2.5, 6,  "Z", (0, 0, 0), False),
    ("base",     (0.0, 0.0, 0.25),     (0.20, 0.18, 0.09),  2.0, 2.4, 6,  "Z", (0, 0, 0), False),
    ("tablet",   (0.70, -0.20, 0.80),  (0.16, 0.012, 0.21), 6.0, 8.0, 5,  "Y", (-10, 0, 25), False),
]


def hull_ear():
    pts = []
    for y in (-0.08, 0.08):
        pts += [(0.16, y, 1.74), (0.40, y, 1.74)]
    pts += [(0.46, -0.025, 2.14), (0.46, 0.025, 2.14)]
    return pts


def hull_tie():
    pts = []
    for (hw, z, yf, yb) in ((0.038, 0.90, -0.19, -0.13), (0.045, 0.855, -0.24, -0.17),
                            (0.062, 0.73, -0.268, -0.20), (0.0, 0.64, -0.262, -0.20)):
        for x in ({0.0} if hw == 0 else {hw, -hw}):
            pts += [(x, yf, z), (x, yb, z)]
    return pts


def hull_thruster():
    pts = [(0.11 * math.cos(a), 0.11 * math.sin(a), 0.19)
           for a in np.linspace(0, 2 * math.pi, 10, endpoint=False)]
    return pts + [(0.0, 0.0, 0.0)]


HULL_PARTS = [("ear", hull_ear, True), ("tie", hull_tie, False), ("thruster", hull_thruster, False)]
PART_NAMES = [p[0] for p in SQ_PARTS] + [h[0] for h in HULL_PARTS]
PID = {n: i for i, n in enumerate(PART_NAMES)}
FRAMES = {}   # part name -> (center, rotation 3x3) for texture-space features (+X side)


def sq_mesh(radii, e1, e2, n, axis):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=n - 1, use_grid_fill=True)
    k = "XYZ".index(axis)
    i, j = [a for a in range(3) if a != k]
    for v in bm.verts:
        q = np.array(v.co[:])
        F = (abs(q[i]) ** e1 + abs(q[j]) ** e1) ** (e2 / e1) + abs(q[k]) ** e2
        p = q * F ** (-1.0 / e2) * np.array(radii)
        v.co = Vector(p)
    return bm


def make_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_parts():
    objs = []
    for name, c, r, e1, e2, n, axis, rdeg, mirrored in SQ_PARTS:
        mat = bpy.data.materials.new("part_" + name)
        R = rot(rdeg)
        FRAMES[name] = (np.array(c), np.array(R))
        for side in ((1, -1) if mirrored else (1,)):
            bm = sq_mesh(r, e1, e2, n, axis)
            M = Matrix.Translation((c[0] * side, c[1], c[2])) @ R.to_4x4()
            bmesh.ops.transform(bm, matrix=M, verts=bm.verts)   # mirrored parts are x-symmetric
            objs.append(make_obj(f"{name}_{side}", bm, mat))
    for name, fn, mirrored in HULL_PARTS:
        mat = bpy.data.materials.new("part_" + name)
        for side in ((1, -1) if mirrored else (1,)):
            bm = bmesh.new()
            vs = [bm.verts.new((x * side, y, z)) for x, y, z in fn()]
            res = bmesh.ops.convex_hull(bm, input=vs)
            bmesh.ops.delete(bm, geom=res["geom_interior"] + res["geom_unused"], context="VERTS")
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            objs.append(make_obj(f"{name}_{side}", bm, mat))
    return objs


# ---------------------------------------------------------------- color function
def superellipse(a, b, ra, rb, e=4.0):
    return (np.abs(a / ra) ** e + np.abs(b / rb) ** e) ** (1.0 / e)


def shade(P, N, part, trand):
    """sRGB color, emissive mask (0..1) and roughness for surface samples (design coords)."""
    n = len(P)
    col = np.tile(WHITE, (n, 1))
    glow = np.zeros(n)
    rough = np.full(n, 0.5)
    is_ = lambda *names: np.isin(part, [PID[x] for x in names])
    x, y, z = P.T
    ax = np.abs(x)
    nx_out = N[:, 0] * np.where(x >= 0, 1, -1)
    front = N[:, 1] < -0.35

    # ---- base colors per part
    col[is_("torso", "sleeve", "pod", "toppanel")] = NAVY
    col[is_("neck", "wrist")] = DARK
    col[is_("tie")] = MAGENTA
    col[is_("badge")] = BADGE
    col[is_("thruster")] = CYAN
    glow[is_("thruster")] = 1.0

    # ---- visor: glossy black with a faint purple sheen at the top, cyan eye bars
    vm = is_("visor")
    vz = (z - 1.37) / 0.30
    col[vm] = VISOR + np.clip(vz[vm, None] - 0.35, 0, 1) * np.array([0.10, 0.04, 0.20])
    rough[vm] = 0.12
    eyes = vm & front & (superellipse(ax - 0.16, z - 1.37, 0.048, 0.10, 4) < 1.0)
    col[eyes] = CYAN
    glow[eyes] = 1.0
    # dark rim on the head shell around the visor
    rim = is_("head") & (N[:, 1] < -0.2) & (superellipse(x, z - 1.37, 0.47, 0.34, 3.4) < 1.0)
    col[rim] = NAVY

    # ---- headsets: outer face = dark hub, cyan ring, white shell, magenta outer rim
    hs = is_("headset")
    rr = np.hypot(y - 0.0, z - 1.36)
    face = hs & (nx_out > 0.6)
    col[hs & ~face] = NAVY
    col[face & (rr < 0.10)] = DARK
    ring = face & (rr >= 0.10) & (rr < 0.145)
    col[ring] = CYAN
    glow[ring] = 1.0
    mag = face & (rr >= 0.205) & (rr < 0.225)
    col[mag] = MAGENTA
    glow[mag] = 1.0

    # ---- ears: white fin, front face dark inset with cyan outline
    em = is_("ear") & (N[:, 1] < -0.3)
    A, B, C = np.array([0.20, 1.84]), np.array([0.40, 1.84]), np.array([0.45, 2.10])
    det = (B[0] - A[0]) * (C[1] - A[1]) - (B[1] - A[1]) * (C[0] - A[0])
    w1 = ((ax - A[0]) * (C[1] - A[1]) - (z - A[1]) * (C[0] - A[0])) / det
    w2 = ((B[0] - A[0]) * (z - A[1]) - (B[1] - A[1]) * (ax - A[0])) / det
    m = np.minimum(np.minimum(1 - w1 - w2, w1), w2)
    col[em & (m > 0.17)] = DARK
    eo = em & (m > 0.07) & (m <= 0.17)
    col[eo] = CYAN
    glow[eo] = 1.0

    # ---- top panel: magenta light strip
    tp = is_("toppanel") & (N[:, 2] > 0.6) & (np.abs(x) < 0.09) & (np.abs(y + 0.02) < 0.025)
    col[tp] = MAGENTA
    glow[tp] = 1.0

    # ---- suit front: white shirt V, magenta lapel piping
    tf = is_("torso") & (N[:, 1] < -0.2)
    wv = 0.16 * np.clip((z - 0.60) / (0.92 - 0.60), 0, 1)
    col[tf & (ax < wv)] = SHIRT
    pip = tf & (np.abs(ax - wv - 0.035) < 0.007) & (z > 0.58)
    col[pip] = MAGENTA
    glow[pip] = 0.6
    # jacket button
    col[tf & (np.hypot(x, z - 0.58) < 0.016)] = DARK

    # ---- tie: lighter inner chevron
    tie = is_("tie") & (N[:, 1] < -0.3)
    col[tie & (np.abs(x) < 0.5 * (z - 0.68)) & (z < 0.84)] = np.array([1.0, 0.45, 0.88])
    col[tie & (z > 0.855)] = np.array([0.78, 0.08, 0.58])     # knot

    # ---- ID badge: clip + small glowing screen with bars
    c, R = FRAMES["badge"]
    lb = (P - c) @ R
    bf = is_("badge") & (N[:, 1] < -0.3)
    scr = bf & (np.abs(lb[:, 0]) < 0.03) & (lb[:, 2] > -0.045) & (lb[:, 2] < 0.015)
    col[scr] = HOLO
    glow[scr] = 0.4
    bars = np.zeros(n, bool)
    for bx, bh in ((-0.016, 0.022), (0.0, 0.036), (0.016, 0.05)):
        bars |= (np.abs(lb[:, 0] - bx) < 0.005) & (lb[:, 2] < -0.04 + bh)
    col[scr & bars] = CYAN
    glow[scr & bars] = 1.0
    col[bf & (lb[:, 2] > 0.03) & (np.abs(lb[:, 0]) < 0.012)] = DARK            # clip slot

    # ---- hover base: cyan glow ring around the underside
    bs = is_("base")
    bring = bs & (N[:, 2] < -0.45)
    col[bring] = CYAN
    glow[bring] = 1.0

    # ---- holographic tablet
    c, R = FRAMES["tablet"]
    lt = (P - c) @ R
    tb = is_("tablet")
    se = superellipse(lt[:, 0], lt[:, 2], 0.16, 0.21, 6)
    col[tb] = HOLO
    glow[tb] = 0.45
    border = tb & ((se > 0.86) | (np.abs(lt[:, 1]) < 0.006) & (se > 0.8))
    tbars = np.zeros(n, bool)
    for bx, bh in ((-0.085, 0.08), (-0.03, 0.14), (0.025, 0.11), (0.08, 0.21)):
        tbars |= (np.abs(lt[:, 0] - bx) < 0.019) & (lt[:, 2] > -0.15) & (lt[:, 2] < -0.15 + bh)
    tbars |= (np.abs(lt[:, 2] - 0.13) < 0.012) & (lt[:, 0] > -0.11) & (lt[:, 0] < 0.04)
    hot = tb & (border | tbars)
    col[hot] = CYAN
    glow[hot] = 1.0

    # subtle facet tone variation on the shell / suit
    var = glow == 0
    col[var] = np.clip(col[var] * (1.0 + 0.025 * trand[var, None]), 0, 1)
    return col, glow, rough


# ---------------------------------------------------------------- texel bake
def bake_textures(me, owner):
    T = len(me.polygons)
    ls = np.zeros(T, int)
    me.polygons.foreach_get("loop_start", ls)
    lv = np.zeros(len(me.loops), int)
    me.loops.foreach_get("vertex_index", lv)
    co = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    uvs = np.zeros(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uvs)
    uvs = uvs.reshape(-1, 2)
    li = ls[:, None] + np.arange(3)
    tri_p = co[lv[li]]
    tri_uv = uvs[li] * (TEX * SS) - 0.5
    nrm = np.cross(tri_p[:, 1] - tri_p[:, 0], tri_p[:, 2] - tri_p[:, 0])
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
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
    col, glow, rough = shade(P, nrm[tid], owner[tid], trand[tid])

    _, cnt = np.unique(pix[dist_in > 0.3], return_counts=True)
    overlap = int((cnt > 1).sum())

    img = np.zeros((W * W, 5))
    order = np.argsort(dist_in >= 0, kind="stable")    # samples inside their triangle win
    img[pix[order], :3] = col[order]
    img[pix[order], 3] = glow[order]
    img[pix[order], 4] = rough[order]
    filled = np.zeros(W * W, bool)
    filled[pix] = True
    img = img.reshape(W, W, 5)
    filled = filled.reshape(W, W)
    for _ in range(12):       # dilate into the UV gutters
        acc = np.zeros_like(img)
        cnt2 = np.zeros((W, W))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(img * filled[..., None], dx, 1), dy, 0)
            cnt2 += np.roll(np.roll(filled, dx, 1), dy, 0)
        grow = ~filled & (cnt2 > 0)
        img[grow] = acc[grow] / cnt2[grow][:, None]
        filled |= grow
    img = img.reshape(TEX, SS, TEX, SS, 5).mean(axis=(1, 3))
    return img, overlap


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


# ---------------------------------------------------------------- main
def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    objs = build_parts()
    base = next(o for o in objs if o.name.startswith("head"))
    coll = bpy.data.collections.new("operands")
    for ob in objs:
        if ob is base:
            continue
        scene.collection.objects.unlink(ob)
        coll.objects.link(ob)
    mod = base.modifiers.new("union", "BOOLEAN")
    mod.operation = "UNION"
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    mod.solver = "EXACT"
    mod.material_mode = "TRANSFER"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    for ob in objs:
        bpy.data.objects.remove(ob)
    bpy.data.collections.remove(coll)

    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()

    # face ownership from the transferred part materials
    mat_pid = np.array([PID[m.name[5:].split(".")[0]] for m in me.materials])
    mi = np.zeros(len(me.polygons), int)
    me.polygons.foreach_get("material_index", mi)
    owner = mat_pid[mi]

    robo = bpy.data.objects.new("RoboManager", me)
    scene.collection.objects.link(robo)
    bpy.context.view_layer.objects.active = robo
    robo.select_set(True)
    for p in me.polygons:
        p.use_smooth = False

    me.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    img, overlap = bake_textures(me, owner)
    col_img = save_png(img[..., :3], "robo_manager_color.png")
    msk_img = save_png(np.repeat(img[..., 3:4], 3, axis=2), "robo_manager_emissive.png", "Non-Color")
    rgh_img = save_png(np.repeat(img[..., 4:5], 3, axis=2), "robo_manager_roughness.png", "Non-Color")

    # single material, scale to 3.5 studs tall, origin at bottom center of the body
    me.materials.clear()
    co = np.array([v.co[:] for v in me.vertices])
    s = TARGET_H / (co[:, 2].max() - co[:, 2].min())
    body = ~np.isin(owner, [PID["tablet"]])
    bv = np.array([me.vertices[i].co[:] for p in np.nonzero(body)[0] for i in me.polygons[p].vertices])
    cx = 0.5 * (bv[:, 0].min() + bv[:, 0].max())
    cy = 0.5 * (bv[:, 1].min() + bv[:, 1].max())
    me.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -co[:, 2].min())))
    me.update()

    def make_mat(name, preview):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = col_img
        nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.5
        if preview:
            tr = nt.nodes.new("ShaderNodeTexImage")
            tr.image = rgh_img
            nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
            tm = nt.nodes.new("ShaderNodeTexImage")
            tm.image = msk_img
            nt.links.new(tc.outputs["Color"], bsdf.inputs["Emission Color"])
            mul = nt.nodes.new("ShaderNodeMath")
            mul.operation = "MULTIPLY"
            mul.inputs[1].default_value = 5.0
            nt.links.new(tm.outputs["Color"], mul.inputs[0])
            nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
        return m

    me.materials.append(make_mat("RoboManager", False))

    bm = bmesh.new()
    bm.from_mesh(me)
    nonman = sum(1 for e in bm.edges if not e.is_manifold)
    ngons = sum(1 for f in bm.faces if len(f.verts) != 3)
    loose_v = sum(1 for v in bm.verts if not v.link_faces)
    shells = len(set(owner.tolist()))
    bm.free()
    vco = np.array([v.co[:] for v in me.vertices])
    dims = vco.max(0) - vco.min(0)
    stats = (f"tris={len(me.polygons)} verts={len(me.vertices)} nonmanifold_edges={nonman} "
             f"ngons={ngons} loose_verts={loose_v} uv_overlap_px={overlap} parts={shells} "
             f"dims_m=({dims[0]:.3f},{dims[1]:.3f},{dims[2]:.3f}) "
             f"studs=({dims[0]/0.28:.2f},{dims[1]/0.28:.2f},{dims[2]/0.28:.2f})")
    print("STATS", stats)

    bpy.ops.object.select_all(action="DESELECT")
    robo.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "robo_manager.fbx"), use_selection=True,
        object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True,
        axis_forward="-Z", axis_up="Y")

    # ---- verification render (front 3/4)
    me.materials[0] = make_mat("RoboManager_preview", True)
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.06, 0.07, 0.12, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    fm = bpy.data.meshes.new("floor")
    fm.from_pydata([(-20, -20, -0.06), (20, -20, -0.06), (20, 20, -0.06), (-20, 20, -0.06)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("floor", fm)
    fmat = bpy.data.materials.new("floor")
    fmat.use_nodes = True
    fmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.015, 0.018, 0.03, 1)
    fm.materials.append(fmat)
    scene.collection.objects.link(floor)
    for nm, energy, rx, rz in (("key", 3.0, 45, 30), ("rim", 1.5, 60, 200)):
        L = bpy.data.objects.new(nm, bpy.data.lights.new(nm, "SUN"))
        L.data.energy = energy
        L.data.angle = math.radians(25)
        L.rotation_euler = (math.radians(rx), 0, math.radians(rz))
        scene.collection.objects.link(L)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    target = Vector((0.03, 0.0, 0.5 * TARGET_H))
    d = Vector((0.55, -0.83, 0.18)).normalized()
    cam.location = target + d * 1.85
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "robo_manager.blend"), relative_remap=True)

    if RENDER:
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 48
        scene.cycles.use_denoising = True
        scene.render.resolution_x = scene.render.resolution_y = 800
        scene.view_settings.view_transform = "Standard"
        scene.render.filepath = os.path.join(OUT, "robo_manager_preview.png")
        bpy.ops.render.render(write_still=True)
    print("DONE", stats)


if __name__ == "__main__":
    main()
