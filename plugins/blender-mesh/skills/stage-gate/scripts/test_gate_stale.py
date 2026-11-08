"""A report goes stale when any earlier stage is redone after it, not only the stage just before it.

  python test_gate_stale.py

Builds a session of empty files with chosen modification times and runs gate.py on it.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gate.py")
TIMES = {"session.json": 100, "rig/rig.blend": 200, "rig/report.json": 210, "uv/uv.blend": 300, "uv/report.json": 310,
         "texture/texture.blend": 400, "texture/report.json": 410, "motions/walk/motion.blend": 450,
         "motions/walk/report.json": 460, "motions/walk/prop/report.json": 470, "motions/library.blend": 500,
         "export/model.glb": 600, "export/report.json": 610, "export/unreal/report.json": 700}
STAGES = {"rigging": "rig/report.json", "uv": "uv/report.json", "texture": "texture/report.json",
          "animation": "anim/report.json", "prop_contact": "anim/prop/report.json", "export": "export/report.json",
          "engine_unreal": "export/unreal/report.json"}


def make(root, changed=None, missing=()):
    """A session whose files carry TIMES, with the times in `changed` instead and `missing` never made."""
    d = tempfile.mkdtemp(dir=root)
    for rel, t in TIMES.items():
        if rel in missing:
            continue
        fp = os.path.join(d, rel)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        with open(fp, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"v": 1}) if rel.endswith("report.json") else "{}")
        t = (changed or {}).get(rel, t)
        os.utime(fp, (t, t))
    return d


def passing(d, gates):
    out = {}
    for stage in STAGES:
        r = subprocess.run([sys.executable, "-I", GATE, d, stage, "--gates", gates, "--anim", "motions/walk"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        out[stage] = r.returncode == 0
    return out


root = tempfile.mkdtemp(prefix="gate_stale_")
good = []
try:
    gates = os.path.join(root, "gates.json")
    with open(gates, "w", encoding="utf-8") as fh:
        json.dump({k: [{"name": k, "file": f, "path": "v", "min": 1}] for k, f in STAGES.items()}, fh)
    everything, motion = set(STAGES), {"animation", "prop_contact"}
    cases = [  # name, files given other times, files never made, the stages that must still pass
        ("nothing redone", {}, (), everything),
        ("model edited", {"session.json": 800}, (), set()),
        ("rig redone after everything", {"rig/rig.blend": 800, "rig/report.json": 810}, (), {"rigging"}),
        ("UV redone", {"uv/uv.blend": 800, "uv/report.json": 810}, (), {"rigging", "uv"}),
        ("texture redone", {"texture/texture.blend": 800, "texture/report.json": 810}, (), {"rigging", "uv", "texture"}),
        ("walk baked again", {"motions/walk/motion.blend": 800, "motions/walk/report.json": 810}, (),
         everything - {"prop_contact"}),
        ("a motion added to the library", {"motions/library.blend": 800}, (), everything - {"export", "engine_unreal"}),
        ("GLB saved again but not checked", {"export/model.glb": 800}, (), everything - {"export", "engine_unreal"}),
        ("model edited after the rig, UV redone on the old rig", {"session.json": 250}, (), set()),
        ("check of an old GLB, newer than the texture", {"texture/texture.blend": 605, "texture/report.json": 606,
                                                         "motions/library.blend": 607}, (), {"rigging", "uv", "texture"}),
        ("a prop with no rig", {}, ("rig/rig.blend", "rig/report.json"), everything - {"rigging"}),
        ("a prop with no rig, edited after its UV", {"session.json": 350}, ("rig/rig.blend", "rig/report.json"), set()),
        ("no motions", {}, ("motions/walk/motion.blend", "motions/walk/report.json", "motions/walk/prop/report.json",
                            "motions/library.blend"), everything - motion),
    ]
    for name, changed, missing, want in cases:
        got = passing(make(root, changed, missing), gates)
        ok = {s for s, p in got.items() if p} == want
        good.append(ok)
        print(f"{'ok  ' if ok else 'FAIL'} {name}: passing {sorted(s for s, p in got.items() if p)}"
              + ("" if ok else f" (want {sorted(want)})"))
finally:
    shutil.rmtree(root, ignore_errors=True)
print(f"[test] {sum(good)}/{len(good)} passed")
sys.exit(0 if all(good) else 1)
