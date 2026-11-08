"""Known layouts with known answers. Runs with any Python that has NumPy (Blender's has).

  blender -b --factory-startup --python-exit-code 1 --python test_uv_raster.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uv_raster import coverage  # noqa: E402

square = [[(0, 0), (1, 0), (1, 1)], [(0, 0), (1, 1), (0, 1)]]
half = [[(0, 0), (1, 0), (1, 1)]]
twice = square + square
cases = [("two triangles cover the square", coverage(square, [0, 0], 512)["utilisation"], 1.0),
         ("one triangle covers half", coverage(half, [0], 512)["utilisation"], 0.5),
         ("the same island folded onto itself", coverage(twice, [0, 0, 0, 0], 512)["overlap_any"], 1.0),
         ("a fold inside one island is no island overlap", coverage(twice, [0, 0, 0, 0], 512)["overlap_islands"], 0.0),
         ("two islands on the same place", coverage(twice, [0, 0, 1, 1], 512)["overlap_islands"], 1.0)]
good = 0
for name, got, want in cases:
    ok = abs(got - want) < 0.01
    good += ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {got:.3f} (want {want})")
print(f"[test] {good}/{len(cases)} passed")
sys.exit(0 if good == len(cases) else 1)
