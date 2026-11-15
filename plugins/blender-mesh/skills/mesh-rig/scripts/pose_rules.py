"""Pose rules a rig spec can ask for, applied after the pose's own rotations. Shared by every script
that poses a mesh-rig character (rig_session.py; an animation or a measuring script may import it too).

  auto_raise(rig, spec_bones, update)   a bone with "auto_raise" (a clavicle) lifts when its arm passes
                                        the horizontal, measured by where the elbow is, not the hand
  driven_rotations(spec_bones)          {source bone: [(driven bone, share)]} from "driven_by"
  apply_driven(rig, spec_bones, update) turn each driven bone by its share of its source's turn
  apply_twist_helpers(rig, spec_bones, update)
                                        a helper with "follows" and "twist_share" is set from its source's turn,
                                        swing and twist taken apart (added 2026-11-15)
  joint_ranges(spec_bones)              [(bone, range)] for every bone with "bend_max" (added 2026-11-15)
  joint_angles(rig, ranges)             {bone: (bend, side, excess)}: how far each ranged joint closes, which way,
                                        and how far past its range it is
  hinge_axis(rig, child, toward)        the hinge's axis in the world as the parent stands: a turn about it by a
                                        positive angle folds the child towards "bend_toward"
  hinge_roll(rig, child, toward, parent_dir, want)
                                        how far a hinge's parent must turn about itself for the hinge's axis to lie
                                        along want (p x u for an IK with pole p and root-to-end line u)
  align_hinge(rig, child, toward, want, update)
                                        turn the parent about itself by that much (an IK's knee or elbow)

All are no-ops for a spec that does not use the keys, so older rigs pose exactly as before.
"""
import math

from mathutils import Matrix, Quaternion, Vector


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


def apply_driven(rig, spec_bones, update):
    """Turn every "driven_by" bone by `share` of its source's turn, after the pose's own rotations. The source's
    turn is taken against the bone it hangs from (its pose against its rest, both in the parent's frame), so a
    parent's turn, which a driven child of that parent already inherits, is not counted twice. The rig check
    (rig_session.py) and the bake (anim_session.py) both call this, so a corrective shape passed in the check is
    the one the motions bake (2026-11-14: the check used only the rotations written in a pose, the bake the
    source's whole turn from rest, parent included)."""
    out = {}
    for src, lst in driven_rotations(spec_bones).items():
        pb = rig.pose.bones.get(src)
        if pb is None:
            continue
        par = pb.parent
        Mp = par.matrix.to_3x3().normalized() if par else Matrix.Identity(3)
        Mp_rest = par.bone.matrix_local.to_3x3().normalized() if par else Matrix.Identity(3)
        local_pose = Mp.inverted() @ pb.matrix.to_3x3().normalized()
        local_rest = Mp_rest.inverted() @ pb.bone.matrix_local.to_3x3().normalized()
        axis, ang = (local_pose @ local_rest.inverted()).to_quaternion().to_axis_angle()
        if ang > math.pi:
            ang -= 2 * math.pi
        if abs(ang) < 1e-9:
            continue
        world_axis = (Mp @ axis).normalized()
        for d, share in lst:
            if d in rig.pose.bones:
                _turn(rig, d, world_axis[:], math.degrees(ang) * share, update)
                out[d] = out.get(d, 0.0) + math.degrees(ang) * share
    return out


def twist_helpers(spec_bones):
    """[(helper, source, share, twist_share)] for every bone with "follows" and "twist_share", in spec order, both
    sides of a mirrored bone. A source named without a side follows the helper's side."""
    out = []
    for b in spec_bones:
        if b.get("follows") is None or b.get("twist_share") is None:
            continue
        for name, side in _sides(b):
            out.append((name, _named(b["follows"], side), float(b.get("share", 0.5)), float(b["twist_share"])))
    return out


def apply_twist_helpers(rig, spec_bones, update):
    """Set every helper with "twist_share" from its source's turn (2026-11-15, Musoe v3's joined arm and leg).

    The source's turn is taken against the helper's own parent (rest to pose), then split into its twist about the
    source's own rest axis and the swing that is left. The helper gets `share` of the swing and `twist_share` of the
    twist, about the source's head, and rides on its parent. Run after every other rule (auto_raise moves the arm).

    Why: a plain "follows" helper turns by its share of every rotation given to its source, twist included. An elbow
    helper of a forearm that twists 180 degrees (a cleaver turned edge-down) then twists the elbow's skin by 90 and
    collapses it; a helper with twist_share 0 bends with the elbow and never twists. Because only the swing is taken,
    a twist near 180 degrees, whose sign is ambiguous, cannot make the helper jump. Returns {helper: degrees}."""
    out = {}
    for h, src, share, tws in twist_helpers(spec_bones):
        ph, ps = rig.pose.bones.get(h), rig.pose.bones.get(src)
        if ph is None or ps is None:
            continue
        par = ph.parent
        Mp = par.matrix.copy() if par else Matrix.Identity(4)
        Mp_rest = par.bone.matrix_local.copy() if par else Matrix.Identity(4)
        s_pose = Mp.inverted() @ ps.matrix                     # the source in the helper's parent frame
        s_rest = Mp_rest.inverted() @ ps.bone.matrix_local
        q = (s_pose.to_3x3().normalized() @ s_rest.to_3x3().normalized().inverted()).to_quaternion()
        if q.w < 0:
            q = -q
        axis = (s_rest.to_3x3().normalized() @ Vector((0, 1, 0))).normalized()
        along = q.x * axis.x + q.y * axis.y + q.z * axis.z
        tw = Quaternion((q.w, axis.x * along, axis.y * along, axis.z * along))
        if tw.magnitude < 1e-9:                            # a half turn about an axis square to the source
            tw = Quaternion()
        tw.normalize()
        swing = q @ tw.inverted()
        target = Quaternion().slerp(swing, share) @ Quaternion().slerp(tw, tws)
        pivot = s_rest.translation
        R = Matrix.Translation(pivot) @ target.to_matrix().to_4x4() @ Matrix.Translation(-pivot)
        ph.matrix = Mp @ R @ Mp_rest.inverted() @ ph.bone.matrix_local
        update()
        out[h] = math.degrees(target.angle)
    return out


