"""meshop — apply modelling operations to a session, like actions in Blender.

  blender -b --factory-startup --python meshop.py -- SESSION_DIR OP '<json args>' [LABEL]
  blender -b --factory-startup --python meshop.py -- SESSION_DIR --run STEPS.jsonl [--strict] [--from N]

Each step: run OP on the model -> save steps/NNN_<op>[_label].blend -> append to log.jsonl
-> write a viewport-style snapshot (snaps/NNN.png: front / side / top / 3-4, selection in
orange). The first step opens the session's current .blend; with --run the next steps
continue on the model in memory, so a whole steps file costs one Blender start while every
step is still saved, logged and snapshotted as if it had been run alone. Snapshots render
in background processes.
Named selections are stored on the mesh as int attributes "sel_<name>" (face,
edge or point domain) so later steps can refer to them by name.

OPs: primitive select transform extrude inset loopcut bevel mirror subsurf
     cleanup material undo note        (arguments: see the skills' SKILL.md)
"""
import glob
import json
import math
import os
import subprocess
import sys
import traceback

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import session_state  # noqa: E402
from mathutils.kdtree import KDTree


def read_file(*args, **kwargs):
    """The whole of a file, closed again."""
    with open(*args, **kwargs) as fh:
        return fh.read()


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:]
SDIR = os.path.abspath(argv[0])
SFILE = os.path.join(SDIR, "session.json")
os.makedirs(os.path.join(SDIR, "steps"), exist_ok=True)
os.makedirs(os.path.join(SDIR, "snaps"), exist_ok=True)
S = read_json(SFILE, encoding="utf-8") if os.path.exists(SFILE) else \
    {"object": "Model", "steps": [], "current": None, "active": None, "mirror": None}
DOM = {"face": "faces", "edge": "edges", "vert": "verts"}
ATTR_DOM = {"face": "FACE", "edge": "EDGE", "vert": "POINT"}
NOSNAP = bool(os.environ.get("MESHOP_NOSNAP"))
SNAP_MAX = 4                            # snapshot processes running at once
SNAP_JOBS = []                          # running snapshots: (step number, process)
PY = []                                 # the Pillow Python, once looked up
LOADED = [False]                        # is the session's current step in memory?
ADDING = [False]                        # is this `primitive` step adding a part to the model?
CHECKS = []                             # automatic checks of the running step: [{"kind", "msg"}]


class StepError(Exception):
    """The step cannot be done; the session on disk stays as it was."""


def fail(msg):
    raise StepError(msg)


def warn(kind, msg):
    CHECKS.append({"kind": kind, "msg": msg})


def save_session():
    with open(SFILE, "w", encoding="utf-8") as fh:
        json.dump(S, fh, indent=1)


# ----------------------------------------------------------------------- open state
def do_undo():
    if len(S["steps"]) < 2:
        fail("nothing to undo")
    finish_snapshots()                            # a snapshot may still be writing the undone step
    session_state.undo(S, SDIR)                   # files go, and mirror and tier return to that step's
    save_session()
    LOADED[0] = False                             # memory holds the undone state: reopen next time
    print(f"[meshop] undo -> {S['current']}", flush=True)


def open_state(op):
    """Bring the session's current step into memory (once per process, or after undo)."""
    if op == "primitive" and not ADDING[0]:
        for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials):
            for x in list(coll):
                coll.remove(x)
    elif not LOADED[0]:
        if not S["current"]:
            fail("session has no model yet; start with primitive")
        bpy.ops.wm.open_mainfile(filepath=os.path.join(SDIR, S["current"]))
    LOADED[0] = True


def model():
    return bpy.data.objects[S["object"]]


# ----------------------------------------------------------------------- selections
def sel_layer(bm, domain, name, create=False):
    seq = getattr(bm, DOM[domain])
    lay = seq.layers.int.get("sel_" + name)
    if lay is None and create:
        lay = seq.layers.int.new("sel_" + name)
    return lay


def sel_domain(bm, name):
    for d in ("face", "edge", "vert"):
        if sel_layer(bm, d, name) is not None:
            return d
    fail(f"no selection named '{name}'")


def get_sel(bm, name, domain=None):
    """Elements of a named selection, converted to `domain` if given."""
    d = sel_domain(bm, name)
    lay = sel_layer(bm, d, name)
    els = [x for x in getattr(bm, DOM[d]) if x[lay]]
    if domain is None or domain == d:
        return els
    if domain == "vert":
        return list(dict.fromkeys(v for x in els for v in (x.verts if d != "vert" else [x])))
    if domain == "edge":
        if d == "face":
            return list(dict.fromkeys(e for f in els for e in f.edges))
        vs = set(els)
        return [e for e in bm.edges if e.verts[0] in vs and e.verts[1] in vs]
    if domain == "face":
        vs = set(v for x in els for v in (x.verts if d != "vert" else [x]))
        return [f for f in bm.faces if all(v in vs for v in f.verts)]


def set_sel(bm, name, domain, elements):
    """Store a named selection. Adding a BMesh data layer invalidates every element
    reference held in Python, so elements are converted to indices FIRST and callers
    must not reuse element references after calling this."""
    seq = getattr(bm, DOM[domain])
    seq.index_update()
    keep = {x.index for x in elements if x.is_valid}
    for d in ("face", "edge", "vert"):              # a name lives in one domain only
        lay = sel_layer(bm, d, name)
        if lay is not None and d != domain:
            getattr(bm, DOM[d]).layers.int.remove(lay)
    lay = sel_layer(bm, domain, name, create=True)
    seq = getattr(bm, DOM[domain])
    seq.index_update()
    for x in seq:
        x[lay] = 1 if x.index in keep else 0
    S["active"] = name
    return len(keep)


def set_sels(bm, domain, named):
    """Store several selections from element lists computed before any layer change."""
    seq = getattr(bm, DOM[domain])
    seq.index_update()
    ids = {k: [x.index for x in v if x.is_valid] for k, v in named.items()}
    out = {}
    for k, idx in ids.items():
        seq = getattr(bm, DOM[domain])
        seq.ensure_lookup_table()
        out[k] = set_sel(bm, k, domain, [seq[i] for i in idx])
    return out


