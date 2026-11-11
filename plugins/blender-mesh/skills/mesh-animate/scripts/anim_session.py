"""Make one motion on a rigged character, bake it to keys and measure it.

  blender -b SOURCE.blend --python anim_session.py -- --spec MOTION.json --rig RIG.json --out DIR
      --library LIBRARY.blend [--object Model]

Two kinds of motion: "walk" (procedural, feet on a planted path) and "keys" (key poses with easing
and per-bone delay, feet placed by IK where each pose puts them). Both get secondary motion from
`follow`: trailing bones are damped springs driven by the acceleration of what carries them.
Everything is baked, so no constraints need to travel. A keyed motion either loops or plays once
(`"loop": false`, an attack); a motion made in place may record the path the game moves the character
along (`travel`). With a carry file in grip mode a weapon's point can be tracked and its strike
measured. The action is added to LIBRARY.blend beside earlier ones. Writes DIR/motion.blend,
DIR/report.json and DIR/poses.json (sampled frames, for the rig's deformation test).
"""
import argparse
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motion_metrics import overlap_metrics, pops, spacing_crest, spikes, strike_metrics  # noqa: E402
from prop_attach import carry_matrix  # noqa: E402


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


ap = argparse.ArgumentParser()
ap.add_argument("--spec", required=True)
ap.add_argument("--rig", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--library", required=True)
ap.add_argument("--object", default="Model")
ap.add_argument("--carry", default="", help="a carry file: the weapon whose point a strike measures")
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
W = read_json(a.spec, encoding="utf-8")
for extra in ([W["include_poses"]] if isinstance(W.get("include_poses"), str) else W.get("include_poses", [])):
    shared = read_json(os.path.join(os.path.dirname(os.path.abspath(a.spec)), extra), encoding="utf-8")
    W["poses"] = {**shared.get("poses", shared), **W.get("poses", {})}   # the motion's own poses win
CARRY = read_json(a.carry, encoding="utf-8") if a.carry else None
RIG = read_json(a.rig, encoding="utf-8")
NAME = W.get("name", "motion")
KIND = W.get("type", "walk")
FOLLOW = {b["follows"]: (b["name"], b.get("share", 0.5)) for b in RIG["bones"] if b.get("follows")}
HELPER_OF = {v[0]: k for k, v in FOLLOW.items()}
ob = bpy.data.objects[a.object]
rig = bpy.data.objects["Rig"]
sc = bpy.context.scene
N = W.get("cycle_frames", W.get("frames"))
LOOP = W.get("loop", True)
BAKE = N + 1 if LOOP else N                            # a loop bakes its first frame again at the end
S = W.get("stride", 0.0)                               # metres travelled per cycle
STANCE = W.get("stance", 0.6)
sc.render.fps = W.get("fps", 24)
clamped = [0]
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"


def arm_axis(side):
    """The hinge of a rest arm: square to it, in the plane of the shoulders. The same formula serves both
    sides: an axis is mirrored as a pseudo-vector, so the right arm's comes out mirrored by itself and a
    positive bend folds either forearm forwards."""
    b = rig.data.bones[f"upper_arm.{side}"]
    d = b.tail_local - b.head_local
    n = math.hypot(d.x, d.z)
    return (-d.z / n, 0, d.x / n)


ARM_AXIS = {s: arm_axis(s) for s in "LR"}


def update():
    bpy.context.view_layer.update()


def reset():
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    update()


def turn(name, axis, deg):
    """Rotate a bone about a world axis through its head; helper bones take their share."""
    if abs(deg) < 1e-6:
        return
    pb = rig.pose.bones[name]
    h = pb.matrix.translation.copy()
    R = Matrix.Rotation(math.radians(deg), 4, Vector(axis).normalized())
    pb.matrix = Matrix.Translation(h) @ R @ Matrix.Translation(-h) @ pb.matrix
    update()
    base, _, side = name.partition(".")
    if base in FOLLOW:
        helper, share = FOLLOW[base]
        turn(f"{helper}.{side}" if side else helper, axis, deg * share)


def turn_local(name, axis, deg):
    """Rotate a bone about one of its own axes as it stands now, so a finger curls the same way
    whatever the arm above it has done."""
    pb = rig.pose.bones[name]
    turn(name, (pb.matrix.to_3x3().normalized() @ Vector(axis))[:], deg)


def rotate(r):
    (turn_local if r.get("local") else turn)(r["bone"], r["axis"], r["deg"])


def move(name, offset):
    pb = rig.pose.bones[name]
    m = pb.matrix.copy()
    m.translation += Vector(offset)
    pb.matrix = m
    update()


def aim(name, target):
    pb = rig.pose.bones[name]
    cur = (pb.tail - pb.head).normalized()
    q = cur.rotation_difference((Vector(target) - pb.head).normalized())
    if q.angle > 1e-6:
        turn(name, q.axis[:], math.degrees(q.angle))


def level(name, pitch=0.0, yaw=0.0):
    """Give a bone its rest orientation in the world, tilted by pitch degrees about X, the whole turned
    by yaw degrees about the vertical."""
    pb = rig.pose.bones[name]
    want = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Matrix.Rotation(math.radians(pitch), 3, "X") \
        @ pb.bone.matrix_local.to_3x3()
    q = (want @ pb.matrix.to_3x3().inverted()).to_quaternion()
    if q.angle > 1e-6:
        turn(name, q.axis[:], math.degrees(q.angle))


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)


