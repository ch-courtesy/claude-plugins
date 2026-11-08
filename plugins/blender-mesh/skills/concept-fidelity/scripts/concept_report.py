"""Concept feedback report for the artist (system Python + Pillow only).

Checks a turnaround *before* any modelling: in orthographic views the same
part must occupy the same heights in front and side. Every part's top,
bottom and centre are compared; gaps above the tolerance are flagged.
If single-view / joint fit results exist, each part's contradiction cost
(how much fitting both views at once costs that part) is added.

  python -I concept_report.py CONCEPT_DIR [FIT_DIR] [TOL_CM]
Writes CONCEPT_DIR/feedback.md and CONCEPT_DIR/feedback.png
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


cdir = sys.argv[1]
fdir = sys.argv[2] if len(sys.argv) > 2 else None
TOL = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
cfg = read_json(os.path.join(cdir, "concept.json"), encoding="utf-8")
SIZE, RES = cfg["size"], cfg["res"]
PIX = SIZE / RES
VIEWS = ["front", "side"]
VN = {"front": "정면", "side": "측면"}
KIND = {"top": "위끝", "bottom": "아래끝", "center": "중심"}
labels = {v: Image.open(os.path.join(cdir, f"labels_{v}.png")).convert("L") for v in VIEWS}


def heights(img, lab, cv):
    """Top / bottom / centre height (metres) of one part, or None if absent."""
    mask = img.point(lambda x: 255 if x == lab else 0)
    box = mask.getbbox()
    if not box:
        return None
    col = mask.resize((1, img.height), Image.BOX)
    rows = list(col.get_flattened_data() if hasattr(col, "get_flattened_data") else col.getdata())
    w = sum(rows)
    c = sum((r + 0.5) * x for r, x in enumerate(rows)) / w
    vmax = cv + SIZE / 2
    return {"top": vmax - box[1] * PIX, "bottom": vmax - box[3] * PIX, "center": vmax - c * PIX}


labels_all = {v: Image.open(os.path.join(cdir, f"labels_{v}.png")).convert("L")
              for v in ("front", "side", "back", "top") if os.path.exists(os.path.join(cdir, f"labels_{v}.png"))}
H = {v: {int(k): heights(labels[v], int(k), cfg["frames"][v][1]) for k in cfg["parts"]} for v in VIEWS}
findings = []
for k, part in cfg["parts"].items():
    a, b = H["front"][int(k)], H["side"][int(k)]
    if not a or not b:
        continue
    for kind in KIND:
        gap = (a[kind] - b[kind]) * 100
        if abs(gap) > TOL:
            findings.append({"part": part["name"], "label": int(k), "kind": kind, "gap_cm": round(gap, 1),
                             "front_m": round(a[kind], 3), "side_m": round(b[kind], 3)})
findings.sort(key=lambda f: -abs(f["gap_cm"]))

# contradiction cost from fits (single-view ceiling minus joint), if available
cost = {}
if fdir and all(os.path.exists(os.path.join(fdir, p)) for p in
                ("fit.json", "front_only/fit.json", "side_only/fit.json")):
    J = read_json(os.path.join(fdir, "fit.json"))["fit"]["scores"]
    for v in VIEWS:
        C = read_json(os.path.join(fdir, f"{v}_only", "fit.json"))["fit"]["scores"][v]
        for k in cfg["parts"]:
            cost.setdefault(k, {})[v] = round(C["part_iou"].get(k, 0) - J[v]["part_iou"].get(k, 0), 3)

# ---------------------------------------------------------------- markdown
md = [f"# 원화 피드백 리포트 — {os.path.basename(os.path.abspath(cdir))}", "",
      f"정사영 턴어라운드에서 같은 부위는 정면과 측면에서 높이가 같아야 합니다. "
      f"허용 오차 {TOL}cm를 넘는 곳 {len(findings)}건.", "",
      "| 부위 | 기준 | 정면 (m) | 측면 (m) | 차이 |", "|---|---|---|---|---|"]
md += [f"| {f['part']} | {KIND[f['kind']]} | {f['front_m']:.3f} | {f['side_m']:.3f} | **{f['gap_cm']:+.1f}cm** |"
       for f in findings]
md += ["", "주의: 한 뷰에서 다른 부위에 가려진 부분이 있으면 그 뷰의 끝 높이가 달라 보일 수 있습니다. "
       "'중심'보다 '위끝/아래끝' 차이가 클 때 특히 가림 여부를 먼저 확인하세요."]
if cost:
    md += ["", "## 두 뷰를 동시에 맞출 때 부위가 잃는 점수 (모순 비용)", "",
           "한 뷰만 맞췄을 때의 부위 IoU − 두 뷰를 함께 맞췄을 때의 부위 IoU. 0.05 이상이면 굵게.", "",
           "| 부위 | 정면 | 측면 |", "|---|---|---|"]
    for k, part in cfg["parts"].items():
        c = cost.get(k, {})
        fmt = lambda x: f"**{x:+.2f}**" if x >= 0.05 else f"{x:+.2f}"  # noqa: E731
        md.append(f"| {part['name']} | {fmt(c.get('front', 0))} | {fmt(c.get('side', 0))} |")
# part extents per view (metres): starting values and bounds for a parametric model
md += ["", "## 부위 범위 (모델 초기값·범위 설정용, 단위 m)", "",
       "가로축: 정면 = x (오른쪽이 캐릭터의 왼쪽), 측면 = y (왼쪽이 앞), 후면 = -x.", "",
       "| 부위 | 뷰 | 가로 최소 | 가로 최대 | 높이 최소 | 높이 최대 |", "|---|---|---|---|---|---|"]
for k, part in cfg["parts"].items():
    for v in [x for x in ("front", "side", "back", "top") if x in labels_all]:
        img = labels_all[v]
        box = img.point(lambda x, k=int(k): 255 if x == k else 0).getbbox()
        if not box:
            continue
        cu, cv = cfg["frames"][v]
        umin, vmax = cu - SIZE / 2, cv + SIZE / 2
        md.append(f"| {part['name']} | {v} | {umin + box[0] * PIX:+.3f} | {umin + box[2] * PIX:+.3f} | "
                  f"{vmax - box[3] * PIX:.3f} | {vmax - box[1] * PIX:.3f} |")
with open(os.path.join(cdir, "feedback.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(md) + "\n")

# ---------------------------------------------------------------- annotated image
F = font
SC, GAP = 2, 150
panel = RES * SC
img = Image.new("RGB", (panel * 2 + GAP + 40, panel + 120), (250, 249, 246))
dr = ImageDraw.Draw(img)
dr.text((20, 10), f"원화 피드백 — 정면↔측면 높이 불일치 {len(findings)}건 (허용 {TOL}cm)",
        fill=(30, 30, 40), font=F(20, True))
x0 = {"front": 20, "side": 20 + panel + GAP}
for v in VIEWS:
    lab = labels[v]
    col = Image.new("RGB", lab.size, (255, 255, 255))
    for k, part in cfg["parts"].items():
        col.paste(tuple(part["rgb"]), mask=lab.point(lambda x, k=int(k): 255 if x == k else 0))
    img.paste(col.resize((panel, panel), Image.NEAREST), (x0[v], 50))
    dr.text((x0[v] + 6, 54), VN[v], fill=(60, 60, 70), font=F(16, True))
palette = [(220, 40, 40), (240, 120, 20), (40, 110, 220), (150, 60, 200), (20, 150, 120)]


def ypix(v, h):
    return 50 + ((cfg["frames"][v][1] + SIZE / 2) - h) / PIX * SC


for i, f in enumerate(findings[:5]):
    c = palette[i % len(palette)]
    yf, ys = ypix("front", f["front_m"]), ypix("side", f["side_m"])
    dr.line([(x0["front"], yf), (x0["front"] + panel, yf)], fill=c, width=2)
    dr.line([(x0["side"], ys), (x0["side"] + panel, ys)], fill=c, width=2)
    dr.line([(x0["front"] + panel, yf), (x0["side"], ys)], fill=c, width=2)   # slant = mismatch
    dr.text((x0["front"] + panel + 6, (yf + ys) / 2 - 18 + (i % 2) * 14),
            f"{f['part']} {KIND[f['kind']]} {f['gap_cm']:+.1f}cm", fill=c, font=F(12, True))
img.save(os.path.join(cdir, "feedback.png"))
sys.stdout.reconfigure(encoding="utf-8")      # Windows console defaults to cp949
print("\n".join(md))
