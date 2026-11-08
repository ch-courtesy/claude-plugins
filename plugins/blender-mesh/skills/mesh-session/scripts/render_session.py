"""Studio render of a modelling session's current step (runs in Blender).

  blender -b --python render_session.py -- SESSION_DIR OUT.png [--res 1000] [--samples 96]
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ap = argparse.ArgumentParser()
ap.add_argument("session")
ap.add_argument("out")
ap.add_argument("--res", type=int, default=1000)
ap.add_argument("--samples", type=int, default=96)
ap.add_argument("--exposure", type=float, default=0.0, help="stops; lights are set so albedo 0.18 renders near mid-grey")
ap.add_argument("--fill", type=float, default=0.85, help="fraction of the frame the model fills")
ap.add_argument("--blend", default="", help="render this file instead of the session's current step")
ap.add_argument("--pose", default="", help="bone rotations as JSON: [{\"bone\", \"axis\", \"deg\"}]")
ap.add_argument("--attach", default="", help="a second .blend whose Model hangs from a bone, for a prop in hand")
ap.add_argument("--attach-bone", default="hand.L")
ap.add_argument("--attach-drop", type=float, default=0.3, help="metres from the prop's origin up to its grip")
ap.add_argument("--attach-handle", type=float, default=None, help="heading of the prop's handle; it turns to cross the palm")
ap.add_argument("--attach-light", type=float, default=0.0, help="watts of a warm light inside the prop")
ap.add_argument("--attach-light-height", type=float, default=0.11)
ap.add_argument("--view", default="", choices=["", "front", "side", "back"],
                help="orthographic turnaround view on a plain background, as on a model sheet")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
sdir = os.path.abspath(a.session)
S = json.load(open(os.path.join(sdir, "session.json"), encoding="utf-8"))
bpy.ops.wm.open_mainfile(filepath=os.path.abspath(a.blend) if a.blend else os.path.join(sdir, S["current"]))
sc = bpy.context.scene
ob = bpy.data.objects[S["object"]]
if a.pose:                                             # world-axis bone rotations, parents first
    rig = bpy.data.objects.get("Rig")
    for r in json.loads(a.pose):
        pb = rig.pose.bones[r["bone"]]
        h = pb.matrix.translation.copy()
        rot = Matrix.Rotation(math.radians(r["deg"]), 4, Vector(r["axis"]).normalized())
        pb.matrix = Matrix.Translation(h) @ rot @ Matrix.Translation(-h) @ pb.matrix
        bpy.context.view_layer.update()
if not ob.data.materials:
    m = bpy.data.materials.new("Clay")
    m.diffuse_color = (0.7, 0.68, 0.65, 1)
    if m.node_tree:
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.7, 0.68, 0.65, 1)
    ob.data.materials.append(m)
if a.attach:
    with bpy.data.libraries.load(os.path.abspath(a.attach), link=False) as (src, dst):
        dst.objects = ["Model"]
    prop = dst.objects[0]
    sc.collection.objects.link(prop)
    bpy.context.view_layer.update()
    rig_ = bpy.data.objects["Rig"]
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "mesh-animate", "scripts"))
    from prop_attach import prop_matrix
    prop.matrix_world = prop_matrix(rig_, a.attach_bone, a.attach_drop, 0.0, 0, 1, a.attach_handle)
    if a.attach_light:
        d_ = bpy.data.lights.new("Glow", "POINT")
        d_.energy, d_.color, d_.shadow_soft_size = a.attach_light, (1.0, 0.62, 0.28), 0.02
        o_ = bpy.data.objects.new("Glow", d_)
        sc.collection.objects.link(o_)
        o_.location = prop.location + Vector((0, 0, a.attach_light_height))
dg = bpy.context.evaluated_depsgraph_get()
pts = [ob.matrix_world @ Vector(c) for c in ob.evaluated_get(dg).bound_box]
lo = Vector([min(p[i] for p in pts) for i in range(3)])
hi = Vector([max(p[i] for p in pts) for i in range(3)])
c, size = (lo + hi) / 2, max(hi - lo)

bpy.ops.mesh.primitive_plane_add(size=size * 30, location=(0, 0, lo.z - 0.002))
g = bpy.context.active_object
g.name = "ENV_Ground"
gm = bpy.data.materials.new("Ground")
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.18, 0.19, 0.21, 1)
g.data.materials.append(gm)
for name, off, e, col in (("Key", (2.2, -2.6, 3.0), 260, (1, 0.95, 0.9)), ("Fill", (-2.6, -1.8, 1.4), 90, (0.85, 0.9, 1)),
                          ("Rim", (-0.4, 2.8, 2.4), 220, (0.9, 0.95, 1))):
    d = bpy.data.lights.new(name, "AREA")
    d.energy, d.size, d.color = e * size * size, 2.5 * size, col
    o = bpy.data.objects.new(name, d)
    sc.collection.objects.link(o)
    o.location = c + Vector(off) * size
    o.rotation_euler = (c - o.location).to_track_quat("-Z", "Y").to_euler()
w = sc.world or bpy.data.worlds.new("World")
sc.world = w
if w.node_tree and w.node_tree.nodes.get("Background"):
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.04, 0.045, 0.055, 1)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.lens = 50
sc.collection.objects.link(cam)
sc.camera = cam
AXES = {"front": (0, -1, 0), "side": (1, 0, 0), "back": (0, 1, 0)}
back = Vector(AXES.get(a.view, (1.5, -2.6, 0.8))).normalized()   # from the model towards the camera
R = (-back).to_track_quat("-Z", "Y").to_matrix()
half = math.tan(cam.data.angle / 2) * a.fill           # the model fills this fraction of the frame
right, up = R.col[0], R.col[1]
dist = max(max(abs((p - c).dot(right)), abs((p - c).dot(up))) / half + (p - c).dot(back) for p in pts)
cam.location = c + back * dist
cam.rotation_euler = R.to_euler()
if a.view:
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2 * max(max(abs((p - c).dot(right)), abs((p - c).dot(up))) for p in pts) / a.fill
    g.hide_render = True
    if w.node_tree and w.node_tree.nodes.get("Background"):
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.78, 1)
    sc.render.film_transparent = False
sc.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for dev in ("OPTIX", "CUDA", "METAL", "HIP"):
        try:
            prefs.compute_device_type = dev
            prefs.get_devices()
            if any(x.type == dev for x in prefs.devices):
                for x in prefs.devices:
                    x.use = x.type == dev
                sc.cycles.device = "GPU"
                break
        except TypeError:
            continue
except Exception:  # noqa: BLE001 - CPU fallback
    pass
sc.cycles.samples, sc.cycles.use_denoising = a.samples, True
sc.render.resolution_x = sc.render.resolution_y = a.res
sc.view_settings.exposure = a.exposure
sc.render.filepath = os.path.abspath(a.out)
bpy.ops.render.render(write_still=True)
print("[render_session] wrote", a.out)
