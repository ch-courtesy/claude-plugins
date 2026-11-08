"""Paint a model's texture from its concept: every texel takes its colour from the painted
turnaround panels where the model shows that spot, and from its material elsewhere.

  blender -b UV.blend --python texture_session.py -- --concept DIR --out DIR [--object Model]
      [--map Brass=buckle ...] [--size 2048] [--keep Brass ...] [--erode 6] [--one-side] [--no-fill]

The concept folder needs concept.json, labels_<view>.png and panel_<view>.png (the painting
alone, same window as the labels). A texel uses a panel only if it faces that view, is not
hidden there, and lands on the same part, so paint from one part cannot leak onto another;
pixels next to a part border are skipped because they hold the drawing's outline. Texels no panel
reaches take the colours around them on the same part, so no seam shows where the paint ends.

Writes DIR/albedo.png, DIR/texture.blend (materials sample the image, --keep ones stay plain),
DIR/flat_<view>.png (an unlit render of the saved file from each view), DIR/unseen_<side>.png (the
same from sides with no panel, to look at) and DIR/report.json.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "concept-fidelity", "scripts"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

from mathutils import Matrix, Vector  # noqa: E402

from fid.raster import BASIS, Frame, VIEWS  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--concept", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--object", default="Model")
ap.add_argument("--map", nargs="*", default=[])
ap.add_argument("--keep", nargs="*", default=[])
ap.add_argument("--see-through", nargs="*", default=[], help="materials that do not hide what is behind them")
ap.add_argument("--emit", nargs="*", default=[], help="materials whose glow takes the painted colour")
ap.add_argument("--turn", nargs="*", default=None,
                help="the model looks the same turned 180 degrees about Z: far sides use the near sides' panels; name views to turn only those")
ap.add_argument("--turn-skip", nargs="*", default=[], help="parts a turned panel leaves alone, when their front has a one-off mark")
ap.add_argument("--blend-power", type=float, default=8.0,
                help="panels are weighted by facing to this power: high lets the panel that sees a texel best win")
ap.add_argument("--feather", type=int, default=12, help="panel pixels over which a panel's paint fades out where its part ends")
ap.add_argument("--fade", type=float, default=0.3, help="paint fades out over this much facing above --facing")
ap.add_argument("--fill-cells", type=int, default=64, help="voxels across a part for the fill, a power of two")
ap.add_argument("--one-side", action="store_true", help="the side panel paints its own side only, for an asymmetric model")
ap.add_argument("--no-fill", action="store_true", help="leave unpainted texels plain: only to prove the seam measure can fail")
ap.add_argument("--size", type=int, default=2048)
ap.add_argument("--erode", type=int, default=6)
ap.add_argument("--ink-facing", type=float, default=0.5, help="dark lines need this much facing, or they smear")
ap.add_argument("--facing", type=float, default=0.05, help="smallest cosine between a texel's normal and a view")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
cdir, out = os.path.abspath(a.concept), os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
cfg = json.load(open(os.path.join(cdir, "concept.json"), encoding="utf-8"))
PART = {int(k): v["name"] for k, v in cfg["parts"].items()}
BY_NAME = {v.lower(): k for k, v in PART.items()}
RENAME = {k.lower(): v.lower() for k, v in (x.split("=", 1) for x in a.map)}
ob = bpy.data.objects[a.object]
DIRS = {"front": (0, -1, 0), "back": (0, 1, 0), "side": (1, 0, 0)}


def load(path):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"
    w, h = img.size
    return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]


def save(rgb, path):
    h, w, _ = rgb.shape
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.concatenate([rgb[::-1], np.ones((h, w, 1), np.float32)], -1).ravel())
    img.filepath_raw, img.file_format = path, "PNG"
    img.save()


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def lab(rgb):
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


# ---- the rest surface
arm = ob.modifiers.get("Armature")
if arm:
    arm.show_viewport = False
dg = bpy.context.evaluated_depsgraph_get()
dg.update()
ev = ob.evaluated_get(dg)
m = ev.to_mesh()
m.calc_loop_triangles()
t, n = len(m.loop_triangles), len(m.vertices)
V = np.empty(n * 3)
m.vertices.foreach_get("co", V)
V = V.reshape(n, 3)
N = np.empty(n * 3)
m.vertex_normals.foreach_get("vector", N)
N = N.reshape(n, 3)
T = np.empty(t * 3, np.int64)
m.loop_triangles.foreach_get("vertices", T)
T = T.reshape(t, 3)
Lp = np.empty(t * 3, np.int64)
m.loop_triangles.foreach_get("loops", Lp)
Lp = Lp.reshape(t, 3)
poly = np.empty(t, np.int64)
m.loop_triangles.foreach_get("polygon_index", poly)
slot = np.array([p.material_index for p in m.polygons])[poly]
UV = np.empty(len(m.loops) * 2)
m.uv_layers.active.data.foreach_get("uv", UV)
UV = UV.reshape(-1, 2)
ev.to_mesh_clear()

slot_part, slot_rgb = {}, {}
for i, s in enumerate(ob.material_slots):
    name = s.material.name
    slot_part[i] = BY_NAME.get(RENAME.get(name.lower(), name.lower()), 0)
    b = s.material.node_tree.nodes.get("Principled BSDF")
    slot_rgb[i] = to_srgb(np.array(b.inputs["Base Color"].default_value[:3]))

CLEAR_SLOTS = [i for i, s_ in enumerate(ob.material_slots) if s_.material.name in a.see_through]
SOLID = ~np.isin(slot, CLEAR_SLOTS)

# ---- texels: position, normal and slot of every UV pixel
R = a.size
pos = np.zeros((R, R, 3), np.float32)
nor = np.zeros((R, R, 3), np.float32)
tex_slot = np.full((R, R), -1, np.int16)
Q = UV[Lp] * R
for k in range(t):
    q = Q[k]
    x0, y0 = np.floor(q.min(0)).astype(int) - 1
    x1, y1 = np.ceil(q.max(0)).astype(int) + 1
    x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, R), min(y1, R)
    if x1 <= x0 or y1 <= y0:
        continue
    gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
    (ax, ay), (bx, by), (cx, cy) = q
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-12:
        continue
    u = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
    v = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
    w = 1 - u - v
    ins = (u >= -0.02) & (v >= -0.02) & (w >= -0.02)
    if not ins.any():
        continue
    ys, xs = np.nonzero(ins)
    ys, xs = ys + y0, xs + x0
    uu, vv, ww = u[ins, None], v[ins, None], w[ins, None]
    a3, b3, c3 = T[k]
    pos[ys, xs] = uu * V[a3] + vv * V[b3] + ww * V[c3]
    nor[ys, xs] = uu * N[a3] + vv * N[b3] + ww * N[c3]
    tex_slot[ys, xs] = slot[k]
filled = tex_slot >= 0
P = pos[filled].astype(np.float64)
Nn = nor[filled].astype(np.float64)
Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)
S = tex_slot[filled]
parts = np.array([slot_part[int(i)] for i in S])
base = np.array([slot_rgb[int(i)] for i in S], np.float32)


def depth_map(view, fr):
    """Nearest surface per pixel, each triangle rasterised exactly: point samples leave holes on
    long thin faces, and a hole here reads as "hidden", which striped the paint."""
    u, v, d = VIEWS[view](V)
    X, Y = (u - fr.umin) / fr.pix, (fr.vmax - v) / fr.pix
    res = fr.res
    z = np.full((res, res), np.inf)
    for tri in T[SOLID]:
        xs, ys, ds = X[tri], Y[tri], d[tri]
        x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 2, res)
        y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 2, res)
        if x1 <= x0 or y1 <= y0:
            continue
        den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(den) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        p = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
        q = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
        r = 1 - p - q
        ins = (p >= -0.05) & (q >= -0.05) & (r >= -0.05)
        if ins.any():
            blk = z[y0:y1, x0:x1]
            blk[ins] = np.minimum(blk[ins], (p * ds[0] + q * ds[1] + r * ds[2])[ins])
    return z


def border_distance(labels, limit):
    """Pixels from each pixel to the nearest other label, counted up to limit, by growing the borders."""
    edge = np.zeros(labels.shape, bool)
    for axis in (0, 1):
        for step_ in (1, -1):
            edge |= np.roll(labels, step_, axis) != labels
    dist = np.where(edge, 0, limit).astype(np.int32)
    grown = edge
    for d in range(1, limit):
        grown = grown | np.roll(grown, 1, 0) | np.roll(grown, -1, 0) | np.roll(grown, 1, 1) | np.roll(grown, -1, 1)
        dist = np.where(grown & (dist == limit), d, dist)
    return dist


def eroded(labels, k):
    """Each part without the pixels within k of another part: those hold the outline."""
    r = labels.shape[0]
    p = np.pad(labels, k, mode="edge")
    same = np.ones(labels.shape, bool)
    for i in range(2 * k + 1):
        for j in range(2 * k + 1):
            same &= p[i:i + r, j:j + r] == labels
    return np.where(same, labels, -1)


def blur(x, axes):
    """A small blur that stops at the edge of the grid. Wrapping round would carry colour from one
    end of a part to the other: a rope's dark hole once appeared as a smudge on the far end."""
    for axis in axes:
        n = x.shape[axis]
        before = np.take(x, np.maximum(np.arange(n) - 1, 0), axis)
        after = np.take(x, np.minimum(np.arange(n) + 1, n - 1), axis)
        x = (before + 2 * x + after) / 4
    return x