def centre(x):
    return x.calc_center_median() if isinstance(x, bmesh.types.BMFace) else \
        ((x.verts[0].co + x.verts[1].co) / 2 if isinstance(x, bmesh.types.BMEdge) else x.co)


AXIS = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}


def edge_ring(seed):
    ring, seen = [seed], {seed}
    for f0 in seed.link_faces:
        e, f = seed, f0
        while f is not None and len(f.verts) == 4:
            opp = [x for x in f.edges if not (set(x.verts) & set(e.verts))]
            if not opp or opp[0] in seen:
                break
            e = opp[0]
            ring.append(e)
            seen.add(e)
            nf = [g for g in e.link_faces if g is not f]
            f = nf[0] if nf else None
    return ring


def edge_loop(seed):
    loop, seen = [seed], {seed}
    for v in seed.verts:
        e, cur = seed, v
        while len(cur.link_edges) == 4:
            fe = set(e.link_faces)
            nxt = [x for x in cur.link_edges if x is not e and not (set(x.link_faces) & fe)]
            if len(nxt) != 1 or nxt[0] in seen:
                break
            e = nxt[0]
            loop.append(e)
            seen.add(e)
            cur = e.other_vert(cur)
    return loop


def query(bm, domain, w):
    """Elements matching every condition in w (see mesh-select SKILL.md)."""
    els = list(getattr(bm, DOM[domain]))
    if domain == "face":
        bm.normal_update()
    if "normal" in w:
        n = Vector(w["normal"]).normalized()
        def nrm(x):  # faces/verts have normals; an edge uses the mean of its faces' normals
            if domain != "edge":
                return x.normal
            s = sum((f.normal for f in x.link_faces), Vector())
            return s.normalized() if s.length > 1e-9 else s
        if domain != "face":
            bm.normal_update()
        els = [x for x in els if nrm(x).dot(n) >= w.get("normal_min_dot", 0.9)]
    for k, cmp in (("min", lambda a, b: a >= b - 1e-6), ("max", lambda a, b: a <= b + 1e-6)):
        lim = w.get(k)
        if lim:
            els = [x for x in els if all(l is None or cmp(c, l) for c, l in zip(centre(x), lim))]
    if domain == "edge" and "sharp" in w:            # Select Sharp Edges: face angle >= degrees
        lim = math.radians(w["sharp"])
        els = [e for e in els if len(e.link_faces) == 2 and e.calc_face_angle(0.0) >= lim]
    if domain == "edge" and "along" in w:            # edges parallel to an axis
        ax = AXIS[w["along"]]
        els = [e for e in els if abs((e.verts[1].co - e.verts[0].co).normalized().dot(ax)) >= 0.7]
    for k, keep in (("in", True), ("not_in", False)):  # membership of other named selections
        if k in w:
            names = w[k] if isinstance(w[k], list) else [w[k]]
            member = set()
            for nm in names:
                member |= set(get_sel(bm, nm, domain))
            els = [x for x in els if (x in member) == keep]
    if domain == "face" and "material" in w:          # faces using a material, by name
        slots = [s.material.name if s.material else "" for s in bpy.data.objects[S["object"]].material_slots]
        els = [f for f in els if f.material_index < len(slots) and slots[f.material_index] == w["material"]]
    if "nearest" in w:
        p = Vector(w["nearest"])
        els = sorted(els, key=lambda x: (centre(x) - p).length)[: w.get("count", 1)]
    if domain == "edge" and w.get("ring") and els:
        els = edge_ring(els[0])
    if domain == "edge" and w.get("loop") and els:
        els = edge_loop(els[0])
    return els


# ----------------------------------------------------------------------- helpers
def verts_of(bm, name):
    return get_sel(bm, name, "vert")


def pivot_of(verts, spec):
    if isinstance(spec, list):
        return Vector(spec)
    if spec == "origin":
        return Vector((0, 0, 0))
    return sum((v.co for v in verts), Vector()) / max(1, len(verts))


def falloff(t, kind):
    t = min(max(t, 0.0), 1.0)
    return {"linear": 1 - t, "sphere": math.sqrt(max(0.0, 1 - t * t)),
            "smooth": 1 - (3 * t * t - 2 * t * t * t)}[kind]


def snap_seam(bm):
    """With a mirror modifier, keep seam vertices on the mirror plane."""
    if S.get("mirror"):
        i = "xyz".index(S["mirror"])
        for v in bm.verts:
            if abs(v.co[i]) < 1e-3:
                v.co[i] = 0.0


