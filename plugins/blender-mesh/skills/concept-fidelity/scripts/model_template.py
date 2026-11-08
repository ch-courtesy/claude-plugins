"""Template parametric blockout — copy next to your concept and edit.

A model module exposes:
  PARAMS  {name: (first guess, lo, hi)}   the bounds ARE modelling assumptions —
                                          make them wide enough to reach every pose
                                          the concept shows (a too-tight bound once made
                                          a tail tip unreachable)
  LABELS  {label id: name}                must match the concept's part labels
  Model   class with render(vec, views, frames) -> {view: label image}

World convention: Z up, character faces -Y, X is the character's left.
Use only analytic primitives (ellipsoids, sphere chains, triangle meshes) so the
3D build can reuse exactly the same geometry as the fit (see references/models.md).

This example is a generic creature: body, head, two arms, two legs.
"""
import numpy as np

from fid.raster import Canvas
from fid.shapes import chain

PARAMS = {
    "body_z": (0.55, 0.40, 0.70), "body_sx": (0.22, 0.12, 0.35), "body_sy": (0.18, 0.10, 0.30),
    "body_sz": (0.25, 0.15, 0.35),
    "head_y": (-0.02, -0.15, 0.10), "head_z": (0.95, 0.80, 1.10), "head_s": (0.18, 0.10, 0.26),
    "arm_x": (0.35, 0.20, 0.50), "arm_z": (0.45, 0.30, 0.65), "arm_r": (0.05, 0.03, 0.08),
    "leg_x": (0.10, 0.04, 0.18), "leg_r": (0.07, 0.04, 0.10),
}
NAMES = list(PARAMS)
GUESS = np.array([PARAMS[n][0] for n in NAMES])
LO = np.array([PARAMS[n][1] for n in NAMES])
HI = np.array([PARAMS[n][2] for n in NAMES])
LABELS = {1: "body", 2: "head", 3: "limbs"}
I3 = np.eye(3)


def primitives(vec):
    """Return [(kind, label, data)] with kind 'ell' | 'sph' | 'tris'."""
    p = dict(zip(NAMES, vec))
    ell = {1: ([(0, 0, p["body_z"])], [(p["body_sx"], p["body_sy"], p["body_sz"])], [I3]),
           2: ([(0, p["head_y"], p["head_z"])], [(p["head_s"],) * 3], [I3])}
    out = [("ell", lab, tuple(np.array(x, float) for x in data)) for lab, data in ell.items()]
    shoulder_z = p["body_z"] + p["body_sz"] * 0.6
    hip_z = p["body_z"] - p["body_sz"] * 0.6
    for s in (1, -1):
        out.append(("sph", 3, chain((s * p["body_sx"] * 0.8, 0, shoulder_z),
                                    (s * p["arm_x"], -0.03, p["arm_z"]), p["arm_r"], n=12)))
        out.append(("sph", 3, chain((s * p["leg_x"], 0, hip_z), (s * p["leg_x"], 0, p["leg_r"]),
                                    p["leg_r"], n=14)))
    return out


class Model:
    def render(self, vec, views, frames):
        prims = primitives(vec)
        imgs = {}
        for v in views:
            cv = Canvas(frames[v])
            for kind, lab, data in prims:
                {"ell": cv.ellipsoids, "sph": cv.spheres, "tris": cv.triangles}[kind](*data, v, lab)
            imgs[v] = cv.image()
        return imgs
