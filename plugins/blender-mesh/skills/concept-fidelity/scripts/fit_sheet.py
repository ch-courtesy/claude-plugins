"""Comparison sheet: concept labels | start diff | fit diff per view, with scores.

  python -I fit_sheet.py RUN_DIR OVERLAY_DIR OUT_PNG [--source CROP_<view>.png ...]
(system Python + Pillow). RUN_DIR holds fit.json; OVERLAY_DIR holds overlays.py output.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fid.fonts import font  # noqa: E402


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


run, ov, out = sys.argv[1:4]
R = read_json(os.path.join(run, "fit.json"), encoding="utf-8")


views = [v for v in ("front", "side", "back", "top") if os.path.exists(os.path.join(ov, f"target_{v}.png"))]
T, LW = 260, 80
cols = [("concept", "target_{v}.png", None), ("start vs concept", "start_{v}_diff.png", "start"),
        ("fit vs concept", "fit_{v}_diff.png", "fit")]
W, H = LW + len(cols) * (T + 8) + 10, 70 + len(views) * (T + 30)
sheet = Image.new("RGB", (W, H), (250, 249, 246))
d = ImageDraw.Draw(sheet)
d.text((10, 8), "grey match · red missing · blue extra · orange wrong part", fill=(60, 60, 70), font=font(14))
for k, (name, _, _) in enumerate(cols):
    d.text((LW + k * (T + 8) + 4, 38), name, fill=(40, 40, 50), font=font(14))
for r, v in enumerate(views):
    y = 60 + r * (T + 30)
    held = v in R.get("held_out", [])
    d.text((8, y + T // 2 - 10), v + ("\n(held-out)" if held else ""), fill=(200, 60, 40) if held else (30, 30, 40),
           font=font(14))
    for k, (_, pat, stage) in enumerate(cols):
        im = Image.open(os.path.join(ov, pat.format(v=v))).convert("RGB").resize((T, T), Image.NEAREST)
        sheet.paste(im, (LW + k * (T + 8), y))
        if stage:
            s = R[stage]["scores"][v]
            d.text((LW + k * (T + 8) + 2, y + T + 4),
                   f"IoU {s['iou']:.3f} · part {s['part_iou_mean']:.3f} · {s['contour_mean_cm']:.1f}cm",
                   fill=(60, 60, 70), font=font(12))
sheet.save(out)
print("sheet:", out, sheet.size)