def pull_push(image, mask):
    """Fill everything outside mask from the colours inside it: halve the picture repeatedly keeping
    the masked average, then come back up, keeping each level's colours where it has any. The fill
    meets the paint at the paint's own colour and fades to a broad average further away."""
    h, w = mask.shape
    size = 1 << int(np.ceil(np.log2(max(h, w))))
    c = np.zeros((size, size, 3), np.float64)
    m = np.zeros((size, size), np.float64)
    c[:h, :w] = image * mask[..., None]
    m[:h, :w] = mask
    levels = [(c, m)]
    while c.shape[0] > 1:
        c = c.reshape(c.shape[0] // 2, 2, c.shape[1] // 2, 2, 3).sum((1, 3))
        m = m.reshape(m.shape[0] // 2, 2, m.shape[1] // 2, 2).sum((1, 3))
        levels.append((c, m))
    fill = c / np.maximum(m[..., None], 1e-9)
    for c, m in reversed(levels[:-1]):
        up = blur(np.repeat(np.repeat(fill, 2, 0), 2, 1), (0, 1))
        weight = np.minimum(m, 1.0)[..., None]
        fill = weight * c / np.maximum(m[..., None], 1e-9) + (1 - weight) * up
    return fill[:h, :w].astype(np.float32)


def field_3d(points, colours, weights, query, cells=64):
    """Colour at the query points from the coloured points around them in space: the same pull and
    push as above in a grid of voxels. Being in space, it does not care where the UV islands end."""
    lo = np.minimum(points.min(0), query.min(0))
    cell = max(float((np.maximum(points.max(0), query.max(0)) - lo).max()), 1e-6) / (cells - 1e-3)
    i = ((points - lo) / cell).astype(int)
    flat = (i[:, 0] * cells + i[:, 1]) * cells + i[:, 2]
    size = cells ** 3
    m = np.bincount(flat, weights, size).reshape(cells, cells, cells)
    c = np.stack([np.bincount(flat, weights * colours[:, k], size) for k in range(3)], -1).reshape(cells, cells, cells, 3)
    levels = [(c, m)]
    while c.shape[0] > 1:
        n = c.shape[0] // 2
        c = c.reshape(n, 2, n, 2, n, 2, 3).sum((1, 3, 5))
        m = m.reshape(n, 2, n, 2, n, 2).sum((1, 3, 5))
        levels.append((c, m))
    fill = c / np.maximum(m[..., None], 1e-9)
    for c, m in reversed(levels[:-1]):
        up = blur(np.repeat(np.repeat(np.repeat(fill, 2, 0), 2, 1), 2, 2), (0, 1, 2))
        weight = np.minimum(m, 1.0)[..., None]
        fill = weight * c / np.maximum(m[..., None], 1e-9) + (1 - weight) * up
    g = np.clip((query - lo) / cell - 0.5, 0, cells - 1.001)
    i0 = g.astype(int)
    f = g - i0
    out_ = np.zeros((len(query), 3))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out_ += w[:, None] * fill[i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz]
    return out_


def box(x, r):
    """Mean over a square of side 2r + 1, by running sums, on an array with rows and columns first."""
    for axis in (0, 1):
        n = x.shape[axis]
        s = np.cumsum(x, axis, dtype=np.float64)
        s = np.concatenate((np.zeros_like(np.take(s, [0], axis)), s), axis)
        x = np.take(s, np.minimum(np.arange(n) + r + 1, n), axis) - np.take(s, np.maximum(np.arange(n) - r, 0), axis)
    return x / (2 * r + 1) ** 2


def seam_in_space(colours, points, normals, part_of, is_painted, cells=32):
    """The seam measured on the surface, not in the UV layout, where two neighbours may be far apart on
    the model: painted against filled texels of a part inside one small cube, facing the same way."""
    side = np.argmax(np.abs(normals), 1) * 2 + (np.take_along_axis(normals, np.argmax(np.abs(normals), 1)[:, None], 1)[:, 0] > 0)
    result = {}
    for k in np.unique(part_of):
        sel = part_of == k
        if is_painted[sel].sum() < 500 or (~is_painted[sel]).sum() < 500:
            continue
        p = points[sel]
        lo = p.min(0)
        cell = max(float((p.max(0) - lo).max()), 1e-6) / cells
        i = ((p - lo) / cell).astype(np.int64)
        key = ((i[:, 0] * (cells + 1) + i[:, 1]) * (cells + 1) + i[:, 2]) * 6 + side[sel]
        ids, inverse = np.unique(key, return_inverse=True)
        on = is_painted[sel]
        n_on = np.bincount(inverse[on], minlength=len(ids))
        n_off = np.bincount(inverse[~on], minlength=len(ids))
        both = (n_on >= 20) & (n_off >= 20)
        if both.sum() < 10:
            continue
        c = colours[sel]
        m_on = np.stack([np.bincount(inverse[on], c[on, j], len(ids)) for j in range(3)], -1)[both] / n_on[both, None]
        m_off = np.stack([np.bincount(inverse[~on], c[~on, j], len(ids)) for j in range(3)], -1)[both] / n_off[both, None]
        d = np.sqrt(((lab(m_on) - lab(m_off)) ** 2).sum(-1))
        facing = ids[both] % 6
        worst = int(np.argmax(d))
        at = (ids[both][worst] // 6 // (cells + 1) ** 2, ids[both][worst] // 6 // (cells + 1) % (cells + 1), ids[both][worst] // 6 % (cells + 1))
        result[PART.get(int(k), str(int(k)))] = {
            "p95": float(np.percentile(d, 95)), "median": float(np.median(d)), "cubes": int(both.sum()),
            "by_side": {"-x +x -y +y -z +z".split()[f]: round(float(np.median(d[facing == f])), 1) for f in np.unique(facing)},
            "worst_at": [round(float(lo[j] + (at[j] + 0.5) * cell), 3) for j in range(3)],
            "worst_colours": [[round(float(x), 2) for x in m_on[worst]], [round(float(x), 2) for x in m_off[worst]]]}
    return result


# ---- paint
PART_L = {k: float(lab(np.array(v["rgb"], float) / 255)[0]) for k, v in ((int(a_), b_) for a_, b_ in cfg["parts"].items())}
part_l = np.array([PART_L.get(int(k), 0.0) for k in parts])
INK = 20.0                                             # this much darker than the part's colour counts as ink
acc = np.zeros((len(P), 3))
wsum = np.zeros(len(P))
seen = np.zeros(len(P), bool)
best = np.zeros(len(P))                                # how squarely the best panel sees each texel
used = np.zeros(len(P), bool)                          # painted means some panel was used, however faintly
top_w, top_c = np.zeros(len(P)), np.zeros((len(P), 3))   # the two strongest panels, for the mixing measure
next_w, next_c = np.zeros(len(P)), np.zeros((len(P), 3))
views = [v for v in DIRS if os.path.exists(os.path.join(cdir, f"panel_{v}.png"))]
turned = set() if a.turn is None else set(a.turn or views)
PANEL = {}
for v in views:
    img = load(os.path.join(cdir, f"panel_{v}.png"))
    res = img.shape[0]
    lab_map = np.round(load(os.path.join(cdir, f"labels_{v}.png"))[..., 0] * 255).astype(np.int16)
    # nearest label by pixel centre, for any ratio of panel to label size
    rows = ((np.arange(img.shape[0]) + 0.5) * lab_map.shape[0] / img.shape[0]).astype(int)
    cols = ((np.arange(img.shape[1]) + 0.5) * lab_map.shape[1] / img.shape[1]).astype(int)
    lab_map = lab_map[rows][:, cols]
    fr = Frame(*cfg["frames"][v], cfg["size"], res)
    z = depth_map(v, fr)
    PANEL[v] = (img, lab_map, fr, z)
    clean = eroded(lab_map, a.erode)
    Pv, Nv = P, Nn
    if v in turned:                                    # surfaces facing away, turned to face the view
        far = Nn @ np.array(DIRS[v], float) < 0        # only what faces away: the rest is seen directly
        far &= ~np.isin(parts, [BY_NAME[x.lower()] for x in a.turn_skip])
        Pv, Nv = P.copy(), Nn.copy()
        Pv[far, :2] *= -1
        Nv[far, :2] *= -1
    elif v == "side" and not a.one_side:               # the side view stands for both sides
        Pv, Nv = P.copy(), Nn.copy()
        Pv[:, 0] = np.abs(P[:, 0])
        Nv[:, 0] = np.where(P[:, 0] < 0, -Nn[:, 0], Nn[:, 0])
    u, vv, d = VIEWS[v](Pv)
    px, py = fr.to_px(u, vv)
    ok = (px >= 0) & (px < res) & (py >= 0) & (py < res)
    px, py = np.clip(px, 0, res - 1), np.clip(py, 0, res - 1)
    facing = Nv @ np.array(DIRS[v], float)
    visible = ok & (facing > 0.0) & (np.abs(d - z[py, px]) < 0.015)
    seen |= visible
    use = visible & (facing > a.facing) & (clean[py, px] == parts)
    ink = lab(img[py, px])[:, 0] < part_l - INK
    use &= ~(ink & (facing < a.ink_facing))            # a line on a glancing surface smears into a blot
    best = np.maximum(best, np.where(use, facing, 0.0))
    # the panel that sees a texel best wins, and a panel fades out towards where its part ends in the
    # drawing, so a mark drawn slightly apart in two panels is not shown twice, and paint hidden in one
    # panel by something in front does not stop on a hard edge
    near = border_distance(lab_map, a.erode + a.feather + 1)[py, px]
    feather = np.clip((near - a.erode) / max(a.feather, 1), 0, 1) if a.feather else np.ones(len(P))
    w = np.where(use, np.maximum(facing, 1e-6) ** a.blend_power * (0.05 + 0.95 * feather), 0.0)
    colour = img[py, px]
    up = w > top_w
    next_w, next_c = np.where(up, top_w, np.maximum(next_w, np.where(up, 0, w))), np.where(
        up[:, None], top_c, np.where(((w > next_w) & ~up)[:, None], colour, next_c))
    top_w, top_c = np.where(up, w, top_w), np.where(up[:, None], colour, top_c)
    acc += w[:, None] * colour
    wsum += w
    used |= use
painted = used & (wsum > 0)
both = painted & (top_w >= 0.3 * np.maximum(wsum, 1e-12)) & (next_w >= 0.3 * np.maximum(wsum, 1e-12))
differ = np.sqrt(((lab(top_c) - lab(next_c)) ** 2).sum(-1)) >= 10
mixed = both & differ
col = base.astype(np.float64)
col[painted] = acc[painted] / wsum[painted, None]

# stray ink: the share of each part that is ink, on the model against the drawing
INK_SKIP = {BY_NAME.get("skin"), BY_NAME.get("eye")}
model_l = lab(col)[:, 0]
draw_dark, draw_all = {}, {}
for v, (img, lab_map, fr, z) in PANEL.items():
    clean = eroded(lab_map, a.erode)
    lum = lab(img)[..., 0]
    for k in PART:
        m_ = clean == k
        draw_all[k] = draw_all.get(k, 0) + int(m_.sum())
        draw_dark[k] = draw_dark.get(k, 0) + int((lum[m_] < PART_L[k] - INK).sum())
ink_ratio = {}
for k, name in PART.items():
    sel = painted & (parts == k)
    if k in INK_SKIP or sel.sum() < 500 or not draw_all.get(k):
        continue
    on_model = float((model_l[sel] < PART_L[k] - INK).mean())
    on_drawing = draw_dark[k] / draw_all[k]
    ink_ratio[name] = {"model": on_model, "drawing": on_drawing, "ratio": on_model / max(on_drawing, 0.002)}

albedo = np.zeros((R, R, 3), np.float32)
albedo[filled] = col
part_grid = np.full((R, R), -1, np.int32)
part_grid[filled] = parts
painted_grid = np.zeros((R, R), bool)
painted_grid[filled] = painted
if not a.no_fill:
    # A panel is least reliable where it sees a surface edge-on, and its outline darkens there, so
    # paint fades out with facing into a colour made from the paint it can trust. Beside that paint
    # the colour simply continues it across the UV; further off it comes from the space around, which
    # does not care where islands end. Near paint a voxel would average in the outline next door.
    trust = np.clip((best - a.facing) / a.fade, 0, 1)
    trust = trust * trust * (3 - 2 * trust)
    trust[~painted] = 0.0
    final = col.copy()
    for k in np.unique(parts):
        sel = parts == k
        src = sel & (trust > 0.5)
        if src.sum() < 50:
            continue
        F_ = np.zeros_like(col)
        F_[sel] = field_3d(P[src], col[src], trust[src], P[sel], a.fill_cells)
        paint = np.zeros((R, R, 3), np.float32)
        paint[filled] = np.where(src[:, None], col, 0.0)
        mask = np.zeros((R, R), bool)
        mask[filled] = src
        beside = pull_push(paint, mask)[filled][sel]
        near = np.clip(2 * box(mask.astype(np.float64), 16)[filled][sel], 0, 1)[:, None]
        fill_k = near * beside + (1 - near) * F_[sel]
        final[sel] = trust[sel, None] * col[sel] + (1 - trust[sel, None]) * fill_k
    albedo[filled] = final
known = filled.copy()
for _ in range(10):                                    # bleed into the gutters between islands
    grow = np.zeros_like(albedo)
    cnt = np.zeros((R, R), np.float32)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        sh = np.roll(known, (dy, dx), (0, 1))
        grow += np.roll(albedo, (dy, dx), (0, 1)) * np.roll(known, (dy, dx), (0, 1))[..., None]
        cnt += sh
    new = (~known) & (cnt > 0)
    albedo[new] = grow[new] / cnt[new, None]
    known |= new
save(albedo[::-1], os.path.join(out, "albedo.png"))     # rows above run with v, images run top down
saved = load(os.path.join(out, "albedo.png"))[::-1]    # the seam is measured on the file itself
seam = seam_in_space(saved[filled], P, Nn, parts, painted)

# ---- materials sample the image
image = bpy.data.images.load(os.path.join(out, "albedo.png"))
image.pack()
for sl in ob.material_slots:
    if sl.material.name in a.keep:
        continue
    nt = sl.material.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    nt.links.new(tex.outputs["Color"], nt.nodes.get("Principled BSDF").inputs["Base Color"])
    if sl.material.name in a.emit:
        nt.links.new(tex.outputs["Color"], nt.nodes.get("Principled BSDF").inputs["Emission Color"])
if arm:
    arm.show_viewport = True
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "texture.blend"))

# ---- measure a real render of what was saved: unlit, from each view, in the concept's window.
# Measuring the texels computed above would miss anything lost between them and the renderer.
if CLEAR_SLOTS:                                        # see-through parts are left out of the flat render
    import bmesh
    bm_ = bmesh.new()
    bm_.from_mesh(ob.data)
    bmesh.ops.delete(bm_, geom=[f for f in bm_.faces if f.material_index in CLEAR_SLOTS], context="FACES")
    bm_.to_mesh(ob.data)
    bm_.free()
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.show_shadows = False
sc.display.shading.show_cavity = False
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = cfg["size"]
R_ = {"painted_fraction": float(painted.mean()), "seen_fraction": float(seen.mean()),
      "painted_of_seen": float(painted[seen].mean()), "ink": ink_ratio,
      "ink_ratio_worst": max(x["ratio"] for x in ink_ratio.values()), "views": {},
      "seam": seam, "seam_delta_e": max((x["median"] for x in seam.values()), default=0.0), "filled": not a.no_fill,
      "mixed_disagreement": float(mixed[painted].mean()) if painted.any() else 0.0,
      "mixed_by_part": {PART.get(int(k), str(int(k))): round(float(mixed[painted & (parts == k)].mean()), 4)
                        for k in np.unique(parts[painted])}}
for v, (img, lab_map, fr, z) in PANEL.items():
    res = img.shape[0]
    U, Vv, D = (Vector(x.tolist()) for x in BASIS[v])
    cu, cv_ = cfg["frames"][v]
    cam.location = U * cu + Vv * cv_ - D * 5
    cam.rotation_euler = Matrix((U, Vv, -D)).transposed().to_euler()
    sc.render.resolution_x = sc.render.resolution_y = res
    fp = os.path.join(out, f"flat_{v}.png")
    sc.render.filepath = fp
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(fp)
    im.colorspace_settings.name = "Non-Color"
    px_ = np.array(im.pixels[:], dtype=np.float32).reshape(res, res, 4)[::-1]
    flat, has = px_[..., :3], px_[..., 3] > 0.99
    clean = eroded(lab_map, a.erode)
    mask = has & (clean > 0)
    la, lb = lab(flat), lab(img)
    de = np.linalg.norm(la - lb, axis=-1)
    per = {}
    for k, name in PART.items():
        pm = mask & (clean == k)
        if pm.sum() > 20:
            per[name] = float(np.linalg.norm(la[pm].mean(0) - lb[pm].mean(0)))
    sv = {"delta_e_median": float(np.median(de[mask])), "delta_e_p90": float(np.percentile(de[mask], 90)),
          "part_delta_e": per, "worst_part_delta_e": max(per.values()), "worst_part": max(per, key=per.get)}
    skin = BY_NAME.get("skin")
    fm = mask & (clean == skin) if skin else None
    if fm is not None and fm.sum() > 50:
        sv["skin_correlation"] = float(np.corrcoef(la[fm][:, 0], lb[fm][:, 0])[0, 1])
    R_["views"][v] = sv
    print(f"[texture] {v}: median dE {sv['delta_e_median']:.1f}, p90 {sv['delta_e_p90']:.1f}, "
          f"worst part {sv['worst_part']} {sv['worst_part_delta_e']:.1f}, skin correlation {sv.get('skin_correlation', 0):.2f}")
centre = Vector((0, 0, sum(cfg["frames"][v][1] for v in PANEL) / len(PANEL)))
sc.render.resolution_x = sc.render.resolution_y = 1024
for name, away in (("back", (0, 1, 0)), ("left", (-1, 0, 0))):    # sides no score looks at: for your eyes
    if name in PANEL:
        continue
    cam.location = centre + Vector(away) * 5
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, f"unseen_{name}.png")
    bpy.ops.render.render(write_still=True)
json.dump(R_, open(os.path.join(out, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("[texture] ink, model / drawing:", {k: f"{x['model'] * 100:.1f}% / {x['drawing'] * 100:.1f}%" for k, x in ink_ratio.items()})
print(f"[texture] seen from a view: {seen.mean() * 100:.0f}% of the texels; painted: {painted[seen].mean() * 100:.0f}% of those")
print(f"[texture] seam, worst part: median dE {R_['seam_delta_e']:.1f}", {k: round(x["median"], 1) for k, x in seam.items()})
print(f"[texture] painted {painted.mean() * 100:.0f}% of the texels from the concept; wrote {out}")
