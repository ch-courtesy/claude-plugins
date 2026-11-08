"""Concept-fidelity metrics on label images (0 = background)."""
import numpy as np


def iou(a, b):
    a, b = a > 0, b > 0
    union = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum() / union) if union else 1.0


def label_iou(A, B, labels=None):
    labels = labels or sorted((set(np.unique(A)) | set(np.unique(B))) - {0})
    out = {}
    for l in labels:
        a, b = A == l, B == l
        u = np.logical_or(a, b).sum()
        if u:
            out[int(l)] = float(np.logical_and(a, b).sum() / u)
    return out


def _contour(mask):
    p = np.pad(mask, 1)
    inner = p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    ys, xs = np.nonzero(mask & ~inner)
    return np.stack([xs, ys], 1).astype(float)


def contour_distance(A, B, pix, max_pts=900):
    """Symmetric mean and max (Hausdorff) distance between outlines, metres."""
    pa, pb = _contour(A > 0), _contour(B > 0)
    if not len(pa) or not len(pb):
        return float("inf"), float("inf")
    rng = np.random.default_rng(0)
    if len(pa) > max_pts:
        pa = pa[rng.choice(len(pa), max_pts, replace=False)]
    if len(pb) > max_pts:
        pb = pb[rng.choice(len(pb), max_pts, replace=False)]
    d = np.sqrt(((pa[:, None, :] - pb[None, :, :]) ** 2).sum(-1))
    ab, ba = d.min(1), d.min(0)
    return float((ab.mean() + ba.mean()) / 2 * pix), float(max(ab.max(), ba.max()) * pix)


def landmark(img, label, kind, pix, frame):
    """Height (metres, view-space v) of a labelled region's top/bottom/centre."""
    ys, _ = np.nonzero(img == label) if label else np.nonzero(img > 0)
    if not len(ys):
        return None
    row = {"top": ys.min(), "bottom": ys.max() + 1, "center": ys.mean() + 0.5}[kind]
    return float(frame.vmax - row * pix)


def score_view(model, target, frame, labels=None):
    mean_d, max_d = contour_distance(model, target, frame.pix)
    per = label_iou(model, target, labels)
    return {
        "iou": iou(model, target),
        "contour_mean_cm": mean_d * 100,
        "contour_max_cm": max_d * 100,
        "part_iou": per,
        "part_iou_mean": float(np.mean(list(per.values()))) if per else 1.0,
    }
