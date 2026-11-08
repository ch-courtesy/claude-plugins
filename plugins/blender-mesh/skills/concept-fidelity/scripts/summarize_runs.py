"""Mean ± sd over repeat fits (seeds). System Python, no numpy.

  python -I summarize_runs.py RUN_DIR [RUN_DIR ...]      (each holds fit.json)
"""
import json
import os
import statistics as st
import sys


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


sys.stdout.reconfigure(encoding="utf-8")
runs = [read_json(os.path.join(d, "fit.json"), encoding="utf-8") for d in sys.argv[1:]]
views = list(runs[0]["fit"]["scores"])
held = set(runs[0].get("held_out", []))
print(f"{len(runs)} runs (seeds {[r.get('seed') for r in runs]})")
print(f"{'view':16} {'IoU':>18} {'part IoU':>18} {'contour cm':>18}")
for v in views:
    cells = []
    for key in ("iou", "part_iou_mean", "contour_mean_cm"):
        xs = [r["fit"]["scores"][v][key] for r in runs]
        sd = st.stdev(xs) if len(xs) > 1 else 0.0
        cells.append(f"{st.mean(xs):.3f} ± {sd:.3f}".rjust(18))
    print(f"{v + (' [held-out]' if v in held else ''):16} " + " ".join(cells))
print("range IoU per view: " + ", ".join(
    f"{v} {min(r['fit']['scores'][v]['iou'] for r in runs):.3f}-{max(r['fit']['scores'][v]['iou'] for r in runs):.3f}"
    for v in views))
if len(runs) < 3:
    print("note: fewer than 3 runs - differences of a few hundredths may be luck")
