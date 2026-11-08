"""Unwrap a model into one UV layout and measure the layout.

  blender -b MODEL.blend --python uv_session.py -- --out DIR [--object Model] [--angle 66]
      [--margin 0.002] [--res 1024]

Smart UV Project finds the islands; their borders become seams and each island is flattened
again with the angle-based unwrap (a projection alone stretches curved parts); islands are
then scaled to one texel density and packed. Measures the
UVs of the evaluated surface, which is what a texture is painted on: texel density spread,
overlap, utilisation and per-triangle stretch. Writes DIR/uv.blend, DIR/report.json and
DIR/layout.png (islands coloured by stretch).
"""
import argparse
import json
import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uv_raster import coverage  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--object", default="Model")
ap.add_argument("--angle", type=float, default=66.0)
ap.add_argument("--margin", type=float, default=0.002)
ap.add_argument("--res", type=int, default=1024)
ap.add_argument("--method", default="unwrap", choices=["project", "unwrap", "unwrap_subsurf"],
                help="project: keep Smart UV Project's islands as they are, for flat-sided parts")
ap.add_argument("--keep-subsurf", action="store_true",
                help="unwrap the cage and keep the modifier, if the subdivision must stay live")
ap.add_argument("--uv-smooth", default="", help="Subdivision modifier UV smoothing, e.g. SMOOTH_ALL or NONE")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
ob = bpy.data.objects[a.object]
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
me = ob.data
if a.uv_smooth:
    for x in ob.modifiers:
        if x.type == "SUBSURF":
            x.uv_smooth = a.uv_smooth
for layer in list(me.uv_layers):
    me.uv_layers.remove(layer)
me.uv_layers.new(name="UVMap")

if not a.keep_subsurf:                                  # unwrap the surface that gets painted
    for x in list(ob.modifiers):
        if x.type == "SUBSURF":
            ob.modifiers.move(list(ob.modifiers).index(x), 0)
            bpy.ops.object.modifier_apply(modifier=x.name)
arm_index = next((i for i, x in enumerate(ob.modifiers) if x.type == "ARMATURE"), None)
if arm_index is not None:                              # the unwrap can only use a subsurf that comes first
    ob.modifiers.move(arm_index, len(ob.modifiers) - 1)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(a.angle), island_margin=a.margin, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.select_all(action="SELECT")
if a.method != "project":                              # flatten each island properly
    bpy.ops.uv.seams_from_islands(mark_seams=True, mark_sharp=False)
    bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=a.margin, use_subsurf_data=a.method == "unwrap_subsurf")
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.average_islands_scale()
bpy.ops.uv.pack_islands(rotate=True, margin=a.margin, shape_method="CONCAVE")
bpy.ops.object.mode_set(mode="OBJECT")
if arm_index is not None:
    ob.modifiers.move(len(ob.modifiers) - 1, arm_index)
arm = ob.modifiers.get("Armature")
if arm:
    arm.show_viewport = False                          # measure the rest surface

dg = bpy.context.evaluated_depsgraph_get()
dg.update()
ev = ob.evaluated_get(dg)
m = ev.to_mesh()
m.calc_loop_triangles()
t = len(m.loop_triangles)
n = len(m.vertices)
V = np.empty(n * 3)
m.vertices.foreach_get("co", V)
V = V.reshape(n, 3)
T = np.empty(t * 3, np.int64)
m.loop_triangles.foreach_get("vertices", T)
T = T.reshape(t, 3)
L = np.empty(t * 3, np.int64)
m.loop_triangles.foreach_get("loops", L)
L = L.reshape(t, 3)
poly = np.empty(t, np.int64)
m.loop_triangles.foreach_get("polygon_index", poly)
tri_slot = np.array([p.material_index for p in m.polygons])[poly]
UV = np.empty(len(m.loops) * 2)
m.uv_layers.active.data.foreach_get("uv", UV)
UV = UV.reshape(-1, 2)
P = V[T]
Q = UV[L]
ev.to_mesh_clear()

