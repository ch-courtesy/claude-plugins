"""Turn a painted turnaround sheet into per-view part-label maps (runs in Blender).

  blender -b --factory-startup --python segment_turnaround.py -- CONFIG.json

Per view:
  1. background = flood fill from the crop border through light pixels; the
     character's closed dark outline stops it (light halo/background colours
     can equal fur/glove colours, so colour alone cannot separate them)
  2. keep the connected component under the view centre (drops neighbours)
  3. thick dark regions -> the dark part (e.g. suit); thin dark lines = outline
  4. other pixels -> nearest palette colour; outline pixels take the label of
     their neighbours
All views share one pixel scale and one ground line (same sheet row), so
height disagreements between views stay measurable.
"""
import json
import os
import sys

import bpy
import numpy as np

cfg_path = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
C = json.load(open(cfg_path, encoding="utf-8"))
base = os.path.dirname(cfg_path)
out_dir = os.path.join(base, C["out_dir"])
os.makedirs(out_dir, exist_ok=True)

img = bpy.data.images.load(os.path.join(base, C["image"]))
img.colorspace_settings.name = "Non-Color"
W, H = img.size
A = (np.array(img.pixels[:]).reshape(H, W, 4)[::-1, :, :3] * 255).astype(np.float32)
r0, r1 = C["row"]
S = r1 - r0                                    # square crop side (pixels)
LUM = np.array([0.299, 0.587, 0.114])


def shift(m, dy, dx):
    out = np.zeros_like(m)
    ys, yd = (slice(dy, None), slice(None, -dy)) if dy > 0 else ((slice(None, dy), slice(-dy, None)) if dy < 0 else (slice(None), slice(None)))
    xs, xd = (slice(dx, None), slice(None, -dx)) if dx > 0 else ((slice(None, dx), slice(-dx, None)) if dx < 0 else (slice(None), slice(None)))
    out[ys, xs] = m[yd, xd]
    return out


def dilate(m, r=1):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= shift(m, dy, dx)
    return out


def erode(m, r=1):
    return ~dilate(~m, r)


def grow(seed, allowed):
    cur = seed & allowed
    while True:
        nxt = dilate(cur) & allowed
        if (nxt == cur).all():
            return cur
        cur = nxt


