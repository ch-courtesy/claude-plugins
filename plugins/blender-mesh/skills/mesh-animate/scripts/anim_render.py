"""Render a walk cycle as a seamless loop: the camera follows the character over a floor whose
pattern repeats every stride, so the last frame runs into the first.

  blender -b WALK.blend --python anim_render.py -- --out DIR [--res 640] [--samples 32]
      [--prop PROP.blend --prop-bone hand.L --prop-drop 0.30 --prop-swing 7 --prop-light 1.5 --prop-handle -45]
      [--carry CARRY.json]

Writes DIR/frame_NNN.png. A prop hangs from the bone and swings behind it like a pendulum, or, with a
carry file in grip mode, is held rigidly by its socket bone. A motion made in place that records the
path the game moves the character along (`root_path` in its report) is shown moving along it.
"""
import argparse
import json
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prop_attach import carry_matrix  # noqa: E402


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--report", required=True)
ap.add_argument("--object", default="Model")
ap.add_argument("--res", type=int, default=640)
ap.add_argument("--samples", type=int, default=32)
ap.add_argument("--prop", default="")
ap.add_argument("--prop-bone", default="hand.L")
ap.add_argument("--prop-drop", type=float, default=0.3)
ap.add_argument("--prop-swing", type=float, default=7.0)
ap.add_argument("--prop-light", type=float, default=1.5)
ap.add_argument("--prop-handle", type=float, default=None)
ap.add_argument("--carry", default="", help="a carry file; fills the prop options above")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
if a.carry:
    carry = read_json(a.carry, encoding="utf-8")
    a.prop, a.prop_light = carry["prop"], carry.get("light", 0.0)
else:
    carry = {"bone": a.prop_bone, "drop": a.prop_drop, "swing": a.prop_swing, "handle": a.prop_handle}
out = os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
R = read_json(a.report, encoding="utf-8")
N, S = R["frames"], R["stride_m"]
PATH = R.get("root_path")                              # where the game moves a motion made in place
sc = bpy.context.scene
ob = bpy.data.objects[a.object]
rig = bpy.data.objects["Rig"]

# ---- floor: a checker whose square is half a stride, so one cycle moves it exactly two squares
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -0.001))
floor = bpy.context.active_object
fm = bpy.data.materials.new("Floor")
nt = fm.node_tree
tc = nt.nodes.new("ShaderNodeTexCoord")
ck = nt.nodes.new("ShaderNodeTexChecker")
ck.inputs["Color1"].default_value = (0.20, 0.21, 0.24, 1)
ck.inputs["Color2"].default_value = (0.26, 0.27, 0.30, 1)
checker_size = abs(S) / 2 if abs(S) > 1e-6 else 0.25
ck.inputs["Scale"].default_value = 1 / checker_size
nt.links.new(tc.outputs["Object"], ck.inputs["Vector"])
nt.links.new(ck.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
floor.data.materials.append(fm)

# ---- lights, world and a camera that travels with the character
for name, off, e, col in (("Key", (2.2, -2.6, 3.0), 300, (1, 0.93, 0.85)), ("Fill", (-2.6, -1.8, 1.4), 90, (0.8, 0.86, 1)),
                          ("Rim", (-0.4, 2.8, 2.4), 240, (0.85, 0.92, 1))):
    d = bpy.data.lights.new(name, "AREA")
    d.energy, d.size, d.color = e, 2.5, col
    o = bpy.data.objects.new(name, d)
    sc.collection.objects.link(o)
    o.location = Vector((0, 0, 0.6)) + Vector(off)
    o.rotation_euler = (Vector((0, 0, 0.6)) - o.location).to_track_quat("-Z", "Y").to_euler()
    o.parent = rig
w = sc.world or bpy.data.worlds.new("World")
sc.world = w
if w.node_tree and w.node_tree.nodes.get("Background"):
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.035, 0.05, 1)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.data.lens = 60
sc.collection.objects.link(cam)
sc.camera = cam
cam.parent = rig
fit = max(1.0, bpy.data.objects[a.object].dimensions.z / 1.3)
aim = Vector((0.04, 0, 0.62 * fit))
cam.location = aim + Vector((1.9, -2.6, 0.7)).normalized() * 3.0 * fit
cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()

prop = None
if a.prop:
    with bpy.data.libraries.load(os.path.abspath(a.prop), link=False) as (src, dst):
        dst.objects = ["Model"]
    prop = dst.objects[0]
    prop.name = "Prop"
    sc.collection.objects.link(prop)
    glow = bpy.data.lights.new("Glow", "POINT")
    glow.energy, glow.color, glow.shadow_soft_size = a.prop_light, (1.0, 0.62, 0.28), 0.02
    glow_ob = bpy.data.objects.new("Glow", glow)
    sc.collection.objects.link(glow_ob)

sc.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for dev in ("OPTIX", "CUDA"):
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
sc.view_settings.exposure = -0.3

body = bpy.data.objects[a.object]
for f in range(N):
    sc.frame_set(f + 1)
    rig.location = PATH[f] if PATH else (0, -S * f / N, 0)   # the feet hold still on the floor
    if body.parent is None:                            # or the bones turn about points the mesh has left
        body.location = rig.location
    bpy.context.view_layer.update()
    if prop:
        prop.matrix_world = carry_matrix(rig, carry, f, N)
        glow_ob.location = prop.matrix_world @ Vector((0, 0, 0.11))
    sc.render.filepath = os.path.join(out, f"frame_{f:03d}.png")
    bpy.ops.render.render(write_still=True)
print("[anim] rendered", N, "frames to", out)
