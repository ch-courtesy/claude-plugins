"""Diff overlays and coloured label images from a fit.npz (runs in Blender's Python).

  blender -b --factory-startup --python overlays.py -- FIT_NPZ OUT_DIR CONCEPT_JSON

Colours: grey = model and concept agree (same part), orange = both filled but a
different part, red = concept only (missing), blue = model only (extra).
Part colours come from concept.json ("parts": {id: {"rgb": [...]}}).
"""
import json
import os
import sys

import bpy
import numpy as np

npz, out_dir, cjson = (os.path.abspath(x) for x in sys.argv[sys.argv.index("--") + 1:][:3])
os.makedirs(out_dir, exist_ok=True)
PAL = {int(k): tuple(v["rgb"]) for k, v in json.load(open(cjson, encoding="utf-8"))["parts"].items()}
PAL = {k: (200, 205, 225) if min(c) > 235 else c for k, c in PAL.items()}   # keep white parts visible


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
    return rgb


def overlay(model, target):
    rgb = np.full(model.shape + (3,), 255, np.uint8)
    both = (model > 0) & (target > 0)
    rgb[both & (model == target)] = (175, 175, 180)
    rgb[both & (model != target)] = (245, 150, 40)
    rgb[(target > 0) & (model == 0)] = (220, 40, 40)
    rgb[(model > 0) & (target == 0)] = (40, 90, 230)
    return rgb


data = np.load(npz)
views = sorted({k.split("_", 1)[1] for k in data})
stages = sorted({k.split("_", 1)[0] for k in data} - {"target"})
for v in views:
    t = data[f"target_{v}"]
    save(coloured(t), os.path.join(out_dir, f"target_{v}.png"))
    for s in stages:
        save(overlay(data[f"{s}_{v}"], t), os.path.join(out_dir, f"{s}_{v}_diff.png"))
        save(coloured(data[f"{s}_{v}"]), os.path.join(out_dir, f"{s}_{v}_labels.png"))
print("[overlays] wrote", out_dir, views, stages)
