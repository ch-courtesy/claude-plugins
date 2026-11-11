"""An option given without its value stops with a message naming it, not a traceback.

  python test_options.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MESH = os.path.join(HERE, "mesh.py")
GATE = os.path.join(HERE, "..", "..", "stage-gate", "scripts", "gate.py")

sys.path.insert(0, HERE)
import mesh  # noqa: E402


def run(args):
    r = subprocess.run([sys.executable] + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout + r.stderr


good = []
with tempfile.TemporaryDirectory() as d:
    cases = [([MESH, d, "controls", "rig.json", "--carry"], "--carry needs a value"),
             ([MESH, d, "controls", "rig.json", "--carry", "c.json", "--prop-motion"], "--prop-motion needs a value"),
             ([MESH, d, "controls", "rig.json", "--attack", "a.json"], "needs --carry"),
             ([MESH, d, "controls", "rig.json", "--carry", "--attack", "a.json"], "--carry needs a value"),
             ([GATE, d, "modeling", "--gates"], "--gates needs a value")]
    for args, want in cases:
        code, out = run(args)
        ok = code != 0 and want in out and "Traceback" not in out
        good.append(ok)
        print(f"{'ok  ' if ok else 'FAIL'} {' '.join(args[2:])}: {out.strip().splitlines()[-1] if out.strip() else code}")
argv = ["x", "--map", "A=a", "--exposure", "-0.5", "--map", "B=b"]
maps = mesh.opts(argv, "--map")
exposure = mesh.opt(argv, "--exposure")
ok = maps == ["A=a", "B=b"] and exposure == "-0.5" and argv == ["x"]
good.append(ok)
print(f"{'ok  ' if ok else 'FAIL'} repeated options and a negative value: {maps} {exposure} {argv}")
print(f"[test] {sum(good)}/{len(good)} passed")
sys.exit(0 if all(good) else 1)
