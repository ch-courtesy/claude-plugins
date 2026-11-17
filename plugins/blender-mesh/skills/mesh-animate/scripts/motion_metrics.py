"""Motion measurements independent of Blender scene state (requires NumPy)."""
import numpy as np


def overlap_metrics(driver, follower, loop=True):
    """Signed lag of comparable rest-relative rotation vectors, in frames.

    Positive means the follower trails. Search both directions within a quarter
    cycle so a leading follower cannot win a later periodic alias. Stationary or
    unrelated signals have no measurable lag and must not pass an overlap gate.
    """
    x, y = np.asarray(driver, dtype=float), np.asarray(follower, dtype=float)
    result = {"overlap_lag_frames": None, "overlap_correlation": 0.0, "follower_ratio": 0.0}
    if x.ndim != 2 or x.shape != y.shape or len(x) < 8 or not (np.isfinite(x).all() and np.isfinite(y).all()):
        return result
    x, y = x - x.mean(0), y - y.mean(0)
    axis = np.linalg.svd(x, full_matrices=False)[2][0]
    dx, dy = x @ axis, y @ axis
    if min(dx.std(), dy.std()) < 1e-5:
        return result
    result["follower_ratio"] = float(dy.std() / dx.std())
    lags = range(-(len(x) // 4), len(x) // 4 + 1)
    scores = []
    for k in lags:
        if loop:
            a, b = dx, np.roll(dy, -k)
        else:
            a, b = (dx[:-k], dy[k:]) if k > 0 else ((dx[-k:], dy[:k]) if k < 0 else (dx, dy))
            a, b = a - a.mean(), b - b.mean()
        norm = np.linalg.norm(a) * np.linalg.norm(b)
        scores.append(float(a @ b / norm) if norm > 1e-12 else -1.0)
    best = int(np.argmax(scores))
    result["overlap_correlation"] = scores[best]
    if scores[best] >= 0.5:
        result["overlap_lag_frames"] = list(lags)[best]
        result["overlap_at_limit"] = best in (0, len(scores) - 1)   # still rising: at least this much, not a peak
    return result


def strike_metrics(P, fps, impact, start=0, end=None, slow=0.25):
    """How a weapon point strikes, from its track P (frames x 3, metres) and the frame meant as the hit.

    The strike is the run of frames before the fastest frame (searched from `start` to `end`) in which
    the point moves at `slow` of that top speed or more. The wind-up ends where the point was furthest
    back along the strike's direction before the strike began, and lasts as long as the point was moving
    back to get there, so a hold at the top counts as neither. Speeds are central differences. The
    top-down travel is the path length on the ground plane from the strike's start to the hit.
    """
    P = np.asarray(P, dtype=float)
    n = len(P)
    end = n - 1 if end is None else min(end, n - 1)
    v = np.zeros_like(P)
    v[1:-1] = (P[2:] - P[:-2]) / 2
    v[0], v[-1] = P[1] - P[0], P[-1] - P[-2]
    speed = np.linalg.norm(v, axis=1) * fps
    lo, hi = max(start, 0), max(end, start)
    peak = lo + int(np.argmax(speed[lo:hi + 1]))
    top = float(speed[peak])
    s0 = peak
    while s0 > 0 and speed[s0 - 1] >= slow * top:
        s0 -= 1
    hit = min(max(impact, 0), n - 1)
    d = P[hit] - P[s0]
    u = d / np.linalg.norm(d) if np.linalg.norm(d) > 1e-9 else np.zeros(3)
    along = (P[:s0 + 1] - P[s0]) @ u
    back = int(np.argmin(along))                       # furthest back before the strike
    w = back
    while w > 0 and float((P[w] - P[w - 1]) @ u) < 0:
        w -= 1
    path = P[s0:hit + 1, :2] if hit > s0 else P[hit:s0 + 1, :2]
    return {"tip_speed_m_s": top, "peak_frame": peak, "impact_offset_frames": abs(peak - hit),
            "strike_start_frame": s0, "strike_s": (peak - s0) / fps, "wind_up_s": (back - w) / fps,
            "top_travel_m": float(np.linalg.norm(np.diff(path, axis=0), axis=1).sum())}


def pops(samples, exempt=(), loop=True):
    """The largest jump in a sampled surface: the second difference of each point between frames, in
    metres per frame squared, as (value, frame, point). A loop wraps round; frames in `exempt` (a hit,
    a landing) are left out, as a sharp change there is meant."""
    S = np.asarray(samples, dtype=float)
    if loop:
        S = np.concatenate([S[-1:], S, S[:1]])
        centre = np.arange(len(samples))
    else:
        centre = np.arange(1, len(samples) - 1)
    J = np.linalg.norm(S[2:] - 2 * S[1:-1] + S[:-2], axis=2)
    keep = np.array([c not in set(exempt) for c in centre])
    if not keep.any():
        return 0.0, None, None
    J = np.where(keep[:, None], J, -1.0)
    i, k = np.unravel_index(int(J.argmax()), J.shape)
    return float(J[i, k]), int(centre[i]), int(k)


def spikes(samples, exempt=(), loop=True, floor=0.002):
    """The largest pop that does not depend on how fast the motion is: a frame's change of velocity (the
    second difference, per point) against the larger of the same two frames earlier and later, plus a
    small floor for stillness. Playing a whole motion k times faster scales every second difference by
    k squared, so the ratio stays; one frame off its path raises its own value alone. Frames in `exempt`
    are left out. Returns (ratio, frame, point)."""
    S = np.asarray(samples, dtype=float)
    n = len(S)
    if loop:
        T = np.concatenate([S[-3:], S, S[:3]])
        centre = np.arange(n)
    else:
        T = S
        centre = np.arange(3, n - 3)
    A = np.linalg.norm(T[2:] - 2 * T[1:-1] + T[:-2], axis=2)
    if len(A) < 5:
        return 0.0, None, None
    R = A[2:-2] / (np.maximum(A[:-4], A[4:]) + floor)
    keep = np.array([c not in set(exempt) for c in centre])
    if not keep.any():
        return 0.0, None, None
    R = np.where(keep[:, None], R, -1.0)
    i, k = np.unravel_index(int(R.argmax()), R.shape)
    return float(R[i, k]), int(centre[i]), int(k)


def spacing_crest(P, loop=True, still=0.001):
    """How unevenly a point's velocity changes, whatever its speed or rhythm: the crest factor (top over
    root mean square) of its acceleration over that of its speed. Any sinusoid scores 1 at any period;
    a linear key, where velocity turns in a kink, scores high. None for a point moving under `still`
    metres a frame. P is frames x 3."""
    P = np.asarray(P, dtype=float)
    if loop:
        v = np.roll(P, -1, axis=0) - P
        a = np.roll(v, -1, axis=0) - v
    else:
        v = np.diff(P, axis=0)
        a = np.diff(v, axis=0)
    sv, sa = np.linalg.norm(v, axis=1), np.linalg.norm(a, axis=1)
    if sv.max() <= still or len(sa) == 0:
        return None

    def crest(x):
        return float(x.max() / max(np.sqrt((x ** 2).mean()), 1e-12))
    return crest(sa) / crest(sv)


# ---------------------------------------------------------------- how the body drives a strike (2026-11-14)
# Ported from a craft rubric (the project's rubric_anim.py), whose measures were checked against broken
# and fixed controls before the user agreed to gate them: the hips lead the chest and the chest the arm (A2), the
# edge faces the cut (A4), the swing carries on past the hit (A5), the hips go down into it (A6).
DROP_NEED = {"h": 0.08, "v": 0.20, "spin": 0.08}      # hips drop as a share of the leg, by kind of strike
CHAIN_LINKS = ("hips", "chest", "arm", "hand")


def _qmul(a, b):
    w1, x1, y1, z1 = a
    w2, x2, y2, z2 = b
    return np.array([w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2, w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                     w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2])


def _turn_vector(q0, q1):
    """The turn from q0 to q1 (w, x, y, z) as axis times angle in degrees, the short way."""
    r = _qmul(np.asarray(q1, float), np.array([q0[0], -q0[1], -q0[2], -q0[3]], float))
    if r[0] < 0:
        r = -r
    s = float(np.linalg.norm(r[1:]))
    if s < 1e-12:
        return np.zeros(3)
    return r[1:] / s * np.degrees(2 * np.arctan2(s, r[0]))


def _parabolic(y, i):
    if 0 < i < len(y) - 1:
        d = y[i - 1] - 2 * y[i] + y[i + 1]
        if abs(d) > 1e-12:
            return i + 0.5 * (y[i - 1] - y[i + 1]) / d
    return float(i)


def strike_craft(tip, normal, edge, shoulder, hips_z, leg, links, fps, kind="h", start=0, end=None, impact=None):
    """How the body drives a weapon's strike. All per-frame arrays have one row per baked frame.

    tip, normal, edge, shoulder: weapon point, blade-plane normal, edge direction (unit), weapon-side shoulder.
    hips_z: hips height; leg: hip-joint height at rest. links: {name: quaternions (w, x, y, z)} for "hips" (in
    the world), "chest" (against the hips), "arm" (upper arm against the chest), "hand" (against the upper arm).
    kind: "h" a horizontal strike, "v" a vertical one, "spin" a whole-body turn.

    Speeds are forward differences: frame i's speed is from i to i+1. The fastest frame is searched from `start`
    to `end`; the strike is the run of frames round it at half that speed or more; the swing turns round at the
    first trough before it. Returns:
    - chain lags (A2): the frame each link turns fastest about its own swing axis (a parabola through the peak),
      relative to the link it hangs from, from 6 frames before the turn to 3 after the peak; a link that turns
      under 5 degrees there rides rigidly and lags 0. chain_lag_min/max take chest-hips and arm-chest for "h",
      only arm-chest for "v" (the hips need not turn) and "spin" (the hips turn with the whole body);
    - edge_off_plane_deg, edge_to_cut_deg (A4): the cut's direction out of the blade's plane, and against the
      edge, weighted by speed over the strike;
    - follow_deg, follow_frames (A5): after the hit (the later of the frame after the fastest and `impact`: with
      the hips leading, the point can peak a frame or two before the arm reaches its hit key, and those frames
      are still the strike) and a hold of up to 4 frames under a tenth of top speed, how far the point keeps
      turning about the shoulder the way the strike turned;
    - hips_drop_leg, hips_drop_margin (A6): the hips' lowest point under the first frame as a share of the leg,
      and that less DROP_NEED[kind].
    """
    T = np.asarray(tip, float)
    N_ = np.asarray(normal, float)
    E_ = np.asarray(edge, float)
    SH = np.asarray(shoulder, float)
    n = len(T)
    v = np.linalg.norm(np.diff(T, axis=0), axis=1) * fps
    end = n - 2 if end is None else min(end, n - 2)
    lo = min(max(start, 0), end)
    p = lo + int(np.argmax(v[lo:end + 1]))
    vmax = float(v[p])
    out = {"craft_kind": kind, "craft_peak_frame": p}
    if vmax <= 1e-9:
        return out
    turn = p
    while turn > 0 and v[turn - 1] <= v[turn]:
        turn -= 1
    s0 = p
    while s0 > 0 and v[s0 - 1] >= 0.5 * vmax:
        s0 -= 1
    s1 = p
    while s1 < len(v) - 1 and v[s1 + 1] >= 0.5 * vmax:
        s1 += 1
    # A4
    offs, leads, ws = [], [], []
    for i in range(s0, s1 + 1):
        d = T[i + 1] - T[i]
        d = d / max(np.linalg.norm(d), 1e-12)
        nm, ed = (N_[i] + N_[i + 1]) / 2, (E_[i] + E_[i + 1]) / 2
        offs.append(np.degrees(np.arcsin(min(1.0, abs(float(d @ nm)) / max(np.linalg.norm(nm), 1e-12)))))
        leads.append(np.degrees(np.arccos(np.clip(float(d @ ed) / max(np.linalg.norm(ed), 1e-12), -1, 1))))
        ws.append(v[i])
    ws = np.array(ws)
    out["edge_off_plane_deg"] = float(np.dot(offs, ws) / ws.sum())
    out["edge_to_cut_deg"] = float(np.dot(leads, ws) / ws.sum())
    # A5
    plane = np.cross(T[p] - SH[p], T[p + 1] - SH[p + 1])
    plane = plane / max(np.linalg.norm(plane), 1e-12)
    c, hold = max(p + 1, impact if impact is not None else 0), 0
    while c < n - 1 and hold < 4 and v[c] < 0.1 * vmax:
        c += 1
        hold += 1
    sweep, fol = 0.0, 0
    while c < n - 1:
        u0, u1 = T[c] - SH[c], T[c + 1] - SH[c + 1]
        st = float(np.degrees(np.arctan2(float(np.cross(u0, u1) @ plane), float(u0 @ u1))))
        if st <= 0.2:
            break
        sweep += st
        fol += 1
        c += 1
    out.update({"follow_deg": sweep, "follow_frames": fol, "follow_hold_frames": hold})
    # A2
    w0, w1 = max(0, turn - 6), min(n - 1, p + 3)
    peaks, turned = {}, {}
    for name in CHAIN_LINKS:
        Q = np.asarray(links[name], float)
        om = np.array([_turn_vector(Q[i], Q[i + 1]) for i in range(n - 1)])
        mean = om[max(turn, 0):w1].sum(0)
        axis = mean / max(np.linalg.norm(mean), 1e-9)
        sp = om @ axis
        k = w0 + int(np.argmax(sp[w0:w1]))
        peaks[name] = _parabolic(sp, k)
        turned[name] = float(np.clip(sp[w0:w1], 0, None).sum())

    def lag(child, parent):
        return 0.0 if turned[child] < 5.0 else peaks[child] - peaks[parent]

    lags = {"chest_hips": lag("chest", "hips"), "arm_chest": lag("arm", "chest")}
    used = [lags["chest_hips"], lags["arm_chest"]] if kind == "h" else [lags["arm_chest"]]
    out.update({"chain_peaks": peaks, "chain_turned_deg": turned, "chain_lag_chest_hips": lags["chest_hips"],
                "chain_lag_arm_chest": lags["arm_chest"], "chain_lag_min": min(used), "chain_lag_max": max(used)})
    # A6
    z = np.asarray(hips_z, float)
    drop = float(z[0] - z.min()) / leg if leg > 0 else 0.0
    out.update({"hips_drop_leg": drop, "hips_drop_margin": drop - DROP_NEED.get(kind, 0.08)})
    return out


# ---------------------------------------------------------------- body mechanics (2026-11-16)
G = 9.81


def airborne_runs(air, loop=True):
    """[(first, last)] frame runs where `air` is true (both feet off the ground), last inclusive. A loop's run that
    wraps round the end is joined with the one at the start."""
    air = list(bool(a) for a in air)
    n = len(air)
    if not n or all(air):
        return [(0, n - 1)] if n else []
    runs, i = [], 0
    while i < n:
        if air[i]:
            j = i
            while j + 1 < n and air[j + 1]:
                j += 1
            runs.append((i, j))
            i = j + 1
        else:
            i += 1
    if loop and len(runs) > 1 and runs[0][0] == 0 and runs[-1][1] == n - 1:
        runs = [(runs[-1][0], runs[0][1] + n)] + runs[1:-1]
    return runs


def ballistic(hips_z, air, fps, loop=True, min_frames=2):
    """How the hips rise while both feet are off the ground, against free fall. A flight of t seconds (from the last
    frame on the ground to the first frame back on it) carries the body g t^2 / 8 above the straight line between
    the two (taken on the same frames, so a sampled free fall scores 1); hips that rise less glide, more float. Returns ballistic_min and ballistic_max (rise over that need,
    over flights of at least min_frames airborne frames), flight_share (airborne frames over all), and the worst
    flight's rise and need in mm; None ratios when nothing flies.

    Why: Musoe's run had both feet up in 12 of its 16 frames and a 2.4 cm bob, which a flight of 0.29 s cannot
    have (10 cm); the gates measured pops and slides, so cutting the bob to pass them made it glide."""
    z = np.asarray(hips_z, float)
    n = len(z)
    out = {"flight_share": float(np.mean(np.asarray(air, bool))) if n else 0.0, "ballistic_min": None,
           "ballistic_max": None, "flight_rise_mm": None, "flight_need_mm": None}
    ratios = []
    for a, b in airborne_runs(air, loop):
        if b - a + 1 < min_frames:
            continue
        i0, i1 = a - 1, b + 1                          # last frame down, first frame down again
        if not loop and (i0 < 0 or i1 >= n):
            continue
        idx = np.arange(i0, i1 + 1)
        zz = z[idx % n]
        t = (i1 - i0) / fps
        chord = zz[0] + (zz[-1] - zz[0]) * (idx - i0) / (i1 - i0)
        rise = float((zz - chord).max())
        k = np.arange(1, i1 - i0)                      # the free-fall rise on the same frames (a peak can fall
        need = float((G / 2 * (k / fps) * ((i1 - i0 - k) / fps)).max())   # between two of them)
        ratios.append((rise / need, rise, need))
    if ratios:
        lo, hi = min(ratios), max(ratios)
        out.update(ballistic_min=lo[0], ballistic_max=hi[0], flight_rise_mm=lo[1] * 1000, flight_need_mm=lo[2] * 1000)
    return out


def _phase(x):
    """Phase (radians) and amplitude of a loop's first harmonic: the swing once per cycle, whatever its shape."""
    x = np.asarray(x, float)
    c = np.fft.rfft(x - x.mean())[1] if len(x) > 2 else 0j
    return float(np.angle(c)), float(abs(c)) * 2 / max(len(x), 1)


def arm_leg_opposition(arm, thigh, free, still_deg=2.0):
    """How each free arm swings against the opposite thigh in a loop (series of signed degrees, forward positive):
    the cosine of the phase lag between their once-a-cycle swings, 1 when the left arm comes forward with the right
    leg, -1 for a same-side swing; -1 for an arm that swings less than still_deg. Returns the least over the free
    arms, the largest lag in degrees and the free arms' least swing range (None values without a free arm).

    The phase of the first harmonic, not a correlation of the curves: a thigh held forward most of the cycle (high
    knees) is not a sinusoid, and a correlation of the curves scored a same-side swing above Musoe's own run."""
    cs, lags, rng = [], [], []
    for s in free:
        o = "R" if s == "L" else "L"
        pa, aa = _phase(arm[s])
        pt, at = _phase(thigh[o])
        lag = (pa - pt + np.pi) % (2 * np.pi) - np.pi
        ok = aa >= still_deg / 2 and at >= still_deg / 2
        cs.append(float(np.cos(lag)) if ok else -1.0)
        lags.append(abs(float(np.degrees(lag))) if ok else 180.0)
        rng.append(float(np.ptp(np.asarray(arm[s], float))))
    if not cs:
        return {"arm_leg_opposition": None, "arm_leg_lag_deg": None, "free_arm_swing_deg": None}
    return {"arm_leg_opposition": min(cs), "arm_leg_lag_deg": max(lags), "free_arm_swing_deg": min(rng)}


def free_arm_range(quats):
    """The largest turn between any two frames of one arm's orientation against the chest ([w, x, y, z] per frame),
    in degrees: a hand held still at the chest through a whole motion turns a few degrees."""
    q = np.asarray(quats, float)
    if len(q) < 2:
        return 0.0
    q = q / np.linalg.norm(q, axis=1, keepdims=True)
    d = np.abs(q @ q.T).clip(0, 1)
    return float(np.degrees(2 * np.arccos(d.min())))


def jump_phases(hips_z, air, fps, stand_z, leg, before=0.4, after=0.3, min_frames=3):
    """For a one-shot jump (a flight of at least min_frames): how far the hips sink in the `before` seconds ahead of
    leaving the ground (the crouch that launches it) and in the `after` seconds after touching down (the landing
    taken in the legs), each over the leg's length. None when nothing flies."""
    z = np.asarray(hips_z, float)
    runs = [(a, b) for a, b in airborne_runs(air, loop=False) if b - a + 1 >= min_frames and a > 0 and b < len(z) - 1]
    if not runs:
        return {"jump_crouch": None, "jump_absorb": None}
    a, b = max(runs, key=lambda r: r[1] - r[0])
    k0 = max(0, a - 1 - int(round(before * fps)))
    crouch = (stand_z - float(z[k0:a].min())) / leg
    k1 = min(len(z), b + 2 + int(round(after * fps)))
    absorb = (float(z[b + 1]) - float(z[b + 1:k1].min())) / leg
    return {"jump_crouch": crouch, "jump_absorb": absorb}