pal = {int(k): np.array(v["rgb"], np.float32) for k, v in C["palette"].items()}
dark_label = C["dark_label"]
views = {}
for name, cx in C["views"].items():
    x0 = int(cx - S // 2)
    pad = np.full((S, S, 3), C["background"], np.float32)
    xa, xb = max(0, x0), min(W, x0 + S)
    pad[:, xa - x0: xb - x0] = A[r0:r1, xa:xb]
    lum = pad @ LUM
    chroma = pad.max(-1) - pad.min(-1)
    light = (lum > C["light_lum"]) & (chroma < C.get("bg_max_chroma", 255))   # pale & unsaturated
    border = np.zeros((S, S), bool)
    border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
    if C.get("halo_mode") == "peel_color":
        # peel, from the outside in, pixels close to this view's halo colour
        # (measured on the outermost layer); stops at the dark contour
        fig_all = ~grow(border, light)
        line = lum < C.get("barrier_lum", C["outline_lum"])
        outer = fig_all & ~erode(fig_all, 2)
        halo_rgb = np.median(pad[outer & ~line], 0)
        near = (((pad - halo_rgb) ** 2).sum(-1) < C.get("halo_tol", 22) ** 2) & ~line
        fig = fig_all.copy()
        while True:
            edge = fig & near & dilate(~fig, 1)
            if not edge.any():
                break
            fig &= ~edge
        print(f"[segment] {name}: halo colour {halo_rgb.round().astype(int).tolist()}, "
              f"peeled {int(fig_all.sum() - fig.sum())}px")
        bg = ~fig
    elif C.get("halo_mode") == "erode":
        # the halo has a near-constant width around the whole character: peel
        # layers from the outside until the layer is mostly the dark contour
        fig_all = ~grow(border, light)
        line = lum < C.get("barrier_lum", C["outline_lum"])
        w = 0
        for k in range(1, 10):
            layer = erode(fig_all, k - 1) & ~erode(fig_all, k)
            if layer.any() and line[layer].mean() > 0.5:
                break
            w = k
        print(f"[segment] {name}: halo width {w}px")
        bg = ~erode(fig_all, w)
    elif C.get("halo_mode") == "hybrid":
        # 1) pale/unsaturated background fill -> full character incl. the pale halo
        fig_all = ~grow(border, light)
        # 2) thickened-contour fill -> "outside the contour" (may leak through gaps)
        r = C.get("barrier_r", 2)
        line = lum < C.get("barrier_lum", C["outline_lum"])
        outside = dilate(grow(border, ~dilate(line, r)), r) & ~line
        # 3) remove only outside pixels whose colour matches this view's halo colour,
        #    so a leak cannot erase saturated fur behind a contour gap
        ring = fig_all & outside & dilate(~fig_all, 3)
        halo_rgb = np.median(pad[ring], 0) if ring.any() else np.array(C["background"], np.float32)
        near_halo = ((pad - halo_rgb) ** 2).sum(-1) < C.get("halo_tol", 30) ** 2
        bg = ~(fig_all & ~(outside & near_halo))
        print(f"[segment] {name}: halo colour {halo_rgb.round().astype(int).tolist()}")
    elif C.get("outline_barrier"):
        # the character's dark contour is the wall: everything reachable from the
        # border without crossing it (background, pale "sticker" halo) is outside
        r = C.get("barrier_r", 1)
        line = lum < C.get("barrier_lum", C["outline_lum"])
        wall = dilate(line, r)                      # thickened contour seals small gaps
        bg = grow(border, ~wall)
        bg = dilate(bg, r) & ~line                  # give back the thickening, up to the line
    else:
        bg = grow(border, light)
    fig = ~bg
    peel = C.get("peel_halo")
    if peel:
        # strip a pale, unsaturated "sticker" halo from the outside in; the dark
        # contour (not pale) stops it, saturated cream fur is not pale enough
        pale = (lum > peel["lum"]) & (chroma < peel["chroma"])
        for _ in range(peel.get("max_layers", 1000)):   # halo is only a few px wide
            edge = fig & pale & dilate(~fig, 1)
            if not edge.any():
                break
            fig &= ~edge
    centre = np.zeros((S, S), bool)
    c0 = S // 2
    centre[c0 - 3:c0 + 3, c0 - 3:c0 + 3] = True
    fig = grow(centre & fig, fig)                      # main character only
    dark = fig & (lum < C["dark_lum"])
    thick = dilate(erode(dark, C["outline_r"]), C["outline_r"]) & dark
    outline = fig & (lum < C["outline_lum"]) & ~thick
    lab = np.zeros((S, S), np.int16)
    lab[thick] = dark_label
    rest = fig & ~thick & ~outline
    keys = [k for k in pal if k != dark_label]
    P = np.stack([pal[k] for k in keys])
    d = ((pad[rest][:, None, :] - P[None]) ** 2).sum(-1)
    lab[rest] = np.array(keys)[d.argmin(1)]
    for _ in range(12):                                # outline -> neighbour labels
        hole = fig & (lab == 0)
        if not hole.any():
            break
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nb = shift(lab, dy, dx)
            take = hole & (lab == 0) & (nb > 0)
            lab[take] = nb[take]
    for k, r in C.get("open_labels", {}).items():      # drop small specks of a label
        m = lab == int(k)
        lab[m & ~dilate(erode(m, r), r)] = 0
        for _ in range(6):
            hole = fig & (lab == 0)
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                nb = shift(lab, dy, dx)
                take = hole & (lab == 0) & (nb > 0) & (nb != int(k))
                lab[take] = nb[take]
    ks = [k for k in pal]                              # 3x3 majority vote: drop specks
    votes = np.stack([sum(shift(lab == k, dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1))
                      for k in ks])
    lab = np.where(fig, np.array(ks)[votes.argmax(0)], 0).astype(np.int16)
    views[name] = (lab, x0)

# shared scale and ground line (from the reference view)
ref = views[C["reference_view"]][0]
rows = np.nonzero(ref.any(1))[0]
baseline = rows.max() + 1
pix_m = C["height_m"] / (baseline - rows.min())
frames = {}
for name, (lab, x0) in views.items():
    ys, xs = np.nonzero(lab)
    top_rows = ys < ys.min() + 0.3 * (baseline - ys.min())          # head band
    u0 = xs[top_rows].mean() + 0.5                                   # head axis = u origin
    cu = (S / 2 - u0) * pix_m
    cv = (baseline - S / 2) * pix_m
    frames[name] = [round(float(cu), 5), round(float(cv), 5)]
    rgba = np.zeros((S, S, 4), np.float32)
    rgba[..., :3] = (lab / 255.0)[..., None]
    rgba[..., 3] = 1
    im = bpy.data.images.new(f"labels_{name}", S, S, alpha=True)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(rgba[::-1].ravel())
    im.filepath_raw = os.path.join(out_dir, f"labels_{name}.png")
    im.file_format = "PNG"
    im.save()
    vis = np.full((S, S, 3), 255, np.float32)
    for k, c in pal.items():
        vis[lab == k] = c
    rgba[..., :3] = vis / 255.0
    im2 = bpy.data.images.new(f"vis_{name}", S, S, alpha=True)
    im2.colorspace_settings.name = "Non-Color"
    im2.pixels.foreach_set(rgba[::-1].ravel())
    im2.filepath_raw = os.path.join(out_dir, f"vis_{name}.png")
    im2.file_format = "PNG"
    im2.save()
    counts = {int(k): int((lab == k).sum()) for k in np.unique(lab) if k}
    print(f"[segment] {name}: {counts}")

meta = {"size": round(float(S * pix_m), 5), "res": S, "frames": frames,
        "parts": {str(k): {"name": v["name"], "rgb": v["rgb"]} for k, v in C["palette"].items()},
        "source": C.get("source", ""), "height_m": C["height_m"]}
json.dump(meta, open(os.path.join(out_dir, "concept.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
print(f"[segment] pix {pix_m * 100:.3f} cm, frames {frames}")
