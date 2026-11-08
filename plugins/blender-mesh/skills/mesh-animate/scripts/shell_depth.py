"""How far closed shells pass into each other. Needs Blender's mathutils and NumPy.

A mesh made of overlapping parts has no single inside, so each connected shell is tested alone: a
point is inside a closed shell when a ray from it crosses the surface an odd number of times, and
its depth is the distance to that shell's surface.
"""
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

RAYS = [Vector(v).normalized() for v in ((0.27, 0.53, 0.80), (-0.71, 0.37, 0.59), (0.43, -0.81, 0.39))]


def shells_of(mesh):
    """Connected pieces of a mesh: vertex indices, faces renumbered inside the piece, open edges."""
    parent = list(range(len(mesh.vertices)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for e in mesh.edges:
        a, b = root(e.vertices[0]), root(e.vertices[1])
        if a != b:
            parent[a] = b
    groups = {}
    for i in range(len(mesh.vertices)):
        groups.setdefault(root(i), []).append(i)
    faces, counts = {}, {}
    for p in mesh.polygons:
        faces.setdefault(root(p.vertices[0]), []).append(p)
    for e in mesh.edges:
        counts[tuple(sorted(e.vertices))] = 0
    for p in mesh.polygons:
        for k in p.edge_keys:
            counts[tuple(sorted(k))] += 1
    out = []
    for key, verts in groups.items():
        index = {v: i for i, v in enumerate(verts)}
        polys = faces.get(key, [])
        materials = {}
        for p in polys:
            materials[p.material_index] = materials.get(p.material_index, 0) + 1
        out.append({"verts": np.array(verts), "faces": [[index[v] for v in p.vertices] for p in polys],
                    "material": max(materials, key=materials.get) if materials else 0,
                    "open_edges": sum(1 for k, n in counts.items() if n != 2 and k[0] in index)})
    return out


def tree(points, faces):
    return BVHTree.FromPolygons([tuple(p) for p in points.tolist()], faces, all_triangles=False, epsilon=0.0)


def crossings(bvh, point, ray):
    hits, origin = 0, point
    for _ in range(256):
        location = bvh.ray_cast(origin, ray)[0]
        if location is None:
            break
        hits += 1
        origin = location + ray * 1e-6
    return hits


def inside(bvh, point):
    """Three rays vote: one that grazes an edge can miscount a crossing and flip the answer."""
    return sum(crossings(bvh, point, ray) % 2 for ray in RAYS) >= 2


def into(points, bvh, low, high):
    """Deepest of the points inside a shell whose bounds are low..high: (depth, point) or None."""
    candidates = points[((points >= low) & (points <= high)).all(axis=1)]
    best = None
    for p in candidates.tolist():
        v = Vector(p)
        if inside(bvh, v):
            depth = bvh.find_nearest(v)[3]
            if best is None or depth > best[0]:
                best = (depth, p)
    return best


def shell_depth(a_points, a_faces, b_points, b_faces):
    """Deepest penetration between two closed shells, both ways: (depth, point), or None if they
    do not touch. Depth is 0.0 when surfaces cross with no vertex inside: touching, not sunk in."""
    a_low, a_high, b_low, b_high = a_points.min(0), a_points.max(0), b_points.min(0), b_points.max(0)
    if (a_high < b_low).any() or (b_high < a_low).any():
        return None
    a, b = tree(a_points, a_faces), tree(b_points, b_faces)
    found = [x for x in (into(a_points, b, b_low, b_high), into(b_points, a, a_low, a_high)) if x]
    if found:
        return max(found, key=lambda x: x[0])
    crossing = a.overlap(b)
    return (0.0, list(a_points[a_faces[crossing[0][0]][0]])) if crossing else None
