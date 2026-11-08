"""3D asset inspector: quantitative checks of the rubric + review renders.

  blender -b MODEL.blend --python inspect_model.py -- OUT_DIR [--tier pc] [--tiers PATH] [--no-render]

Writes OUT_DIR/report.json and (unless --no-render) front/side/back/top
Workbench clay renders plus a base-cage wireframe (Cycles). Environment
objects (named ENV_*, or any large flat sheet) are left out of everything.

Checks, by rubric discipline (see references/rubric.md):
  modeling  mesh hygiene, topology mix, triangle budget (base cage vs render),
            ground contact, rest-pose symmetry
  texturing Principled BSDF values: metalness 0/1, roughness range, albedo range
  uv/bake   per mesh with UVs: texel-density spread, UV utilisation, island overlap
  rigging   unweighted vertices, max bone influences per vertex
"""
import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("out_dir")
ap.add_argument("--tier", default="pc")
ap.add_argument("--tiers", default=os.path.join(HERE, "..", "assets", "tiers.json"))
ap.add_argument("--no-render", action="store_true")
ap.add_argument("--asymmetric", action="store_true", help="the design is not symmetric: skip the rest-pose symmetry check")
args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
out_dir = os.path.abspath(args.out_dir)
os.makedirs(out_dir, exist_ok=True)
TIERS = read_json(args.tiers, encoding="utf-8")
TIER, CHK = TIERS[args.tier], TIERS["checks"]
scene = bpy.context.scene


def is_env(o):
    """ENV_* by name, or a large flat sheet (ground/backdrop) by shape."""
    if o.name.startswith("ENV_"):
        return True
    if o.type != "MESH":
        return False
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    ext = sorted(max(p[i] for p in pts) - min(p[i] for p in pts) for i in range(3))
    return ext[0] < 1e-3 and ext[1] > 2.0


env_found = []
for o in scene.objects:
    if is_env(o):
        o.hide_render = True
        env_found.append(o.name)
visible = [o for o in scene.objects
           if not o.hide_render and o.type in {"MESH", "CURVE", "META", "SURFACE"}]
meshes = [o for o in visible if o.type == "MESH"]
report = {"file": bpy.data.filepath, "tier": args.tier, "objects": len(visible),
          "meshes": {}, "environment_excluded": env_found}


def eval_tris(objs, subsurf):
    """Triangle count of the evaluated geometry, with subdivision on or off."""
    saved = []
    for ob in objs:
        for m in getattr(ob, "modifiers", []):
            if m.type == "SUBSURF":
                saved.append((m, m.show_viewport))
                m.show_viewport = subsurf and m.show_viewport
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    total = 0
    for ob in objs:
        ev = ob.evaluated_get(dg)
        try:
            me = ev.to_mesh()
        except RuntimeError:
            continue
        if me:
            total += sum(len(p.vertices) - 2 for p in me.polygons)
        ev.to_mesh_clear()
    for m, v in saved:
        m.show_viewport = v
    return total


dg = bpy.context.evaluated_depsgraph_get()
lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
for ob in visible:
    for c in ob.evaluated_get(dg).bound_box:
        w = ob.matrix_world @ Vector(c)
        lo, hi = Vector(map(min, lo, w)), Vector(map(max, hi, w))

