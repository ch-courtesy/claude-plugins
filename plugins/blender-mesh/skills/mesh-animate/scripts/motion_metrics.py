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
