"""Self-test of the joint range and hinge rules in pose_rules.py, on a two-bone arm built in an empty scene.

  blender -b --factory-startup --python test_pose_rules.py

Prints "[test] N/N passed" and exits 1 on a failure. Each case poses the arm on purpose (folded forwards, backwards,
sideways, past its range, with the upper arm turned about itself) and checks what joint_angles reads, and that
align_hinge brings a sideways fold back into the hinge."""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pose_rules import align_hinge, hinge_roll, joint_angles, joint_ranges  # noqa: E402

bpy.ops.wm.read_factory_settings(use_empty=True)
arm = bpy.data.armatures.new("A")
rig = bpy.data.objects.new("Rig", arm)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
up = arm.edit_bones.new("upper_arm.L")
up.head, up.tail = (0.2, 0, 1.4), (0.5, 0, 1.4)       # a T-pose arm along +x
fa = arm.edit_bones.new("forearm.L")
fa.head, fa.tail = (0.5, 0, 1.4), (0.8, 0, 1.4)
fa.parent = up
bpy.ops.object.mode_set(mode="POSE")
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
update = bpy.context.view_layer.update

SPEC = [{"name": "forearm", "mirror": True, "bend_max": 140, "bend_toward": [0, -1, 0]}]
RANGES = [r for r in joint_ranges(SPEC) if r[0] == "forearm.L"]
results = []


def check(name, ok, got):
    results.append(ok)
    print(f"[test] {'ok  ' if ok else 'FAIL'} {name}: {got}")


def reset():
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    update()


def turn(bone, axis, deg):
    pb = rig.pose.bones[bone]
    h = pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, Vector(axis)) @ Matrix.Translation(-h) \
        @ pb.matrix
    update()


def angles():
    return joint_angles(rig, RANGES)["forearm.L"]


# the hinge of a forearm along +x folding towards -y is +x cross -y = -z: a positive turn about -z folds it forwards
reset()
turn("forearm.L", (0, 0, -1), 90)
b, s, e = angles()
check("folded forwards 90: bend +90, side 0, in range", abs(b - 90) < 0.1 and abs(s) < 0.1 and e == 0, (b, s, e))
reset()
turn("forearm.L", (0, 0, -1), 150)
b, s, e = angles()
check("folded forwards 150: 10 past bend_max 140", abs(b - 150) < 0.1 and abs(e - 10) < 0.1, (b, s, e))
reset()
turn("forearm.L", (0, 0, -1), -30)
b, s, e = angles()
check("folded backwards 30: bend -30, 20 past bend_min -10", abs(b + 30) < 0.1 and abs(e - 20) < 0.1, (b, s, e))
reset()
turn("forearm.L", (0, 1, 0), 40)                       # down, out of the hinge's plane
b, s, e = angles()
check("folded sideways 40: side 40, 20 past side_max 20", abs(abs(s) - 40) < 0.1 and abs(e - 20) < 0.1, (b, s, e))
reset()
turn("upper_arm.L", (1, 0, 0), 90)                     # the upper arm turned about itself: the hinge turns with it
turn("forearm.L", (0, 0, -1), 90)                      # the old forward fold is now out of the hinge
b, s, e = angles()
check("upper arm turned 90, forearm folded the old way: read as sideways", abs(abs(s) - 90) < 0.1, (b, s, e))
# align_hinge: aim the upper arm, turn it about itself for a fold towards -y, then the forearm folds in its hinge
reset()
turn("upper_arm.L", (1, 0, 0), 70)                     # some turn left to chance by an earlier step
want = Vector((0, 0, -1))                              # the hinge of a fold towards -y
turned = align_hinge(rig, "forearm.L", RANGES[0][1]["toward"], want, update)
turn("forearm.L", (0, 0, -1), 80)
b, s, e = angles()
check("align_hinge undoes a 70 degree turn: the fold is back in the hinge", abs(turned + 70) < 0.1 and abs(s) < 0.1
      and abs(b - 80) < 0.1, (turned, b, s))
reset()
check("hinge_roll is None for a hinge axis along the parent",
      hinge_roll(rig, "forearm.L", RANGES[0][1]["toward"], (1, 0, 0), (1, 0, 0)) is None, "None")
plain = [r for r in joint_ranges([{"name": "shin", "bend_max": 150}])]
check("a range without bend_toward has no hinge limits", plain == [("shin", {"max": 150.0})], plain)
mirrored = dict(joint_ranges(SPEC))["forearm.R"]["toward"]
check("bend_toward is mirrored in x on the .R side", mirrored == [-0.0, -1, 0] or mirrored == [0, -1, 0], mirrored)

print(f"[test] {sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
