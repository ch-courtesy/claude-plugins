"""Where a carried prop sits on a frame. The renderer, the contact check and the motion bake share this,
so every score is taken from the same placement the pictures show.

Two ways of carrying:
- hang (the default): the prop hangs below a bone and swings like a pendulum (a lantern, a bucket);
- grip: the prop is held rigidly by a socket bone, as a weapon is held in a fist.
"""
import math

from mathutils import Euler, Matrix, Vector


def prop_matrix(rig, bone, drop, swing_deg, frame, frames, handle=None, offset=None):
    """The prop hangs `drop` metres below the middle of the bone and swings like a pendulum.

    `handle` is the heading of the prop's handle in its own frame, in degrees. Given, the prop turns
    about its vertical axis so the handle crosses the palm, square to the bone, as a real grip does;
    left fixed, a raised arm runs into the handle's legs. `offset` moves the grip from the middle of the
    bone, in metres along the bone's own axes, for a hand whose grip is not at its middle.
    """
    pb = rig.pose.bones[bone]
    grip = rig.matrix_world @ (pb.center + (pb.matrix.to_3x3().normalized() @ Vector(offset) if offset else Vector()))
    t = 2 * math.pi * frame / frames
    swing = Matrix.Rotation(math.radians(swing_deg) * math.sin(t - 1.0), 4, "X") \
        @ Matrix.Rotation(math.radians(swing_deg * 0.5) * math.sin(2 * t - 1.3), 4, "Y")
    across = Matrix.Identity(4)
    if handle is not None:
        d = rig.matrix_world.to_3x3() @ (pb.tail - pb.head)
        across = Matrix.Rotation(math.atan2(d.y, d.x) + math.pi / 2 - math.radians(handle), 4, "Z")
    return Matrix.Translation(grip) @ swing @ Matrix.Translation((0, 0, -drop)) @ across


def grip_matrix(rig, bone, grip_point, rotate=(0.0, 0.0, 0.0), offset=None):
    """The prop held rigidly by a socket bone: its own point `grip_point` sits at the bone's head
    (moved by `offset`, metres along the bone's axes) and the prop is turned by `rotate`, XYZ Euler
    degrees in the bone's frame (Blender's XYZ order: X first, then Y, then Z). A socket whose Y axis runs
    along the handle towards the blade takes the prop's upright handle with rotate [-90, roll, 0]: X by -90
    lays the prop's +Z on the bone's +Y, then Y by roll turns the edge about the handle."""
    pb = rig.pose.bones[bone]
    at = Matrix.Translation(Vector(offset)) if offset else Matrix.Identity(4)
    turn = Euler([math.radians(x) for x in rotate], "XYZ").to_matrix().to_4x4()
    return rig.matrix_world @ pb.matrix @ at @ turn @ Matrix.Translation(-Vector(grip_point))


def carry_matrix(rig, carry, frame, frames):
    """The prop's world matrix on a frame, from a carry description (see the mesh-animate skill)."""
    if carry.get("mode", "hang") == "grip":
        return grip_matrix(rig, carry["bone"], carry["grip_point"], carry.get("rotate", (0, 0, 0)), carry.get("offset"))
    return prop_matrix(rig, carry["bone"], carry["drop"], carry["swing"], frame, frames, carry.get("handle"),
                       carry.get("offset"))
