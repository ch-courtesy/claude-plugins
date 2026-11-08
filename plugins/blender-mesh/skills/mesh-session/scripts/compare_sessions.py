"""Compare two sessions step by step.

  compare_sessions.py A B            same shape: order-independent cage faces and selection,
                                     nearest-point distance between cage and evaluated vertices
  compare_sessions.py A B --exact    also the same cage element order: vertices, faces and
                                     selection flags by index, edges as a list of vertex pairs

The evaluated mesh is always compared as a shape: it is derived output, and the order of its
elements follows the (meaningless) direction of each cage edge.
"""
import json
import math
import os
import sys


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


a, b = sys.argv[1], sys.argv[2]
EXACT = "--exact" in sys.argv
TOL = 1e-4
A = read_json(os.path.join(a, "session.json"), encoding="utf-8")
B = read_json(os.path.join(b, "session.json"), encoding="utf-8")
if len(A["steps"]) != len(B["steps"]):
    sys.exit(f"different step counts: {len(A['steps'])} vs {len(B['steps'])}")
R = 4  # 0.1 mm
CELL = 1e-3


def key(p):
    return tuple(round(x, R) + 0.0 for x in p)


def faces(j):
    v = j["base"]["v"]
    return sorted(tuple(sorted(key(v[i]) for i in f)) for f in j["base"]["f"])


def selected(j):
    s, base = j.get("selection") or {}, j["base"]
    if not s:
        return []
    v = base["v"]
    if s["domain"] == "vert":
        els = [[i] for i in range(len(v))]
    else:
        els = base["e"] if s["domain"] == "edge" else base["f"]
    return sorted(tuple(sorted(key(v[i]) for i in e)) for e, flag in zip(els, s["flags"]) if flag)


def gap(va, vb):
    """Largest distance from a point of va to its nearest point of vb (CELL if none is near)."""
    grid = {}
    for q in vb:
        grid.setdefault(tuple(math.floor(c / CELL) for c in q), []).append(q)
    worst = 0.0
    around = [(i, j, k) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1)]
    for p in va:
        c = [math.floor(x / CELL) for x in p]
        best = CELL
        for d in around:
            for q in grid.get((c[0] + d[0], c[1] + d[1], c[2] + d[2]), ()):
                best = min(best, max(abs(x - y) for x, y in zip(p, q)))
        worst = max(worst, best)
    return worst


worst, diffs = 0.0, 0
for sa, sb in zip(A["steps"], B["steps"]):
    n = sa["n"]
    ia = {k: v for k, v in (sa.get("info") or {}).items() if k != "rings"}
    ib = {k: v for k, v in (sb.get("info") or {}).items() if k != "rings"}
    for k, x, y in (("op", sa["op"], sb["op"]), ("label", sa["label"], sb["label"]), ("info", ia, ib),
                    ("stats", sa["stats"], sb["stats"]), ("active", sa.get("active"), sb.get("active"))):
        if x != y:
            print(f"{n:03d} {k}: {x} != {y}")
            diffs += 1
    ja = read_json(os.path.join(a, "snaps", f"{n:03d}.json"))
    jb = read_json(os.path.join(b, "snaps", f"{n:03d}.json"))
    if faces(ja) != faces(jb):
        print(f"{n:03d} cage faces differ")
        diffs += 1
    if selected(ja) != selected(jb):
        print(f"{n:03d} selection differs")
        diffs += 1
    for part in ("base", "eval"):
        va, vb = ja[part]["v"], jb[part]["v"]
        if len(va) != len(vb):
            print(f"{n:03d} {part} vertex count {len(va)} != {len(vb)}")
            diffs += 1
            continue
        worst = max(worst, gap(va, vb), gap(vb, va))
    if EXACT:
        for k, x, y in (("vertex", ja["base"]["v"], jb["base"]["v"]), ("face", ja["base"]["f"], jb["base"]["f"]),
                        ("edge", [sorted(e) for e in ja["base"]["e"]], [sorted(e) for e in jb["base"]["e"]]),
                        ("selection", ja["selection"], jb["selection"])):
            if x != y:
                print(f"{n:03d} {k} order differs")
                diffs += 1
pngs = sum(1 for s in B["steps"] if os.path.exists(os.path.join(b, "snaps", f"{s['n']:03d}.png")))
print(f"{os.path.basename(a)} vs {os.path.basename(b)} [{'exact' if EXACT else 'shape'}]: {len(A['steps'])} steps, "
      f"{diffs} differences, max vertex distance {worst:.3g} m, snapshots {pngs}/{len(B['steps'])}")
sys.exit(1 if diffs or worst > TOL else 0)
