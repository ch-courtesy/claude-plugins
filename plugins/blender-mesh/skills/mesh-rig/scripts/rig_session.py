"""Rig a character made of parts, bend it through test poses and measure the damage.

  blender -b MODEL.blend --python rig_session.py -- --spec RIG.json --out DIR [--object Model]
      [--res 420]

Bones and binding come from RIG.json (see the mesh-rig skill). A part is every connected piece
of the mesh holding faces of a named selection, so a mirrored sleeve is two pieces. Weights are
computed, not auto-generated: a part is rigid on one bone, or blends along a chain of bones with
a smooth step at each joint, so weights are predictable on overlapping parts where bone-heat
weighting fails. Writes DIR/rig.blend, DIR/report.json and DIR/pose_<name>.png.
"""
import argparse
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pose_rules import auto_raise, driven_rotations  # noqa: E402


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


ap = argparse.ArgumentParser()
ap.add_argument("--spec", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--object", default="Model")
ap.add_argument("--res", type=int, default=420)
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
SPEC = read_json(a.spec, encoding="utf-8")
ob = bpy.data.objects[a.object]
sc = bpy.context.scene
if ob.modifiers.get("Mirror"):
    sys.exit("[rig] apply the mirror first: mesh.py <session> mirror '{\"axis\":\"x\",\"mode\":\"apply\"}'")


def flip(p):
    return [-p[0], p[1], p[2]]


# ---- bones: "mirror": true makes name.L at +x and name.R at -x
BONES, SIDED = [], set()
FOLLOW = {b["follows"]: (b["name"], b.get("share", 0.5)) for b in SPEC["bones"] if b.get("follows")}
DRIVEN = driven_rotations(SPEC["bones"])
AUTO_RAISE = any(b.get("auto_raise") for b in SPEC["bones"])
LIFTED = {}                                            # clavicle -> degrees lifted in the last pose
for b in SPEC["bones"]:
    if b.get("mirror"):
        SIDED.add(b["name"])
for b in SPEC["bones"]:
    par = b.get("parent")
    if b.get("mirror"):
        for side, f in (("L", lambda p: p), ("R", flip)):
            BONES.append((f"{b['name']}.{side}", f(b["head"]), f(b["tail"]), f"{par}.{side}" if par in SIDED else par))
    else:
        BONES.append((b["name"], b["head"], b["tail"], par))
arm = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm)
sc.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for name, h, t, par in BONES:
    eb = arm.edit_bones.new(name)
    eb.head, eb.tail = h, t
    if par:
        eb.parent = arm.edit_bones[par]
bpy.ops.object.mode_set(mode="OBJECT")
BONE = {n: (np.array(h, float), np.array(t, float)) for n, h, t, _ in BONES}


def side_of(name, x):
    return f"{name}.{'L' if x >= 0 else 'R'}" if name in SIDED else name


# ---- parts as connected pieces of the cage
bm = bmesh.new()
bm.from_mesh(ob.data)
bm.verts.ensure_lookup_table()
piece = {}
pieces = []
for v0 in bm.verts:
    if v0.index in piece:
        continue
    k, todo = len(pieces), [v0]
    piece[v0.index] = k
    ids = [v0.index]
    while todo:
        v = todo.pop()
        for e in v.link_edges:
            o = e.other_vert(v)
            if o.index not in piece:
                piece[o.index] = k
                ids.append(o.index)
                todo.append(o)
    pieces.append(ids)
owner = {}
# A part with "region": true weights only the vertices of its own faces, so one connected piece (a body whose
# sleeves and trousers are joined to the torso) can hold several parts. Whole-piece rules claim pieces first;
# region rules claim vertices, the first region rule in the spec winning a vertex on a border.
REGION_RULES = [r for r in SPEC["parts"] if r.get("region")]
for rule in [r for r in SPEC["parts"] if not r.get("region")] + REGION_RULES:
    lay = bm.faces.layers.int.get("sel_" + rule["part"])
    if lay is None:
        sys.exit(f"[rig] no selection named {rule['part']}")
    for k in {piece[f.verts[0].index] for f in bm.faces if f[lay]}:
        owner.setdefault(k, rule)
vert_rule = {}
for rule in REGION_RULES:
    lay = bm.faces.layers.int.get("sel_" + rule["part"])
    for f in bm.faces:
        if f[lay]:
            for v in f.verts:
                vert_rule.setdefault(v.index, rule)
