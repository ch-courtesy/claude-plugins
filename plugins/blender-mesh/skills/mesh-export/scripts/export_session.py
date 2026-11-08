"""Export a finished model to GLB and prove it survived: read the file back and check it.

  blender -b TEXTURE.blend --python export_session.py -- --out DIR [--object Model] [--spec RIG.json]

Applies the subdivision (armature kept), bakes the spec's poses into one animation, exports,
records the posed surface, then starts a clean scene, imports the GLB and measures what came
back: triangles, joints, influences, height, images, and each pose compared with the original.
A GLB without a rig is fine: skin and pose checks are then skipped. Writes DIR/model.glb,
DIR/check.blend (the imported model) and DIR/report.json.
"""
import argparse
import json
import math
import os
import struct
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--object", default="Model")
ap.add_argument("--spec", default="")
ap.add_argument("--height", type=float, default=0.0, help="expected height, when there is no spec")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
glb = os.path.join(out, "model.glb")
SPEC = json.load(open(a.spec, encoding="utf-8")) if a.spec else {"poses": []}
ob = bpy.data.objects[a.object]
rig = bpy.data.objects.get("Rig")
bpy.context.view_layer.objects.active = ob
ob.select_set(True)


FOLLOW = {b["follows"]: (b["name"], b.get("share", 0.5)) for b in SPEC.get("bones", []) if b.get("follows")}


def expand(rots):
    res = []
    for r in rots:
        res.append((r["bone"], r["axis"], r["deg"]))
        if r.get("mirror", True) and r["bone"].endswith(".L"):
            x = r["axis"]
            res.append((r["bone"][:-2] + ".R", [x[0], -x[1], -x[2]], r["deg"]))
    for name, axis, deg in list(res):                  # helpers take their share of the rotation
        base, _, side = name.partition(".")
        if base in FOLLOW:
            h, share = FOLLOW[base]
            res.append((f"{h}.{side}" if side else h, axis, deg * share))
    return res


def set_pose(arm, rots, order):
    """World-axis rotations about each bone's head, parents first."""
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for name, axis, deg in sorted(expand(rots), key=lambda x: order[x[0]]):
        pb = arm.pose.bones[name]
        h = pb.matrix.translation.copy()
        R = Matrix.Rotation(math.radians(deg), 4, Vector(axis).normalized())
        pb.matrix = Matrix.Translation(h) @ R @ Matrix.Translation(-h) @ pb.matrix
        bpy.context.view_layer.update()


def surface(o):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    e = o.evaluated_get(dg)
    m = e.to_mesh()
    n = len(m.vertices)
    V = np.empty(n * 3)
    m.vertices.foreach_get("co", V)
    V = V.reshape(n, 3)
    M = np.array(o.matrix_world)
    V = V @ M[:3, :3].T + M[:3, 3]
    m.calc_loop_triangles()
    t = len(m.loop_triangles)
    e.to_mesh_clear()
    return V, t


# ---- the subdivided surface becomes the mesh; only the armature stays live
sub = next((m for m in ob.modifiers if m.type == "SUBSURF"), None)
if sub:
    ob.modifiers.move(list(ob.modifiers).index(sub), 0)
    bpy.ops.object.modifier_apply(modifier=sub.name)
for m in list(ob.modifiers):
    if m.type == "MIRROR":
        bpy.ops.object.modifier_apply(modifier=m.name)
order = {b.name: i for i, b in enumerate(rig.data.bones)} if rig else {}
if rig:
    rig.animation_data_create()
    if rig.animation_data.action:
        rig.animation_data.action.use_fake_user = True
        rig.animation_data.action = None
    set_pose(rig, [], order)
rest_src, src_tris = surface(ob)
source = {}
if rig:
    for p in SPEC["poses"]:
        set_pose(rig, p["rot"], order)
        source[p["name"]] = surface(ob)[0]
    set_pose(rig, [], order)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for k, p in enumerate([{"rot": []}] + SPEC["poses"] + [{"rot": []}]):
        set_pose(rig, p["rot"], order)
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.keyframe_insert("rotation_quaternion", frame=1 + k * 16)
            pb.keyframe_insert("location", frame=1 + k * 16)
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.animation_data.action.name = "PoseTour"
    set_pose(rig, [], order)
    bpy.context.scene.frame_set(1)

bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
if rig:
    rig.select_set(True)
bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_apply=False, export_skins=bool(rig),
                          export_animations=bool(rig), export_animation_mode="ACTIONS", export_yup=True)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_pose import merge_textures, repeated_textures  # noqa: E402

print(f"[export] merged {merge_textures(glb)} repeated texture entries")

# ---- the file itself
with open(glb, "rb") as fh:
    magic, _, _ = struct.unpack("<4sII", fh.read(12))
    n, kind = struct.unpack("<I4s", fh.read(8))
    G = json.loads(fh.read(n))
R = {"file_mb": os.path.getsize(glb) / 2 ** 20, "valid_header": magic == b"glTF" and kind == b"JSON", "source_tris": src_tris,
     "images": len(G.get("images", [])), "embedded_images": sum(1 for i in G.get("images", []) if "bufferView" in i),
     "materials": len(G.get("materials", [])), "meshes": len(G.get("meshes", [])), "skins": len(G.get("skins", [])),
     "joints": len(G["skins"][0]["joints"]) if G.get("skins") else 0, "source_bones": len(order),
     "animations": len(G.get("animations", [])), "duplicate_textures": repeated_textures(G),
     "channels": sum(len(x["channels"]) for x in G.get("animations", []))}

# ---- read it back into an empty scene
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
back = max(meshes, key=lambda o: len(o.data.polygons))
if arms:
    arm = arms[0]
    arm.animation_data_clear()
    order2 = {b.name: i for i, b in enumerate(arm.data.bones)}
    set_pose(arm, [], order2)                           # importer may leave its first action posed
V, tris = surface(back)
R.update({"tris": tris, "tris_diff": abs(tris - src_tris) / src_tris, "height": float(V[:, 2].max() - V[:, 2].min()),
          "ground": float(V[:, 2].min()), "joints_missing": R["source_bones"] - R["joints"]})
if SPEC.get("height") or a.height:
    R["height_error"] = abs(R["height"] - (SPEC.get("height") or a.height))
if arms:
    names = {g.index: g.name for g in back.vertex_groups}
    me = back.data
    infl = [sum(1 for g in v.groups if g.weight > 1e-3) for v in me.vertices]
    sums = [sum(g.weight for g in v.groups) for v in me.vertices if v.groups]
    R.update({"max_influences": max(infl), "unweighted": sum(1 for x in infl if x == 0),
              "weight_sum_error": float(max(abs(x - 1) for x in sums)), "groups": len(names)})
    err = {}
    for p in SPEC["poses"]:
        set_pose(arm, p["rot"], order2)
        Vb, _ = surface(back)
        S = source[p["name"]]
        tree = KDTree(len(S))
        for i, c in enumerate(S):
            tree.insert(c, i)
        tree.balance()
        d = np.array([tree.find(c)[2] for c in Vb[::2]])
        err[p["name"]] = {"p99_mm": float(np.percentile(d, 99) * 1000), "max_mm": float(d.max() * 1000),
                          "source_motion_mm": float(np.linalg.norm(S - rest_src, axis=1).max() * 1000),
                          "file_motion_mm": float(np.linalg.norm(Vb - V, axis=1).max() * 1000)}
    R["pose_error"] = err
    R["pose_motion_mm"] = min(min(x["source_motion_mm"], x["file_motion_mm"]) for x in err.values())
    R["pose_error_p99_mm"] = max(x["p99_mm"] for x in err.values())
    set_pose(arm, [], order2)
json.dump(R, open(os.path.join(out, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
back.name = a.object
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "check.blend"))
print(f"[export] {R['file_mb']:.1f} MB, tris {tris} (source {src_tris}), joints {R['joints']}/{R['source_bones']}, "
      f"influences {R.get('max_influences')}, height {R['height']:.3f}, images {R['embedded_images']}/{R['images']}, "
      f"animations {R['animations']} ({R['channels']} channels), pose error p99 {R.get('pose_error_p99_mm', 0):.2f} mm")