# ----------------------------------------------------------------------- operations
def make_tube(t, a):
    """A quad tube along `path` (like a bevelled curve turned into a mesh). With a mirror the ends
    stay open and must lie on the plane; without one they are closed with quads. Each
    cross-section is carried along the path without twisting."""
    path = [Vector(p) for p in a["path"]]
    r, sides = a.get("radius", 0.02), a.get("sides", 6)
    if len(path) < 2:
        fail("a tube needs at least two path points")
    tan = [(path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized() for k in range(len(path))]
    side = tan[0].orthogonal().normalized()
    rings = []
    for k, c in enumerate(path):
        if k:
            side = (side - tan[k] * side.dot(tan[k])).normalized()
        up = tan[k].cross(side)
        rings.append([t.verts.new(c + r * (side * math.cos(2 * math.pi * j / sides) + up * math.sin(2 * math.pi * j / sides)))
                      for j in range(sides)])
    for p, q in zip(rings, rings[1:]):
        for j in range(sides):
            t.faces.new([p[j], p[(j + 1) % sides], q[(j + 1) % sides], q[j]])
    if S.get("mirror"):
        i = "xyz".index(S["mirror"])
        for ring in (rings[0], rings[-1]):
            for v in ring:
                v.co[i] = 0.0
    elif sides % 2:
        fail("a tube without a mirror closes its ends with quads, which needs an even number of sides")
    else:
        for ring in (rings[0], rings[-1]):             # close the ends with a strip of quads
            p, q = 0, sides - 1
            while p + 1 < q - 1:
                t.faces.new([ring[p], ring[p + 1], ring[q - 1], ring[q]])
                p, q = p + 1, q - 1
    bmesh.ops.recalc_face_normals(t, faces=t.faces)


def make_shape(a):
    """Build the primitive `a` in its own BMesh, transformed and, with a mirror, cut at the
    plane if it crosses it. A separate BMesh means nothing here can touch the existing model."""
    t = bmesh.new()
    kind, size = a.get("type", "cube"), a.get("size", [1, 1, 1])
    if kind == "cube":
        bmesh.ops.create_cube(t, size=1.0)
    elif kind == "ball":                               # quad ball: a subdivided cube on a sphere, no poles
        bmesh.ops.create_cube(t, size=1.0)
        bmesh.ops.subdivide_edges(t, edges=t.edges[:], cuts=a.get("cuts", 3), use_grid_fill=True)
        for v in t.verts:
            v.co = v.co.normalized() * 0.5
    elif kind == "cylinder":
        bmesh.ops.create_cone(t, cap_ends=True, segments=a.get("segments", 16),
                              radius1=a.get("radius", 0.5), radius2=a.get("radius", 0.5), depth=a.get("depth", 1.0))
    elif kind == "sphere":
        bmesh.ops.create_uvsphere(t, u_segments=a.get("segments", 16), v_segments=a.get("rings", 8),
                                  radius=a.get("radius", 0.5))
    elif kind == "plane":
        bmesh.ops.create_grid(t, x_segments=1, y_segments=1, size=0.5)
    elif kind == "tube":
        make_tube(t, a)
    else:
        fail(f"unknown primitive {kind}")
    if kind in ("cube", "ball", "plane"):
        bmesh.ops.scale(t, vec=Vector(size), verts=t.verts)
    if a.get("rotate"):
        mat = Euler([math.radians(x) for x in a["rotate"]]).to_matrix()
        for v in t.verts:
            v.co = mat @ v.co
    bmesh.ops.translate(t, vec=Vector(a.get("location", [0, 0, 0])), verts=t.verts)
    if S.get("mirror"):
        i = "xyz".index(S["mirror"])
        if min(v.co[i] for v in t.verts) < -1e-6:
            no = Vector((0, 0, 0))
            no[i] = 1.0
            bmesh.ops.bisect_plane(t, geom=t.verts[:] + t.edges[:] + t.faces[:], dist=1e-5, plane_co=(0, 0, 0),
                                   plane_no=no, clear_inner=True)
            for v in t.verts:
                if abs(v.co[i]) < 1e-4:
                    v.co[i] = 0.0
    return t


def copy_shape(t, bm):
    """Append the BMesh t to bm; returns the new faces and frees t."""
    t.verts.index_update()
    vs = [bm.verts.new(v.co) for v in t.verts]
    faces = [bm.faces.new([vs[v.index] for v in f.verts]) for f in t.faces]
    t.free()
    return faces


def op_primitive(a):
    me = bpy.data.meshes.new(S["object"])
    bm = bmesh.new()
    copy_shape(make_shape(a), bm)
    set_sel(bm, "all", "face", bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(S["object"], me)
    bpy.context.scene.collection.objects.link(ob)
    return {"created": a.get("type", "cube")}


def op_add(bm, a):
    """Add a separate part to the mesh, like Shift+A in edit mode. With a mirror, a part that
    crosses the plane is cut there; a part on the +side simply gets mirrored."""
    faces = copy_shape(make_shape(a), bm)
    n = set_sel(bm, a.get("result", "added"), "face", faces)
    return {"created": a.get("type", "cube"), "faces": n}


def op_select(bm, a):
    domain = a.get("domain", "face")
    els = query(bm, domain, a.get("where", {}))
    mode = a.get("mode", "set")
    if mode != "set":
        cur = set(get_sel(bm, a["name"], domain)) if any(
            sel_layer(bm, d, a["name"]) for d in DOM) else set()
        els = {"add": cur | set(els), "sub": cur - set(els), "and": cur & set(els)}[mode]
    for _ in range(a.get("grow", 0)):
        vs = {v for x in els for v in (x.verts if domain != "vert" else [x])}
        els = list(getattr(bm, DOM[domain])) if domain == "vert" else \
            [x for x in getattr(bm, DOM[domain]) if any(v in vs for v in x.verts)]
        if domain == "vert":
            els = [v for v in els if v in vs or any(e.other_vert(v) in vs for e in v.link_edges)]
    n = set_sel(bm, a["name"], domain, els)
    if n == 0 and not a.get("allow_empty"):
        fail(f"selection '{a['name']}' is empty — check the conditions")
    return {"selected": n, "domain": domain}


def region_outline(faces):
    """The boundary of a face region as an ordered vertex list, and whether it is closed.
    Edges on the mirror seam are not part of the outline."""
    fs = set(faces)
    mi = "xyz".index(S["mirror"]) if S.get("mirror") else None
    edges = [e for e in dict.fromkeys(e for f in faces for e in f.edges)
             if sum(1 for g in e.link_faces if g in fs) == 1
             and not (mi is not None and all(abs(v.co[mi]) < 1e-4 for v in e.verts))]
    nbr = {}
    for e in edges:
        p, q = e.verts
        nbr.setdefault(p, []).append(q)
        nbr.setdefault(q, []).append(p)
    if not nbr or any(len(n) > 2 for n in nbr.values()):
        fail("the selection's boundary is not a single loop")
    ends = [v for v, n in nbr.items() if len(n) == 1]
    cur = ends[0] if ends else next(iter(nbr))
    chain, prev = [cur], None
    while True:
        nxt = [v for v in nbr[cur] if v is not prev]
        if not nxt or nxt[0] is chain[0]:
            break
        prev, cur = cur, nxt[0]
        chain.append(cur)
    if len(chain) != len(nbr):
        fail("the selection's boundary is not a single loop")
    return chain, not ends


def op_outline(bm, a):
    """Put the boundary of a face region on given points (like LoopTools Circle, but to any
    shape). Inner vertices relax inside it; seam vertices stay on the mirror plane."""
    faces = get_sel(bm, a["sel"], "face")
    pts = [Vector(p) for p in a["outline"]]
    chain, closed = region_outline(faces)
    if len(chain) != len(pts):
        fail(f"outline has {len(pts)} points but the boundary has {len(chain)} vertices")
    cc = sum((v.co for v in chain), Vector()) / len(chain)
    cp = sum(pts, Vector()) / len(pts)
    orders = [chain, chain[::-1]]
    if closed:
        orders = [o[k:] + o[:k] for o in orders for k in range(len(o))]
    best = min(orders, key=lambda o: sum(((v.co - cc) - (p - cp)).length_squared for v, p in zip(o, pts)))
    region = list(dict.fromkeys(v for f in faces for v in f.verts))
    fixed = set(best)
    inner = [v for v in region if v not in fixed]
    mi = "xyz".index(S["mirror"]) if S.get("mirror") else None
    seam = {v for v in inner if mi is not None and abs(v.co[mi]) < 1e-4}
    for v, p in zip(best, pts):
        v.co = p
    inside = set(region)                               # inner vertices settle between their neighbours,
    for _ in range(40):                                # so they stay inside the new outline
        for v in inner:
            nb = [e.other_vert(v) for e in v.link_edges if e.other_vert(v) in inside]
            v.co = sum((o.co for o in nb), Vector()) / max(1, len(nb))
            if v in seam:
                v.co[mi] = 0.0
    return {"moved": len(best) + len(inner), "closed": closed}


def op_transform(bm, a):
    if "outline" in a:
        return op_outline(bm, a)
    vs = verts_of(bm, a["sel"])
    p = pivot_of(vs, a.get("pivot", "median"))
    seam = set()
    if S.get("mirror"):                                # like Mirror "clipping"
        axis = "xyz".index(S["mirror"])
        seam = {v for v in bm.verts if abs(v.co[axis]) < 1e-4}
        if a.get("pivot", "median") == "median" and seam & set(vs):
            p[axis] = 0.0                              # the whole (mirrored) selection's median
    mat = Euler([math.radians(x) for x in a.get("rotate", [0, 0, 0])]).to_matrix()
    sc, tr = Vector(a.get("scale", [1, 1, 1])), Vector(a.get("translate", [0, 0, 0]))

    def T(co):
        d = co - p
        return p + mat @ Vector((d.x * sc.x, d.y * sc.y, d.z * sc.z)) + tr
    targets = {v: T(v.co) for v in vs}
    radius = a.get("proportional")
    if radius:                                         # proportional editing
        kd = KDTree(len(vs))
        for i, v in enumerate(vs):
            kd.insert(v.co, i)
        kd.balance()
        kind = a.get("falloff", "smooth")
        for v in bm.verts:
            if v in targets:
                continue
            co, i, dist = kd.find(v.co)
            if dist < radius:
                src = vs[i]
                w = falloff(dist / radius, kind)
                targets[v] = v.co + w * (T(v.co) - v.co)
    for v, co in targets.items():
        if v in seam:
            co[axis] = 0.0                             # seam vertices slide on the mirror plane
        v.co = co
    return {"moved": len(targets)}


def op_extrude(bm, a):
    faces = get_sel(bm, a["sel"], "face")
    if Vector(a.get("vector", [0, 0, 0])).length < 1e-9 and abs(a.get("distance", 0.1)) < 1e-9:
        warn("zero_extrude", "extrude distance 0: duplicate faces on top of the old ones (undo, or cleanup)")
    if a.get("individual"):
        fs = set(faces)
        touching = sum(1 for e in {e for f in faces for e in f.edges} if sum(1 for g in e.link_faces if g in fs) == 2)
        if touching:
            warn("individual_adjacent", f"{touching} edges are shared by faces extruded individually — their walls "
                                        "touch back to back (inset individual first, or extrude as a region)")
        ret = bmesh.ops.extrude_discrete_faces(bm, faces=faces)
        top = ret["faces"]
        bm.normal_update()
        for f in top:
            bmesh.ops.translate(bm, vec=f.normal * a.get("distance", 0.1), verts=f.verts)
    else:
        n = sum((f.normal for f in faces), Vector()).normalized()
        ret = bmesh.ops.extrude_face_region(bm, geom=faces)
        nv = {g for g in ret["geom"] if isinstance(g, bmesh.types.BMVert)}
        top = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
        if a.get("along") == "normals":               # shrink/fatten: each vertex along its own normal
            topf = [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]
            src = {f: f.normal.copy() for f in faces}
            for v in nv:
                ns = [src[f] for f in faces if any((w.co - v.co).length < 1e-7 for w in f.verts)]
                vn = sum(ns, Vector()).normalized() if ns else n
                mi = "xyz".index(S["mirror"]) if S.get("mirror") else None
                if mi is not None and abs(v.co[mi]) < 1e-4:
                    vn[mi] = 0.0                       # clipping: a seam vertex slides on the plane
                v.co += vn * a.get("distance", 0.1)
            del topf
        else:
            vec = Vector(a["vector"]) if "vector" in a else n * a.get("distance", 0.1)
            bmesh.ops.translate(bm, vec=vec, verts=list(nv))
        bmesh.ops.delete(bm, geom=[f for f in faces if f.is_valid], context="FACES_ONLY")
        if S.get("mirror"):                           # like Mirror "clipping": no wall on the seam
            i = "xyz".index(S["mirror"])
            wall = [f for f in bm.faces if all(abs(v.co[i]) < 1e-4 for v in f.verts)]
            bmesh.ops.delete(bm, geom=wall, context="FACES_ONLY")
        bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context="EDGES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context="VERTS")
    bm.normal_update()
    res = a.get("result", a["sel"])
    top = [f for f in top if f.is_valid]
    sides = list({g for f in top for v in f.verts for g in v.link_faces} - set(top))
    # New walls copy their neighbour's custom data, so they would inherit its selections:
    # X_sides then spreads along every later extrusion. A wall belongs only to <result>_sides.
    for name, lay in bm.faces.layers.int.items():
        if name.startswith("sel_"):
            for f in sides:
                f[lay] = 0
    n = set_sels(bm, "face", {res + "_sides": sides, res: top})   # last one becomes active
    return {"top_faces": n[res], "side_faces": n[res + "_sides"]}


def op_inset(bm, a):
    faces = get_sel(bm, a["sel"], "face")
    kw = dict(thickness=a.get("thickness", 0.05), depth=a.get("depth", 0.0), use_even_offset=True)
    before = {f: (f.normal.copy(), f.calc_area()) for f in faces}
    if a.get("individual"):
        ret = bmesh.ops.inset_individual(bm, faces=faces, **kw)
    else:
        ret = bmesh.ops.inset_region(bm, faces=faces, **kw)
    bm.normal_update()
    bad = sum(1 for f, (n0, a0) in before.items() if f.is_valid and (f.normal.dot(n0) < 0 or f.calc_area() < 0.02 * a0))
    if bad:
        warn("inset_thick", f"{bad} inner faces collapsed or flipped — thickness too large for the face")
    res = a.get("result", a["sel"])
    n = set_sels(bm, "face", {res + "_rim": list(ret["faces"]), res: [f for f in faces if f.is_valid]})
    return {"inner": n[res], "rim": n[res + "_rim"]}


def crossing_rings(bm, i, val, within):
    """Edge rings made of edges running along axis i that cross the plane co[i] = val
    (optionally only among edges matching `within`, a mesh-select `where`)."""
    eps = 1e-6
    cand = query(bm, "edge", within) if within else list(bm.edges)
    cand = [e for e in cand if e.calc_length() > 1e-9
            and abs((e.verts[1].co - e.verts[0].co).normalized()[i]) >= 0.7
            and min(v.co[i] for v in e.verts) < val - eps and max(v.co[i] for v in e.verts) > val + eps]
    rings, seen = [], set()
    for e in cand:
        if e not in seen:
            r = edge_ring(e)
            seen.update(r)
            rings.append(r)
    return rings


def op_loopcut(bm, a):
    """Loop cut: pick the edge ring(s), split each ring edge at the same place, connect.
    Rings come from `where` (nearest edge, grown), `ring` (named edges) or, with only
    `at`, every ring whose edges cross the plane axis = value (one or more values)."""
    at = a.get("at")
    loops, tot = [], {"new_verts": 0, "ring_edges": 0, "rings": 0}
    if "ring" in a or "where" in a:
        ring = get_sel(bm, a["ring"], "edge") if "ring" in a else query(bm, "edge", dict(a["where"], ring=True))
        jobs = [(ring, at["value"] if at else None)]
        if at and isinstance(at["value"], list):
            fail("a list of `at` values needs ring discovery by plane: leave out `where`/`ring`")
    elif at:
        jobs = None
    else:
        fail("loopcut needs `where`, `ring` or `at`")
    if jobs is not None:
        clamped = cut_ring(bm, jobs[0][0], a, jobs[0][1], loops, tot)
    else:
        i = "xyz".index(at["axis"])
        clamped = 0
        for val in (at["value"] if isinstance(at["value"], list) else [at["value"]]):
            rings = crossing_rings(bm, i, val, a.get("within"))
            if not rings:
                fail(f"no edges along {at['axis']} cross {at['axis']} = {val}" + (" inside `within`" if a.get("within") else ""))
            for r in rings:
                clamped += cut_ring(bm, r, a, val, loops, tot)
    if clamped:
        warn("loopcut_span", f"{clamped} ring edges do not span {at['axis']} = {at['value']} (cut clamped near an end) "
                             "— wrong ring or value?")
    set_sel(bm, a.get("result", "loop"), "edge", loops)
    return {"new_verts": tot["new_verts"], "loop_edges": len(loops), "ring_edges": tot["ring_edges"], "rings": tot["rings"]}


def low_end(e):
    """The end of an edge with the smaller coordinate on the edge's main axis."""
    p, q = e.verts
    d = q.co - p.co
    i = max(range(3), key=lambda k: abs(d[k]))
    return p if d[i] > 0 else q


def ring_starts(ring, faces):
    """For every ring edge, the end a fraction is measured from: the seed's low end, carried
    across each ring face, so the loop stays on one side all the way round. (An edge's own
    vertex order is arbitrary: using it makes the loop zigzag.)"""
    links = {}
    for f, e1, e2 in faces:
        links.setdefault(e1, []).append((f, e2))
        links.setdefault(e2, []).append((f, e1))
    start = {}
    for seed in ring:                                  # a ring can come in separate pieces
        if seed in start:
            continue
        start[seed] = low_end(seed)
        todo = [seed]
        while todo:
            e = todo.pop()
            for f, o in links.get(e, ()):
                if o not in start:
                    side = next(x for x in f.edges if x is not e and x is not o and start[e] in x.verts)
                    start[o] = side.other_vert(start[e])
                    todo.append(o)
    return start


def cut_ring(bm, ring, a, at_value, loops, tot):
    """Cut one edge ring; appends new loop edges to `loops`; returns how many ring edges
    had to be clamped because the `at` plane does not cross them."""
    ringset = set(ring)
    cuts = a.get("cuts", 1) if at_value is None else 1
    at = a.get("at")
    clamped = 0
    faces = []
    # dict.fromkeys, not a set: BMesh elements hash by address, so a set's order changes
    # from run to run and with it the element order of everything built afterwards
    for f in dict.fromkeys(f for e in ring for f in e.link_faces):
        es = [e for e in f.edges if e in ringset]
        if len(es) == 2:
            faces.append((f, es[0], es[1]))
    newv = {}
    starts = ring_starts(ring, faces)
    for e in ring:
        A = starts[e]
        B = e.other_vert(A)
        if at_value is not None:                      # exact placement on an axis
            i = "xyz".index(at["axis"])
            span = B.co[i] - A.co[i]
            raw = (at_value - A.co[i]) / span if abs(span) > 1e-9 else -1.0
            if not 0.02 <= raw <= 0.98:
                clamped += 1
            fr = [min(max(raw, 0.02), 0.98)]
        elif cuts == 1:
            fr = [a.get("fraction", 0.5)]
        else:
            fr = [(k + 1) / (cuts + 1) for k in range(cuts)]
        cur, base, made = e, 1.0, []
        for f_ in sorted(fr, reverse=True):           # split from the far end towards A
            _, nv = bmesh.utils.edge_split(cur, A, f_ / base)
            made.append(nv)
            cur = next(x for x in nv.link_edges if x.other_vert(nv) is A)
            base = f_
        newv[e] = (A, list(reversed(made)))           # ordered from A
    for f, e1, e2 in faces:
        A1, L1 = newv[e1]
        A2, L2 = newv[e2]
        adjacent = any(x.other_vert(A1) is A2 for x in A1.link_edges)
        for v1, v2 in zip(L1, L2 if adjacent else list(reversed(L2))):
            loops += bmesh.ops.connect_verts(bm, verts=[v1, v2])["edges"]
    tot["new_verts"] += sum(len(v[1]) for v in newv.values())
    tot["ring_edges"] += len(ring)
    tot["rings"] += 1
    return clamped


def op_bevel(bm, a):
    edges = get_sel(bm, a["sel"], "edge")
    vs = list(dict.fromkeys(v for e in edges for v in e.verts))
    if S.get("mirror"):
        i = "xyz".index(S["mirror"])
        on_seam = [e for e in edges if all(abs(v.co[i]) < 1e-4 for v in e.verts)]
        if on_seam:
            warn("bevel_seam", f"{len(on_seam)} selected edges lie on the mirror seam — skipped (a bevel there "
                               "would cross the mirror plane)")
            edges = [e for e in edges if e not in on_seam]
            vs = list(dict.fromkeys(v for e in edges for v in e.verts))
    ret = bmesh.ops.bevel(bm, geom=edges + vs, offset=a.get("offset", 0.02), offset_type="OFFSET",
                          segments=a.get("segments", 2), profile=a.get("profile", 0.5), affect="EDGES",
                          clamp_overlap=True)
    if not ret["faces"]:
        warn("bevel_none", "no bevel faces were made (no usable edges, or the offset clamped to 0)")
    set_sel(bm, a.get("result", "bevel"), "face", ret["faces"])
    return {"bevel_faces": len(ret["faces"])}


def op_cleanup(bm, a):
    out = {}
    if a.get("merge", 1e-4):
        n0 = len(bm.verts)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=a.get("merge", 1e-4))
        out["merged"] = n0 - len(bm.verts)
        if out["merged"]:
            warn("merged", f"merged {out['merged']} coincident vertices — an earlier step left duplicates "
                           "(look back through the snapshots)")
    if a.get("dissolve_degenerate", True):
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    if a.get("delete_loose", True):
        loose = [v for v in bm.verts if not v.link_edges]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        out["loose_removed"] = len(loose)
    if a.get("recalc_normals", True):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return out


def op_material(bm, a, ob):
    m = bpy.data.materials.get(a["name"])
    if m is None:
        m = bpy.data.materials.new(a["name"])
        if m.node_tree is None:
            m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")       # (re)apply values: lets a later step retune it
    if "color" in a or b.inputs["Base Color"].default_value[0] == 0.8:
        b.inputs["Base Color"].default_value = (*a.get("color", [0.8, 0.8, 0.8]), 1)
        m.diffuse_color = (*a.get("color", [0.8, 0.8, 0.8]), 1)
    if "metallic" in a:
        b.inputs["Metallic"].default_value = a["metallic"]
    if "roughness" in a:
        b.inputs["Roughness"].default_value = a["roughness"]
    if "alpha" in a:                                   # see-through, and it survives glTF export
        b.inputs["Alpha"].default_value = a["alpha"]
        m.surface_render_method = "BLENDED"
    if "emission" in a:                                # strength; the colour is the base colour
        b.inputs["Emission Color"].default_value = b.inputs["Base Color"].default_value
        b.inputs["Emission Strength"].default_value = a["emission"]
    new_slot = m.name not in [s.material.name for s in ob.material_slots if s.material]
    if new_slot:
        ob.data.materials.append(m)
    idx = [s.material.name if s.material else "" for s in ob.material_slots].index(m.name)
    sel = a.get("sel")
    if sel == "*" or (sel is None and new_slot):   # first assignment without sel = the base material
        faces = list(bm.faces)
    elif sel is None:                               # existing material, no sel: retune values only
        return {"faces": 0, "slot": idx, "retuned": True}
    else:
        faces = get_sel(bm, sel, "face")
    for f in faces:
        f.material_index = idx
    return {"faces": len(faces), "slot": idx}


def op_mirror(ob, a):
    axis = a.get("axis", "x")
    i = "xyz".index(axis)
    if a.get("mode", "setup") == "setup":
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        no = Vector((0, 0, 0))
        no[i] = 1.0
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=(0, 0, 0), plane_no=no, clear_inner=True)
        snap = [v for v in bm.verts if abs(v.co[i]) < 1e-4]
        for v in snap:
            v.co[i] = 0.0
        bm.to_mesh(ob.data)
        bm.free()
        m = ob.modifiers.new("Mirror", "MIRROR")
        m.use_axis = [k == i for k in range(3)]
        m.use_clip, m.use_mirror_merge, m.merge_threshold = True, True, 1e-3
        S["mirror"] = axis
        return {"kept": "+" + axis, "seam_verts": len(snap)}
    m = ob.modifiers.get("Mirror")
    if m is None:
        fail("no Mirror modifier to apply")
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)
    S["mirror"] = None
    return {"applied": True}


