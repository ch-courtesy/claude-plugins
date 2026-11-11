"""Measure a finished model against a concept turnaround (runs in Blender's Python).

  blender -b MODEL.blend --python compare_model.py -- --concept DIR --out DIR
      [--object Model] [--map Brass=buckle ...] [--see-through Glass ...] [--export DIR]

Projects the evaluated mesh (modifiers on) into the concept's views as part-label images,
each material standing for the part of the same name (case-insensitive; --map renames),
and scores every view that has a label map. Nothing is fitted or aligned: model and concept
share one coordinate frame, so a wrong size or position counts as a difference.

Writes to --out: compare.json (scores, per-part extents, largest gaps), compare.md,
concept_<view>.png, model_<view>.png, diff_<view>.png (grey = same part, orange = other
part, red = concept only, blue = model only). --export writes the model's own label maps
as a concept folder (a known-answer test: comparing with it must give IoU 1).
"""
import argparse
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402

from fid import metrics  # noqa: E402
from fid.raster import Canvas, Frame  # noqa: E402


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


ap = argparse.ArgumentParser()
ap.add_argument("--concept", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--object", default="")
ap.add_argument("--map", nargs="*", default=[], help="Material=part")
ap.add_argument("--export", default="")
ap.add_argument("--see-through", nargs="*", default=[], help="materials shown only where nothing lies behind them")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
cdir, out = os.path.abspath(a.concept), os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
cfg = read_json(os.path.join(cdir, "concept.json"), encoding="utf-8")
PART = {int(k): v["name"] for k, v in cfg["parts"].items()}
BY_NAME = {v.lower(): k for k, v in PART.items()}
PAL = {int(k): tuple(v["rgb"]) for k, v in cfg["parts"].items()}
RENAME = {k.lower(): v.lower() for k, v in (x.split("=", 1) for x in a.map)}
UNMAPPED = 250


def load(path):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"          # raw label values, no colour transform
    w, h = img.size
    return np.round(np.array(img.pixels[:]).reshape(h, w, 4)[::-1, :, 0] * 255).astype(np.int16)


def save(rgb, path):
    h, w, _ = rgb.shape
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.concatenate([rgb[::-1] / 255.0, np.ones((h, w, 1))], -1).astype(np.float32).ravel())
    img.filepath_raw, img.file_format = path, "PNG"
    img.save()


def coloured(lab):
    rgb = np.full(lab.shape + (3,), 255, np.uint8)
    for k, c in PAL.items():
        rgb[lab == k] = c
    rgb[lab == UNMAPPED] = (255, 0, 255)
    return rgb


def overlay(model, target):
    rgb = np.full(model.shape + (3,), 255, np.uint8)
    both = (model > 0) & (target > 0)
    rgb[both & (model == target)] = (175, 175, 180)
    rgb[both & (model != target)] = (245, 150, 40)
    rgb[(target > 0) & (model == 0)] = (220, 40, 40)
    rgb[(model > 0) & (target == 0)] = (40, 90, 230)
    return rgb


def extents(img, label, fr):
    ys, xs = np.nonzero(img == label) if label else np.nonzero(img > 0)
    if not len(ys):
        return None
    return {"left": fr.umin + xs.min() * fr.pix, "right": fr.umin + (xs.max() + 1) * fr.pix,
            "top": fr.vmax - ys.min() * fr.pix, "bottom": fr.vmax - (ys.max() + 1) * fr.pix}


# ---- the evaluated mesh as triangles with part labels
meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("ENV_")]
ob = bpy.data.objects[a.object] if a.object else max(meshes, key=lambda o: len(o.data.polygons))
dg = bpy.context.evaluated_depsgraph_get()
me = ob.evaluated_get(dg).to_mesh()
me.calc_loop_triangles()
n = len(me.vertices)
V = np.empty(n * 3)
me.vertices.foreach_get("co", V)
V = V.reshape(n, 3)
M = np.array(ob.matrix_world)
V = V @ M[:3, :3].T + M[:3, 3]
t = len(me.loop_triangles)
F = np.empty(t * 3, np.int64)
me.loop_triangles.foreach_get("vertices", F)
F = F.reshape(t, 3)
poly = np.empty(t, np.int64)
me.loop_triangles.foreach_get("polygon_index", poly)
face_slot = np.array([p.material_index for p in me.polygons])
slot_label, unmapped = {}, []
for i, s in enumerate(ob.material_slots):
    name = s.material.name if s.material else ""
    lab = BY_NAME.get(RENAME.get(name.lower(), name.lower()))
    if lab is None:
        unmapped.append(name)
        lab = UNMAPPED
    slot_label[i] = lab
if unmapped:
    print(f"[compare] materials without a part: {unmapped} (use --map Material=part)")
tri_label = np.array([slot_label.get(int(s), UNMAPPED) for s in face_slot[poly]])
CLEAR = {BY_NAME.get(RENAME.get(n.lower(), n.lower())) for n in a.see_through}