e1, e2 = P[:, 1] - P[:, 0], P[:, 2] - P[:, 0]
a3 = np.linalg.norm(np.cross(e1, e2), axis=1) / 2
d1, d2 = Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0]
auv = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]) / 2
ok = (a3 > 1e-10) & (auv > 1e-12)
dens = np.sqrt(auv[ok] / a3[ok])
w = a3[ok]
mean = float((dens * w).sum() / w.sum())
cv = float(math.sqrt(((dens - mean) ** 2 * w).sum() / w.sum()) / mean)

# stretch: singular values of the map from the triangle's plane to UV space
ex = e1[ok] / np.linalg.norm(e1[ok], axis=1, keepdims=True)
nrm = np.cross(e1[ok], e2[ok])
ey = np.cross(nrm / np.linalg.norm(nrm, axis=1, keepdims=True), ex)
x1 = np.einsum("ij,ij->i", e1[ok], ex)
x2, y2 = np.einsum("ij,ij->i", e2[ok], ex), np.einsum("ij,ij->i", e2[ok], ey)
Ss = d1[ok] / x1[:, None]
St = (d2[ok] - Ss * x2[:, None]) / y2[:, None]
aa, bb, cc = (Ss * Ss).sum(1), (Ss * St).sum(1), (St * St).sum(1)
root = np.sqrt(np.maximum((aa - cc) ** 2 + 4 * bb * bb, 0))
s_hi, s_lo = np.sqrt((aa + cc + root) / 2), np.sqrt(np.maximum((aa + cc - root) / 2, 1e-20))
stretch = s_hi / s_lo
order_ = np.argsort(stretch)
area_cum = np.cumsum(a3[ok][order_]) / a3[ok].sum()
stretch_area = float(stretch[order_][np.searchsorted(area_cum, 0.95)])   # 95% of the surface is below this
slots = tri_slot[ok]
names = [s.name for s in ob.material_slots]
by_material = {(names[i] if i < len(names) else "(no material)"): round(float(np.percentile(stretch[slots == i], 95)), 2)
               for i in np.unique(slots)}

# overlap and utilisation on a raster
R = a.res
cov = coverage(Q, np.zeros(len(Q), int), R)
cover = cov["count"]
R_ = {"tris": t, "islands_margin": a.margin, "texel_density_cv": cv, "stretch_p50": float(np.percentile(stretch, 50)),
      "stretch_p95": float(np.percentile(stretch, 95)), "stretch_p95_area": stretch_area, "overlap_fraction": cov["overlap_any"],
      "utilisation": cov["utilisation"], "out_of_bounds": float(((Q < 0) | (Q > 1)).any(axis=(1, 2)).mean()), "stretch_p95_by_material": by_material}
with open(os.path.join(out, "report.json"), "w", encoding="utf-8") as fh:
    json.dump(R_, fh, indent=1)

img = bpy.data.images.new("layout", R, R, alpha=True)
rgb = np.zeros((R, R, 4), np.float32)
rgb[..., 3] = 1
rgb[cover == 1, :3] = (0.75, 0.78, 0.82)
rgb[cover > 1, :3] = (1.0, 0.1, 0.1)
img.pixels.foreach_set(rgb.ravel())
img.filepath_raw, img.file_format = os.path.join(out, "layout.png"), "PNG"
img.save()
if arm:
    arm.show_viewport = True
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "uv.blend"))
print(f"[uv] density CV {cv:.3f}, stretch p95 {R_['stretch_p95']:.2f} (by area {stretch_area:.2f}), overlap {R_['overlap_fraction'] * 100:.2f}%, "
      f"utilisation {R_['utilisation'] * 100:.0f}%, out of bounds {R_['out_of_bounds'] * 100:.1f}%")
print("[uv] stretch p95 by material:", by_material)
