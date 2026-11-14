"""Geometry helpers for plan scripts that join parts which bend together into one surface (box-modeling,
references/continuous-body.md). Pure Python, no Blender: a plan imports it and writes ordinary mesh-session steps.

  sys.path.insert(0, "<skills>/box-modeling/scripts"); import joins

  joins.surface_point(section, y, z)          a point on a mirrored body section at (y, z), on its +x side
  joins.armhole(section, yc, zc, dy, dz, n)   n points of an elliptic hole on that surface, ring order of a limb
  joins.TubeRings(axis_origin, axis_dir, rows)  a limb drawn as rings along an axis (the overlapping-part design)
  joins.loft(hole, ring, tube, count)         rings from the hole to a ring of the limb that stay on the limb's
                                              drawn surface wherever that surface lies outside the straight blend
  joins.patch_steps(step, ...)                the steps that extrude a limb out of a 2 x 2 patch of the body

Why: a limb made as its own tube and pushed into the body only overlaps it. Nothing can blend across the joint, so the
shoulder or hip cannot fold smoothly, and raising the limb opens the overlap. A limb grown out of the body's own faces
is one surface; its first rings follow the hole, then blend into the drawn rings, so the silhouette stays the drawing's.
"""
import math


def _bisect(f, lo, hi, it=50):
    """The root of f between lo and hi (f(lo) and f(hi) of opposite sign)."""
    flo = f(lo)
    for _ in range(it):
        mid = (lo + hi) / 2
        fm = f(mid)
        if (fm < 0) == (flo < 0):
            lo, flo = mid, fm
        else:
            hi = mid
    return (lo + hi) / 2


def surface_point(section, y, z):
    """The point on the +x side of a mirrored body at height z whose y is `y`. `section(theta, z)` gives (x, y) on
    the body's outline at angle theta (0 the front seam, pi the back seam), y growing with theta."""
    th = _bisect(lambda t: section(t, z)[1] - y, 1e-4, math.pi - 1e-4)
    x, _ = section(th, z)
    return [x, y, z]


def inside_section(section, z_lo, z_hi, samples=96):
    """inside(p) for a mirrored body given by section(theta, z) between heights z_lo and z_hi: p (either side) is
    inside when it lies within the outline at its height."""
    def inside(p):
        x, y, z = abs(p[0]), p[1], p[2]
        if not z_lo <= z <= z_hi:
            return False
        pts = [section(math.pi * k / samples, z) for k in range(samples + 1)]
        pts = [(0.0, pts[0][1])] + pts + [(0.0, pts[-1][1])]
        hit = False                                    # even-odd rule on the closed outline
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
            if (y0 > y) != (y1 > y) and x < x0 + (x1 - x0) * (y - y0) / (y1 - y0):
                hit = not hit
        return hit
    return inside


def armhole(section, yc, zc, dy, dz, n=8):
    """n points of an ellipse on the body's surface, centred at (yc, zc), half depth dy and half height dz. Point 0 is
    the top, then towards +y (the back): the order of a limb ring whose point 0 faces up and point n/4 faces +y."""
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        out.append(surface_point(section, yc + dy * math.sin(t), zc + dz * math.cos(t)))
    return out


class TubeRings:
    """A limb drawn as closed rings of n points each, at distances s along an axis (origin o, unit direction a).
    rows: [(s, ring)]. Gives the drawn surface's distance from the axis along each of the n lines, at any s."""

    def __init__(self, o, a, rows):
        self.o, self.a = list(o), list(a)
        self.rows = sorted(rows, key=lambda r: r[0])

    def axis(self, s):
        return [self.o[j] + self.a[j] * s for j in range(3)]

    def along(self, p):
        return sum((p[j] - self.o[j]) * self.a[j] for j in range(3))

    def radius(self, i, s):
        """Distance of line i from the axis at s, linear between rows (held at the ends)."""
        rs = [(s_, math.dist(ring[i], self.axis(s_))) for s_, ring in self.rows]
        if s <= rs[0][0]:
            return rs[0][1]
        for (s0, r0), (s1, r1) in zip(rs, rs[1:]):
            if s <= s1:
                return r0 + (r1 - r0) * (s - s0) / (s1 - s0)
        return rs[-1][1]


def loft(hole, ring, tube, count, at=None, inside=None, min_step=0.0):
    """`count` rings between `hole` and `ring` (same point order). Point i of ring k is the straight blend at
    u = k / (count + 1) (or at[k - 1]), then pushed out from the limb's axis to the drawn surface if the blend fell
    inside it, so a bulge the drawing has near the joint (a deltoid) is kept. Points are only ever pushed outwards.
    A first ring close to the hole (at = [0.15, ...]) catches a bulge that sits right at the joint.
    inside(p): True where p is inside the body. Where the drawn limb runs inside the body (an armpit: the drawn sleeve
    went into the torso there) a pushed point would land inside the body and fold the new surface back onto it, so
    such a point keeps its straight blend.
    min_step: ring k lies at least k * min_step metres from the hole on every line, but never past the even spacing
    k / (count + 1). A limb that leaves the body at an angle has short lines on its inner side (the armpit of an arm
    hanging 40 degrees down); without this its rings bunch up there into a crease that stretches several times over
    when the limb is raised."""
    out = []
    for k in range(1, count + 1):
        u0 = at[k - 1] if at else k / (count + 1)
        pts = []
        for i, (p, q) in enumerate(zip(hole, ring)):
            length = math.dist(p, q)
            u = u0
            if min_step and length > 1e-9:
                u = max(u0, min(k * min_step / length, k / (count + 1)))
            b = [p[j] + (q[j] - p[j]) * u for j in range(3)]
            s = tube.along(b)
            c = tube.axis(s)
            d = [b[j] - c[j] for j in range(3)]
            r = math.sqrt(sum(x * x for x in d))
            want = tube.radius(i, s)
            if r < want and r > 1e-9:
                pushed = [c[j] + d[j] * want / r for j in range(3)]
                if inside is None or not inside(pushed):
                    b = pushed
            pts.append([round(x, 4) for x in b])
        out.append(pts)
    return out


def patch_steps(step, name, patch_where, count, hole, rings, vec):
    """Steps that grow a limb out of the body: select the 2 x 2 patch of faces (`patch_where`, a mesh-select
    `where`, expected to give `count` faces), put its border on the hole, then extrude it ring by ring onto `rings`
    (each a list of points; the outline step keeps the point order nearest to the previous ring). Faces made are
    named <name>_c<k>_sides (the walls) and <name>_c<k> (the end cap); returns those names for a region selection."""
    step("select", name + "_patch", {"selected": count}, name=name + "_c0", where=patch_where)
    step("transform", name + "_hole", sel=name + "_c0", outline=hole)
    names = []
    for k, ring in enumerate(rings, 1):
        step("extrude", f"{name}_{k}", sel=f"{name}_c{k - 1}", vector=list(vec), result=f"{name}_c{k}")
        step("transform", f"{name}_shape{k}", sel=f"{name}_c{k}", outline=ring)
        names.append(f"{name}_c{k}_sides")
    return names + [f"{name}_c{len(rings)}"]
