"""Fast orthographic label rasteriser (numpy only).

Projects triangle meshes and sphere chains into label images with a
z-buffer, so each pixel knows which part is nearest the camera. Used in
place of a real render inside optimisation loops (~ms instead of seconds).
"""
import numpy as np

# world (x, y, z) -> (u right, v up, depth away from camera); character faces -Y
VIEWS = {
    "front": lambda P: (P[:, 0], P[:, 2], P[:, 1]),     # camera at -Y
    "back": lambda P: (-P[:, 0], P[:, 2], -P[:, 1]),    # camera at +Y
    "side": lambda P: (P[:, 1], P[:, 2], -P[:, 0]),     # camera at +X, face on the left
    "top": lambda P: (P[:, 0], P[:, 1], -P[:, 2]),      # camera at +Z, face at the bottom
}


# the same views as world-space axes: (u axis, v axis, depth axis)
BASIS = {
    "front": tuple(np.array(a, float) for a in ((1, 0, 0), (0, 0, 1), (0, 1, 0))),
    "back": tuple(np.array(a, float) for a in ((-1, 0, 0), (0, 0, 1), (0, -1, 0))),
    "side": tuple(np.array(a, float) for a in ((0, 1, 0), (0, 0, 1), (-1, 0, 0))),
    "top": tuple(np.array(a, float) for a in ((1, 0, 0), (0, 1, 0), (0, 0, -1))),
}


class Frame:
    """Square image window in view space: centre (cu, cv), size in metres."""

    def __init__(self, cu, cv, size, res):
        self.res, self.pix = res, size / res
        self.umin, self.vmax = cu - size / 2, cv + size / 2

    def to_px(self, u, v):
        return (np.floor((u - self.umin) / self.pix).astype(np.int64),
                np.floor((self.vmax - v) / self.pix).astype(np.int64))


def _bary(k):
    pts = [(i, j, k - i - j) for i in range(k + 1) for j in range(k + 1 - i)]
    return np.array(pts, float) / k


_BARY = {k: _bary(k) for k in range(1, 17)}


def _quarter(t):
    """Each triangle of a (n, 3) array of corner values as four, by the midpoints of its edges."""
    a, b, c = t[:, 0], t[:, 1], t[:, 2]
    ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
    return np.concatenate([np.stack(x, 1) for x in ((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca))])


class Canvas:
    def __init__(self, frame):
        self.f = frame
        self.idx, self.depth, self.label = [], [], []

    def _push(self, px, py, d, lab):
        r = self.f.res
        ok = (px >= 0) & (px < r) & (py >= 0) & (py < r)
        self.idx.append(py[ok] * r + px[ok])
        self.depth.append(d[ok])
        self.label.append(np.full(ok.sum(), lab, np.int16))

    def triangles(self, V, F, view, label):
        u, v, d = VIEWS[view](V)
        tu, tv, td = u[F], v[F], d[F]
        while True:                      # the sample table stops at 16 a side: halve what is larger
            edge = np.hypot(tu - np.roll(tu, 1, 1), tv - np.roll(tv, 1, 1)).max(1)
            big = edge / self.f.pix * 1.6 > 16
            if not big.any():
                break
            tu, tv, td = (np.concatenate((t[~big], _quarter(t[big]))) for t in (tu, tv, td))
        ks = np.clip(np.ceil(edge / self.f.pix * 1.6), 1, 16).astype(int)
        for k in np.unique(ks):          # sample density per triangle size
            sel = ks == k
            B = _BARY[int(k)]
            px, py = self.f.to_px((tu[sel] @ B.T).ravel(), (tv[sel] @ B.T).ravel())
            self._push(px, py, (td[sel] @ B.T).ravel(), label)

    def spheres(self, C, R, view, label):
        """Rasterise a batch of spheres at once (vectorised discs + depth)."""
        u, v, d = VIEWS[view](np.asarray(C, float))
        R = np.asarray(R, float)
        rp = R / self.f.pix
        n = int(np.ceil(rp.max()))
        oy, ox = np.mgrid[-n:n + 1, -n:n + 1]
        ox, oy = ox.ravel(), oy.ravel()
        d2 = ox ** 2 + oy ** 2
        inside = d2[None, :] <= (rp ** 2)[:, None]
        px0, py0 = self.f.to_px(u, v)
        dz = d[:, None] - np.sqrt(np.maximum(R[:, None] ** 2 - d2[None, :] * self.f.pix ** 2, 0))
        self._push((px0[:, None] + ox[None, :])[inside], (py0[:, None] + oy[None, :])[inside],
                   dz[inside], label)

    def ellipsoids(self, C, A, Rs, view, label):
        """Exact orthographic rasterisation of rotated ellipsoids.
        C (n,3) centres, A (n,3) semi-axes, Rs (n,3,3) rotations (columns = axes)."""
        U, Vv, D = BASIS[view]
        for c, a, R in zip(np.asarray(C, float), np.asarray(A, float), np.asarray(Rs, float)):
            Sig = R @ np.diag(a * a) @ R.T
            M = R @ np.diag(1 / (a * a)) @ R.T
            hu, hv = np.sqrt(U @ Sig @ U), np.sqrt(Vv @ Sig @ Vv)
            cu, cv = U @ c, Vv @ c
            x0, y1 = self.f.to_px(np.array([cu - hu]), np.array([cv - hv]))
            x1, y0 = self.f.to_px(np.array([cu + hu]), np.array([cv + hv]))
            xs = np.arange(max(x0[0], 0), min(x1[0] + 1, self.f.res))
            ys = np.arange(max(y0[0], 0), min(y1[0] + 1, self.f.res))
            if not len(xs) or not len(ys):
                continue
            PX, PY = np.meshgrid(xs, ys)
            u = self.f.umin + (PX.ravel() + 0.5) * self.f.pix
            v = self.f.vmax - (PY.ravel() + 0.5) * self.f.pix
            q = np.outer(u, U) + np.outer(v, Vv) - c
            qa = 2 * (q @ M @ D)
            qc = np.einsum("ij,jk,ik->i", q, M, q) - 1
            ad = D @ M @ D
            disc = qa * qa - 4 * ad * qc
            ok = disc >= 0
            t = (-qa[ok] - np.sqrt(disc[ok])) / (2 * ad)
            self._push(PX.ravel()[ok], PY.ravel()[ok], t, label)

    def image(self, close=True):
        r = self.f.res
        img = np.zeros(r * r, np.int16)
        if self.idx:
            idx = np.concatenate(self.idx)
            dep = np.concatenate(self.depth)
            lab = np.concatenate(self.label)
            order = np.lexsort((dep, idx))
            s = idx[order]
            first = np.r_[True, s[1:] != s[:-1]]
            img[s[first]] = lab[order][first]
        img = img.reshape(r, r)
        return fill_pinholes(img) if close else img


def fill_pinholes(img):
    """Fill isolated empty pixels surrounded by >= 6 labelled neighbours."""
    m = img > 0
    p = np.pad(img, 1)
    pm = p > 0
    nb = sum(np.roll(np.roll(pm, dy, 0), dx, 1)[1:-1, 1:-1]
             for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
    hole = (~m) & (nb >= 6)
    if hole.any():
        lab = np.zeros_like(img)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            cand = np.roll(np.roll(p, dy, 0), dx, 1)[1:-1, 1:-1]
            lab = np.where((lab == 0) & (cand > 0), cand, lab)
        img = np.where(hole, lab, img)
    return img
