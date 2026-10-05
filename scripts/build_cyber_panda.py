"""Build the low-poly cyber-panda cub for Roblox (MeshPart + SurfaceAppearance).

Run with the `bpy` module (pip install bpy) or Blender:
    python3 scripts/build_cyber_panda.py
    blender -b -P scripts/build_cyber_panda.py

Outputs (in ./export):
    cyber_panda.fbx            single triangulated, flat-shaded mesh (texture embedded)
    cyber_panda_color.png      1024x1024 ColorMap (baked base color)
    cyber_panda_emissive.png   1024x1024 emissive mask (white = cyan glow)
    cyber_panda.blend          source scene
    cyber_panda_preview.png    verification render (front 3/4)
"""
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
SS = 2                      # supersampling for the texel bake
TARGET_LEN = 4 * 0.28       # 4 studs long, in metres
RENDER = os.environ.get("PANDA_RENDER", "1") == "1"

WHITE = np.array([0.93, 0.94, 0.96])
BLACK = np.array([0.075, 0.08, 0.095])
CYAN = np.array([0x2E, 0xC8, 0xFF]) / 255.0

# ---------------------------------------------------------------- parts
# Everything is modelled facing -Y, Z up, ground at z=0 (design units, rescaled at the end).
HEAD_PIVOT = Vector((0.0, -0.15, 0.55))
R_HEAD = Matrix.Rotation(math.radians(-8), 3, "X")   # head tilted up a little

# name, center, radii, rotation (deg xyz), icosphere subdivisions, mirrored, group, flatten bottom
PARTS_DEF = [
    ("torso",    (0.0, 0.08, 0.38),     (0.28, 0.42, 0.27),    (0, 0, 0),  3, False, "body", False),
    ("rump",     (0.0, 0.32, 0.38),     (0.27, 0.24, 0.26),    (0, 0, 0),  3, False, "body", False),
    ("tail",     (0.0, 0.54, 0.47),     (0.075, 0.07, 0.075),  (0, 0, 0),  2, False, "body", False),
    ("core",     (0.0, -0.33, 0.30),    (0.07, 0.03, 0.07),    (0, 0, 0),  2, False, "body", False),
    ("shoulder", (0.20, -0.13, 0.40),   (0.15, 0.17, 0.17),    (0, 0, 0),  3, True,  "body", False),
    ("fleg",     (0.21, -0.19, 0.20),   (0.115, 0.12, 0.19),   (0, 0, 0),  3, True,  "body", False),
    ("fpaw",     (0.215, -0.25, 0.045), (0.125, 0.15, 0.08),   (0, 0, 0),  3, True,  "body", True),
    ("thigh",    (0.20, 0.32, 0.25),    (0.15, 0.21, 0.20),    (0, 0, 0),  3, True,  "body", False),
    ("hpaw",     (0.21, 0.24, 0.045),   (0.12, 0.16, 0.08),    (0, 0, 0),  3, True,  "body", True),
    ("head",     (0.0, -0.30, 0.68),    (0.34, 0.30, 0.30),    (0, 0, 0),  4, False, "head", False),
    ("muzzle",   (0.0, -0.56, 0.555),   (0.14, 0.10, 0.085),   (0, 0, 0),  3, False, "head", False),
    ("nose",     (0.0, -0.655, 0.605),  (0.04, 0.025, 0.026),  (0, 0, 0),  2, False, "head", False),
    ("ear",      (0.22, -0.26, 0.93),   (0.10, 0.055, 0.10),   (0, 0, 15), 3, True,  "head", False),
]
PART_NAMES = sorted({p[0] for p in PARTS_DEF})
PID = {n: i for i, n in enumerate(PART_NAMES)}
S_MIRROR = Matrix(((-1, 0, 0), (0, 1, 0), (0, 0, 1)))


def euler_mat(deg):
    m = Matrix.Identity(3)
    for axis, a in zip("XYZ", deg):
        m = Matrix.Rotation(math.radians(a), 3, axis) @ m
    return m