def op_subsurf(ob, a):
    m = ob.modifiers.get("Subsurf") or ob.modifiers.new("Subsurf", "SUBSURF")
    m.levels = m.render_levels = a.get("levels", 2)
    out = {"levels": m.levels}
    if "crease" in a:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        lay = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
        edges = get_sel(bm, a["crease"]["sel"], "edge")
        for e in edges:
            e[lay] = a["crease"].get("value", 1.0)
        bm.to_mesh(ob.data)
        bm.free()
        out["creased_edges"] = len(edges)
    if a.get("shade_smooth", True):
        for p in ob.data.polygons:
            p.use_smooth = True
    if a.get("apply"):
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=m.name)
        out["applied"] = True
    return out


# ----------------------------------------------------------------------- dispatch
def canonical_order(bm):
    """Sort elements by position. Blender's extrude emits edges and faces in an order that
    changes from run to run; sorted, a replay gives the same element order every time, so
    ties (`nearest`) resolve the same way and runs can be compared exactly."""
    for seq in (bm.verts, bm.edges, bm.faces):
        order = sorted(seq, key=lambda x: tuple(round(c, 5) for c in centre(x)))
        rank = {x: i for i, x in enumerate(order)}     # BMesh sort keys must be numbers
        seq.sort(key=lambda x: rank[x])
        seq.index_update()