CAGE_EDGES = np.array([[e.verts[0].index, e.verts[1].index] for e in bm.edges], np.int64).reshape(-1, 2) \
    if REGION_RULES else None
CO = np.array([v.co[:] for v in bm.verts])
bm.free()
loose = [k for k in range(len(pieces)) if k not in owner]
if loose:
    print(f"[rig] {len(loose)} pieces match no part, near", [np.round(CO[pieces[k]].mean(0), 2).tolist() for k in loose][:4])


# ---- weights
def smooth(t):
    """The step at a joint. Linear spreads the stretch evenly; a smoothstep is 1.5 times steeper
    in the middle, which is where the outside of a bend tears first."""
    t = np.clip(t, 0, 1)
    return t if SPEC.get("blend_profile", "linear") == "linear" else t * t * (3 - 2 * t)


def chain_weights(P, chain, blend, blends=None, shifts=None):
    """Weights along a chain of bones: each vertex finds its place along the chain, and every
    joint is a smooth step `blend` metres long (or blends[i] for joint i), centred on the joint or
    shifts[i] metres past it. At most two bones per vertex."""
    segs = [BONE[n] for n in chain]
    lens = [float(np.linalg.norm(t - h)) for h, t in segs]
    cum = np.r_[0, np.cumsum(lens)]
    best, arc = np.full(len(P), np.inf), np.zeros(len(P))
    for i, (h, t) in enumerate(segs):
        d = t - h
        u = np.clip(((P - h) @ d) / (d @ d), 0, 1)
        dist = np.linalg.norm(P - (h + u[:, None] * d), axis=1)
        m = dist < best
        best[m] = dist[m]
        arc[m] = cum[i] + u[m] * lens[i]
    bl = list(blends) if blends else [blend] * (len(chain) - 1)
    if shifts:
        cum = cum + np.r_[0, list(shifts), 0][:len(cum)]
    steps = [np.ones(len(P))] + [smooth((arc - cum[i]) / bl[i - 1] + 0.5) for i in range(1, len(chain))] + [np.zeros(len(P))]
    return [steps[i] - steps[i + 1] for i in range(len(chain))], best, arc


def rule_weights(rule, P, x):
    """(bone, weights) pairs for points P under one part rule, the side taken from x, and the shape the stretch
    bound uses (chain, radius, length), or None for a rigid part."""
    if "bone" in rule:
        return [(side_of(rule["bone"], x), np.ones(len(P)))], None
    if "split" in rule:                                # by height: a sole stays flat on its own bone
        sp = rule["split"]
        low, high = side_of(sp["low"], x), side_of(sp["high"], x)
        t_ = np.clip((P[:, 2] - (sp["at"] - sp["width"] / 2)) / sp["width"], 0, 1)
        if sp.get("fade"):                             # keep the upper bone off what sticks out, like a toe
            ax_, f0, f1 = sp["fade"]
            t_ = t_ * np.clip((P[:, ax_] - f0) / (f1 - f0), 0, 1)
        shape = ([high, low], float(np.median(np.linalg.norm(P[:, :2] - P[:, :2].mean(0), axis=1))),
                 float(P[:, 2].max() - P[:, 2].min()))
        parts_ = [(low, 1 - t_), (high, t_)]
        if sp.get("helper"):                           # low, helper, high up the joint
            hi_w, lo_w = np.clip(2 * t_ - 1, 0, 1), 1 - np.clip(2 * t_, 0, 1)
            parts_ = [(low, lo_w), (side_of(sp["helper"], x), 1 - lo_w - hi_w), (high, hi_w)]
        return parts_, shape
    names = [side_of(n, x) for n in rule["chain"]]
    ws, dist, arc = chain_weights(P, names, rule.get("blend", 0.05), rule.get("blends"), rule.get("shifts"))
    shape = (names, float(np.median(dist)), float(arc.max() - arc.min()))
    pairs_ = list(zip(names, ws))
    if rule.get("helper") and len(names) == 2:         # parent, helper, child across the joint
        step_ = ws[1]
        child = np.clip(2 * step_ - 1, 0, 1)
        parent_w = 1 - np.clip(2 * step_, 0, 1)
        pairs_ = [(names[0], parent_w), (side_of(rule["helper"], x), 1 - parent_w - child), (names[1], child)]
    elif rule.get("helper"):                           # the helper at joint `helper_joint` (0: the first); others as usual
        h_ = rule.get("helper_joint", 0)
        step_ = sum(ws[h_ + 1:])                       # the share past that joint
        rest = np.clip(2 * step_ - 1, 0, 1)
        parent_w = 1 - np.clip(2 * step_, 0, 1)
        up = np.where(step_ < 1 - 1e-9, parent_w / np.maximum(1 - step_, 1e-9), 0.0)
        down = np.where(step_ > 1e-9, rest / np.maximum(step_, 1e-9), 0.0)
        pairs_ = [(n, w * up) for n, w in zip(names[:h_ + 1], ws[:h_ + 1])] + \
                 [(side_of(rule["helper"], x), 1 - parent_w - rest)] + \
                 [(n, w * down) for n, w in zip(names[h_ + 1:], ws[h_ + 1:])]
    return pairs_, shape