def build_parts():
    """Create one jittered icosphere-ellipsoid object per part; return objects + ownership table."""
    rng = random.Random(11)
    objs, table = [], []
    for name, c, r, rot, sd, mirrored, group, flat in PARTS_DEF:
        R = euler_mat(rot)
        base = bmesh.new()
        bmesh.ops.create_icosphere(base, subdivisions=sd, radius=1.0)
        jit = 0.03 if group == "head" else 0.04
        for v in base.verts:   # radial jitter -> crystalline facets
            v.co *= 1.0 + rng.uniform(-jit, jit)
        sides = (1, -1) if mirrored else (1,)
        for side in sides:
            bm = base.copy()
            cc = Vector(c)
            RR = R.copy()
            if side < 0:
                cc.x = -cc.x
                RR = S_MIRROR @ R @ S_MIRROR
            for v in bm.verts:
                co = RR @ Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2])) + cc
                if group == "head":
                    co = R_HEAD @ (co - HEAD_PIVOT) + HEAD_PIVOT
                if flat:
                    co.z = max(co.z, 0.0)
                v.co = co
            me = bpy.data.meshes.new(f"{name}_{side}")
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new(me.name, me)
            bpy.context.scene.collection.objects.link(ob)
            objs.append(ob)
            table.append((PID[name], np.array(cc), np.array(r), np.array(RR), group == "head"))
        base.free()
    return objs, table


def untilt(P, N):
    Rt = np.array(R_HEAD).T
    piv = np.array(HEAD_PIVOT)
    return (P - piv) @ Rt.T + piv, N @ Rt.T


def assign_parts(cent, table):
    """Owner part of each face = ellipsoid whose normalised radius is closest to the face."""
    best = np.full(len(cent), np.inf)
    owner = np.zeros(len(cent), int)
    head_c, _ = untilt(cent, np.zeros_like(cent))
    for pid, c, r, R, is_head in table:
        p = head_c if is_head else cent
        loc = ((p - c) @ R) / r
        g = np.abs(np.linalg.norm(loc, axis=1) - 1.0)
        upd = g < best
        best[upd] = g[upd]
        owner[upd] = pid
    return owner


# ---------------------------------------------------------------- color function
def cells_mask(a, b, s, cells):
    c = np.floor(a / s).astype(int)
    r = np.floor(b / s).astype(int)
    m = np.zeros(a.shape, bool)
    for ci, ri in cells:
        m |= (c == ci) & (r == ri)
    return m