# ---------------------------------------------------------------- per-mesh: hygiene, rigging
for ob in meshes:
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(ob.matrix_world)
    bm.verts.ensure_lookup_table()
    sizes = [len(f.verts) for f in bm.faces]
    parent = list(range(len(bm.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in bm.edges:
        a, b = find(e.verts[0].index), find(e.verts[1].index)
        if a != b:
            parent[a] = b
    kd = KDTree(len(bm.verts))
    for v in bm.verts:
        kd.insert(v.co, v.index)
    kd.balance()
    info = {
        "verts": len(bm.verts), "faces": len(bm.faces),
        "tris": sizes.count(3), "quads": sizes.count(4), "ngons": sum(1 for s in sizes if s > 4),
        "non_manifold_edges": sum(1 for e in bm.edges if not e.is_manifold),
        "non_manifold_verts": sum(1 for v in bm.verts if not v.is_manifold),
        "boundary_edges": sum(1 for e in bm.edges if e.is_boundary),
        "duplicate_verts": sum(1 for v in bm.verts if len(kd.find_range(v.co, 1e-5)) > 1),
        "zero_area_faces": sum(1 for f in bm.faces if f.calc_area() < 1e-10),
        "islands": len({find(i) for i in range(len(bm.verts))}),
        "signed_volume": round(bm.calc_volume(signed=True), 4),
    }
    bm.free()
    ev.to_mesh_clear()
    rest = ob.data.vertices
    if 50 < len(rest) and abs(sum(v.co.x for v in rest) / len(rest)) < 0.02:
        kd = KDTree(len(rest))
        for v in rest:
            kd.insert(v.co, v.index)
        kd.balance()
        errs = [kd.find(Vector((-v.co.x, v.co.y, v.co.z)))[2] for v in rest]
        info["symmetry_max"] = round(max(errs), 4)
    arm = next((m for m in ob.modifiers if m.type == "ARMATURE" and m.object), None)
    if arm:
        bones = {b.name for b in arm.object.data.bones}
        idx = {g.index for g in ob.vertex_groups if g.name in bones}
        infl = [sum(1 for g in v.groups if g.group in idx and g.weight > 1e-3) for v in rest]
        info["bones"] = len(bones)
        info["unweighted_verts"] = infl.count(0)
        info["max_bone_influences"] = max(infl) if infl else 0
    report["meshes"][ob.name] = info

# ---------------------------------------------------------------- budget
report["budget"] = {"tris_base_cage": eval_tris(visible, subsurf=False),
                    "tris_render": eval_tris(visible, subsurf=True),
                    "lod0_tris_max": TIER["lod0_tris_max"]}

# ---------------------------------------------------------------- materials (PBR values)
def srgb(c):
    return 1.055 * c ** (1 / 2.4) - 0.055 if c > 0.0031308 else 12.92 * c


mats = {s.material for o in visible for s in getattr(o, "material_slots", []) if s.material}
report["materials"] = {}
for mat in mats:
    nt = mat.node_tree
    for node in (nt.nodes if nt else []):
        if node.type != "BSDF_PRINCIPLED":
            continue
        inp = node.inputs
        unlinked = lambda n: not inp[n].is_linked  # noqa: E731
        em = inp["Emission Strength"].default_value if unlinked("Emission Strength") else 0
        if em > 0 and unlinked("Base Color") and max(inp["Base Color"].default_value[:3]) < 1e-3:
            continue                                   # pure emitter, not a surface
        m = {}
        tw = inp["Transmission Weight"]
        if not tw.is_linked and tw.default_value > 0.5:
            m["transmissive"] = True               # glass: low roughness / white base are normal
        if unlinked("Metallic"):
            m["metallic"] = round(inp["Metallic"].default_value, 3)
        if unlinked("Roughness"):
            m["roughness"] = round(inp["Roughness"].default_value, 3)
        if unlinked("Base Color"):
            rgb = inp["Base Color"].default_value[:3]
            m["albedo_srgb_lum"] = round(0.2126 * srgb(rgb[0]) + 0.7152 * srgb(rgb[1]) + 0.0722 * srgb(rgb[2]), 3)
            m["albedo_srgb_max"] = round(max(srgb(c) for c in rgb), 3)
        report["materials"][mat.name] = m

# ---------------------------------------------------------------- UV metrics
sys.path.insert(0, os.path.join(HERE, "..", "..", "mesh-uv", "scripts"))
from uv_raster import coverage  # noqa: E402  the UV stage's own raster, so both read a layout alike


def uses_image_texture(ob):
    for slot in ob.material_slots:
        nt = slot.material.node_tree if slot.material else None
        if nt and any(n.type == "TEX_IMAGE" for n in nt.nodes):
            return True
    return False


# Blender primitives ship with default UVs, so UV quality only matters where a
# material actually samples an image texture.
report["uv"] = {}
textured = [ob for ob in meshes if uses_image_texture(ob)]
report["uv_scope"] = ("meshes with image-texture materials: " + ", ".join(o.name for o in textured)
                      if textured else "not scored: no material samples an image texture")
RES = 512
for ob in textured:
    me = ob.data
    if not me.uv_layers:
        continue
    uv = me.uv_layers.active.data
    me.calc_loop_triangles()
    scale = ob.matrix_world.to_3x3()
    # UV islands: faces joined across edges whose two UVs agree on both sides
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    bm.faces.ensure_lookup_table()
    par = list(range(len(bm.faces)))

    def f2(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    for e in bm.edges:
        if len(e.link_loops) != 2:
            continue
        l1, l2 = e.link_loops
        a1, b1 = l1[uvl].uv, l1.link_loop_next[uvl].uv
        a2, b2 = l2.link_loop_next[uvl].uv, l2[uvl].uv
        if (a1 - a2).length < 1e-6 and (b1 - b2).length < 1e-6:
            x, y = f2(l1.face.index), f2(l2.face.index)
            if x != y:
                par[x] = y
    island = [f2(f.index) for f in bm.faces]
    bm.free()
    dens, areas, tris_uv, tri_island = [], [], [], []
    for t in me.loop_triangles:
        P = [scale @ me.vertices[v].co for v in t.vertices]
        Q = [uv[l].uv.copy() for l in t.loops]
        a3 = ((P[1] - P[0]).cross(P[2] - P[0])).length / 2
        a2 = abs((Q[1] - Q[0]).cross(Q[2] - Q[0])) / 2
        if a3 < 1e-12:
            continue
        dens.append(a2 / a3)
        areas.append(a3)
        tris_uv.append([(q.x, q.y) for q in Q])
        tri_island.append(island[t.polygon_index])
    if not dens:
        continue
    cov = coverage(tris_uv, tri_island, RES)
    W = sum(areas)
    mean_d = sum(d * a for d, a in zip(dens, areas)) / W
    td = [math.sqrt(d / mean_d) for d in dens]            # relative texel density
    mu = sum(x * a for x, a in zip(td, areas)) / W
    sd = math.sqrt(sum(a * (x - mu) ** 2 for x, a in zip(td, areas)) / W)
    report["uv"][ob.name] = {
        "islands": len(set(island)),
        "texel_density_px_per_m": round(math.sqrt(mean_d) * TIER["texture_res"], 1),
        "texel_density_cv": round(sd / mu, 3),
        "utilisation": round(cov["utilisation"], 3),
        "overlap_fraction": round(cov["overlap_islands"], 4),
    }

# ---------------------------------------------------------------- ground contact
lowest = {}
for ob in visible:
    ev = ob.evaluated_get(dg)
    try:
        me = ev.to_mesh()
    except RuntimeError:
        continue
    if me and len(me.vertices):
        lowest[ob.name] = round(min((ob.matrix_world @ v.co).z for v in me.vertices), 4)
    ev.to_mesh_clear()
report["lowest_objects"] = dict(sorted(lowest.items(), key=lambda kv: kv[1])[:3])
if lowest:
    lo.z = min(lowest.values())
report["bbox_min"], report["bbox_max"] = [round(c, 3) for c in lo], [round(c, 3) for c in hi]

# ---------------------------------------------------------------- warnings (by discipline)
raw = []                                    # (discipline, kind, object, detail)


def flag(disc, kind, obj, detail=""):
    raw.append((disc, kind, obj, str(detail)))


for name, i in report["meshes"].items():
    for key, label in (("non_manifold_edges", "non-manifold edges"), ("non_manifold_verts", "non-manifold verts"),
                       ("duplicate_verts", "coincident duplicate verts"), ("zero_area_faces", "zero-area faces"),
                       ("ngons", "n-gons")):
        if i.get(key):
            flag("modeling", label, name, i[key])
    if i["signed_volume"] < 0 and not i["boundary_edges"]:
        flag("modeling", "normals point inward", name)
    if i.get("symmetry_max", 0) > CHK["symmetry_max_m"] and not args.asymmetric:
        flag("modeling", "asymmetric at rest", name, f"max {i['symmetry_max']} m")
    if i.get("unweighted_verts"):
        flag("rigging", "verts not bound to any bone", name, i["unweighted_verts"])
    lim = TIER["max_bone_influences"]
    if lim and i.get("max_bone_influences", 0) > lim:
        flag("rigging", f"bone influences over tier limit {lim}", name, f"up to {i['max_bone_influences']}")
b = report["budget"]
if b["lod0_tris_max"] and b["tris_base_cage"] > b["lod0_tris_max"]:
    flag("modeling", f"over {args.tier} LOD0 budget {b['lod0_tris_max']} tris", "scene",
         f"base cage {b['tris_base_cage']}")
first = next(iter(report["lowest_objects"]), "?")
tol = CHK["ground_tolerance_m"]
if lo.z < -tol:
    flag("modeling", "sinks below the ground", first, f"min z {lo.z:.3f}")
elif lo.z > tol:
    flag("modeling", "floats above the ground", first, f"lowest z {lo.z:.3f}")
r0, r1 = CHK["roughness_range"]
a0, a1 = CHK["albedo_srgb_range"]
for name, m in report["materials"].items():
    met = m.get("metallic")
    if met is not None and CHK["metalness_tolerance"] < met < 1 - CHK["metalness_tolerance"]:
        flag("texturing", "metalness neither 0 nor 1", name, met)
    if m.get("transmissive"):
        continue
    if "roughness" in m and not r0 <= m["roughness"] <= r1:
        flag("texturing", f"roughness outside {r0}-{r1}", name, m["roughness"])
    if "albedo_srgb_lum" in m:
        if met is not None and met >= 1 - CHK["metalness_tolerance"]:
            if m["albedo_srgb_max"] < CHK["metal_albedo_srgb_min"]:
                flag("texturing", "metal albedo too dark", name, f"sRGB max {m['albedo_srgb_max']}")
        elif not a0 <= m["albedo_srgb_lum"] <= a1:
            flag("texturing", f"albedo luminance outside {a0}-{a1}", name, m["albedo_srgb_lum"])
for ob in textured:
    if not ob.data.uv_layers:
        flag("uv_bake", "textured but has no UV layer", ob.name)
for name, u in report["uv"].items():
    if u["texel_density_cv"] > CHK["texel_density_cv_max"]:
        flag("uv_bake", "uneven texel density", name, f"CV {u['texel_density_cv']}")
    if u["overlap_fraction"] > CHK["uv_overlap_max"]:
        flag("uv_bake", "UV islands overlap", name, f"{u['overlap_fraction'] * 100:.1f}%")
    if u["utilisation"] < CHK["uv_utilisation_min"]:
        flag("uv_bake", "low UV space utilisation", name, f"{u['utilisation'] * 100:.0f}%")

# one line per (discipline, kind) so a 160-object scene does not drown the report
warn = {"modeling": [], "texturing": [], "uv_bake": [], "rigging": []}
groups = {}
for disc, kind, obj, det in raw:
    groups.setdefault((disc, kind), []).append(f"{obj} ({det})" if det else obj)
for (disc, kind), objs in groups.items():
    more = f" ... +{len(objs) - 3} more" if len(objs) > 3 else ""
    warn[disc].append(f"{kind}: {len(objs)}x - {', '.join(objs[:3])}{more}")
report["warnings"] = warn
report["warnings_detail"] = [dict(zip(("discipline", "kind", "object", "detail"), r)) for r in raw]
with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
n_warn = sum(len(v) for v in warn.values())
print(f"[inspect] {n_warn} warnings:", {k: len(v) for k, v in warn.items()})
for k, v in warn.items():
    for w in v:
        print(f"[inspect]   {k}: {w}")
if args.no_render:
    print("[inspect] wrote", out_dir)
    sys.exit(0)

# ---------------------------------------------------------------- review renders
centre, extent = (lo + hi) / 2, max(hi - lo)
cam = bpy.data.objects.new("_InspectCam", bpy.data.cameras.new("_InspectCam"))
scene.collection.objects.link(cam)
scene.camera = cam
scene.render.image_settings.file_format = "PNG"
scene.render.use_compositing = False


def place(direction, ortho=True, dist=4.0):
    d = Vector(direction).normalized()
    cam.location = centre + d * extent * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO" if ortho else "PERSP"
    cam.data.ortho_scale, cam.data.lens, cam.data.clip_end = extent * 1.12, 50, extent * 10


scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = scene.render.resolution_y = 640
sh = scene.display.shading
sh.light, sh.color_type, sh.single_color = "STUDIO", "SINGLE", (0.75, 0.74, 0.72)
sh.show_cavity, sh.cavity_type, sh.show_object_outline, sh.show_shadows = True, "BOTH", True, False
scene.display.render_aa = "8"
for name, d in (("front", (0, -1, 0)), ("side", (1, 0, 0)), ("back", (0, 1, 0)), ("top", (0, -0.001, 1))):
    place(d)
    scene.render.filepath = os.path.join(out_dir, f"{name}.png")
    bpy.ops.render.render(write_still=True)

for ob in meshes:                      # wireframe shows the base cage
    for m in ob.modifiers:
        if m.type == "SUBSURF":
            m.show_render = False
wire = bpy.data.materials.new("_Wire")
if wire.node_tree is None:
    wire.use_nodes = True
nt = wire.node_tree
nt.nodes.clear()
wf, base, line = nt.nodes.new("ShaderNodeWireframe"), nt.nodes.new("ShaderNodeBsdfDiffuse"), nt.nodes.new("ShaderNodeEmission")
mix, outn = nt.nodes.new("ShaderNodeMixShader"), nt.nodes.new("ShaderNodeOutputMaterial")
wf.use_pixel_size = True
wf.inputs["Size"].default_value = 1.0
base.inputs["Color"].default_value = (0.85, 0.85, 0.85, 1)
line.inputs["Color"].default_value = (0.02, 0.05, 0.12, 1)
for a, b_ in ((wf.outputs[0], mix.inputs[0]), (base.outputs[0], mix.inputs[1]),
              (line.outputs[0], mix.inputs[2]), (mix.outputs[0], outn.inputs["Surface"])):
    nt.links.new(a, b_)
bpy.context.view_layer.material_override = wire
scene.render.engine = "CYCLES"
scene.cycles.samples, scene.cycles.use_denoising = 24, False
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for dv in prefs.devices:
        dv.use = dv.type == "OPTIX"
    scene.cycles.device = "GPU"
except Exception:  # noqa: BLE001 - CPU fallback is fine
    pass
scene.render.resolution_x = scene.render.resolution_y = 900
place((0.55, -0.83, 0.12), ortho=False, dist=1.75)
scene.render.filepath = os.path.join(out_dir, "wire.png")
bpy.ops.render.render(write_still=True)
print("[inspect] wrote", out_dir)
