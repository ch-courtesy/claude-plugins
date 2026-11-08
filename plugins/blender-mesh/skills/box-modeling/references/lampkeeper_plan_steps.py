"""Plan for the lamp-keeper, modelled from the turnaround of the concept folder concept_lampkeeper.

Every number below comes from that concept's cross-section table (concept_profile.py) and
extents; design.md gives the intent. This script only writes the steps out, one modelling
action per line: `py -3 plan_steps.py > steps.jsonl`, then `mesh.py <session> run steps.jsonl`.
Parts overlap instead of growing from each other, the way a character is built from a head,
a hood, sleeves and boots: each part is a cube extruded ring by ring, every ring given its
measured outline.
"""
import json
import math
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="\n")
STEPS = []
null = None


def step(op, label="", expect=None, **args):
    s = {"op": op, "args": args, "label": label}
    if expect:
        s["expect"] = expect
    STEPS.append(s)


def lin(hexrgb):
    c = [int(hexrgb[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [round(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4, 4) for x in c]


def sp(v, p):
    return math.copysign(abs(v) ** (2 / p), v)


def half_ring(z, a, yf, yb, nf=2.0, nb=2.0, n=8):
    """Half a ring from the front seam to the back seam; z may be a function of the angle."""
    c, b, pts = (yf + yb) / 2, (yb - yf) / 2, []
    for k in range(n):
        t = math.pi * k / (n - 1)
        co, si = math.cos(t), math.sin(t)
        p = nf if co > 0 else nb
        x, y = a * sp(si, p), c - b * sp(co, p)
        pts.append([round(max(x, 0.0), 4), round(y, 4), round(z(t) if callable(z) else z, 4)])
    pts[0][0] = pts[-1][0] = 0.0
    return pts


def tilted_ring(u, l, a, n=8):
    """Half a ring standing between a top point u and a bottom point l, both (y, z)."""
    pts = []
    for k in range(n):
        t = math.pi * k / (n - 1)
        co, si = math.cos(t), math.sin(t)
        y = (u[0] + l[0]) / 2 + (u[0] - l[0]) / 2 * co
        z = (u[1] + l[1]) / 2 + (u[1] - l[1]) / 2 * co
        pts.append([round(a * si, 4), round(y, 4), round(z, 4)])
    pts[0][0] = pts[-1][0] = 0.0
    return pts


def closed_ring(z, cx, ax, yf, yb, p=2.4, n=10):
    c, b, pts = (yf + yb) / 2, (yb - yf) / 2, []
    for k in range(n):
        t = 2 * math.pi * k / n
        pts.append([round(cx + ax * sp(math.sin(t), p), 4), round(c - b * sp(math.cos(t), p), 4), round(z, 4)])
    return pts


def arm_ring(c, r1, r2, n=10):
    """A closed ring across the arm: e1 lies in the XZ plane, square to the arm's direction."""
    e1 = (0.643, 0.766)
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        co, si = math.cos(t), math.sin(t)
        pts.append([round(c[0] + r1 * co * e1[0], 4), round(c[1] + r2 * si, 4), round(c[2] + r1 * co * e1[1], 4)])
    return pts


def grid(name, xs, ys):
    """Loop cuts that make a part's caps a 2 x 3 grid: 8 outline points, or 10 when closed."""
    within = {"in": name}
    step("loopcut", name + "_gx", at={"axis": "x", "value": xs}, within=within, result=name + "_gx")
    step("loopcut", name + "_gy", at={"axis": "y", "value": ys}, within=within, result=name + "_gy")


def caps(name):
    step("select", name + "_bottom", {"selected": 6}, name=name + "_bottom", where={"in": name, "normal": [0, 0, -1]})
    step("select", name + "_c1", {"selected": 6}, name=name + "_c1", where={"in": name, "normal": [0, 0, 1]})


def rings(name, outlines):
    """Give the part's two cube caps their outlines, then extrude one ring per outline."""
    step("transform", name + "_shape0", sel=name + "_bottom", outline=outlines[0])
    step("transform", name + "_shape1", sel=name + "_c1", outline=outlines[1])
    for k, o in enumerate(outlines[2:], 2):
        step("extrude", f"{name}_{k}", sel=f"{name}_c{k - 1}", vector=[0, 0, 0.01], result=f"{name}_c{k}")
        step("transform", f"{name}_shape{k}", sel=f"{name}_c{k}", outline=o)


# ---------------------------------------------------------------- materials (concept palette)
MAT = {"Hood": ("3A427A", 0.75), "Skin": ("EEBE98", 0.5), "Eye": ("16121E", 0.2), "Tunic": ("C66834", 0.8),
       "Belt": ("4A2E24", 0.6), "Trousers": ("68625C", 0.85), "Boots": ("805030", 0.55), "Mitten": ("ECDEB8", 0.8)}


def material(sel, name, label):
    step("material", label, sel=sel, name=name, color=lin(MAT[name][0]), metallic=0, roughness=MAT[name][1])


# ---------------------------------------------------------------- tunic: the base part
step("primitive", "tunic", type="cube", size=[0.46, 0.42, 0.05], location=[0, -0.01, 0.325], tier="pc")
step("mirror", axis="x")
step("note", "tunic_name", tier="pc")
step("select", "tunic", name="tunic", where={})
step("material", "tunic_mat", name="Tunic", color=lin(MAT["Tunic"][0]), metallic=0, roughness=MAT["Tunic"][1])
grid("tunic", 0.11, [-0.09, 0.07])
caps("tunic")
rings("tunic", [half_ring(*r) for r in (
    (0.300, 0.235, -0.225, 0.200, 3), (0.350, 0.215, -0.225, 0.180, 3), (0.402, 0.214, -0.230, 0.172, 3),
    (0.448, 0.214, -0.228, 0.170, 3), (0.500, 0.195, -0.200, 0.160, 3), (0.550, 0.175, -0.175, 0.150, 2.6),
    (0.600, 0.120, -0.120, 0.125), (0.640, 0.080, -0.080, 0.090))])
step("extrude", "belt", sel="tunic_c3_sides", distance=0.012, along="normals", result="belt")
material("belt", "Belt", "belt_mat")
material("belt_sides", "Belt", "belt_side_mat")

# ---------------------------------------------------------------- buckle
step("primitive", "buckle", add=True, type="cube", size=[0.092, 0.04, 0.084], location=[0, -0.226, 0.425], result="buckle")
step("material", "buckle_mat", sel="buckle", name="Brass", color=lin("ECC054"), metallic=1, roughness=0.35)

# ---------------------------------------------------------------- hood: cape, bell, folded tail
step("primitive", "hood", add=True, type="cube", size=[0.5, 0.4, 0.04], location=[0, 0.005, 0.57], result="hood")
material("hood", "Hood", "hood_mat")
grid("hood", 0.125, [-0.08, 0.09])
caps("hood")
HOOD = [
    half_ring(lambda t: 0.545 + 0.06 * math.sin(t) ** 2, 0.258, -0.197, 0.207),
    half_ring(lambda t: 0.585 + 0.03 * math.sin(t) ** 2, 0.255, -0.180, 0.205),
    half_ring(0.640, 0.222, -0.115, 0.205, 3),
    half_ring(0.700, 0.242, -0.065, 0.235, 4),
    half_ring(0.750, 0.257, -0.050, 0.255, 4),
    half_ring(0.800, 0.267, -0.040, 0.270, 4),
    half_ring(0.850, 0.272, -0.050, 0.275, 4),
    half_ring(0.900, 0.267, -0.065, 0.277, 4),
    half_ring(0.950, 0.262, -0.100, 0.272, 3),
    half_ring(0.976, 0.260, -0.150, 0.268, 2.6),
    half_ring(0.988, 0.256, -0.235, 0.264, 2.4),
    half_ring(1.004, 0.249, -0.250, 0.258, 2.2),
    half_ring(1.025, 0.232, -0.235, 0.245),
    half_ring(1.050, 0.217, -0.215, 0.232),
    half_ring(1.100, 0.187, -0.165, 0.217),
    tilted_ring((-0.130, 1.140), (0.213, 1.125), 0.160),
    tilted_ring((-0.095, 1.180), (0.235, 1.150), 0.135),
    tilted_ring((-0.050, 1.242), (0.270, 1.150), 0.115),
    tilted_ring((0.020, 1.292), (0.300, 1.145), 0.100),
    tilted_ring((0.110, 1.314), (0.325, 1.130), 0.090),
    tilted_ring((0.205, 1.292), (0.345, 1.115), 0.070),
    tilted_ring((0.290, 1.246), (0.370, 1.095), 0.045),
    tilted_ring((0.345, 1.200), (0.390, 1.080), 0.032),
    tilted_ring((0.400, 1.140), (0.410, 1.060), 0.022),
    tilted_ring((0.445, 1.070), (0.430, 1.030), 0.013),
    tilted_ring((0.466, 1.030), (0.452, 1.012), 0.006),
]
rings("hood", HOOD)

# ---------------------------------------------------------------- head, nose, eyes
step("primitive", "head", add=True, type="ball", size=[0.425, 0.41, 0.405], location=[0, -0.03, 0.80], result="head")
material("head", "Skin", "head_mat")
step("primitive", "nose", add=True, type="ball", size=[0.112, 0.112, 0.112], location=[0, -0.215, 0.752], result="nose")
material("nose", "Skin", "nose_mat")
# deep eyes: press a socket into the face, then set the eye into it
step("select", "socket", name="socket", domain="vert",
     where={"in": "head", "nearest": [0.0925, -0.21, 0.8225], "count": 4})
step("transform", "socket_press", sel="socket", translate=[0, 0.044, 0], proportional=0.07)
step("primitive", "eye", add=True, type="ball", cuts=1, size=[0.10, 0.07, 0.124], location=[0.0925, -0.166, 0.8225], result="eye")
material("eye", "Eye", "eye_mat")

# the rim of the hood opening: a tube round the face, from the crown seam to the chin seam
RIM = []
for k in range(11):
    t = math.pi * k / 10
    co, si = math.cos(t), math.sin(t)
    y = -0.024 - (0.206 * abs(co) ** 5 if co > 0 else 0.146 * abs(co) ** 4)   # the band in the side view
    RIM.append([round(0.222 * si, 4), round(y, 4), round(0.800 + 0.192 * co, 4)])
step("primitive", "rim", add=True, type="tube", path=RIM, radius=0.017, sides=6, result="rim")
material("rim", "Hood", "rim_mat")

# ---------------------------------------------------------------- sleeve and mitten
step("primitive", "sleeve", add=True, type="cube", size=[0.1, 0.14, 0.05], location=[0.12, 0, 0.62], result="sleeve")
grid("sleeve", 0.12, [-0.03, 0.03])
caps("sleeve")
step("select", "sleeve_v", name="sleeve_v", domain="vert", where={"in": "sleeve"})
step("transform", "sleeve_tilt", sel="sleeve_v", rotate=[0, 130, 0])
rings("sleeve", [arm_ring(c, r1, r2) for c, r1, r2 in (
    ((0.100, 0, 0.635), 0.050, 0.070), ((0.165, 0, 0.585), 0.075, 0.085), ((0.205, 0, 0.552), 0.075, 0.082),
    ((0.222, 0, 0.538), 0.075, 0.080), ((0.238, 0, 0.524), 0.075, 0.078), ((0.254, 0, 0.511), 0.074, 0.075),
    ((0.271, 0, 0.497), 0.073, 0.071), ((0.290, 0, 0.480), 0.073, 0.064), ((0.310, 0, 0.463), 0.075, 0.054))])
step("primitive", "mitten", add=True, type="ball", cuts=2, size=[0.15, 0.126, 0.21], rotate=[0, 130, 0],
     location=[0.355, 0, 0.435], result="mitten")
material("mitten", "Mitten", "mitten_mat")
step("primitive", "thumb", add=True, type="ball", cuts=1, size=[0.13, 0.062, 0.062], rotate=[0, -23, -49],
     location=[0.392, -0.078, 0.492], result="thumb")
material("thumb", "Mitten", "thumb_mat")

# ---------------------------------------------------------------- trouser leg and boot
step("primitive", "leg", add=True, type="cube", size=[0.2, 0.28, 0.04], location=[0.112, 0.005, 0.31], result="leg")
material("leg", "Trousers", "leg_mat")
grid("leg", 0.112, [-0.05, 0.06])
caps("leg")
step("select", "leg_flip", name="leg_top", where={"in": "leg_c1"})
LEG = [closed_ring(*r) for r in (
    (0.318, 0.112, 0.092, -0.120, 0.130), (0.290, 0.112, 0.112, -0.147, 0.157), (0.250, 0.115, 0.107, -0.147, 0.153),
    (0.232, 0.116, 0.100, -0.135, 0.145), (0.215, 0.118, 0.090, -0.115, 0.135), (0.200, 0.119, 0.087, -0.112, 0.132),
    (0.185, 0.120, 0.085, -0.110, 0.130))]
step("transform", "leg_shape0", sel="leg_c1", outline=LEG[0])
step("transform", "leg_shape1", sel="leg_bottom", outline=LEG[1])
step("extrude", "leg_2", sel="leg_bottom", vector=[0, 0, -0.01], result="leg_b2")
step("transform", "leg_shape2", sel="leg_b2", outline=LEG[2])
step("extrude", "leg_3", sel="leg_b2", vector=[0, 0, -0.01], result="leg_b3")
step("transform", "leg_shape3", sel="leg_b3", outline=LEG[3])
for k in (4, 5, 6):
    step("extrude", f"leg_{k}", sel=f"leg_b{k - 1}", vector=[0, 0, -0.01], result=f"leg_b{k}")
    step("transform", f"leg_shape{k}", sel=f"leg_b{k}", outline=LEG[k])

step("primitive", "boot", add=True, type="cube", size=[0.2, 0.4, 0.03], location=[0.1225, -0.065, 0.015], result="boot")
material("boot", "Boots", "boot_mat")
grid("boot", 0.1225, [-0.15, 0.03])
caps("boot")
rings("boot", [closed_ring(*r) for r in (
    (0.000, 0.1225, 0.104, -0.268, 0.142, 3.2), (0.030, 0.1225, 0.104, -0.265, 0.137, 3.2),
    (0.060, 0.1225, 0.103, -0.258, 0.132, 3), (0.100, 0.1225, 0.098, -0.245, 0.127, 2.6),
    (0.125, 0.1225, 0.090, -0.170, 0.124), (0.150, 0.1225, 0.084, -0.108, 0.122),
    (0.190, 0.1205, 0.086, -0.106, 0.126))])

step("select", "sole", name="sole", where={"in": "boot", "max": [null, null, 0.031]})
step("material", "sole_mat", sel="sole", name="Sole", color=lin("2E1E1C"), metallic=0, roughness=0.7)
step("material", "cuff_mat", sel="boot_c6_sides", name="Cuff", color=lin("9A6A48"), metallic=0, roughness=0.6)

# ---------------------------------------------------------------- smooth
step("subsurf", "smooth", levels=2)
step("subsurf", "crease_buckle", levels=2, crease={"sel": "buckle", "value": 1.0})
step("subsurf", "crease_sole", levels=2, crease={"sel": "boot_bottom", "value": 0.9})
step("subsurf", "crease_hem", levels=2, crease={"sel": "tunic_bottom", "value": 0.9})
step("cleanup", "clean")
step("mirror", "apply", axis="x", mode="apply")

for s in STEPS:
    print(json.dumps(s, ensure_ascii=False))