def other_side(n):
    return n[:-2] + ".R" if n.endswith(".L") else n


def region_weights(k, ids):
    """Weights of a piece that holds region parts: each vertex by its own rule, on its own side. A rule is
    evaluated on the vertex mirrored to +x with the left bones, then given to the side the vertex is on; within
    `side_blend` metres of x = 0 the two sides are mixed, so a piece that crosses the middle (one-piece trousers,
    an apron on two bone columns) is weighted symmetrically. Borders between rules are then smoothed over
    `smooth` rings of edges, and every vertex keeps its four largest weights."""
    loc = {i: j for j, i in enumerate(ids)}
    P = CO[ids]
    W = {}
    by_rule = {}
    for j, i in enumerate(ids):
        by_rule.setdefault(id(vert_rule.get(i, owner[k])), (vert_rule.get(i, owner[k]), []))[1].append(j)
    rule_at = np.zeros(len(ids), np.int64)
    band_at = np.zeros(len(ids))
    for r_id, (rule, js) in enumerate(by_rule.values()):
        js = np.array(js)
        rule_at[js] = r_id
        Pm = P[js].copy()
        Pm[:, 0] = np.abs(Pm[:, 0])
        pairs_, shape = rule_weights(rule, Pm, 1.0)
        band = rule.get("side_blend", 0.0)
        xs = P[js, 0]
        if band > 0:
            fL = np.clip(0.5 + xs / (2 * band), 0, 1)
        else:
            fL = np.where(xs > 1e-4, 1.0, np.where(xs < -1e-4, 0.0, 0.5))
        for n, w in pairs_:
            for nm, f in ((n, fL), (other_side(n), 1 - fL)):
                W.setdefault(nm, np.zeros(len(ids)))[js] += f * w
        band_at[js] = max(band, 1e-4)
        unit = rule.get("measure_as", rule["part"])
        if shape and ("measure_as" not in rule or (k, unit, "L") not in REGION_SHAPE):
            for sd, m in (("L", xs >= 0), ("R", xs < 0)):
                if m.any():
                    nm_ = shape[0] if sd == "L" else [other_side(n) for n in shape[0]]
                    REGION_SHAPE[(k, unit, sd)] = (nm_, shape[1], shape[2])
    sm = np.array([r.get("smooth", 0) for r, _ in by_rule.values()], np.int64)
    rings = int(sm.max()) if len(sm) else 0
    if rings and len(by_rule) > 1:
        E_ = np.array([(loc[a_], loc[b_]) for a_, b_ in CAGE_EDGES if a_ in loc and b_ in loc], np.int64).reshape(-1, 2)
        # a border between two rules is smoothed over the larger of their "smooth" ring counts (0 keeps it sharp)
        border = rule_at[E_[:, 0]] != rule_at[E_[:, 1]]
        reach = np.maximum(sm[rule_at[E_[:, 0]]], sm[rule_at[E_[:, 1]]]) * border
        budget = np.zeros(len(ids), np.int64)
        np.maximum.at(budget, E_[:, 0], reach)
        np.maximum.at(budget, E_[:, 1], reach)
        for _ in range(rings):                         # each ring of edges further from the border spends one
            nb_ = budget.copy()
            np.maximum.at(nb_, E_[:, 0], budget[E_[:, 1]] - 1)
            np.maximum.at(nb_, E_[:, 1], budget[E_[:, 0]] - 1)
            budget = nb_
        zone = budget > 0
        deg = np.bincount(E_.ravel(), minlength=len(ids)).astype(float) + 1
        names_ = list(W)
        M = np.stack([W[n] for n in names_], 1)
        for _ in range(3 * rings):                     # Jacobi: a zone vertex takes the mean of itself and its neighbours
            S_ = M.copy()
            np.add.at(S_, E_[:, 0], M[E_[:, 1]])
            np.add.at(S_, E_[:, 1], M[E_[:, 0]])
            M = np.where(zone[:, None], S_ / deg[:, None], M)
        W = {n: M[:, c] for c, n in enumerate(names_)}
    names_ = list(W)
    M = np.stack([W[n] for n in names_], 1)
    # smoothing can carry a weight round the middle of the body to the other side; outside a rule's side band a
    # vertex keeps only its own side's bones
    xs_ = P[:, 0]
    for c, n in enumerate(names_):
        if n.endswith(".R"):
            M[xs_ > band_at, c] = 0.0
        elif n.endswith(".L"):
            M[xs_ < -band_at, c] = 0.0
    if M.shape[1] > 4:                                # four influences at most, as engines take
        cut = np.argsort(-M, axis=1)[:, 4:]
        np.put_along_axis(M, cut, 0.0, axis=1)
    M[M <= 1e-4] = 0.0
    M /= np.maximum(M.sum(1, keepdims=True), 1e-12)
    return [(n, M[:, c]) for c, n in enumerate(names_)], rule_at, list(by_rule.values())


