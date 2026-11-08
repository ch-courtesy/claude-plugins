"""Does a carried prop pass through the character carrying it? Measured on every frame of a motion,
with the placement the renderer uses.

  blender -b MOTION.blend --python prop_contact.py -- --prop PROP.blend --report REPORT.json \
      --out DIR [--object Model] [--bone hand.L] [--drop 0.30] [--swing 7] [--grip Bail] [--handle -45] [--every 1]

Writes DIR/report.json. The part of the prop made to be held (--grip, a material) sits inside the
hand on purpose, so that one pairing is the grip: it is reported as grip_depth_mm and must touch on
every frame. Every other pairing counts, including the rest of the prop against the same hand.
"""
import argparse
import json
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prop_attach import prop_matrix  # noqa: E402
from shell_depth import shell_depth, shells_of  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--prop", required=True)
ap.add_argument("--report", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--object", default="Model")
ap.add_argument("--bone", default="hand.L")
ap.add_argument("--drop", type=float, default=0.3)
ap.add_argument("--swing", type=float, default=7.0)
ap.add_argument("--grip", default="Bail")
ap.add_argument("--handle", type=float, default=None, help="heading of the prop's handle in its own frame")
ap.add_argument("--offset", type=float, nargs=3, default=None, help="grip point from the bone's middle, in its own axes")
ap.add_argument("--every", type=int, default=1)
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])

sc = bpy.context.scene
ob = bpy.data.objects[a.object]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
N = json.load(open(a.report, encoding="utf-8"))["frames"]
with bpy.data.libraries.load(os.path.abspath(a.prop), link=False) as (src, dst):
    dst.objects = list(src.objects)
prop = next(o for o in dst.objects if o and o.type == "MESH")


def plain(name):
    return name.split(".")[0]


def main_bone(verts):
    """The bone a shell mostly follows, by summed weight."""
    total = {}
    for i in verts.tolist():
        for g in ob.data.vertices[i].groups:
            total[g.group] = total.get(g.group, 0.0) + g.weight
    return ob.vertex_groups[max(total, key=total.get)].name if total else "-"


body = shells_of(ob.data)
for s in body:
    s["bone"] = main_bone(s["verts"])
    s["name"] = f"{plain(ob.data.materials[s['material']].name)}@{s['bone']}"
held = shells_of(prop.data)
for s in held:
    s["name"] = plain(prop.data.materials[s["material"]].name)
open_shells = sum(1 for s in body + held if s["open_edges"])

rest = np.empty(len(prop.data.vertices) * 3)
prop.data.vertices.foreach_get("co", rest)
rest = rest.reshape(-1, 3)
skin = np.empty(len(ob.data.vertices) * 3)
pairs, worst, grip_depth = {}, None, 0.0
checked, not_held, contact, by_frame = 0, [], 0, []
for f in range(0, N, a.every):
    sc.frame_set(f + 1)
    bpy.context.view_layer.update()
    place = np.array(prop_matrix(rig, a.bone, a.drop, a.swing, f, N, a.handle, a.offset))
    world = rest @ place[:3, :3].T + place[:3, 3]
    dg = bpy.context.evaluated_depsgraph_get()
    evaluated = ob.evaluated_get(dg)
    me = evaluated.to_mesh()
    if len(me.vertices) != len(ob.data.vertices):
        sys.exit("[prop] the evaluated mesh changed its vertex count: apply the subdivision first")
    me.vertices.foreach_get("co", skin)
    evaluated.to_mesh_clear()
    m = np.array(ob.matrix_world)
    deformed = skin.reshape(-1, 3) @ m[:3, :3].T + m[:3, 3]
    gripped, touched, deepest = False, False, 0.0
    for h in held:
        hp = world[h["verts"]]
        for b in body:
            hit = shell_depth(hp, h["faces"], deformed[b["verts"]], b["faces"])
            if hit is None:
                continue
            if h["name"] == a.grip and b["bone"] == a.bone:
                gripped = True
                grip_depth = max(grip_depth, hit[0])
                continue
            touched = True
            deepest = max(deepest, hit[0])
            key = f"{h['name']} x {b['name']}"
            if key not in pairs or hit[0] > pairs[key]["depth_mm"] / 1000:
                pairs[key] = {"depth_mm": round(hit[0] * 1000, 2), "frame": f + 1}
            if worst is None or hit[0] > worst["depth"]:
                worst = {"depth": hit[0], "frame": f + 1, "pair": key, "point": [round(float(x), 4) for x in hit[1]]}
    checked += 1
    by_frame.append(round(deepest * 1000, 1))
    contact += touched
    if not gripped:
        not_held.append(f + 1)

R = {"prop": os.path.abspath(a.prop), "bone": a.bone, "drop": a.drop, "swing": a.swing, "handle": a.handle, "grip": a.grip,
     "frames": N, "frames_checked": checked, "frames_unchecked": N - checked, "shells_body": len(body),
     "shells_prop": len(held), "open_shells": open_shells, "max_depth_mm": round(worst["depth"] * 1000, 2) if worst else 0.0,
     "worst": worst, "contact_frames": contact, "pairs": dict(sorted(pairs.items(), key=lambda kv: -kv[1]["depth_mm"])),
     "by_frame_mm": by_frame, "grip_depth_mm": round(grip_depth * 1000, 2), "frames_not_held": len(not_held), "not_held": not_held[:20]}
os.makedirs(a.out, exist_ok=True)
json.dump(R, open(os.path.join(a.out, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
top = f"{worst['pair']} on frame {worst['frame']}" if worst else "nothing touches"
print(f"[prop] {checked}/{N} frames; deepest {R['max_depth_mm']} mm ({top}); grip {R['grip_depth_mm']} mm; "
      f"not held on {len(not_held)} frames; open shells {open_shells}")
