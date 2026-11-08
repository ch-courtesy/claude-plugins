"""Undo puts the mirror and the tier back, through `mesh.py undo` and through an undo step in a steps
file; every step stores its mode state, and a session written before steps stored it still undoes.

  python test_undo_state.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import session_state  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MESH = os.path.join(HERE, "mesh.py")
STEPS = [{"op": "primitive", "args": {"type": "cube", "size": [0.4, 0.4, 0.4], "location": [0, 0, 0.2], "tier": "pc"}},
         {"op": "mirror", "args": {"axis": "x"}},
         {"op": "mirror", "args": {"mode": "apply"}},
         {"op": "subsurf", "args": {"levels": 1, "tier": "mobile"}}]


def session(d):
    with open(os.path.join(d, "session.json"), encoding="utf-8") as fh:
        return json.load(fh)


def save(d, S):
    with open(os.path.join(d, "session.json"), "w", encoding="utf-8") as fh:
        json.dump(S, fh, indent=1)


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
    S = session(a)
    stored = [s.get("state") for s in S["steps"]]
    want = [{"mirror": None, "tier": "pc"}, {"mirror": "x", "tier": "pc"}, {"mirror": None, "tier": "pc"},
            {"mirror": None, "tier": "mobile"}]
    good.append(stored == want and all(session_state.replayed(S["steps"][:k + 1]) == w for k, w in enumerate(want)))
    print(f"{'ok  ' if good[-1] else 'FAIL'} each step stores its state, and the history agrees: {stored}")
    seen = []
    for _ in range(3):
        subprocess.run([sys.executable, MESH, a, "undo"], capture_output=True)
        seen.append({k: session(a)[k] for k in ("mirror", "tier")})
    good.append(seen == want[2::-1])
    print(f"{'ok  ' if good[-1] else 'FAIL'} mesh.py undo, three times: {seen}")
    old = os.path.join(root, "old")
    build(old)
    S = session(old)
    for s in S["steps"]:
        s.pop("state")
    save(old, S)
    seen = []
    for _ in range(3):
        subprocess.run([sys.executable, MESH, old, "undo"], capture_output=True)
        seen.append({k: session(old)[k] for k in ("mirror", "tier")})
    good.append(seen == want[2::-1])
    print(f"{'ok  ' if good[-1] else 'FAIL'} a session from before steps stored their state: {seen}")
    b = os.path.join(root, "steps")
    build(b, [{"op": "undo", "args": {}}, {"op": "undo", "args": {}}])
    got = {k: session(b)[k] for k in ("mirror", "tier")}
    good.append(got == want[1])
    print(f"{'ok  ' if good[-1] else 'FAIL'} two undo steps in a steps file: {got} (want {want[1]})")
finally:
    shutil.rmtree(root, ignore_errors=True)
print(f"[test] {sum(good)}/{len(good)} passed")
sys.exit(0 if all(good) else 1)