groups = {n: ob.vertex_groups.new(name=n) for n, *_ in BONES}
SHAPE = {}                                             # piece -> chain, radius and length along it
REGION_SHAPE = {}                                      # (piece, part, side) -> the same, for region parts
REGION_OF = {}                                         # piece -> per-vertex (part, side) for region pieces
for k, ids in enumerate(pieces):
    rule = owner.get(k)
    if rule is None:
        continue
    P = CO[ids]
    if rule.get("side_blend") is not None or any(i in vert_rule for i in ids):   # region parts, or sides per vertex
        pairs_, rule_at, rules_ = region_weights(k, ids)
        REGION_OF[k] = [(rules_[r][0].get("measure_as", rules_[r][0]["part"]), "L" if P[j, 0] >= 0 else "R")
                        for j, r in enumerate(rule_at)]
        for n, w in pairs_:
            for i, wi in zip(ids, w):
                if wi > 1e-4:
                    groups[n].add([i], float(wi), "REPLACE")
        continue
    x = float(P[:, 0].mean())
    if abs(x) < 1e-3:
        x = 0.0
    if "bone" in rule:
        groups[side_of(rule["bone"], x)].add(ids, 1.0, "REPLACE")
        continue
    pairs_, shape = rule_weights(rule, P, x)
    SHAPE[k] = shape
    for n, w in pairs_:
        for i, wi in zip(ids, w):
            if wi > 1e-4:
                groups[n].add([i], float(wi), "REPLACE")
mod = ob.modifiers.new("Armature", "ARMATURE")
mod.object = rig
mod.use_deform_preserve_volume = SPEC.get("preserve_volume", False)   # dual quaternion skinning
ob.modifiers.move(len(ob.modifiers) - 1, 0)


# ---- binding facts
me = ob.data
unweighted = sum(1 for v in me.vertices if not v.groups)
influences = max((sum(1 for g in v.groups if g.weight > 1e-3) for v in me.vertices), default=0)
sums = [sum(g.weight for g in v.groups) for v in me.vertices if v.groups]
weight_sum_err = max((abs(s - 1) for s in sums), default=0.0)
names = {g.index: g.name for g in ob.vertex_groups}


def wmap(v):
    d = {}
    for g in v.groups:
        n = names[g.group]
        d[n.replace(".L", ".#").replace(".R", ".#")] = g.weight
    return d


SIDE_BLEND = any(r.get("side_blend") is not None for r in SPEC["parts"])


def wmap_sided(v):
    return {names[g.group]: g.weight for g in v.groups}


def other_name(n):
    return n[:-2] + ".R" if n.endswith(".L") else (n[:-2] + ".L" if n.endswith(".R") else n)


kd = KDTree(len(me.vertices))
for i, v in enumerate(me.vertices):
    kd.insert(v.co, i)
