"""Pose rules a rig spec can ask for, applied after the pose's own rotations. Shared by every script
that poses a mesh-rig character (rig_session.py; an animation or a measuring script may import it too).

  auto_raise(rig, spec_bones, update)   a bone with "auto_raise" (a clavicle) lifts when its arm passes
                                        the horizontal, measured by where the elbow is, not the hand
  driven_rotations(spec_bones)          {source bone: [(driven bone, share)]} from "driven_by"

Both are no-ops for a spec that does not use the keys, so older rigs pose exactly as before.
"""
import math

from mathutils import Matrix, Vector


def _sides(b):
    return [(f"{b['name']}.{s}", s) for s in ("L", "R")] if b.get("mirror") else [(b["name"], "")]


def _named(name, side):
    """A bone name from the spec for one side: `upper_arm` -> `upper_arm.L`; a name given with .L follows the side."""
    if not side:
        return name
    if name.endswith(".L") or name.endswith(".R"):
        return name[:-2] + "." + side
    return f"{name}.{side}"


def _turn(rig, name, axis, deg, update):
    pb = rig.pose.bones[name]
    h = pb.matrix.translation.copy()
    R = Matrix.Rotation(math.radians(deg), 4, Vector(axis).normalized())
    pb.matrix = Matrix.Translation(h) @ R @ Matrix.Translation(-h) @ pb.matrix
    update()


def raise_angle(rule, elbow_from_shoulder):
    """Degrees to lift the clavicle for an upper arm pointing along `elbow_from_shoulder` (armature space).
    The arm's angle is taken from straight down (0) through the horizontal (90) to straight up (180), so an arm
    swung past the vertical keeps most of its lift; the lift is `ratio` of the excess over `from_deg` above
    the horizontal, eased in over `soft_deg` and saturating towards `max_deg`, so it never kinks."""
    d = Vector(elbow_from_shoulder)
    if d.length < 1e-9:
        return 0.0
    from_down = math.degrees(math.acos(max(-1.0, min(1.0, -d.z / d.length))))
    excess = from_down - 90.0 - rule.get("from_deg", 0.0)
    if excess <= 0:
        return 0.0
    # (2026-11-14) both ends are smooth: a lift that starts at a slope kinked the shoulder's speed on the frame an
    # arm crossed the horizontal, which a strike's wind-up showed as a pop in the jacket (4.06 against 4). It now
    # eases in over `soft_deg` (a parabola joining the line) and saturates towards `max_deg` (tanh) instead of
    # stopping at it.
    soft = rule.get("soft_deg", 20.0)
    eased = excess * excess / (2 * soft) if excess < soft else excess - soft / 2
    top = rule.get("max_deg", 30.0)
    return top * math.tanh(rule.get("ratio", 0.35) * eased / top)


def auto_raise(rig, spec_bones, update):
    """Lift every bone with "auto_raise": {"arm", "from_deg", "ratio", "max_deg", "keep_arm"} by the rule above.
    The lift turns the clavicle about the axis square to it and to world up, so its tail rises. With keep_arm
    (default) the arm is turned back by the same angle about its own head: it keeps the direction the pose gave
    it and is only carried up, so a pose means the same arm angle with or without the rule. Returns
    {bone: degrees lifted}."""
    out = {}
    for b in spec_bones:
        rule = b.get("auto_raise")
        if not rule:
            continue
        for name, side in _sides(b):
            arm = _named(rule["arm"], side)
            if name not in rig.pose.bones or arm not in rig.pose.bones:
                continue
            pa = rig.pose.bones[arm]
            deg = raise_angle(rule, pa.tail - pa.head)
            out[name] = deg
            if deg <= 0:
                continue
            pc = rig.pose.bones[name]
            axis = (pc.tail - pc.head).normalized().cross(Vector((0, 0, 1)))
            if axis.length < 1e-6:
                continue
            _turn(rig, name, axis[:], deg, update)
            if rule.get("keep_arm", True):
                _turn(rig, arm, axis[:], -deg, update)
    return out


def driven_rotations(spec_bones):
    """{source bone: [(driven bone, share)]}: a bone with "driven_by": [{"bone", "share"}] takes `share` of each
    source's rotation, about the same world axis through its own head (a corrective leaf bone, like a crotch
    bone driven by both thighs). On a mirrored bone, sources named .L are read as the bone's own side."""
    out = {}
    for b in spec_bones:
        for name, side in _sides(b):
            for src in b.get("driven_by", []):
                s = _named(src["bone"], side) if side and src["bone"].endswith(".L") else src["bone"]
                out.setdefault(s, []).append((name, src.get("share", 0.5)))
    return out
