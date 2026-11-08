"""Primitive builders shared by parametric models (numpy only).

All return data the rasteriser understands:
  leaf_tris / cylinder_tris -> (V (n,3), F (m,3))   for Canvas.triangles
  chain                     -> (C (n,3), R (n,))    for Canvas.spheres
  ellipsoids are passed straight to Canvas.ellipsoids(C, A, Rs, view, label)
"""
import math

import numpy as np


def frame_from(x_axis, z_hint):
    """3x3 rotation whose columns are X = x_axis, Z = closest to z_hint, Y = Z x X."""
    x = np.asarray(x_axis, float)
    x = x / np.linalg.norm(x)
    z = np.asarray(z_hint, float)
    z = z - x * (z @ x)
    z = z / np.linalg.norm(z)
    return np.stack([x, np.cross(z, x), z], 1)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1.0]])


def chain(p0, p1, r0, r1=None, n=10):
    """Sphere chain from p0 to p1 (a capsule / tapered limb)."""
    t = np.linspace(0, 1, n)[:, None]
    r1 = r0 if r1 is None else r1
    return np.asarray(p0, float) * (1 - t) + np.asarray(p1, float) * t, (r0 + (r1 - r0) * t).ravel()


def leaf_tris(base, frame, length, width, curl=0.2, bend=0.0, nu=16, nv=8):
    """Pointed leaf / ear / blade surface. Local X = length, Y = width, Z = cup."""
    t, s = np.meshgrid(np.linspace(0, 1, nu + 1), np.linspace(-1, 1, nv + 1), indexing="ij")
    w = width * np.sin(np.pi * (0.15 + 0.85 * t)) ** 0.7
    P = np.stack([t * length, s * w, curl * s ** 2 * w + bend * t * t * length], -1).reshape(-1, 3)
    V = np.asarray(base, float) + P @ np.asarray(frame, float).T
    i, j = np.meshgrid(np.arange(nu), np.arange(nv), indexing="ij")
    a = (i * (nv + 1) + j).ravel()
    F = np.concatenate([np.stack([a, a + 1, a + nv + 2], 1), np.stack([a, a + nv + 2, a + nv + 1], 1)])
    return V, F


def cylinder_tris(cx, cy, z0, z1, r, n=20, step=0.02):
    """Closed vertical cylinder; sides split every `step` m so the rasteriser leaves no gaps."""
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    ring = np.stack([cx + r * np.cos(a), cy + r * np.sin(a)], 1)
    zs = np.linspace(z0, z1, max(2, int(np.ceil(abs(z1 - z0) / step)) + 1))
    m = len(zs)
    V = np.concatenate([np.c_[ring, np.full(n, z)] for z in zs] + [[[cx, cy, z0], [cx, cy, z1]]])
    i = np.arange(n)
    j = (i + 1) % n
    sides = []
    for k in range(m - 1):
        b, tp = k * n, (k + 1) * n
        sides += [np.stack([b + i, b + j, tp + j], 1), np.stack([b + i, tp + j, tp + i], 1)]
    top = (m - 1) * n
    caps = [np.stack([np.full(n, m * n), j, i], 1), np.stack([np.full(n, m * n + 1), top + i, top + j], 1)]
    return V, np.concatenate(sides + caps)


def sym_phase(phase, n):
    """Angular offset keeping a ring of n bumps mirror-symmetric about x=0
    (needs 2*phase = n/2 mod 1: {0, .5} for even n, {.25, .75} for odd n)."""
    base = 0.0 if n % 2 == 0 else 0.25
    return base + 0.5 * round((phase - base) / 0.5)