kd.balance()
sym = 0.0
for v in me.vertices:
    if v.co.x > 1e-4:
        _, j, dist = kd.find(Vector((-v.co.x, v.co.y, v.co.z)))
        if dist < 1e-3:
            if REGION_RULES or SIDE_BLEND:             # a vertex may hold both sides: compare X.L with the mirror's X.R
                p, q = wmap_sided(v), {other_name(n): w for n, w in wmap_sided(me.vertices[j]).items()}
            else:
                p, q = wmap(v), wmap(me.vertices[j])
            sym = max(sym, max(abs(p.get(n, 0) - q.get(n, 0)) for n in set(p) | set(q)))


# ---- measuring the evaluated surface
def evaluated():
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    e = ob.evaluated_get(dg)
    m = e.to_mesh()
    n = len(m.vertices)
    V = np.empty(n * 3)
    m.vertices.foreach_get("co", V)
    return V.reshape(n, 3), m, e


V0, m0, e0 = evaluated()
E = np.empty(len(m0.edges) * 2, np.int64)
m0.edges.foreach_get("vertices", E)
E = E.reshape(-1, 2)
m0.calc_loop_triangles()
T = np.empty(len(m0.loop_triangles) * 3, np.int64)
m0.loop_triangles.foreach_get("vertices", T)
T = T.reshape(-1, 3)
e0.to_mesh_clear()

parent = np.arange(len(V0))


def find(i):
    while parent[i] != i:
        parent[i] = parent[parent[i]]
        i = parent[i]
    return i


for p, q in E:
    rp, rq = find(p), find(q)
    if rp != rq:
        parent[rq] = rp
label = np.array([find(i) for i in range(len(V0))])
roots = np.unique(label)
centres = {r: V0[label == r].mean(0) for r in roots}


def part_name(r):
    best = min(range(len(pieces)), key=lambda k: np.linalg.norm(CO[pieces[k]].mean(0) - centres[r]))
    ROOT_PIECE[r] = best
    side = "" if abs(centres[r][0]) < 1e-3 else ("." + ("L" if centres[r][0] > 0 else "R"))
    return owner.get(best, {"part": "?"})["part"] + side


ROOT_PIECE = {}
NAME = {r: part_name(r) for r in roots}
tri_piece = label[T[:, 0]]
# Measuring units: a piece, or for a piece that holds region parts each (part, side) of it, so a joined body is
# judged per sleeve and per trouser leg instead of as one large piece that would hide a local fault.
ulabel = label.copy()
UNAME = dict(NAME)
USHAPE = {r: SHAPE.get(ROOT_PIECE[r], ((), 0.0, 1.0)) for r in roots}
for r in roots:
    k = ROOT_PIECE[r]
    if k not in REGION_OF:
        continue
    ids_ = pieces[k]
    kd_ = KDTree(len(ids_))
    for j, i in enumerate(ids_):
        kd_.insert(CO[i], j)
    kd_.balance()
    keys = {}
    for v in np.nonzero(label == r)[0]:
        key = REGION_OF[k][kd_.find(V0[v])[1]]
        if key not in keys:
            keys[key] = int(len(V0) + len(UNAME))
            UNAME[keys[key]] = key[0] + "." + key[1]
            USHAPE[keys[key]] = REGION_SHAPE.get((k, key[0], key[1]), ((), 0.0, 1.0))
        ulabel[v] = keys[key]
units = np.unique(ulabel)
tri_unit = ulabel[T[:, 0]]
L0 = np.linalg.norm(V0[E[:, 0]] - V0[E[:, 1]], axis=1)


def tri_area(V):
    return np.linalg.norm(np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]]), axis=1) / 2


A0 = tri_area(V0)


def tri_normals(V):
    n = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)


# triangle pairs sharing an edge, for telling a fold from a bend
te = np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]])
tid = np.tile(np.arange(len(T)), 3)
te.sort(axis=1)
key = te[:, 0].astype(np.int64) * len(V0) + te[:, 1]
order = np.argsort(key, kind="stable")
same = key[order][1:] == key[order][:-1]
PAIR = np.stack([tid[order][:-1][same], tid[order][1:][same]], 1)
N0 = tri_normals(V0)
FLAT_AT_REST = np.einsum("ij,ij->i", N0[PAIR[:, 0]], N0[PAIR[:, 1]]) > 0.5     # under 60 degrees
PAIR_PART = tri_unit[PAIR[:, 0]]


def bone_rotation(name):
    pb = rig.pose.bones[name]
    return (pb.matrix.to_3x3() @ pb.bone.matrix_local.to_3x3().inverted())


