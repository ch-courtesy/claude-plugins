"""Undo puts the mirror back, through `mesh.py undo` and through an undo step in a steps file.

  python test_undo_state.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MESH = os.path.join(HERE, "mesh.py")
STEPS = [{"op": "primitive", "args": {"type": "cube", "size": [0.4, 0.4, 0.4], "location": [0, 0, 0.2], "tier": "pc"}},
         {"op": "mirror", "args": {"axis": "x"}},
         {"op": "mirror", "args": {"mode": "apply"}}]


def session(d):
    with open(os.path.join(d, "session.json"), encoding="utf-8") as fh:
        return json.load(fh)


def build(d, extra=()):
    os.makedirs(d)
    path = os.path.join(d, "steps.jsonl")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(json.dumps(s) for s in list(STEPS) + list(extra)) + "\n")
    subprocess.run([sys.executable, MESH, d, "run", path, "--no-snap"], capture_output=True)


good = []
root = tempfile.mkdtemp(prefix="undo_state_")
try:
    a = os.path.join(root, "command")
    build(a)
    before = session(a)["mirror"]
    subprocess.run([sys.executable, MESH, a, "undo"], capture_output=True)
    after = session(a)["mirror"]
    subprocess.run([sys.executable, MESH, a, "undo"], capture_output=True)
    first = session(a)["mirror"]
    good.append(before is None and after == "x" and first is None and session(a)["tier"] == "pc")
    print(f"{'ok  ' if good[-1] else 'FAIL'} mesh.py undo: applied {before}, undo -> {after}, undo -> {first}")
    b = os.path.join(root, "steps")
    build(b, [{"op": "undo", "args": {}}])
    good.append(session(b)["mirror"] == "x")
    print(f"{'ok  ' if good[-1] else 'FAIL'} undo step in a steps file: mirror {session(b)['mirror']} (want x)")
finally:
    shutil.rmtree(root, ignore_errors=True)
print(f"[test] {sum(good)}/{len(good)} passed")
sys.exit(0 if all(good) else 1)