def solve_leg(side, A, pitch, hang=0.0, yaw=0.0):
    """Two-bone IK to ankle position A, knee forward (forward turned by yaw), then the foot."""
    thigh, shin, foot = f"thigh.{side}", f"shin.{side}", f"foot.{side}"
    H = rig.pose.bones[thigh].head.copy()
    l1, l2 = rig.pose.bones[thigh].length, rig.pose.bones[shin].length
    d = (A - H).length
    if d > (l1 + l2) * 0.999:
        clamped[0] += 1
        d = (l1 + l2) * 0.999
    along = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    out_ = math.sqrt(max(l1 * l1 - along * along, 0.0))
    axis = (A - H).normalized()
    pole = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Vector((0, -1, 0))
    pole = (pole - axis * pole.dot(axis)).normalized()
    aim(thigh, H + axis * along + pole * out_)
    aim(shin, A)
    b = rig.pose.bones[shin]
    d_ = (b.tail - b.head).normalized()
    tilt = min(math.degrees(math.atan2(d_.y, -d_.z)), W.get("hang_limit", 0))
    level(foot, pitch * (1 - hang) + tilt * hang, yaw)


def spin(deg):
    """Turn the whole body about the vertical through the origin: everything hangs from the hips."""
    if abs(deg) < 1e-9:
        return
    pb = rig.pose.bones["hips"]
    pb.matrix = Matrix.Rotation(math.radians(deg), 4, "Z") @ pb.matrix
    update()


# ---------------------------------------------------------------- walk
def rolled(r, deg):
    """How far the ankle moves when the foot turns deg about a pivot r away from the ankle."""
    t = math.radians(deg)
    return Vector((0, r.y * math.cos(t) - r.z * math.sin(t) - r.y, r.y * math.sin(t) + r.z * math.cos(t) - r.z))


KICK_PEAK = max((1 - x / 1000) * math.sin(math.pi * x / 1000) ** 2 for x in range(1001))