def shade(P, N, C, part, trand, table):
    """Return sRGB color (n,3) and emissive mask (n,) for surface samples.
    P sample position, N face normal, C face centroid (design coords), part id, trand per-face rand."""
    n = len(P)
    col = np.tile(WHITE, (n, 1))
    glow = np.zeros(n, bool)
    clean = np.zeros(n, bool)          # skip facet tone variation here (eyes)
    is_ = lambda *names: np.isin(part, [PID[x] for x in names])
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    side = np.where(x >= 0, 1.0, -1.0)
    lat = N[:, 0] * side                # outward-facing component

    # ---- solid black parts
    blk = is_("tail", "core", "shoulder", "fleg", "fpaw", "thigh", "hpaw", "nose", "ear")
    # shoulder saddle band over the back
    blk |= is_("torso") & (C[:, 1] > -0.26) & (C[:, 1] < 0.0) & (C[:, 2] > 0.22) & (N[:, 1] > -0.5)
    # collar: V-band on the chest leading down to the core
    zc = 0.30 + 0.8 * np.abs(x)
    chest = is_("torso") & (N[:, 1] < -0.25)
    blk |= chest & (np.abs(z - zc) < 0.048) & (np.abs(x) < 0.24)
    col[blk] = BLACK
    glow |= chest & (np.abs(z - (zc + 0.062)) < 0.008) & (np.abs(x) > 0.07) & (np.abs(x) < 0.2)

    # ---- chest core: pixel diamond
    m = is_("core") & (N[:, 1] < -0.3)
    q = np.round(x / 0.016), np.round((z - 0.30) / 0.016)
    glow |= m & (np.abs(q[0]) + np.abs(q[1]) <= 2)

    # ---- pixel-block circuits (side-facing)
    sh = is_("shoulder") & (lat > 0.3)
    glow |= sh & cells_mask(-0.02 - y, 0.53 - z, 0.042,
                            [(0, 0), (1, 0), (1, 1), (2, 1), (2, 2), (3, 2), (3, 3)])
    fl = is_("fleg") & (lat > 0.3)
    glow |= fl & cells_mask(-0.13 - y, 0.25 - z, 0.035, [(0, 0), (1, 1)])
    th = is_("thigh") & (lat > 0.3)
    glow |= th & cells_mask(0.49 - y, 0.41 - z, 0.045,
                            [(1, 0), (2, 0), (0, 1), (1, 1), (1, 2), (2, 2), (0, 3)])
    # back-of-neck circuit strokes on the saddle band
    glow |= is_("torso") & blk & (lat > 0.45) & (np.abs(y + 0.13) < 0.009) & (z > 0.40) & (z < 0.52)

    # ---- toe-pad strips
    for nm, cx in (("fpaw", 0.215), ("hpaw", 0.21)):
        m = is_(nm) & (N[:, 1] < -0.3) & (z > 0.012) & (z < 0.072)
        lx = np.abs(x) - cx
        strip = np.zeros(n, bool)
        for off in (-0.058, 0.0, 0.058):
            strip |= np.abs(lx - off) < 0.011
        glow |= m & strip

    # ---- head-group features in un-tilted head space
    hm = is_("head", "muzzle", "ear")
    Ph, Nh = untilt(P, N)
    u, v = Ph[:, 0], Ph[:, 2]
    ua = np.abs(u)
    front = hm & (Nh[:, 1] < -0.15)

    # inner ears
    for pid, c, r, R, is_head in table:
        if pid != PID["ear"]:
            continue
        loc = ((Ph - c) @ R) / r
        nl = Nh @ R
        inner = (nl[:, 1] < -0.35) & (loc[:, 0] ** 2 + (loc[:, 2] + 0.05) ** 2 < 0.62 ** 2)
        glow |= is_("ear") & (np.sign(u) == np.sign(c[0])) & inner

    # eye patches (tilted ellipses, outer end lower)
    ex, ez = 0.14, 0.71
    a = math.radians(-22)
    du, dv = ua - 0.155, v - 0.695
    pu = du * math.cos(a) + dv * math.sin(a)
    pv = -du * math.sin(a) + dv * math.cos(a)
    patch = front & is_("head", "muzzle") & ((pu / 0.112) ** 2 + (pv / 0.086) ** 2 < 1.0)
    col[patch] = BLACK

    # eye glow lines: arc on the outer-lower side of each eye
    de = np.hypot(ua - ex, v - ez)
    ang = np.degrees(np.arctan2(v - ez, ua - ex))
    glow |= patch & (np.abs(de - 0.072) < 0.0065) & (ang > -70) & (ang < 8)
    glow |= patch & (np.abs(de - 0.072) < 0.0065) & (ang > 150) & (ang < 175)

    # eyes
    eye = patch & (de < 0.056)
    t = np.clip((ez - v) / 0.047 * 0.5 + 0.5, 0, 1)[:, None]
    iris = (1 - t) * np.array([0.08, 0.26, 0.70]) + t * np.array([0.32, 0.72, 1.0])
    ecol = np.where((de < 0.047)[:, None], iris, np.array([0.03, 0.05, 0.13]))
    ecol = np.where((de < 0.025)[:, None], np.array([0.02, 0.03, 0.07]), ecol)
    hl = (np.hypot(u - side * ex - 0.019, v - ez - 0.02) < 0.016) | \
         (np.hypot(u - side * ex + 0.017, v - ez + 0.019) < 0.0075)
    ecol = np.where(hl[:, None], np.array([1.0, 1.0, 1.0]), ecol)
    col[eye] = ecol[eye]
    clean |= eye
    glow &= ~eye

    # cheek pixel blocks (above the outer patch edge)
    glow |= front & is_("head") & ~patch & cells_mask(ua - 0.245, 0.805 - v, 0.026,
                                                       [(0, 0), (1, 0), (1, 1), (2, 1)])

    # smile on the muzzle
    mz = front & is_("muzzle", "head")
    smile = (np.abs(u) < 0.0055) & (v < 0.585) & (v > 0.548)
    for sx in (-0.028, 0.028):
        d = np.hypot(u - sx, v - 0.555)
        smile |= (np.abs(d - 0.028) < 0.0055) & (v < 0.555)
    col[mz & smile] = BLACK
    clean |= mz & smile

    # facet tone variation (crystalline look)
    f = 1.0 + 0.045 * trand
    var = ~glow & ~clean
    col[var] = np.clip(col[var] * f[var, None], 0, 1)
    col[glow] = CYAN
    return col, glow


