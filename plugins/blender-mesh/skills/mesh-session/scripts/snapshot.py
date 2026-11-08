"""Viewport-style snapshot of one modelling step (system Python + Pillow, no numpy).

  python -I snapshot.py STEP.json OUT.png

Four orthographic panels — front, side (character faces left), top, 3/4 — with the
evaluated surface (modifiers on) flat-shaded, the base cage wireframe on top, and the
active selection in orange, like Blender's edit mode.
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
D = json.load(open(src))
P, HEAD = 420, 44


def norm(a):
    l = math.sqrt(sum(x * x for x in a)) or 1.0
    return [x / l for x in a]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def view(fwd):
    f = norm(fwd)
    hint = [0, 1, 0] if abs(f[2]) > 0.99 else [0, 0, 1]
    r = norm(cross(f, hint))
    return f, r, cross(r, f)


VIEWS = [("front", view([0, 1, 0])), ("side", view([-1, 0, 0])),
         ("top", view([0, 0, -1])), ("3/4", view([-1.0, 1.4, -0.8]))]


def newell(pts):
    n = [0.0, 0.0, 0.0]
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return norm(n)


EV, BV = D["eval"]["v"], D["base"]["v"]
EF = [f for f in D["eval"]["f"] if len(f) >= 3]
BF, BE = D["base"]["f"], D["base"]["e"]
sel = D.get("selection") or {}
flags = sel.get("flags", [])
dom = sel.get("domain")
en = [newell([EV[i] for i in f]) for f in EF]
bn = [newell([BV[i] for i in f]) for f in BF]
edge_faces = {}
for fi, f in enumerate(BF):
    for k in range(len(f)):
        a, b = f[k], f[(k + 1) % len(f)]
        edge_faces.setdefault((min(a, b), max(a, b)), []).append(fi)

pts_all = EV or BV
scale = 1e9
for _, (f, r, u) in VIEWS:
    us = [dot(p, r) for p in pts_all]
    vs = [dot(p, u) for p in pts_all]
    ext = max(max(us) - min(us), max(vs) - min(vs), 1e-6)
    scale = min(scale, P * 0.82 / ext)

img = Image.new("RGB", (2 * P, 2 * P + HEAD), (58, 58, 62))
over = Image.new("RGBA", img.size, (0, 0, 0, 0))
d, do = ImageDraw.Draw(img), ImageDraw.Draw(over)
for k, (name, (f, r, u)) in enumerate(VIEWS):
    ox, oy = (k % 2) * P, HEAD + (k // 2) * P
    us = [dot(p, r) for p in pts_all]
    vs = [dot(p, u) for p in pts_all]
    cu, cv = (max(us) + min(us)) / 2, (max(vs) + min(vs)) / 2

    def pr(p, ox=ox, oy=oy, cu=cu, cv=cv, r=r, u=u):
        return (ox + P / 2 + (dot(p, r) - cu) * scale, oy + P / 2 - (dot(p, u) - cv) * scale)

    light = norm([-f[0] + 0.4 * u[0] - 0.3 * r[0], -f[1] + 0.4 * u[1] - 0.3 * r[1],
                  -f[2] + 0.4 * u[2] - 0.3 * r[2]])
    d.rectangle([ox, oy, ox + P - 1, oy + P - 1], outline=(30, 30, 34))
    order = sorted(range(len(EF)), key=lambda i: -sum(dot(EV[j], f) for j in EF[i]) / len(EF[i]))
    for i in order:
        if dot(en[i], f) > 0.02:                      # back face
            continue
        s = 0.30 + 0.62 * max(0.0, dot(en[i], light))
        c = int(80 + 150 * s)
        d.polygon([pr(EV[j]) for j in EF[i]], fill=(c, c, c + 4))
    front = [dot(n, f) < 0.02 for n in bn]
    for ei, (a, b) in enumerate(BE):                  # base cage wireframe (visible side)
        fs = edge_faces.get((min(a, b), max(a, b)), [])
        if fs and not any(front[x] for x in fs):
            continue
        hot = dom == "edge" and ei < len(flags) and flags[ei]
        d.line([pr(BV[a]), pr(BV[b])], fill=(255, 150, 40) if hot else (25, 25, 30), width=3 if hot else 1)
    if dom == "face":
        for fi, fl in enumerate(flags):
            if fl and front[fi]:
                do.polygon([pr(BV[j]) for j in BF[fi]], fill=(255, 140, 30, 110), outline=(255, 150, 40, 255))
    elif dom == "vert":
        for vi, fl in enumerate(flags):
            if fl:
                x, y = pr(BV[vi])
                do.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 150, 40, 255))
    d.text((ox + 6, oy + 4), name, fill=(220, 220, 225))
img = Image.alpha_composite(img.convert("RGBA"), over).convert("RGB")
d = ImageDraw.Draw(img)
st = D["stats"]
try:
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 14)
except OSError:
    font = ImageFont.load_default()
d.text((8, 6), f"step {D['step']:03d}  {D['op']} {D['label']}   active selection: {D.get('active')}",
       fill=(255, 255, 255), font=font)
d.text((8, 24), f"cage v {st['verts']} f {st['faces']} (q {st['quads']} t {st['tris']} n {st['ngons']})  "
                f"evaluated tris {st['tris_eval']}  non-manifold {st['non_manifold']}", fill=(200, 205, 210), font=font)
img.save(out)
