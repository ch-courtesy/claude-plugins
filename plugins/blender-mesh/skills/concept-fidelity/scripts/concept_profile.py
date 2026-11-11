"""Cross-section table of a concept: at each height, where every part sits in each view —
the numbers to model rings from (system Python + Pillow).

  python -I concept_profile.py CONCEPT_DIR [--step 0.05] [--views front,side] [--half-front]

Each row lists runs "part u0~u1" in metres. In the side view u = y (front of the character is
negative). --half-front prints only the +x half of the front view (symmetric characters).
"""
import json
import os
import sys

from PIL import Image


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


for s in (sys.stdout,):
    try:
        s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
argv = sys.argv[1:]
cdir = argv[0]


def opt(name, default):
    if name not in argv:
        return default
    i = argv.index(name)
    if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
        sys.exit(f"[profile] {name} needs a value")
    return argv[i + 1]


step = float(opt("--step", 0.05))
views = opt("--views", "front,side").split(",")
half = "--half-front" in argv
c = read_json(os.path.join(cdir, "concept.json"), encoding="utf-8")
names = {int(k): v["name"] for k, v in c["parts"].items()}
pix = c["size"] / c["res"]
img = {v: Image.open(os.path.join(cdir, f"labels_{v}.png")).convert("L") for v in views}


def runs(v, z):
    cu, cv = c["frames"][v]
    umin, vmax = cu - c["size"] / 2, cv + c["size"] / 2
    y = int((vmax - z) / pix)
    if not 0 <= y < c["res"]:
        return ""
    px = img[v].load()
    row = [px[x, y] for x in range(c["res"])]
    start = c["res"] // 2 if (half and v == "front") else 0
    out, i = [], start
    while i < c["res"]:
        if row[i] == 0:
            i += 1
            continue
        j = i
        while j < c["res"] and row[j] == row[i]:
            j += 1
        if j - i >= 2:
            out.append(f"{names.get(row[i], row[i])} {umin + i * pix:+.3f}~{umin + j * pix:+.3f}")
        i = j
    return " | ".join(out)


top = max(c["frames"][v][1] + c["size"] / 2 for v in views)
z = round(top, 3)
while z >= 0:
    rows = [(v, runs(v, z)) for v in views]
    if any(r for _, r in rows):
        print(f"z {z:.3f}")
        for v, r in rows:
            print(f"  {v[0].upper()}: {r}")
    z = round(z - step, 3)
