"""Comparison sheet from compare_model.py's output: concept | model | difference per view,
scores, and the largest gaps (system Python + Pillow).

  python -I compare_sheet.py COMPARE_DIR [OUT_PNG]
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

d = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, "sheet.png")
R = json.load(open(os.path.join(d, "compare.json"), encoding="utf-8"))


def font(size):
    for f in ("C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/arial.ttf",
              "/System/Library/Fonts/AppleSDGothicNeo.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


views = list(R["views"])
T, LW, GW = 300, 118, 330
cols = [("concept", "concept_{}.png"), ("model", "model_{}.png"), ("difference", "diff_{}.png")]
W, H = LW + len(cols) * (T + 8) + GW, 44 + len(views) * (T + 10)
sheet = Image.new("RGB", (W, H), (250, 249, 246))
g = ImageDraw.Draw(sheet)
for c, (name, _) in enumerate(cols):
    g.text((LW + c * (T + 8) + 4, 12), name, fill=(40, 40, 46), font=font(16))
for r, v in enumerate(views):
    y = 40 + r * (T + 10)
    s = R["views"][v]
    g.text((8, y + 6), v, fill=(40, 40, 46), font=font(17))
    g.text((8, y + 34), f"IoU {s['iou']:.3f}\npart {s['part_iou_mean']:.3f}\nline {s['contour_mean_cm']:.1f} cm",
           fill=(90, 90, 98), font=font(14))
    for c, (_, pat) in enumerate(cols):
        sheet.paste(Image.open(os.path.join(d, pat.format(v))).convert("RGB").resize((T, T), Image.NEAREST),
                    (LW + c * (T + 8), y))
x = LW + len(cols) * (T + 8) + 6
g.text((x, 12), "largest gaps (model − concept)", fill=(40, 40, 46), font=font(15))
y = 40
for k in R["gaps"][:30]:
    txt = (f"{k['part']} {k['view']} {k['edge']}" if k["delta_cm"] is None
           else f"{k['delta_cm']:+6.1f} cm  {k['part']} {k['view']} {k['edge']}")
    g.text((x, y), txt, fill=(70, 70, 78), font=font(13))
    y += 19
g.text((x, H - 26), "red concept only · blue model only · orange other part", fill=(120, 120, 128), font=font(11))
sheet.save(out)
print("[compare] sheet", out)