def apply_op(op, args):
    """Run the operation on the model in memory; returns (object, result info)."""
    if op == "primitive" and not ADDING[0]:
        info = op_primitive(args)
        ob = model()
    elif op in ("mirror", "subsurf"):
        ob = model()
        info = {"mirror": op_mirror, "subsurf": op_subsurf}[op](ob, args)
    elif op == "note":
        ob, info = model(), {}
    else:
        ob = model()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        fn = {"select": op_select, "transform": op_transform, "extrude": op_extrude, "inset": op_inset,
              "loopcut": op_loopcut, "bevel": op_bevel, "cleanup": op_cleanup, "primitive": op_add}.get(op)
        if op == "material":
            info = op_material(bm, args, ob)
        elif fn is None:
            fail(f"unknown op {op}")
        else:
            info = fn(bm, args)
        if op not in ("select",):
            snap_seam(bm)
        if op in ("extrude", "inset", "loopcut", "bevel", "cleanup", "primitive"):
            canonical_order(bm)
        bm.normal_update()
        bm.to_mesh(ob.data)
        bm.free()
    ob.data.update()
    return ob, info


def tier_budget():
    """Triangle budget of the session tier, from 3d-asset-review's tiers.json when present."""
    tier = S.get("tier")
    if not tier:
        return None
    try:
        tiers = read_json(os.path.join(HERE, "..", "..", "3d-asset-review", "assets", "tiers.json"))
        return tiers.get(tier, {}).get("lod0_tris_max")
    except (OSError, ValueError):
        return {"mobile": 10000, "pc": 50000}.get(tier)


