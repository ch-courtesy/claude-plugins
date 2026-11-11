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
