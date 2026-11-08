"""UV coverage on a pixel grid: a pixel counts when its centre lies inside a triangle. The UV stage and the
asset review both use this, so a layout reads the same in both. Needs NumPy."""
import numpy as np


def coverage(tris, islands, res):
    """tris: (n, 3, 2) UV corners, 0 to 1 across the image; islands: one island id per triangle.

    Returns utilisation (share of pixels covered), overlap_any (share of covered pixels covered twice
    or more, folds inside an island included), overlap_islands (share claimed by two islands) and count
    (how many triangles cover each pixel, rows running with v)."""
    count = np.zeros((res, res), np.int32)
    owner = np.full((res, res), -2, np.int64)
    for tri, isl in zip(np.asarray(tris, float) * res, islands):
        x0, y0 = np.maximum(np.floor(tri.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(tri.max(0)).astype(int), res)
        if x1 <= x0 or y1 <= y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = tri
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        u = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
        v = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
        inside = (u >= 0) & (v >= 0) & (u + v <= 1)
        count[y0:y1, x0:x1] += inside
        block = owner[y0:y1, x0:x1]
        block[inside & (block >= 0) & (block != isl)] = -1
        block[inside & (block == -2)] = isl
    covered = int((count > 0).sum())
    return {"utilisation": covered / res ** 2,
            "overlap_any": float((count > 1).sum() / max(covered, 1)),
            "overlap_islands": float((owner == -1).sum() / max(covered, 1)), "count": count}