def check_step(op, args, bm, stats):
    """Automatic checks: the mechanical part of each technique skill's "Check" section."""
    mi = "xyz".index(S["mirror"]) if S.get("mirror") else None
    prev = S["steps"][-1]["stats"] if S["steps"] and op != "primitive" else None
    if stats["non_manifold"]:
        warn("non_manifold", f"{stats['non_manifold']} non-manifold edges (holes, internal or doubled faces)")
    if prev:
        mult = 2 if (op == "mirror" and args.get("mode") == "apply") else 1   # apply doubles the cage
        for k, what in (("tris", "triangles"), ("ngons", "n-gons")):
            if stats[k] > prev[k] * mult:
                warn(k, f"{stats[k] - prev[k] * mult} new {what} in the cage — subdivision pinches there")
    if mi is not None:
        over = sum(1 for v in bm.verts if v.co[mi] < -1e-4)
        if over:
            warn("mirror_cross", f"{over} vertices crossed the mirror plane ({S['mirror']} < 0) — they overlap the mirrored copy")
    short = sum(1 for e in bm.edges if e.calc_length() < 1e-6)
    flat = sum(1 for f in bm.faces if f.calc_area() < 1e-10)
    if short or flat:
        warn("degenerate", f"{short} zero-length edges, {flat} zero-area faces — run cleanup")
    flip = sum(1 for e in bm.edges if len(e.link_faces) == 2 and not e.is_contiguous)
    if flip:
        warn("winding", f"{flip} edges between faces of opposite winding (flipped normals) — cleanup recalcs normals")
    budget = tier_budget()
    if budget and stats["tris_eval"] > budget:
        warn("budget", f"{stats['tris_eval']} evaluated triangles > {S['tier']} budget {budget}")


