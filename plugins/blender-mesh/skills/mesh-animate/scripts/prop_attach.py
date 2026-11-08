"""Where a carried prop sits on a frame. The renderer and the contact check share this, so the
score is taken from the same placement the pictures show."""
import math

from mathutils import Matrix, Vector


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
