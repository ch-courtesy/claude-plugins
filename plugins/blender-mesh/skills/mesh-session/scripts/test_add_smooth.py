"""A part added to a model shaded smooth is shaded smooth too; on a flat model it stays flat.

  python test_add_smooth.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mesh  # noqa: E402

CUBE = {"op": "primitive", "args": {"type": "cube", "size": [0.4, 0.4, 0.4], "location": [0, 0, 0.2]}}
ADD = {"op": "primitive", "args": {"type": "cube", "size": [0.2, 0.2, 0.2], "location": [0.6, 0, 0.1], "add": True}}
COUNT = ("import bpy; me = max((o for o in bpy.data.objects if o.type == 'MESH'), key=lambda o: len(o.data.polygons)).data; "
         "print('SMOOTH', sum(p.use_smooth for p in me.polygons), len(me.polygons))")


def smooth_faces(root, name, steps):
    d = os.path.join(root, name)
    os.makedirs(d)
    path = os.path.join(d, "steps.jsonl")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(json.dumps(s) for s in steps) + "\n")
    subprocess.run([sys.executable, mesh.__file__, d, "run", path, "--no-snap"], capture_output=True)
    with open(os.path.join(d, "session.json"), encoding="utf-8") as fh:
        current = json.load(fh)["current"]
    r = subprocess.run([mesh.find_blender(), "-b", os.path.join(d, current), "--python-expr", COUNT],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    line = [x for x in r.stdout.splitlines() if x.startswith("SMOOTH")]
    return tuple(int(x) for x in line[0].split()[1:]) if line else None


good = []
root = tempfile.mkdtemp(prefix="add_smooth_")
try:
    got = smooth_faces(root, "smooth", [CUBE, {"op": "subsurf", "args": {"levels": 1}}, ADD])
    good.append(got is not None and got[0] == got[1] == 12)
    print(f"{'ok  ' if good[-1] else 'FAIL'} part added after subsurf: smooth faces {got} (want 12 of 12)")
    got = smooth_faces(root, "flat", [CUBE, ADD])
    good.append(got is not None and got[0] == 0 and got[1] == 12)
    print(f"{'ok  ' if good[-1] else 'FAIL'} part added to a flat model: smooth faces {got} (want 0 of 12)")
finally:
    shutil.rmtree(root, ignore_errors=True)
print(f"[test] {sum(good)}/{len(good)} passed")
sys.exit(0 if all(good) else 1)