def foot_target(side, p):
    """Ankle position and foot pitch relative to the walking body, phase p in [0, 1). The foot lands
    on its heel, rolls flat, lifts its heel about the toe, then swings through."""
    q = (p + (0.0 if side == "L" else 0.5)) % 1.0
    x0 = rest_ankle[side]
    reach = STANCE * S / 2
    strike, off = W["heel_strike"], W["heel_off"]
    hs, ho = W["heel_strike_deg"], W["heel_off_deg"]
    toe = Vector((0, W["toe_y"], x0.z))
    heel = Vector((0, -W["heel_y"], x0.z))
    slip = W.get("debug_slip", 0.0)                    # negative control: feet that skate

    def flat(t):
        return Vector((x0.x, x0.y - reach + S * t + slip * math.sin(2 * math.pi * t / STANCE), x0.z))

    if q < strike:
        deg = -hs * (1 - ease(q / strike))
        return flat(q) + rolled(heel, deg), False, deg, 0.0
    if q < STANCE - off:
        return flat(q), True, 0.0, 0.0
    if q < STANCE:
        deg = ho * ease((q - STANCE + off) / off)
        return flat(q) + rolled(toe, deg), False, deg, 0.0
    u = (q - STANCE) / (1 - STANCE)
    a_ = flat(STANCE) + rolled(toe, ho)
    b_ = flat(0.0) + rolled(heel, -hs)
    v = S * (1 - STANCE)                               # leaves and lands at the stance speed
    h00, h10 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u
    h01, h11 = -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
    y = h00 * a_.y + h10 * v + h01 * b_.y + h11 * v
    z = a_.z + (b_.z - a_.z) * ease(u) + W["lift"] * math.sin(math.pi * u) ** 2
    z += W.get("kick", 0.0) * (1 - u) * math.sin(math.pi * u) ** 2 / KICK_PEAK   # a run's heel rises behind
    return Vector((x0.x, y, z)), False, ho + (-hs - ho) * ease(u), math.sin(math.pi * u) ** 2


def walk_body(f):
    p = (f % N) / N
    reset()
    s1, c1 = math.sin(2 * math.pi * p), math.cos(2 * math.pi * p)
    c2 = math.cos(4 * math.pi * p)
    move("hips", (W["sway"] * math.sin(2 * math.pi * (p - 0.15)), 0, -W["hip_drop"] - W["bob"] * c2))
    roll, yaw = W["roll"], W["yaw"]
    turn("hips", (0, 1, 0), roll * math.sin(2 * math.pi * (p - 0.15)))
    turn("hips", (0, 0, 1), yaw * s1)
    turn("spine", (1, 0, 0), W["lean"])
    turn("spine", (0, 0, 1), -0.5 * yaw * s1)
    turn("chest", (0, 0, 1), -0.8 * yaw * s1)
    turn("chest", (0, 1, 0), -0.6 * roll * math.sin(2 * math.pi * (p - 0.15)))
    turn("head", (0, 0, 1), -0.2 * yaw * s1)
    turn("head", (1, 0, 0), W["nod"] * math.cos(4 * math.pi * p + 0.5) - W["lean"] * 0.7)
    carry = W.get("carry_side", "L")                   # the arm that holds something swings less
    for side, sign in (("R", 1.0), ("L", -1.0)):
        amp, bend = (W["carry_swing"], W["carry_elbow"]) if side == carry else (W["arm_swing"], W["elbow"])
        ax = ARM_AXIS[side]
        swing = sign * amp * c1
        turn(f"upper_arm.{side}", (1, 0, 0), swing)
        turn(f"forearm.{side}", ax, -(bend + 0.35 * amp * (1 - sign * c1) / 2))
        out_ = W.get("carry_out", 0.0) if side == carry else 0.0
        turn(f"upper_arm.{side}", (0, 1, 0), (1 if side == "L" else -1) * (W.get("arm_down", 0.0) - out_))
    for r in W.get("hold", []):
        rotate(r)
    contact = []
    for side in "LR":
        A, on, pitch, hang = foot_target(side, p)
        solve_leg(side, A, pitch, hang)
        contact.append(on)
    return contact


# ---------------------------------------------------------------- key poses
def feet_reach():
    """How far the soles reach out from the centre line at rest, in metres."""
    names = [m.material.name if m.material else "" for m in ob.material_slots]
    want = W.get("sole_material", "Sole")
    if want not in names:
        return 0.0
    k = names.index(want)
    xs = [abs((ob.matrix_world @ ob.data.vertices[v].co).x) for p in ob.data.polygons
          if p.material_index == k and p.normal.z < -0.7 for v in p.vertices]
    return max(xs) if xs else 0.0


FEET_REACH = feet_reach()