def joint_ranges(spec_bones):
    """[(bone, range)] for every bone with "bend_max", both sides of a mirrored bone. The range is a dict:
      max     "bend_max": the most the joint may close, degrees between the bone and its parent (0 = in line)
      toward  "bend_toward": at rest, the world direction the bone swings when the joint closes ([0, -1, 0] for an
              elbow whose forearm folds forward); mirrored in x on the .R side. With it the joint is a hinge: the
              bend is signed about the hinge axis that rides on the parent, and two more limits apply:
      min     "bend_min" (default -10): a bend the wrong way past this is out of range
      side    "side_max" (default 20): how far the bone may leave the hinge's plane, degrees
    An elbow is a forearm's range, a knee a shin's."""
    out = []
    for b in spec_bones:
        if b.get("bend_max") is None:
            continue
        for name, side in _sides(b):
            r = {"max": float(b["bend_max"])}
            if b.get("bend_toward") is not None:
                t_ = list(b["bend_toward"])
                if side == "R":
                    t_[0] = -t_[0]
                r.update(toward=t_, min=float(b.get("bend_min", -10.0)), side=float(b.get("side_max", 20.0)))
            out.append((name, r))
    return out


def joint_angles(rig, ranges):
    """{bone: (bend, side, excess)} in the current pose for (bone, range) pairs from joint_ranges. bend is degrees
    between the bone and its parent; for a hinge ("toward") it is signed about the hinge axis, which is fixed in the
    parent bone (so an upper arm that turns about itself turns the elbow's hinge with it), and side is how far the
    bone has left the hinge's plane. excess is how far past the range the joint is (0 inside it).

    Why (2026-11-15, Musoe v3): the bake never asked how far a joint closed, nor which way. With overlapping rigid
    parts an off-hand folded to 174 degrees, and an elbow bent 112 degrees backwards, only sank one part into the
    other, unseen; joined skin cannot follow either. A bone with no parent is skipped."""
    out = {}
    for name, r in ranges:
        pb = rig.pose.bones.get(name)
        if pb is None or pb.parent is None:
            continue
        par = pb.parent
        p = (par.tail - par.head).normalized()
        c = (pb.tail - pb.head).normalized()
        if r.get("toward") is None:
            bend = math.degrees(c.angle(p, 0.0))
            out[name] = (bend, 0.0, max(0.0, bend - r["max"]))
            continue
        c_rest = (pb.bone.tail_local - pb.bone.head_local).normalized()
        h_rest = c_rest.cross(Vector(r["toward"]))
        if h_rest.length < 1e-6:
            raise ValueError(f"{name}: bend_toward lies along the bone at rest")
        h_par = par.bone.matrix_local.to_3x3().inverted() @ h_rest.normalized()
        h = (par.matrix.to_3x3() @ h_par).normalized()
        bend = math.degrees(math.atan2(p.cross(c).dot(h), p.dot(c)))
        side = math.degrees(math.asin(max(-1.0, min(1.0, c.dot(h)))))
        out[name] = (bend, side, max(0.0, bend - r["max"], r["min"] - bend, abs(side) - r["side"]))
    return out


def hinge_axis(rig, child, toward):
    """The hinge axis of `child`'s joint in the world, riding on its parent as the parent stands; a turn of the child
    about it by a positive angle folds the child towards `toward` (its "bend_toward")."""
    pb = rig.pose.bones[child]
    par = pb.parent
    h = (pb.bone.tail_local - pb.bone.head_local).normalized().cross(Vector(toward)).normalized()
    return (par.matrix.to_3x3() @ (par.bone.matrix_local.to_3x3().inverted() @ h)).normalized()


def hinge_roll(rig, child, toward, parent_dir, want):
    """Degrees the parent of hinge `child` must turn about its own axis, once turned the shortest way to parent_dir,
    for the hinge (given by the child's "bend_toward" `toward`, as joint_ranges gives it) to lie along `want`. For a
    two-bone IK with the joint towards pole p off the root-to-end line u, the hinge is p x u however far the limb is
    bent, so a nearly straight limb gets its turn from the pole as well (taken from the bent child instead, it swung
    from frame to frame as a stance leg straightened). None when `want` lies along the parent."""
    par = rig.pose.bones[child].parent
    a = Vector(parent_dir).normalized()
    want = Vector(want)
    want = want - a * want.dot(a)
    if want.length < 1e-6:
        return None
    h = (par.tail - par.head).normalized().rotation_difference(a) @ hinge_axis(rig, child, toward)
    want.normalize()
    return math.degrees(math.atan2(h.cross(want).dot(a), h.dot(want)))


def align_hinge(rig, child, toward, want, update):
    """Turn the parent of hinge `child` about its own axis so the hinge lies along `want` (p x u, see hinge_roll);
    call it after the parent is aimed and before the child is (2026-11-15). Aiming each bone the shortest way leaves
    the parent's own turn to chance, so a knee or an elbow can fold sideways or backwards, which skin cannot follow.
    Returns the degrees turned, or None."""
    par = rig.pose.bones[child].parent
    a = (par.tail - par.head).normalized()
    ang = hinge_roll(rig, child, toward, a, want)
    if ang is None:
        return None
    _turn(rig, par.name, a[:], ang, update)
    return ang