# ---- every view with a label map
FINE = 3                                               # a canvas marks every pixel it touches, so thin parts read a
                                                       # pixel wide: draw finer and keep the middle sample of each
                                                       # block. Drawn label maps must be made the same way, at 3x
                                                       # and shrunk with NEAREST (SKILL.md), or thin parts differ
views = [v for v in ("front", "side", "back", "top") if os.path.exists(os.path.join(cdir, f"labels_{v}.png"))]
labels = sorted(PART)
R = {"object": ob.name, "concept": cdir, "tris": t, "unmapped": unmapped, "views": {}, "gaps": []}
imgs = {}
for v in views:
    fr = Frame(*cfg["frames"][v], cfg["size"], cfg["res"])
    target = load(os.path.join(cdir, f"labels_{v}.png"))
    fine = Frame(*cfg["frames"][v], cfg["size"], cfg["res"] * FINE)
    cv, glass = Canvas(fine), Canvas(fine)
    for lab in np.unique(tri_label):
        (glass if lab in CLEAR else cv).triangles(V, F[tri_label == lab], v, int(lab))
    model = cv.image()[FINE // 2::FINE, FINE // 2::FINE]
    if glass.idx:                                      # what the drawing paints behind glass wins
        model = np.where(model > 0, model, glass.image()[FINE // 2::FINE, FINE // 2::FINE])
    imgs[v] = model
    sc = metrics.score_view(model, target, fr, labels)
    sc["part_iou"] = {PART[k]: x for k, x in sc["part_iou"].items()}
    sc["extents"] = {}
    for lab, name in [(0, "silhouette")] + [(k, PART[k]) for k in labels]:
        ec, em = extents(target, lab, fr), extents(model, lab, fr)
        sc["extents"][name] = {"concept": ec, "model": em}
        if ec and em:
            for edge in ec:
                R["gaps"].append({"part": name, "view": v, "edge": edge, "concept": ec[edge], "model": em[edge],
                                  "delta_cm": (em[edge] - ec[edge]) * 100})
        elif ec or em:
            R["gaps"].append({"part": name, "view": v, "edge": "missing in " + ("model" if ec else "concept"),
                              "concept": None, "model": None, "delta_cm": None})
    R["views"][v] = sc
    save(coloured(target), os.path.join(out, f"concept_{v}.png"))
    save(coloured(model), os.path.join(out, f"model_{v}.png"))
    save(overlay(model, target), os.path.join(out, f"diff_{v}.png"))
    print(f"[compare] {v}: IoU {sc['iou']:.3f}, part IoU {sc['part_iou_mean']:.3f}, "
          f"contour {sc['contour_mean_cm']:.1f} cm (max {sc['contour_max_cm']:.1f})")
ob.evaluated_get(dg).to_mesh_clear()
R["gaps"].sort(key=lambda g: -1e9 if g["delta_cm"] is None else -abs(g["delta_cm"]))
with open(os.path.join(out, "compare.json"), "w", encoding="utf-8") as fh:
    json.dump(R, fh, ensure_ascii=False, indent=1)

# ---- compare.md
L = [f"# Model vs concept: {ob.name}", "", "| view | IoU | part IoU | contour mean cm | contour max cm |", "|---|---|---|---|---|"]
for v, s in R["views"].items():
    L.append(f"| {v} | {s['iou']:.3f} | {s['part_iou_mean']:.3f} | {s['contour_mean_cm']:.1f} | {s['contour_max_cm']:.1f} |")
L += ["", "## Part IoU", "", "| part | " + " | ".join(views) + " |", "|---|" + "---|" * len(views)]
for k in labels:
    L.append(f"| {PART[k]} | " + " | ".join(f"{R['views'][v]['part_iou'].get(PART[k], float('nan')):.2f}" for v in views) + " |")
L += ["", "## Largest gaps (model minus concept)", "", "| part | view | edge | concept m | model m | gap cm |", "|---|---|---|---|---|---|"]
for g in R["gaps"][:24]:
    if g["delta_cm"] is None:
        L.append(f"| {g['part']} | {g['view']} | {g['edge']} | | | |")
    else:
        L.append(f"| {g['part']} | {g['view']} | {g['edge']} | {g['concept']:.3f} | {g['model']:.3f} | {g['delta_cm']:+.1f} |")
with open(os.path.join(out, "compare.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(L) + "\n")
print("[compare] wrote", out)

if a.export:
    e = os.path.abspath(a.export)
    os.makedirs(e, exist_ok=True)
    shutil.copy(os.path.join(cdir, "concept.json"), os.path.join(e, "concept.json"))
    for v, img in imgs.items():
        g = img.astype(np.float32)[..., None].repeat(3, -1)
        save(g, os.path.join(e, f"labels_{v}.png"))
    print("[compare] exported label maps to", e)