def key_pose(name):
    """A named pose as local rotation and location per bone. `hold` rotations (a fist round a handle)
    are added to every pose after its own. `hips_feet_x` sets the hips' sideways offset in multiples of
    how far the soles reach out, for a pose that must leave the feet whatever the character's stance."""
    reset()
    P = W["poses"].get(name, {})
    hips = list(P.get("hips") or [0.0, 0.0, 0.0])
    if "hips_feet_x" in P:
        hips[0] = P["hips_feet_x"] * FEET_REACH
    if any(hips):
        move("hips", hips)
    for r in P.get("rot", []) + W.get("hold", []):
        rotate(r)
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in rig.pose.bones}


def foot_key(name, side):
    """Where a pose puts an ankle, from its rest place: [dx, dy, dz] in metres and an optional pitch."""
    f = W["poses"].get(name, {}).get("feet", {}).get(side, [0, 0, 0])
    return Vector(f[:3]), (f[3] if len(f) > 3 else 0.0)


EASE = {"inout": lambda t: t * t * (3 - 2 * t), "linear": lambda t: t,
        "out": lambda t: 1 - (1 - t) ** 3, "in": lambda t: t ** 3}
LEG_BONES = ("thigh", "shin", "foot", "knee", "ankle")


def leg_driven(name):
    """Legs are placed by IK, and so are helper bones that follow a leg bone: keying them as well
    would give a helper its share twice."""
    base = name.split(".")[0]
    return base in LEG_BONES or HELPER_OF.get(base) in LEG_BONES


def delay_of(name):
    d = W.get("delay", {})
    if name in d:
        return d[name]
    base, _, side = name.partition(".")
    if base in HELPER_OF:
        return d.get(f"{HELPER_OF[base]}.{side}" if side else HELPER_OF[base], 0)
    return 0


def key_at(t):
    """The two keys round time t and how far between them, eased."""
    keys = W["keys"]
    if LOOP:
        t %= N
    t = min(max(t, keys[0]["frame"]), keys[-1]["frame"])
    k = min(max(i for i, x in enumerate(keys) if x["frame"] <= t), len(keys) - 2)
    k0, k1 = keys[k], keys[k + 1]
    u = (t - k0["frame"]) / max(k1["frame"] - k0["frame"], 1)
    return k0, k1, EASE[k1.get("ease", W.get("ease", "inout"))](u)


def keys_body(f):
    reset()
    keys = W["keys"]
    for pb in rig.pose.bones:
        if leg_driven(pb.name):
            continue
        t = f - delay_of(pb.name)
        if LOOP:
            t %= N
        t = min(max(t, keys[0]["frame"]), keys[-1]["frame"])
        k = min(max(i for i, x in enumerate(keys) if x["frame"] <= t), len(keys) - 2)
        k0, k1 = keys[k], keys[k + 1]
        u = (t - k0["frame"]) / max(k1["frame"] - k0["frame"], 1)
        e = EASE[k1.get("ease", W.get("ease", "inout"))](u)
        q0, l0 = POSES[k0["pose"]][pb.name]
        q1, l1 = POSES[k1["pose"]][pb.name]
        if q0.dot(q1) < 0:                              # the same turn, taken the short way round
            q1 = -q1
        pb.rotation_quaternion = q0.slerp(q1, e)
        pb.location = l0.lerp(l1, e)
    update()
    k0, k1, e = key_at(f)
    y0, y1 = (W["poses"].get(k["pose"], {}).get("yaw", 0.0) for k in (k0, k1))
    yaw = y0 + (y1 - y0) * e
    spin(yaw)
    turning_ = abs(y1 - y0) > 1e-6
    Rz = Matrix.Rotation(math.radians(yaw), 3, "Z")
    contact = []
    for side in "LR":
        (a0, p0), (a1, p1) = foot_key(k0["pose"], side), foot_key(k1["pose"], side)
        at = a0.lerp(a1, e)
        moving = (a1 - a0).length > 1e-4 or turning_      # a foot turning with the body is not planted
        if not moving and W.get("debug_slip"):          # negative control: a planted foot that skates
            at.y += W["debug_slip"] * math.sin(2 * math.pi * f / N)
        if moving:                                      # a foot that steps lifts on its way
            at.z += W.get("step_lift", 0.05) * math.sin(math.pi * e)
        solve_leg(side, Rz @ (rest_ankle[side] + at), p0 + (p1 - p0) * e, yaw=yaw)
        contact.append(not moving and max(a0.z, a1.z) < 1e-4)
    return contact