def bend(names):
    """The total bend along a chain of bones, in radians."""
    out = 0.0
    for p, q in zip(names, names[1:]):
        rel = bone_rotation(q) @ bone_rotation(p).inverted()
        a_ = rel.to_quaternion().angle
        out += min(a_, 2 * math.pi - a_)
    return out


def volumes(V):
    d = np.einsum("ij,ij->i", V[T[:, 0]], np.cross(V[T[:, 1]], V[T[:, 2]])) / 6
    return {r: float(d[tri_piece == r].sum()) for r in roots}


Vol0 = volumes(V0)
pairs = []
for p, q in SPEC.get("attach", []):
    for s in ("", ".L", ".R"):
        ra = [r for r in roots if NAME[r] == p + s]
        rb = [r for r in roots if NAME[r] in (q + s, q)]
        if ra and rb:
            pairs.append((f"{p}{s}-{q}{s}", ra[0], rb[0]))


def gap(V, ra, rb):
    A, B = V[label == ra], V[label == rb]
    t = KDTree(len(B))
    for i, c in enumerate(B):
        t.insert(c, i)
    t.balance()
    return min(t.find(c)[2] for c in A[::3])


G0 = {n: gap(V0, ra, rb) for n, ra, rb in pairs}

# ---- camera and flat viewport-style renders
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_shadows = True
sc.render.resolution_x = sc.render.resolution_y = a.res
sc.render.film_transparent = False
w = sc.world or bpy.data.worlds.new("World")
sc.world = w
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = float(V0[:, 2].max() - V0[:, 2].min()) * 1.5
c = Vector(((V0.min(0) + V0.max(0)) / 2).tolist())
back = Vector((0.9, -2.2, 0.5)).normalized()
cam.location = c + back * 4
cam.rotation_euler = (-back).to_track_quat("-Z", "Y").to_euler()


def set_pose(rots):
    LIFTED.clear()
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    order = {n: i for i, (n, *_) in enumerate(BONES)}
    expanded = []
    for r in rots:
        expanded.append((r["bone"], r["axis"], r["deg"]))
        if r.get("mirror", True) and r["bone"].endswith(".L"):
            ax = r["axis"]
            expanded.append((r["bone"][:-2] + ".R", [ax[0], -ax[1], -ax[2]], r["deg"]))
    for name, axis, deg in list(expanded):             # helpers take their share of the rotation
        base, _, side = name.partition(".")
        if base in FOLLOW:
            h_, share = FOLLOW[base]
            expanded.append((f"{h_}.{side}" if side else h_, axis, deg * share))
    for name, axis, deg in list(expanded):             # corrective bones driven by others ("driven_by")
        for d_, share in DRIVEN.get(name, []):
            expanded.append((d_, axis, deg * share))
    for name, axis, deg in sorted(expanded, key=lambda x: order[x[0]]):
        pb = rig.pose.bones[name]
        h = pb.matrix.translation.copy()
        R = Matrix.Rotation(math.radians(deg), 4, Vector(axis).normalized())
        pb.matrix = Matrix.Translation(h) @ R @ Matrix.Translation(-h) @ pb.matrix
        bpy.context.view_layer.update()
    if AUTO_RAISE:                                     # a clavicle lifts once its arm passes the horizontal
        LIFTED.update(auto_raise(rig, SPEC["bones"], bpy.context.view_layer.update))


# ---- rest check, then every pose
Vr, mr, er = evaluated()
er.to_mesh_clear()
rest_err = float(np.abs(Vr - V0).max()) * 1000
R = {"bones": len(BONES), "pieces": len(pieces), "unmatched_pieces": len(loose), "unweighted": unweighted,
     "max_influences": influences, "weight_sum_error": weight_sum_err, "symmetry_error": sym, "rest_error_mm": rest_err,
     "poses": {}}
worst = {"volume_change": 0.0, "strain_p99": 0.0, "area_ratio_p001": 1.0, "gap_open_cm": 0.0, "stretch_excess": 0.0,
         "fold_share": 0.0}
def apply_pose(pose):
    """Rotations about world axes, or a baked frame as local rotation and location per bone."""
    if "basis" not in pose:
        set_pose(pose["rot"])
        return
    set_pose([])
    for name, (q, loc) in pose["basis"].items():
        pb = rig.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion, pb.location = q, loc
    bpy.context.view_layer.update()


