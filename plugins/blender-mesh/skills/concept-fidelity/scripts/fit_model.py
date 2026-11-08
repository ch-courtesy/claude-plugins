"""Fit a parametric blockout to a segmented concept (runs in Blender's Python).

  blender -b --factory-startup --python fit_model.py -- \
      --model MODEL.py --concept CONCEPT_DIR --out OUT_DIR \
      [--gens 300] [--sigma 0.12] [--seed 1] [--fit-views front,side] [--warm FIT.json]

CONCEPT_DIR holds concept.json + labels_<view>.png (from segment_turnaround.py or
drawn directly). Fits on --fit-views; every other view with a label map is scored
as a held-out check of the 3D shape. Writes OUT_DIR/fit.json and fit.npz.
Run at least 3 seeds and summarise with summarize_runs.py.
"""
import argparse
import importlib.util
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)                      # makes `fid` importable from model files

import bpy  # noqa: E402
import numpy as np  # noqa: E402

from fid import metrics  # noqa: E402
from fid.cmaes import CMAES  # noqa: E402
from fid.raster import Frame  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True)
ap.add_argument("--concept", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--gens", type=int, default=300)
ap.add_argument("--sigma", type=float, default=0.12)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--fit-views", default="front,side")
ap.add_argument("--warm", default=None, help="fit.json whose params_fit start the search")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])

model_path, cdir, out = (os.path.abspath(x) for x in (a.model, a.concept, a.out))
os.makedirs(out, exist_ok=True)
sys.path.insert(0, os.path.dirname(model_path))
spec = importlib.util.spec_from_file_location("concept_model", model_path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

cfg = json.load(open(os.path.join(cdir, "concept.json"), encoding="utf-8"))
ALL = [v for v in ("front", "side", "back", "top") if os.path.exists(os.path.join(cdir, f"labels_{v}.png"))]
FIT = [v for v in a.fit_views.split(",") if v in ALL]
FR = {v: Frame(*cfg["frames"][v], cfg["size"], cfg["res"]) for v in ALL}
LABS = list(m.LABELS)


def load(path):
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "Non-Color"          # raw label values, no colour transform
    w, h = img.size
    return np.round(np.array(img.pixels[:]).reshape(h, w, 4)[::-1, :, 0] * 255).astype(np.int16)


target = {v: load(os.path.join(cdir, f"labels_{v}.png")) for v in ALL}
model = m.Model()
span = m.HI - m.LO
u0 = (m.GUESS - m.LO) / span
if a.warm:
    prev = json.load(open(a.warm, encoding="utf-8"))["params_fit"]
    u0 = (np.array([prev.get(n, g) for n, g in zip(m.NAMES, m.GUESS)]) - m.LO) / span


def vec(u):
    return m.LO + np.clip(u, 0, 1) * span


def loss(u):
    imgs = model.render(vec(u), FIT, FR)
    tot = 0.0
    for v in FIT:
        per = metrics.label_iou(imgs[v], target[v], LABS)
        tot += (1 - metrics.iou(imgs[v], target[v])) + (1 - np.mean(list(per.values()) or [0]))
    # optional design-intent prior supplied by the model module
    prior = m.prior(vec(u)) if hasattr(m, "prior") else 0.0
    return tot / len(FIT) + prior + 0.5 * np.sum(np.maximum(0, -u) + np.maximum(0, u - 1))


def evaluate(u):
    imgs = model.render(vec(u), ALL, FR)
    return imgs, {v: metrics.score_view(imgs[v], target[v], FR[v], LABS) for v in ALL}


t0 = time.time()
start_imgs, start_sc = evaluate(u0)
es = CMAES(u0, a.sigma, seed=a.seed)
best_u, best_f = u0.copy(), loss(u0)
hist = [best_f]
for g in range(a.gens):
    X = es.ask()
    f = np.array([loss(x) for x in X])
    es.tell(f)
    if f.min() < best_f:
        best_f, best_u = float(f.min()), X[f.argmin()].copy()
    hist.append(best_f)
    if g % 50 == 0 or g == a.gens - 1:
        print(f"[fit] gen {g:3d} best {best_f:.4f} sigma {es.sigma:.3f} {time.time() - t0:5.0f}s", flush=True)
fit_imgs, fit_sc = evaluate(best_u)
res = {"model": model_path, "concept": cdir, "fit_views": FIT, "held_out": [v for v in ALL if v not in FIT],
       "generations": a.gens, "evaluations": a.gens * es.lam, "seconds": round(time.time() - t0, 1),
       "seed": a.seed, "loss_start": hist[0], "loss_fit": best_f,
       "start": {"scores": start_sc}, "fit": {"scores": fit_sc},
       "params_guess": dict(zip(m.NAMES, map(float, m.GUESS))),
       "params_fit": dict(zip(m.NAMES, map(float, vec(best_u)))), "history": hist}
json.dump(res, open(os.path.join(out, "fit.json"), "w", encoding="utf-8"), indent=1)
np.savez_compressed(os.path.join(out, "fit.npz"), **{f"target_{v}": target[v] for v in ALL},
                    **{f"start_{v}": start_imgs[v] for v in ALL}, **{f"fit_{v}": fit_imgs[v] for v in ALL})
for v in ALL:
    s0, s1 = start_sc[v], fit_sc[v]
    tag = "" if v in FIT else " [held-out]"
    print(f"[fit] {v}{tag}: IoU {s0['iou']:.3f}->{s1['iou']:.3f}  part {s0['part_iou_mean']:.3f}->"
          f"{s1['part_iou_mean']:.3f}  contour {s0['contour_mean_cm']:.1f}->{s1['contour_mean_cm']:.1f}cm", flush=True)