def body(f):
    return walk_body(f) if KIND == "walk" else keys_body(f)


# ---------------------------------------------------------------- secondary motion
def spring_series(cfg, source):
    """A damped spring per axis, driven by the source point's acceleration. A loop runs several times
    round first, so it starts from its settled state."""
    w = 2 * math.pi / cfg["period"]
    z = cfg.get("damp", 0.3)
    P = np.array(source)
    n = len(P)
    loop = W.get("loop", True)
    idx = np.arange(n)
    A = P[(idx + 1) % n] - 2 * P + P[(idx - 1) % n] if loop else np.gradient(np.gradient(P, axis=0), axis=0)
    drive = np.stack([-A[:, 2], A[:, 0]], 1) * cfg["gain"]      # about X from Z, about Z from X
    th, vel = np.zeros(2), np.zeros(2)
    res = np.zeros((n, 2))
    for _ in range(4 if loop else 1):
        for i in range(n):
            vel = vel - w * w * (th - drive[i]) - 2 * z * w * vel
            th = th + vel
            res[i] = th
    return res


reset()
rest_ankle = {s: rig.pose.bones[f"foot.{s}"].head.copy() for s in "LR"}
if KIND == "keys":
    POSES = {n: key_pose(n) for n in {k["pose"] for k in W["keys"]}}
follow = W.get("follow", [])
series = []
if follow:
    source = {c["source"]: [] for c in follow}
    turning = {c["drag_from"]: [] for c in follow if c.get("drag")}
    for f in range(N):
        body(f)
        for name in source:
            source[name].append(list(rig.pose.bones[name].head))
        for name in turning:
            turning[name].append(rig.pose.bones[name].matrix.to_quaternion())
    series = [spring_series(c, source[c["source"]]) for c in follow]

# ---------------------------------------------------------------- bake
rig.animation_data_create()
if rig.animation_data.action:
    rig.animation_data.action.use_fake_user = True
    rig.animation_data.action = None
old = bpy.data.actions.get(NAME)
if old:
    bpy.data.actions.remove(old)
track = {n: [] for n in W.get("track", [])}
tip = [] if W.get("strike") and CARRY else None
if W.get("strike") and not CARRY:
    sys.exit("[anim] a strike measures the weapon's point: pass the carry file (animate ... --carry carry.json)")
ov = W.get("overlap")
rotation_track = {ov[k]: [] for k in ("driver", "follower")} if ov else {}
frames = []
held = {}                                              # bone -> its matrix in the hand's frame, from the grab
last_q = {}
for f in range(BAKE):
    contact = body(f % N)
    for c, s_ in zip(follow, series):
        if c.get("drag"):                              # cloth keeps the turn it had a few frames ago
            Qs = turning[c["drag_from"]]
            back = (f - c["drag"]) % N if LOOP else max(f - c["drag"], 0)
            q = Qs[back] @ Qs[f % N].inverted()
            if q.angle > 1e-6:
                turn(c["bone"], q.axis[:], math.degrees(q.angle) * c.get("drag_share", 1.0))
        turn(c["bone"], (1, 0, 0), float(s_[f % N][0]))
        turn(c["bone"], (0, 0, 1), float(s_[f % N][1]))
    for h in W.get("hand_off", []):                   # the lid taken off the back: it follows the hand
        if h["grab"] <= f < h["release"]:
            pb, hand = rig.pose.bones[h["bone"]], rig.pose.bones[h["hand"]]
            if h["bone"] not in held:
                held[h["bone"]] = hand.matrix.inverted() @ pb.matrix
            pb.matrix = hand.matrix @ held[h["bone"]]
            update()
        else:
            held.pop(h["bone"], None)
    if W.get("debug_pop") and f == W["debug_pop"]["frame"]:   # negative control: one frame off its path
        move("hips", W["debug_pop"]["offset"])
    for n in track:
        track[n].append(list(rig.pose.bones[n].tail))
    if tip is not None:
        tip.append(list(carry_matrix(rig, CARRY, f, N) @ Vector(W["strike"]["tip"])))
    for n, values in rotation_track.items():
        pb = rig.pose.bones[n]
        q = pb.matrix.to_quaternion() @ pb.bone.matrix_local.to_quaternion().inverted()
        if q.w < 0:
            q.negate()
        axis, angle = q.to_axis_angle()
        values.append(np.array(axis) * angle)
    frames.append({"frame": f, "contact": contact,
                   "basis": {pb.name: [list(pb.rotation_quaternion), list(pb.location)] for pb in rig.pose.bones}})
    for pb in rig.pose.bones:
        q = pb.rotation_quaternion
        if pb.name in last_q and q.dot(last_q[pb.name]) < 0:   # the same turn, kept on the near side
            pb.rotation_quaternion = -q
        last_q[pb.name] = pb.rotation_quaternion.copy()
        pb.keyframe_insert("rotation_quaternion", frame=f + 1)
        pb.keyframe_insert("location", frame=f + 1)