for pose in SPEC["poses"]:
    apply_pose(pose)
    V, m, e = evaluated()
    e.to_mesh_clear()
    L = np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1)
    ok = L0 > 1e-6
    strain = np.abs(L[ok] / L0[ok] - 1)
    by_part = {r: strain[ulabel[E[ok, 0]] == r] for r in units}
    strain_part = UNAME[max(by_part, key=lambda r: np.percentile(by_part[r], 99) if len(by_part[r]) else 0)]
    ok = A0 > 1e-9
    ratio = tri_area(V)[ok] / A0[ok]
    tp = tri_unit[ok]
    area_part = UNAME[min(units, key=lambda r: np.percentile(ratio[tp == r], 0.1) if (tp == r).any() else 9)]
    excess, excess_part, bound_of = 0.0, "", 0.0
    for r in units:                                    # stretch against what the shape allows
        if not len(by_part[r]):
            continue
        p99 = float(np.percentile(by_part[r], 99))
        names_, rad, length = USHAPE[r]
        bound = rad * bend(names_) / max(length, 1e-6) if len(names_) > 1 else 0.0
        allowed = max(0.35, 1.2 * bound)
        if p99 / allowed > excess:
            excess, excess_part, bound_of = p99 / allowed, UNAME[r], bound
    N1 = tri_normals(V)
    folded = FLAT_AT_REST & (np.einsum("ij,ij->i", N1[PAIR[:, 0]], N1[PAIR[:, 1]]) < -0.5)   # over 120 degrees
    shares = {r: float(folded[PAIR_PART == r].mean()) for r in units if (PAIR_PART == r).any()}
    fold_root = max(shares, key=shares.get)
    vol = volumes(V)
    dv = {NAME[r]: abs(vol[r] / Vol0[r] - 1) for r in roots if abs(Vol0[r]) > 1e-7}
    wv = max(dv, key=dv.get)
    gaps = {n: (gap(V, ra, rb) - G0[n]) * 100 for n, ra, rb in pairs}
    wg = max(gaps, key=gaps.get) if gaps else ""
    s = {"volume_change": dv[wv], "volume_part": wv, "strain_p99": float(np.percentile(strain, 99)),
         "strain_max": float(strain.max()), "area_ratio_p001": float(np.percentile(ratio, 0.1)),
         "gap_open_cm": gaps.get(wg, 0.0), "gap_pair": wg, "strain_part": strain_part, "area_part": area_part,
         "stretch_excess": excess, "stretch_excess_part": excess_part, "stretch_bound": bound_of,
         "fold_share": shares[fold_root], "fold_part": UNAME[fold_root]}
    if AUTO_RAISE:
        s["auto_raise_deg"] = {n: round(d, 2) for n, d in LIFTED.items()}
    R["poses"][pose["name"]] = s
    worst["volume_change"] = max(worst["volume_change"], s["volume_change"])
    worst["strain_p99"] = max(worst["strain_p99"], s["strain_p99"])
    worst["area_ratio_p001"] = min(worst["area_ratio_p001"], s["area_ratio_p001"])
    worst["gap_open_cm"] = max(worst["gap_open_cm"], s["gap_open_cm"])
    worst["stretch_excess"] = max(worst["stretch_excess"], s["stretch_excess"])
    worst["fold_share"] = max(worst["fold_share"], s["fold_share"])
    sc.render.filepath = os.path.join(out, f"pose_{pose['name']}.png")
    bpy.ops.render.render(write_still=True)
    print(f"[rig] {pose['name']}: volume {s['volume_change'] * 100:.1f}% ({wv}), strain p99 {s['strain_p99'] * 100:.0f}% "
          f"({strain_part}), against bound {excess:.2f} ({excess_part}, r.t/L {bound_of:.2f}), "
          f"folds {s['fold_share'] * 100:.2f}% ({s['fold_part']}), gap {s['gap_open_cm']:+.1f} cm ({wg})")
R["worst"] = worst
set_pose([])
sc.render.engine = "CYCLES"
for o in (cam,):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "rig.blend"))
with open(os.path.join(out, "report.json"), "w", encoding="utf-8") as fh:   # last: a report means the run finished
    json.dump(R, fh, ensure_ascii=False, indent=1)
print(f"[rig] {len(BONES)} bones, {len(pieces)} pieces, unweighted {unweighted}, max influences {influences}, "
      f"symmetry {sym:.3f}, rest error {rest_err:.4f} mm")