def check_expect(expect, info, stats):
    """A failed expectation rejects the step: nothing is saved, the session is unchanged."""
    have = dict(info if isinstance(info, dict) else {}, **stats, warnings=len(CHECKS))
    bad = []
    for k, want in expect.items():
        got = have.get(k)
        if isinstance(want, list):
            ok = got is not None and (want[0] is None or got >= want[0]) and (want[1] is None or got <= want[1])
        else:
            ok = got == want
        if not ok:
            bad.append(f"{k}: expected {want}, got {got}")
    if bad:
        for c in CHECKS:
            print(f"[meshop]   check {c['kind']}: {c['msg']}")
        fail("expectation not met — step rejected: " + "; ".join(bad))


# ----------------------------------------------------------------------- snapshots
def pillow_python():
    """A system Python that has Pillow (Blender's own Python does not). Cached in the session."""
    cands = [S.get("py")] if S.get("py") else []
    if os.environ.get("MESHOP_PYTHON"):
        cands.append(os.environ["MESHOP_PYTHON"])
    cands += ["py -3", "python3", "python"]
    cands += sorted(glob.glob(r"C:\Program Files\Python3*\python.exe"), reverse=True)
    for c in cands:
        cmd = c.split(" ") if c.startswith("py ") else [c]
        try:
            if subprocess.run(cmd + ["-I", "-c", "import PIL"], capture_output=True, timeout=30).returncode == 0:
                S["py"] = c
                save_session()
                return cmd
        except (OSError, subprocess.TimeoutExpired):
            continue
    return None


def reap(job):
    n, p = job
    try:
        _, err = p.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        p.kill()
        print(f"[meshop] snapshot {n:03d} timed out", flush=True)
        return
    if p.returncode:
        print(f"[meshop] snapshot {n:03d} failed: {err.strip().splitlines()[-1] if err.strip() else p.returncode}", flush=True)


def finish_snapshots():
    while SNAP_JOBS:
        reap(SNAP_JOBS.pop(0))


def start_snapshot(n, jpath, png):
    if not PY:
        PY.append(pillow_python())
        if PY[0] is None:
            print("[meshop] snapshot skipped: no system Python with Pillow found (set MESHOP_PYTHON)", flush=True)
    if PY[0] is None:
        return
    while len(SNAP_JOBS) >= SNAP_MAX:
        reap(SNAP_JOBS.pop(0))
    SNAP_JOBS.append((n, subprocess.Popen(PY[0] + ["-I", os.path.join(HERE, "snapshot.py"), jpath, png],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                                          encoding="utf-8", errors="replace")))