action = rig.animation_data.action
action.name = NAME
action.use_fake_user = True
sc.frame_start, sc.frame_end = 1, N
speed = S / N * sc.render.fps


def travel_path():
    """Where the game moves a motion made in place, per frame, from `travel` keys."""
    keys = W.get("travel")
    if not keys:
        return None
    path = []
    for f in range(BAKE):
        t = min(max(f, keys[0]["frame"]), keys[-1]["frame"])
        k = min(max(i for i, x in enumerate(keys) if x["frame"] <= t), len(keys) - 2) if len(keys) > 1 else 0
        k0, k1 = keys[k], keys[min(k + 1, len(keys) - 1)]
        u = (t - k0["frame"]) / max(k1["frame"] - k0["frame"], 1)
        e = EASE[k1.get("ease", "inout")](u)
        path.append([x0 + (x1 - x0) * e for x0, x1 in zip(k0["at"], k1["at"])])
    return path


root_path = travel_path()

# ---------------------------------------------------------------- mechanics
slots = [s.material.name if s.material else "" for s in ob.material_slots]
sole = slots.index(W.get("sole_material", "Sole"))
me = ob.data
sole_ids = {"L": set(), "R": set()}
for poly in me.polygons:
    if poly.material_index == sole and poly.normal.z < -0.7:
        sole_ids["L" if poly.center.x > 0 else "R"].update(poly.vertices)
sole_ids = {k: np.array(sorted(v)) for k, v in sole_ids.items()}


def surface(f):
    sc.frame_set(f + 1)
    update()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    e = ob.evaluated_get(dg)
    m = e.to_mesh()
    V = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", V)
    e.to_mesh_clear()
    return V.reshape(-1, 3)


