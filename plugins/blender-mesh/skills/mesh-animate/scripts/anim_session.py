"""Make one motion on a rigged character, bake it to keys and measure it.

  blender -b SOURCE.blend --python anim_session.py -- --spec MOTION.json --rig RIG.json --out DIR
      --library LIBRARY.blend [--object Model]

Two kinds of motion: "walk" (procedural, feet on a planted path) and "keys" (key poses with easing
and per-bone delay, feet planted by IK). Both get secondary motion from `follow`: trailing bones are
damped springs driven by the acceleration of what carries them. Everything is baked, so no
constraints need to travel. The action is added to LIBRARY.blend beside earlier ones. Writes
DIR/motion.blend, DIR/report.json and DIR/poses.json (sampled frames, for the rig's deformation test).
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
from motion_metrics import overlap_metrics


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
a = ap.parse_args(sys.argv[sys.argv.index("--") + 1:])
out = os.path.abspath(a.out)
os.makedirs(out, exist_ok=True)
W = read_json(a.spec, encoding="utf-8")
RIG = read_json(a.rig, encoding="utf-8")
NAME = W.get("name", "motion")
KIND = W.get("type", "walk")
FOLLOW = {b["follows"]: (b["name"], b.get("share", 0.5)) for b in RIG["bones"] if b.get("follows")}
HELPER_OF = {v[0]: k for k, v in FOLLOW.items()}
ob = bpy.data.objects[a.object]
rig = bpy.data.objects["Rig"]
sc = bpy.context.scene
N = W.get("cycle_frames", W.get("frames"))
S = W.get("stride", 0.0)                               # metres travelled per cycle
STANCE = W.get("stance", 0.6)
sc.render.fps = W.get("fps", 24)
clamped = [0]
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"


def arm_axis(side):
    """The hinge of a rest arm: square to it, in the plane of the shoulders."""
    b = rig.data.bones[f"upper_arm.{side}"]
    d = b.tail_local - b.head_local
    n = math.hypot(d.x, d.z)
    return (-d.z / n, 0, d.x / n) if side == "L" else (d.z / n, 0, -d.x / n)


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


def level(name, pitch=0.0):
    """Give a bone its rest orientation in the world, tilted by pitch degrees about X."""
    pb = rig.pose.bones[name]
    want = Matrix.Rotation(math.radians(pitch), 3, "X") @ pb.bone.matrix_local.to_3x3()
    q = (want @ pb.matrix.to_3x3().inverted()).to_quaternion()
    if q.angle > 1e-6:
        turn(name, q.axis[:], math.degrees(q.angle))


def ease(t):
    return 0.5 - 0.5 * math.cos(math.pi * t)


def solve_leg(side, A, pitch, hang=0.0):
    """Two-bone IK to ankle position A, knee forward, then the foot."""
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
    pole = Vector((0, -1, 0))
    pole = (pole - axis * pole.dot(axis)).normalized()
    aim(thigh, H + axis * along + pole * out_)
    aim(shin, A)
    b = rig.pose.bones[shin]
    d_ = (b.tail - b.head).normalized()
    tilt = min(math.degrees(math.atan2(d_.y, -d_.z)), W.get("hang_limit", 0))
    level(foot, pitch * (1 - hang) + tilt * hang)


# ---------------------------------------------------------------- walk
def rolled(r, deg):
    """How far the ankle moves when the foot turns deg about a pivot r away from the ankle."""
    t = math.radians(deg)
    return Vector((0, r.y * math.cos(t) - r.z * math.sin(t) - r.y, r.y * math.sin(t) + r.z * math.cos(t) - r.z))


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
    for side, sign, amp, bend in (("R", 1.0, W["arm_swing"], W["elbow"]), ("L", -1.0, W["carry_swing"], W["carry_elbow"])):
        ax = ARM_AXIS[side]
        swing = sign * amp * c1
        turn(f"upper_arm.{side}", (1, 0, 0), swing)
        turn(f"forearm.{side}", ax, -(bend + 0.35 * amp * (1 - sign * c1) / 2))
        down = W.get("arm_down", 0.0) * (1 if side == "L" else -1)
        turn(f"upper_arm.{side}", (0, 1, 0), down - (W.get("carry_out", 0.0) if side == "L" else 0.0))
    contact = []
    for side in "LR":
        A, on, pitch, hang = foot_target(side, p)
        solve_leg(side, A, pitch, hang)
        contact.append(on)
    return contact


# ---------------------------------------------------------------- key poses
def key_pose(name):
    """A named pose as local rotation and location per bone."""
    reset()
    P = W["poses"].get(name, {})
    if P.get("hips"):
        move("hips", P["hips"])
    for r in P.get("rot", []):
        turn(r["bone"], r["axis"], r["deg"])
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in rig.pose.bones}


EASE = {"inout": lambda t: t * t * (3 - 2 * t), "linear": lambda t: t,
        "out": lambda t: 1 - (1 - t) ** 3, "in": lambda t: t ** 3}
LEG_BONES = ("thigh", "shin", "foot", "knee", "ankle")


def delay_of(name):
    d = W.get("delay", {})
    if name in d:
        return d[name]
    base, _, side = name.partition(".")
    if base in HELPER_OF:
        return d.get(f"{HELPER_OF[base]}.{side}" if side else HELPER_OF[base], 0)
    return 0


def keys_body(f):
    reset()
    keys = W["keys"]
    for pb in rig.pose.bones:
        if pb.name.split(".")[0] in LEG_BONES:
            continue
        t = f - delay_of(pb.name)
        if W.get("loop", True):
            t %= N
        t = min(max(t, keys[0]["frame"]), keys[-1]["frame"])
        k = min(max(i for i, x in enumerate(keys) if x["frame"] <= t), len(keys) - 2)
        k0, k1 = keys[k], keys[k + 1]
        u = (t - k0["frame"]) / max(k1["frame"] - k0["frame"], 1)
        e = EASE[k1.get("ease", W.get("ease", "inout"))](u)
        q0, l0 = POSES[k0["pose"]][pb.name]
        q1, l1 = POSES[k1["pose"]][pb.name]
        pb.rotation_quaternion = q0.slerp(q1, e)
        pb.location = l0.lerp(l1, e)
    update()
    for side in "LR":
        solve_leg(side, rest_ankle[side].copy(), 0.0)
    return [True, True]


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
ov = W.get("overlap")
rotation_track = {ov[k]: [] for k in ("driver", "follower")} if ov else {}
frames = []
for f in range(N + 1):
    contact = body(f % N)
    for c, s_ in zip(follow, series):
        if c.get("drag"):                              # cloth keeps the turn it had a few frames ago
            Qs = turning[c["drag_from"]]
            back = (f - c["drag"]) % N if W.get("loop", True) else max(f - c["drag"], 0)
            q = Qs[back] @ Qs[f % N].inverted()
            if q.angle > 1e-6:
                turn(c["bone"], q.axis[:], math.degrees(q.angle) * c.get("drag_share", 1.0))
        turn(c["bone"], (1, 0, 0), float(s_[f % N][0]))
        turn(c["bone"], (0, 0, 1), float(s_[f % N][1]))
    for n in track:
        track[n].append(list(rig.pose.bones[n].tail))
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
        pb.keyframe_insert("rotation_quaternion", frame=f + 1)
        pb.keyframe_insert("location", frame=f + 1)
action = rig.animation_data.action
action.name = NAME
action.use_fake_user = True
sc.frame_start, sc.frame_end = 1, N
speed = S / N * sc.render.fps

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
Vs = [surface(f) for f in range(N + 1)]
slide, penetration, floating = 0.0, 0.0, 0.0
for side, k in (("L", 0), ("R", 1)):
    ids = sole_ids[side]
    world = [V[ids] - np.array([0, step * f, 0]) for f, V in enumerate(Vs)]
    penetration = max(penetration, -min(float(w[:, 2].min()) for w in world))
    start = None
    for f in range(N * 2):                             # a stance can wrap round the end of the cycle
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
closure = float(np.linalg.norm(Vs[N] - Vs[0], axis=1).max())
sample = np.stack(Vs[:N] + Vs[:2])[:, ::9]
jumps = np.linalg.norm(sample[2:] - 2 * sample[1:-1] + sample[:-2], axis=2)
accel = float(jumps.max())
jf, jv = np.unravel_index(int(jumps.argmax()), jumps.shape)
vert_slot = {}
for poly in me.polygons:
    for i in poly.vertices:
        vert_slot[i] = poly.material_index
pop_at = {"frame": int(jf) + 1, "material": slots[vert_slot.get(int(jv) * 9, 0)]}


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
    for V in Vs[:N]:
        feet = V[np.concatenate([sole_ids["L"], sole_ids["R"]])]
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

R = {"name": NAME, "kind": KIND, "frames": N, "fps": sc.render.fps, "speed_m_s": speed, "stride_m": S,
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