# ----------------------------------------------------------------------- one step
def run_step(op, args, label=""):
    """Do one step on the session; returns its log entry (None for undo)."""
    args = dict(args)
    label = label or args.pop("label", "")
    expect = args.pop("expect", None)   # {"faces": 287, "non_manifold": 0, "tris_eval": [null, 20000], ...}
    if "tier" in args:                  # mobile / pc / film: enables the triangle-budget check
        S["tier"] = args["tier"]
    CHECKS.clear()
    if op == "undo":
        do_undo()
        return None
    ADDING[0] = bool(args.get("add"))
    open_state(op)
    ob, info = apply_op(op, args)

    n = len(S["steps"]) + 1
    name = f"{n:03d}_{op}" + (f"_{label}" if label else "")
    rel = f"steps/{name}.blend"
    me = ob.data
    sizes = [len(p.vertices) for p in me.polygons]
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    ev = ob.evaluated_get(dg)
    em = ev.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    mi = "xyz".index(S["mirror"]) if S.get("mirror") else None
    nonman = sum(1 for e in bm.edges if not e.is_manifold and not (mi is not None and e.is_boundary
                                                                   and all(abs(v.co[mi]) < 1e-4 for v in e.verts)))
    stats = {"verts": len(me.vertices), "faces": len(me.polygons), "quads": sizes.count(4), "tris": sizes.count(3),
             "ngons": sum(1 for s in sizes if s > 4), "eval_faces": len(em.polygons), "non_manifold": nonman,
             "tris_eval": sum(len(p.vertices) - 2 for p in em.polygons)}
    check_step(op, args, bm, stats)
    if expect:
        check_expect(expect, info, stats)

    bpy.context.preferences.filepaths.save_version = 0      # no .blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SDIR, rel))
    active = S.get("active")
    jpath = os.path.join(SDIR, "snaps", f"{n:03d}.json")
    if not NOSNAP:
        lay_info = {}
        if active:
            for d in ("face", "edge", "vert"):
                lay = sel_layer(bm, d, active)
                if lay is not None:
                    lay_info = {"domain": d, "flags": [x[lay] for x in getattr(bm, DOM[d])]}
        mw = ob.matrix_world
        snap = {"step": n, "op": op, "label": label, "stats": stats, "active": active, "selection": lay_info,
                "base": {"v": [list(mw @ v.co) for v in me.vertices], "e": [list(e.vertices) for e in me.edges],
                         "f": [list(p.vertices) for p in me.polygons]},
                "eval": {"v": [list(mw @ v.co) for v in em.vertices], "f": [list(p.vertices) for p in em.polygons]}}
        with open(jpath, "w") as fh:
            json.dump(snap, fh)
    bm.free()
    ev.to_mesh_clear()
    entry = {"n": n, "op": op, "label": label, "args": args, "info": info, "stats": stats, "file": rel, "active": active,
             "state": session_state.state_of(S), "checks": list(CHECKS)}
    S["steps"].append(entry)
    S["current"] = rel
    save_session()
    with open(os.path.join(SDIR, "log.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry) + "\n")
    if not NOSNAP:
        start_snapshot(n, jpath, os.path.join(SDIR, "snaps", f"{n:03d}.png"))
    print(f"[meshop] {name}: {json.dumps(info)} | v {stats['verts']} f {stats['faces']} "
          f"(q {stats['quads']} t {stats['tris']} n {stats['ngons']}) eval tris {stats['tris_eval']} "
          f"non-manifold {nonman} | active sel: {active}", flush=True)
    for c in CHECKS:
        print(f"[meshop]   check {c['kind']}: {c['msg']}", flush=True)
    print("[meshop]   checks: " + (f"{len(CHECKS)} warning(s)" if CHECKS else "ok"), flush=True)
    return entry


# ----------------------------------------------------------------------- entry points
def read_steps(path):
    txt = read_file(path, encoding="utf-8")
    if txt.lstrip().startswith("["):
        return json.loads(txt)
    return [json.loads(x) for x in txt.splitlines() if x.strip() and not x.lstrip().startswith(("#", "//"))]


def run_file(path, strict, start):
    """Run a steps file in this process; stop at the first error (or warning with strict)."""
    steps = read_steps(path)
    done = warned = 0
    for k, s in enumerate(steps, 1):
        if k < start:
            continue
        where = f"step {k}/{len(steps)} ({s['op']} {s.get('label', '')})".replace(" )", ")")
        args = dict(s.get("args", {}))
        if s.get("expect"):
            args["expect"] = s["expect"]
        try:
            entry = run_step(s["op"], args, s.get("label", ""))
        except StepError as e:
            print(f"[meshop] ERROR {s['op']}: {e}", flush=True)
            print(f"[meshop] stopped at {where}; fix it and resume with --from {k}", flush=True)
            return False
        except Exception:  # noqa: BLE001 - report which step broke; the session on disk is intact
            traceback.print_exc()
            print(f"[meshop] stopped at {where}; fix it and resume with --from {k}", flush=True)
            return False
        done += 1
        nw = len(entry["checks"]) if entry else 0
        warned += nw
        if strict and nw:
            print(f"[meshop] --strict: stopped after {where} with {nw} check warning(s); "
                  f"resume with --from {k + 1}", flush=True)
            return False
    print(f"[meshop] ran {done} steps, {warned} check warning(s)", flush=True)
    return True


def main():
    if argv[1] == "--run":
        rest = argv[2:]
        ok = run_file(rest[0], "--strict" in rest, int(rest[rest.index("--from") + 1]) if "--from" in rest else 1)
    else:
        ok = True
        try:
            run_step(argv[1], json.loads(argv[2]) if len(argv) > 2 and argv[2] else {}, argv[3] if len(argv) > 3 else "")
        except StepError as e:
            print(f"[meshop] ERROR {argv[1]}: {e}", flush=True)
            ok = False
    finish_snapshots()
    sys.exit(0 if ok else 1)


main()