step = S / N
Vs = [surface(f) for f in range(BAKE)]
slide, penetration, floating = 0.0, 0.0, 0.0
for side, k in (("L", 0), ("R", 1)):
    ids = sole_ids[side]
    world = [V[ids] - np.array([0, step * f, 0]) for f, V in enumerate(Vs)]
    penetration = max(penetration, -min(float(w[:, 2].min()) for w in world))
    start = None
    for f in range(N * 2 if LOOP else N):              # a loop's stance can wrap round the end of the cycle
        i = f % N
        if frames[i]["contact"][k]:
            w = world[i] - (np.array([0, step * N, 0]) * (f // N) if f >= N else 0)
            c = w.mean(0)
            if start is None:
                start = c
            slide = max(slide, float(np.linalg.norm((c - start)[:2])))
            floating = max(floating, float(w[:, 2].min()))
        else:
            start = None
closure = float(np.linalg.norm(Vs[N] - Vs[0], axis=1).max()) if LOOP else 0.0
st = W.get("strike")
exempt = set()                                         # a hit and a landing are meant to be sharp
if st:
    exempt |= set(range(st.get("from", 0), st["impact"] + 3))
for lo_, hi_ in W.get("exempt", []):
    exempt |= set(range(lo_, hi_ + 1))
accel, jf, jv = pops(np.stack(Vs[:N])[:, ::9], exempt=exempt, loop=LOOP)
spike, sf, sv = spikes(np.stack(Vs[:N])[:, ::9], exempt=exempt, loop=LOOP)
vert_slot = {}
for poly in me.polygons:
    for i in poly.vertices:
        vert_slot[i] = poly.material_index
pop_at = {"frame": (jf + 1) if jf is not None else None,
          "material": slots[vert_slot.get(int(jv) * 9, 0)] if jv is not None else ""}
spike_at = {"frame": (sf + 1) if sf is not None else None,
            "material": slots[vert_slot.get(int(sv) * 9, 0)] if sv is not None else ""}


# ---------------------------------------------------------------- principles, as measurable stand-ins
def spacing(P):
    """Largest change of velocity against the top speed: near 1 or more at a linear key, 2 pi / period
    on a smooth swing. None when the point hardly moves."""
    v = np.diff(P, axis=0)
    a_ = np.diff(v, axis=0)
    peak = float(np.linalg.norm(v, axis=1).max())
    return float(np.linalg.norm(a_, axis=1).max()) / peak if peak > 0.001 else None


Q = {}
T = {n: np.array(p) for n, p in track.items()}
sp = {n: spacing(np.vstack([p, p[1:3]])) for n, p in T.items()}
sp = {n: v for n, v in sp.items() if v is not None}
Q["spacing"] = max(sp.values()) if sp else 0.0
Q["spacing_worst"] = max(sp, key=sp.get) if sp else ""
cr = {n: spacing_crest(p[:N], loop=LOOP) for n, p in T.items()}   # the same at any speed or rhythm
cr = {n: v for n, v in cr.items() if v is not None}
Q["spacing_crest"] = max(cr.values()) if cr else 0.0
Q["spacing_crest_worst"] = max(cr, key=cr.get) if cr else ""
Q["motion_amount_mm"] = max(float(np.linalg.norm(p - p.mean(0), axis=1).max()) for p in T.values()) * 1000 if T else 0.0

if ov:
    Q.update(overlap_metrics(rotation_track[ov["driver"]][:N], rotation_track[ov["follower"]][:N],
                             loop=W.get("loop", True)))
    Q["overlap_space"] = "rest_relative_rotation"

pr = W.get("primary")
if pr:
    P = T[pr["point"]]
    f0, f1 = pr["from"], pr["to"]
    d = P[f1] - P[f0]
    travel = float(np.linalg.norm(d))
    u_ = d / travel
    rel = P[f0:f1 + 1] - P[f0]
    s_ = rel @ u_
    Q["travel_mm"] = travel * 1000
    Q["anticipation"] = max(0.0, -float(s_.min())) / travel
    Q["overshoot"] = max(0.0, float(s_.max()) - travel) / travel
    Q["arc"] = float(np.linalg.norm(rel - np.outer(s_, u_), axis=1).max()) / travel

if KIND == "keys":
    outside = 0.0
    for i, V in enumerate(Vs[:N]):
        down = [sole_ids[s_] for s_, k in (("L", 0), ("R", 1)) if frames[i]["contact"][k]]
        if not down:                                   # in the air nothing holds him up: no balance to keep
            continue
        feet = V[np.concatenate(down)]
        lo, hi = feet[:, :2].min(0), feet[:, :2].max(0)
        c = V.mean(0)[:2]
        outside = max(outside, float(np.maximum(np.maximum(lo - c, c - hi), 0).max()))
    Q["balance_outside_mm"] = outside * 1000
else:
    bones = {s: [] for s in "LR"}
    for f in range(N):
        sc.frame_set(f + 1)
        update()
        for s in "LR":
            bones[s].append(list(rig.pose.bones[f"foot.{s}"].head))
    L = np.array(bones["L"])
    Rr = np.roll(np.array(bones["R"]), -(N // 2), axis=0) * np.array([-1, 1, 1])
    Q["lr_symmetry_mm"] = float(np.linalg.norm(L - Rr, axis=1).max()) * 1000

if tip is not None:
    Q.update(strike_metrics(np.array(tip[:N]), sc.render.fps, st["impact"], start=st.get("from", 0),
                            end=st["impact"] + 3))


def evaluated():
    update()
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    e = ob.evaluated_get(dg)
    m = e.to_mesh()
    V = np.empty(len(m.vertices) * 3)
    m.vertices.foreach_get("co", V)
    e.to_mesh_clear()
    return V.reshape(-1, 3)


def posed(name):
    """The mesh standing in a named pose with nothing keyed: where the next motion starts."""
    action = rig.animation_data.action
    rig.animation_data.action = None
    key_pose(name)
    for pb in rig.pose.bones:
        if leg_driven(pb.name):
            pb.matrix_basis = Matrix.Identity(4)
    update()
    yaw = W["poses"].get(name, {}).get("yaw", 0.0)
    spin(yaw)
    for side in "LR":
        at, pitch = foot_key(name, side)
        solve_leg(side, Matrix.Rotation(math.radians(yaw), 3, "Z") @ (rest_ankle[side] + at), pitch, yaw=yaw)
    V = evaluated()
    rig.animation_data.action = action
    return V


end_pose_mm = None
if not LOOP:                                           # cloth still swinging may settle in the next motion
    cloth = {c["bone"] for c in follow}
    gi = {g.index: g.name for g in ob.vertex_groups}
    firm = np.array([not v.groups or gi[max(v.groups, key=lambda g: g.weight).group] not in cloth
                     for v in me.vertices])
    end = W.get("end_pose", W["keys"][-1]["pose"])
    end_pose_mm = float(np.linalg.norm(Vs[N - 1][firm] - posed(end)[firm], axis=1).max()) * 1000
    sc.frame_set(1)
no_foot_down = sum(1 for x in frames[:N] if not any(x["contact"]))   # in the air, or both turning
travel = {}
if root_path:
    rp = np.array(root_path)
    step_ = np.linalg.norm(np.diff(rp, axis=0), axis=1) * sc.render.fps
    travel = {"root_path": root_path, "travel_m": float(np.linalg.norm(rp[-1] - rp[0])),
              "travel_top_speed_m_s": float(step_.max()) if len(step_) else 0.0}

R = {"name": NAME, "kind": KIND, "frames": N, "fps": sc.render.fps, "speed_m_s": speed, "stride_m": S,
     "loop": LOOP, "duration_s": N / sc.render.fps, "pop_spike_ratio": spike, "spike_at": spike_at,
     "end_pose_mm": end_pose_mm, "frames_no_foot_down": no_foot_down, "pop_exempt_frames": sorted(exempt),
     **travel,
     "ik_out_of_reach": clamped[0], "foot_slide_mm": slide * 1000, "ground_penetration_mm": penetration * 1000,
     "stance_float_mm": floating * 1000, "cycle_closure_mm": closure * 1000, "pop_mm_per_frame2": accel * 1000,
     "pop_at": pop_at, "quality": Q}
sc.frame_set(1)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "motion.blend"))
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.library))
every = max(1, N // W.get("check_frames", 8))     # the reports last: they mean the bake and its files are saved
with open(os.path.join(out, "poses.json"), "w", encoding="utf-8") as fh:
    json.dump([{"name": f"f{x['frame']:02d}", "rot": [], "basis": x["basis"]} for x in frames[:N:every]],
              fh)
with open(os.path.join(out, "report.json"), "w", encoding="utf-8") as fh:
    json.dump(R, fh, indent=1)
print(f"[anim] {NAME}: {N} frames; slide {R['foot_slide_mm']:.1f}, under {R['ground_penetration_mm']:.1f}, float "
      f"{R['stance_float_mm']:.1f}, closure {R['cycle_closure_mm']:.2f}, pop {R['pop_mm_per_frame2']:.1f} "
      f"({pop_at['material']} f{pop_at['frame']}), out of reach {clamped[0]}")
print("[anim] quality:", {k: (round(v, 3) if isinstance(v, float) else v) for k, v in Q.items()})
