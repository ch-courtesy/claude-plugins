"""Plan for the lamp-keeper's lantern, from the turnaround of the concept folder concept_lantern.

A prop, so a different shape of problem from the character: square rings instead of round ones,
no mirror (the bail hangs corner to corner, so the lantern is not symmetric across X), see-through
glass and a glowing flame. Numbers come from concept_profile.py and design.md.
`py -3 plan_steps.py > steps.jsonl`, then `mesh.py <session> run steps.jsonl`.
"""
import json
import math
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="\n")
STEPS = []


def step(op, label="", expect=None, **args):
    s = {"op": op, "args": args, "label": label}
    if expect:
        s["expect"] = expect
    STEPS.append(s)


def lin(hexrgb):
    c = [int(hexrgb[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [round(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4, 4) for x in c]


def sq(z, a, k=0.86):
    """A square ring of 12 points: corners, and two per side close to them to keep them crisp."""
    b = a * k
    pts = [(-a, -a), (-b, -a), (b, -a), (a, -a), (a, -b), (a, b), (a, a), (b, a), (-b, a), (-a, a), (-a, b), (-a, -b)]
    return [[round(x, 4), round(y, 4), round(z, 4)] for x, y in pts]


def rr(z, r):
    """A round ring of 12 points."""
    return [[round(r * math.cos(2 * math.pi * k / 12 + math.pi / 4), 4), round(r * math.sin(2 * math.pi * k / 12 + math.pi / 4), 4),
             round(z, 4)] for k in range(12)]


MAT = {"Base": ("464C74", 0.55), "Cap": ("3A427A", 0.5), "Bar": ("423436", 0.6), "Flame": ("F48A2C", 0.6), "Bail": ("D09E48", 0.45)}


def material(sel, name, label, **more):
    step("material", label, sel=sel, name=name, color=lin(MAT[name][0]), metallic=0, roughness=MAT[name][1], **more)


def part(name, rings, first_size, mat=None, add=True, **matargs):
    """A cube with 3 x 3 caps, extruded ring by ring."""
    r0 = rings[0][0]
    z0, z1 = r0[2], rings[1][0][2]
    if add:
        step("primitive", name, add=True, type="cube", size=[first_size * 2, first_size * 2, z1 - z0],
             location=[0, 0, (z0 + z1) / 2], result=name)
    if mat:
        material(name, mat, name + "_mat", **matargs)
    within = {"in": name}
    k = first_size * 0.6
    step("loopcut", name + "_gx", at={"axis": "x", "value": [-k, k]}, within=within, result=name + "_gx")
    step("loopcut", name + "_gy", at={"axis": "y", "value": [-k, k]}, within=within, result=name + "_gy")
    step("select", name + "_bottom", {"selected": 9}, name=name + "_bottom", where={"in": name, "normal": [0, 0, -1]})
    step("select", name + "_c1", {"selected": 9}, name=name + "_c1", where={"in": name, "normal": [0, 0, 1]})
    step("transform", name + "_shape0", sel=name + "_bottom", outline=rings[0])
    step("transform", name + "_shape1", sel=name + "_c1", outline=rings[1])
    for i, o in enumerate(rings[2:], 2):
        step("extrude", f"{name}_{i}", sel=f"{name}_c{i - 1}", vector=[0, 0, 0.002], result=f"{name}_c{i}")
        step("transform", f"{name}_shape{i}", sel=f"{name}_c{i}", outline=o)


# ---------------------------------------------------------------- base: foot, body, ledge
step("primitive", "base", type="cube", size=[0.2, 0.2, 0.004], location=[0, 0, 0.002], tier="pc")
step("select", "base_all", name="base", where={})
part("base", [sq(z, a) for z, a in (
    (0.000, 0.100), (0.004, 0.100), (0.012, 0.100), (0.0165, 0.091), (0.034, 0.089), (0.047, 0.090),
    (0.0505, 0.097), (0.056, 0.097), (0.060, 0.096))], 0.1, mat="Base", add=False)

# ---------------------------------------------------------------- burner, inside the glass
part("burner", [rr(z, r) for z, r in ((0.056, 0.038), (0.062, 0.036), (0.070, 0.033), (0.078, 0.021), (0.086, 0.012))],
     0.03, mat="Base")

# ---------------------------------------------------------------- flame
part("flame", [rr(z, r) for z, r in ((0.084, 0.012), (0.090, 0.024), (0.100, 0.031), (0.110, 0.028), (0.120, 0.022),
                                     (0.130, 0.015), (0.142, 0.0075), (0.150, 0.003), (0.153, 0.0012))], 0.02, mat="Flame", emission=1.2)

# ---------------------------------------------------------------- glass
step("primitive", "glass", add=True, type="cube", size=[0.14, 0.14, 0.006], location=[0, 0, 0.061], result="glass")
step("material", "glass_mat", sel="glass", name="Glass", color=lin("FADE94"), metallic=0, roughness=0.12, alpha=0.3)
part("glass", [sq(z, a, 0.93) for z, a in ((0.058, 0.0695), (0.064, 0.069), (0.168, 0.0585), (0.174, 0.058))], 0.07, add=False)

# ---------------------------------------------------------------- corner bars
for i, (sx, sy) in enumerate(((1, 1), (1, -1), (-1, -1), (-1, 1))):
    name = f"bar{i}"
    path = [[sx * c, sy * c, z] for c, z in ((0.0805, 0.040), (0.0745, 0.115), (0.0685, 0.190))]
    step("primitive", name, add=True, type="tube", path=path, radius=0.0115, sides=6, result=name)
    material(name, "Bar", name + "_mat")

# ---------------------------------------------------------------- cap: eave, dome, knob
part("cap", [sq(0.171, 0.101), sq(0.174, 0.101), sq(0.185, 0.101), sq(0.1885, 0.101), sq(0.1895, 0.077, 0.7), sq(0.202, 0.077, 0.7),
             sq(0.213, 0.070, 0.6), rr(0.2205, 0.054), rr(0.2265, 0.047), rr(0.232, 0.042), rr(0.2345, 0.029), rr(0.244, 0.027),
             rr(0.2465, 0.018)], 0.1, mat="Cap")

# ---------------------------------------------------------------- bail: one hoop, corner to corner
BAIL = []
for k in range(21):
    t = -1 + 2 * k / 20                                # -1 at one ear, 1 at the other
    u = t * 0.088 * math.sqrt(2)                       # along the diagonal
    z = 0.201 + 0.111 * (1 - abs(t) ** 2.4) ** (1 / 2.4)
    BAIL.append([round(u / math.sqrt(2), 4), round(-u / math.sqrt(2), 4), round(z, 4)])
step("primitive", "bail", add=True, type="tube", path=BAIL, radius=0.0098, sides=6, result="bail")
material("bail", "Bail", "bail_mat")
for i, (x, y) in enumerate(((0.088, -0.088), (-0.088, 0.088))):
    step("primitive", f"ear{i}", add=True, type="ball", cuts=1, size=[0.03, 0.03, 0.03], location=[x, y, 0.2], result=f"ear{i}")
    material(f"ear{i}", "Bail", f"ear{i}_mat")

# ---------------------------------------------------------------- smooth
step("subsurf", "smooth", levels=2)
step("cleanup", "clean")

for s in STEPS:
    print(json.dumps(s, ensure_ascii=False))