# ---------------------------------------------------------------- texel bake
def bake_textures(me, owner, table):
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
    tri_p = co[lv[li]]                        # (T,3,3)
    tri_uv = uvs[li] * (TEX * SS) - 0.5       # pixel-center space
    nrm = np.cross(tri_p[:, 1] - tri_p[:, 0], tri_p[:, 2] - tri_p[:, 0])
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
    cent = tri_p.mean(axis=1)
    trand = np.random.default_rng(3).uniform(-1, 1, T)

    W = TEX * SS
    pix, tid, bar, exact, dist_in = [], [], [], [], []
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
        w2 = 1.0 - w0 - w1
        Wb = np.stack([w0, w1, w2], 1)
        # distance (px) of the sample outside each edge = bary * altitude
        L = np.array([np.linalg.norm(c - b), np.linalg.norm(a - c), np.linalg.norm(b - a)])
        h = abs(area2) / np.maximum(L, 1e-9)
        dist = (Wb * h).min(axis=1)
        keep = dist > -1.5
        if not keep.any():
            continue
        Wk = np.clip(Wb[keep], 0, None)
        Wk /= Wk.sum(1, keepdims=True)
        pix.append(ys[keep] * W + xs[keep])
        tid.append(np.full(keep.sum(), t))
        bar.append(Wk)
        exact.append(dist[keep] >= 0)
        dist_in.append(dist[keep])
    pix, tid, bar, exact, dist_in = map(np.concatenate, (pix, tid, bar, exact, dist_in))
    P = np.einsum("nk,nkj->nj", bar, tri_p[tid])
    col, glow = shade(P, nrm[tid], cent[tid], owner[tid], trand[tid], table)

    # UV overlap check: pixel centers covered by >1 triangle (exact coverage)
    _, cnt = np.unique(pix[dist_in > 0.3], return_counts=True)
    overlap = int((cnt > 1).sum())

    img = np.zeros((W * W, 4))
    order = np.argsort(exact, kind="stable")      # exact samples written last (win)
    img[pix[order], :3] = col[order]
    img[pix[order], 3] = glow[order]
    filled = np.zeros(W * W, bool)
    filled[pix] = True
    img = img.reshape(W, W, 4)
    filled = filled.reshape(W, W)
    # dilate into empty space so seams/mips don't bleed background
    for _ in range(12):
        acc = np.zeros_like(img)
        cnt2 = np.zeros((W, W))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(img * filled[..., None], dx, 1), dy, 0)
            cnt2 += np.roll(np.roll(filled, dx, 1), dy, 0)
        grow = ~filled & (cnt2 > 0)
        img[grow] = acc[grow] / cnt2[grow][:, None]
        filled |= grow
    img = img.reshape(TEX, SS, TEX, SS, 4).mean(axis=(1, 3))
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

    objs, table = build_parts()
    base = objs[0]   # torso
    coll = bpy.data.collections.new("operands")
    for ob in objs[1:]:
        scene.collection.objects.unlink(ob)
        coll.objects.link(ob)
    mod = base.modifiers.new("union", "BOOLEAN")
    mod.operation = "UNION"
    mod.operand_type = "COLLECTION"
    mod.collection = coll
    mod.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(base.evaluated_get(dg))
    for ob in objs:
        bpy.data.objects.remove(ob)
    bpy.data.collections.remove(coll)

    # clean topology: merge, drop degenerates, triangulate, fix normals
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()

    panda = bpy.data.objects.new("CyberPanda", me)
    scene.collection.objects.link(panda)
    bpy.context.view_layer.objects.active = panda
    panda.select_set(True)
    for p in me.polygons:
        p.use_smooth = False

    # part ownership per face (design coords)
    cent = np.array([p.center[:] for p in me.polygons])
    owner = assign_parts(cent, table)

    # UV unwrap (non-overlapping islands)
    me.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    img, overlap = bake_textures(me, owner, table)
    col_img = save_png(img[..., :3], "cyber_panda_color.png")
    msk_img = save_png(np.repeat(img[..., 3:4], 3, axis=2), "cyber_panda_emissive.png", "Non-Color")

    # rescale to 4 studs long, origin at bottom center between the feet
    co = np.array([v.co[:] for v in me.vertices])
    s = TARGET_LEN / (co[:, 1].max() - co[:, 1].min())
    feet = np.isin(owner, [PID["fpaw"], PID["hpaw"]])
    fv = np.array([me.vertices[i].co[:] for p in np.nonzero(feet)[0] for i in me.polygons[p].vertices])
    cx = 0.5 * (fv[:, 0].min() + fv[:, 0].max())
    cy = 0.5 * (fv[:, 1].min() + fv[:, 1].max())
    me.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -co[:, 2].min())))
    me.update()

    # materials
    def make_mat(name, emissive):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        tc = nt.nodes.new("ShaderNodeTexImage")
        tc.image = col_img
        nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.55
        if emissive:
            tm = nt.nodes.new("ShaderNodeTexImage")
            tm.image = msk_img
            nt.links.new(tc.outputs["Color"], bsdf.inputs["Emission Color"])
            mul = nt.nodes.new("ShaderNodeMath")
            mul.operation = "MULTIPLY"
            mul.inputs[1].default_value = 4.0
            nt.links.new(tm.outputs["Color"], mul.inputs[0])
            nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
        return m

    mat_export = make_mat("CyberPanda", False)
    me.materials.append(mat_export)

    # ---- validation stats
    bm = bmesh.new()
    bm.from_mesh(me)
    nonman = sum(1 for e in bm.edges if not e.is_manifold)
    ngons = sum(1 for f in bm.faces if len(f.verts) != 3)
    loose_v = sum(1 for v in bm.verts if not v.link_faces)
    bm.free()
    vco = np.array([v.co[:] for v in me.vertices])
    dims = Vector(vco.max(0) - vco.min(0))
    stats = (f"tris={len(me.polygons)} verts={len(me.vertices)} nonmanifold_edges={nonman} "
             f"ngons={ngons} loose_verts={loose_v} uv_overlap_px={overlap} "
             f"dims_m=({dims.x:.3f},{dims.y:.3f},{dims.z:.3f}) "
             f"studs=({dims.x/0.28:.2f},{dims.y/0.28:.2f},{dims.z/0.28:.2f})")
    print("STATS", stats)

    # ---- export
    bpy.ops.object.select_all(action="DESELECT")
    panda.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "cyber_panda.fbx"), use_selection=True,
        object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS",
        mesh_smooth_type="FACE", path_mode="COPY", embed_textures=True,
        axis_forward="-Z", axis_up="Y", use_mesh_modifiers=True)

    # ---- verification render (front 3/4, panda's right side like the reference)
    mat_render = make_mat("CyberPanda_preview", True)
    me.materials[0] = mat_render
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.43, 0.46, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    fm = bpy.data.meshes.new("floor")
    fm.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("floor", fm)
    fmat = bpy.data.materials.new("floor")
    fmat.use_nodes = True
    fmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.4, 0.41, 0.44, 1)
    fm.materials.append(fmat)
    scene.collection.objects.link(floor)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(20)
    sun.rotation_euler = (math.radians(40), 0, math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    target = Vector((0.0, -0.05, 0.42 * TARGET_LEN / 1.12))
    d = Vector((-0.62, -0.78, 0.14)).normalized()
    cam.location = target + d * 2.35
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "cyber_panda.blend"), relative_remap=True)

    if RENDER:
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 48
        try:
            scene.cycles.use_denoising = True
        except Exception:
            pass
        scene.render.resolution_x = scene.render.resolution_y = 800
        scene.view_settings.view_transform = "Standard"
        scene.render.filepath = os.path.join(OUT, "cyber_panda_preview.png")
        bpy.ops.render.render(write_still=True)
    print("DONE", stats)


if __name__ == "__main__":
    main()
