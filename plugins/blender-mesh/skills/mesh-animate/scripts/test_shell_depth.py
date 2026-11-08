"""Known shapes with known answers, so the contact check is tested before it is believed.

  blender -b --factory-startup --python-exit-code 1 --python test_shell_depth.py
"""
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_depth import inside, shell_depth, shells_of, tree  # noqa: E402


def cube(size, centre=(0, 0, 0)):
    """A cube of many small faces, so vertices lie across every side."""
    me = bpy.data.meshes.new("c")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=size)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=19, use_grid_fill=True)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=centre)
    bm.to_mesh(me)
    bm.free()
    return me


def sphere(radius, centre=(0, 0, 0)):
    me = bpy.data.meshes.new("s")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=5, radius=radius)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=centre)
    bm.to_mesh(me)
    bm.free()
    return me


def parts(me):
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    return [(co[s["verts"]], s["faces"], s["open_edges"]) for s in shells_of(me)]


def depth(a, b):
    (pa, fa, _), (pb, fb, _) = parts(a)[0], parts(b)[0]
    r = shell_depth(pa, fa, pb, fb)
    return None if r is None else r[0]


def near(name, got, want, tol):
    ok = got is not None and abs(got - want) <= tol
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {got} (want {want})")
    return ok


good = [
    near("sphere 10 mm into a cube", depth(sphere(0.1, (0, 0, 0.19)), cube(0.2)), 0.01, 0.0005),
    near("sphere 50 mm into a cube", depth(sphere(0.1, (0, 0, 0.15)), cube(0.2)), 0.05, 0.0005),
    near("order does not matter", depth(cube(0.2), sphere(0.1, (0, 0, 0.15))), 0.05, 0.0005),
    near("small sphere deep inside a cube", depth(sphere(0.02), cube(0.2)), 0.1, 0.03),
]
apart = depth(sphere(0.1, (0, 0, 0.21)), cube(0.2))
print(f"{'ok  ' if apart is None else 'FAIL'} separate shapes: {apart} (want None)")
good.append(apart is None)
# a coarse body with no vertex near the sunk part still counts through the other shape's vertices
plate = bpy.data.meshes.new("p")
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
bm.to_mesh(plate)
bm.free()
good.append(near("fine sphere 30 mm into a coarse box", depth(sphere(0.1, (0, 0, 0.57)), plate), 0.03, 0.0005))
# open shells are reported, because inside means nothing without a closed surface
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.faces[0]], context="FACES_ONLY")
open_me = bpy.data.meshes.new("o")
bm.to_mesh(open_me)
bm.free()
n = parts(open_me)[0][2]
print(f"{'ok  ' if n == 4 else 'FAIL'} open edges of a cube with one face gone: {n} (want 4)")
good.append(n == 4)
closed = parts(sphere(0.1))[0][2]
print(f"{'ok  ' if closed == 0 else 'FAIL'} open edges of a sphere: {closed} (want 0)")
good.append(closed == 0)
two = bpy.data.meshes.new("t")
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
r = bmesh.ops.create_cube(bm, size=1.0)
bmesh.ops.translate(bm, verts=r["verts"], vec=(3, 0, 0))
bm.to_mesh(two)
bm.free()
n = len(shells_of(two))
print(f"{'ok  ' if n == 2 else 'FAIL'} shells in two cubes: {n} (want 2)")
good.append(n == 2)
# points outside must stay outside however the rays land on the mesh's edges and corners
pts, faces, _ = parts(cube(0.2))[0]
bvh = tree(pts, faces)
grid = [Vector((x, y, z)) for x in np.linspace(0.12, 0.3, 19) for y in np.linspace(-0.2, 0.2, 21) for z in np.linspace(-0.2, 0.2, 21)]
wrong = sum(inside(bvh, p) for p in grid)
print(f"{'ok  ' if wrong == 0 else 'FAIL'} outside points called inside: {wrong} of {len(grid)} (want 0)")
good.append(wrong == 0)
print(f"[test] {sum(good)}/{len(good)} passed")
sys.exit(0 if all(good) else 1)
