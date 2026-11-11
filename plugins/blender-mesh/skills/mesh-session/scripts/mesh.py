"""mesh.py — one entry point for step-by-step modelling sessions (system Python, stdlib only).

  python mesh.py SESSION OP '<json args>' [LABEL]       one modelling step (runs meshop.py in Blender)
  python mesh.py SESSION run STEPS.jsonl [--strict] [--no-snap] [--from N]
                                                        run a steps file in ONE Blender process, stop
                                                        at the first error (--strict: also at a warning)
  python mesh.py SESSION undo [N]                       step back N steps (default 1), files removed
  python mesh.py SESSION status                         current step, counts, last checks
  python mesh.py SESSION export OUT.jsonl [--expect faces|full|none]
                                                        the session as a replayable steps file
  python mesh.py SESSION report [--pick 9] [--html]     report.md + construction.png (+ .html)
  python mesh.py SESSION finish [--tier pc] [--res 900] [--samples 96] [--exposure 0] [--asymmetric]
                                                        render + 3d-asset-review inspector + report
  python mesh.py SESSION fidelity CONCEPT_DIR [--map Material=part ...]
                                                        measure the current step against a concept
                                                        turnaround (concept-fidelity), into SESSION/fidelity
  python mesh.py SESSION rig SPEC.json                  bones, weights, pose tests and pose sheet (mesh-rig)
  python mesh.py SESSION uv [--angle 66] [--margin .002]  unwrap the rigged model and measure the layout (mesh-uv)
  python mesh.py SESSION texture CONCEPT_DIR [--map Material=part ...]
                                                        paint the UV'd model from the concept (mesh-texture)
  python mesh.py SESSION glb [--spec RIG.json] [--concept DIR --map M=part ...] [--carry CARRY.json]
                                                        export GLB, read it back, measure it (mesh-export)
  python mesh.py SESSION animate MOTION.json RIG.json   bake a motion and measure it (mesh-animate);
      [--carry CARRY.json]                              with a held weapon, measure its strike
  python mesh.py SESSION controls RIG.json [--carry CARRY.json] [--attack ATTACK.json]
                                                        motions made wrong on purpose must fail their gates
  python mesh.py SESSION propcheck MOTION CARRY.json    does a carried prop pass through the body (mesh-animate)
  python mesh.py SESSION unreal [--engine DIR --warm 30 --ddc DIR]
                                                        open the GLB in Unreal and measure it (mesh-export)
  python mesh.py SESSION gate STAGE [--note TEXT]       score a stage against its fixed thresholds (stage-gate)
  python mesh.py SESSION gate --history [STAGE]         every attempt so far
  python mesh.py selftest [--keep DIR] [--only NAME]    replay assets/selftest/*.steps.jsonl and check
  python mesh.py compare A B [--exact]                  two sessions step by step: same shape, or
                                                        (--exact) identical including element order

Steps file: one JSON object per line, {"op": ..., "args": {...}, "label": ..., "expect": {...}};
blank lines and lines starting with # are ignored. `expect` keys are stats (verts, faces,
quads, tris, ngons, non_manifold, tris_eval, warnings) or the op's result keys; a value is
exact, or [min, max] with null for open ends. A step whose expectation fails is rejected.

Blender is found from $BLENDER, PATH, or the standard install folders.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import session_state  # noqa: E402


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


SKILLS = os.path.dirname(os.path.dirname(HERE))
MESHOP = os.path.join(HERE, "meshop.py")
for s in (sys.stdout, sys.stderr):
    try:
        s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


def find_blender():
    if os.environ.get("BLENDER") and os.path.exists(os.environ["BLENDER"]):
        return os.environ["BLENDER"]
    on_path = shutil.which("blender")
    if on_path:
        return on_path
    cands = glob.glob(r"C:\Program Files\Blender Foundation\Blender*\blender.exe")
    cands += glob.glob("/Applications/Blender*.app/Contents/MacOS/Blender")
    cands += glob.glob(os.path.expanduser("~/blender*/blender")) + glob.glob("/opt/blender*/blender")

    def ver(p):
        return [int(x) for x in re.findall(r"\d+", p)] or [0]
    cands.sort(key=ver, reverse=True)
    if not cands:
        sys.exit("[mesh] Blender not found: set BLENDER=/path/to/blender")
    return cands[0]


def blender_run(args, env=None):
    """Run Blender in the background, streaming our own log lines and any Python traceback.
    Returns (returncode, full output)."""
    p = subprocess.Popen([find_blender(), "-b"] + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace", env=env)
    lines, tb = [], False
    for line in p.stdout:
        line = line.rstrip("\n")
        lines.append(line)
        if line.startswith("Traceback"):
            tb = True
        if tb or line.startswith(("[meshop", "[render_session", "[inspect", "[compare", "[rig", "[uv", "[texture", "[export", "[anim", "[prop")):
            print(line, flush=True)
        if tb and line and not line.startswith((" ", "Traceback")):
            tb = False
    p.wait()
    return p.returncode, "\n".join(lines)


def step(sdir, op, args, label=""):
    """One modelling step. Returns True when it was done."""
    code, out = blender_run(["--factory-startup", "--python", MESHOP, "--", sdir, op,
                             json.dumps(args, ensure_ascii=False), label])
    return code == 0 and "[meshop] ERROR" not in out and "Traceback" not in out


def load_session(sdir):
    p = os.path.join(sdir, "session.json")
    if not os.path.exists(p):
        sys.exit(f"[mesh] no session at {sdir}")
    return read_json(p, encoding="utf-8")


def cmd_run(sdir, path, strict=False, nosnap=False, start=1):
    """The whole steps file in ONE Blender process (see meshop.run_file)."""
    args = ["--factory-startup", "--python", MESHOP, "--", sdir, "--run", os.path.abspath(path)]
    if strict:
        args.append("--strict")
    if start > 1:
        args += ["--from", str(start)]
    t0 = time.time()
    _, out = blender_run(args, dict(os.environ, MESHOP_NOSNAP="1") if nosnap else None)
    ok = "\n[meshop] ran " in "\n" + out
    print(f"[mesh] {'finished' if ok else 'stopped'} after {time.time() - t0:.1f}s")
    mark = os.path.join(sdir, "stopped.txt")           # the gate refuses a build that did not finish
    if ok:
        if os.path.exists(mark):
            os.remove(mark)
    else:
        why = [x for x in out.splitlines() if "stopped at" in x or "ERROR" in x]
        with open(mark, "w", encoding="utf-8") as fh_:
            fh_.write((why[-1] if why else "the run did not finish") + "\n")
    return ok


def cmd_undo(sdir, count=1):
    S = load_session(sdir)
    for _ in range(count):
        if len(S["steps"]) < 2:
            print("[mesh] nothing more to undo")
            break
        gone = session_state.undo(S, sdir)
        print(f"[mesh] undone {gone['n']:03d} {gone['op']} {gone.get('label', '')}")
    with open(os.path.join(sdir, "session.json"), "w", encoding="utf-8") as fh_:
        json.dump(S, fh_, indent=1)
    print(f"[mesh] current -> {S['current']}")


def cmd_status(sdir):
    S = load_session(sdir)
    last = S["steps"][-1]
    st = last["stats"]
    print(f"[mesh] {len(S['steps'])} steps, current {S['current']}; mirror {S.get('mirror')}, tier {S.get('tier')}, "
          f"active sel {S.get('active')}")
    print(f"[mesh] cage v {st['verts']} f {st['faces']} (q {st['quads']} t {st['tris']} n {st['ngons']}), "
          f"eval tris {st['tris_eval']}, non-manifold {st['non_manifold']}")
    warned = [(s["n"], c) for s in S["steps"] for c in s.get("checks", [])]
    print(f"[mesh] check warnings in history: {len(warned)}")
    for n, c in warned[-8:]:
        print(f"[mesh]   {n:03d} {c['kind']}: {c['msg']}")


def cmd_export(sdir, out, expect="faces"):
    S = load_session(sdir)
    keys = {"faces": ("faces", "non_manifold"), "full": ("verts", "faces", "quads", "tris", "ngons", "non_manifold",
                                                         "tris_eval"), "none": ()}[expect]
    full = ("verts", "faces", "quads", "tris", "ngons", "non_manifold", "tris_eval")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(f"# exported from {os.path.basename(os.path.abspath(sdir))}: {len(S['steps'])} steps\n")
        for k, s in enumerate(S["steps"]):
            line = {"op": s["op"], "args": s["args"], "label": s.get("label", "")}
            ks = full if (k == len(S["steps"]) - 1 and expect != "none") else keys
            if ks:
                line["expect"] = {x: s["stats"][x] for x in ks}
            fh.write(json.dumps(line, ensure_ascii=False) + "\n")
    print(f"[mesh] wrote {out} ({len(S['steps'])} steps, expect={expect})")


def pillow_python(sdir=None):
    S = load_session(sdir) if sdir and os.path.exists(os.path.join(sdir, "session.json")) else {}
    cands = [S["py"]] if S.get("py") else []
    if os.environ.get("MESHOP_PYTHON"):
        cands.append(os.environ["MESHOP_PYTHON"])
    cands += [sys.executable, "py -3", "python3", "python"]
    cands += sorted(glob.glob(r"C:\Program Files\Python3*\python.exe"), reverse=True)
    for c in cands:
        cmd = c.split(" ") if c.startswith("py ") else [c]
        try:
            if subprocess.run(cmd + ["-I", "-c", "import PIL"], capture_output=True, timeout=30).returncode == 0:
                return cmd
        except (OSError, subprocess.TimeoutExpired):
            continue
    return None


def cmd_report(sdir, extra):
    py = pillow_python(sdir)
    if py is None:
        sys.exit("[mesh] report needs a Python with Pillow (set MESHOP_PYTHON)")
    r = subprocess.run(py + ["-I", os.path.join(HERE, "session_report.py"), sdir] + extra, capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    print((r.stdout or "") + (r.stderr or ""), end="")
    return r.returncode == 0


def clear_reports(sdir, *rels):
    """A stage's old reports go before it runs again, so a run that fails leaves nothing old to pass a gate.
    Every stage writes its report last, after the files it saves."""
    for rel in rels:
        fp = os.path.join(sdir, rel)
        if os.path.exists(fp):
            os.remove(fp)


def made(sdir, rel):
    """Whether a stage's report is there after its run, said aloud when it is not."""
    ok = os.path.exists(os.path.join(sdir, rel))
    if not ok:
        print(f"[mesh] the run failed: no {rel}")
    return ok


def opt(argv, name, default=None, cast=str):
    if name in argv:
        i = argv.index(name)
        val = argv[i + 1]
        del argv[i:i + 2]
        return cast(val)
    return default


def cmd_finish(sdir, argv):
    tier = opt(argv, "--tier", "pc")
    res, samples = opt(argv, "--res", "900"), opt(argv, "--samples", "96")
    exposure = opt(argv, "--exposure", "0")
    declared = ["--asymmetric"] if "--asymmetric" in argv else []
    S = load_session(sdir)
    clear_reports(sdir, os.path.join("review", "report.json"))
    out = os.path.join(sdir, "render.png")
    blender_run(["--python", os.path.join(HERE, "render_session.py"), "--", sdir, out, "--res", res,
                 "--samples", samples, "--exposure", exposure])
    insp = os.path.join(SKILLS, "3d-asset-review", "scripts", "inspect_model.py")
    if os.path.exists(insp):
        blender_run([os.path.join(sdir, S["current"]), "--python", insp, "--",
                     os.path.join(sdir, "review"), "--tier", tier, "--no-render"] + declared)
    else:
        print("[mesh] 3d-asset-review not installed next to this skill — review skipped")
    cmd_report(sdir, ["--html"])


def cmd_fidelity(sdir, argv):
    """Project the current step into a concept's views and score it (concept-fidelity skill)."""
    scripts = os.path.join(SKILLS, "concept-fidelity", "scripts")
    if not os.path.exists(os.path.join(scripts, "compare_model.py")):
        sys.exit("[mesh] concept-fidelity is not installed next to this skill")
    S = load_session(sdir)
    out = os.path.join(sdir, "fidelity")
    clear_reports(sdir, os.path.join("fidelity", "compare.json"))
    maps = []
    while "--map" in argv:
        i = argv.index("--map")
        maps.append(argv[i + 1])
        del argv[i:i + 2]
    extra = ["--map"] + maps if maps else []
    blender_run([os.path.join(sdir, S["current"]), "--python", os.path.join(scripts, "compare_model.py"), "--",
                 "--concept", os.path.abspath(argv[0]), "--out", out, "--object", S["object"]] + extra + argv[1:])
    py = pillow_python(sdir)
    if py is None:
        sys.exit("[mesh] the sheet needs a Python with Pillow (set MESHOP_PYTHON)")
    r = subprocess.run(py + ["-I", os.path.join(scripts, "compare_sheet.py"), out], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    print((r.stdout or "") + (r.stderr or ""), end="")
    return made(sdir, os.path.join("fidelity", "compare.json"))


def cmd_rig(sdir, argv):
    """Rig the current step and bend it through the spec's test poses (mesh-rig skill)."""
    scripts = os.path.join(SKILLS, "mesh-rig", "scripts")
    S = load_session(sdir)
    out = os.path.join(sdir, "rig")
    clear_reports(sdir, os.path.join("rig", "report.json"))
    blender_run([os.path.join(sdir, S["current"]), "--python", os.path.join(scripts, "rig_session.py"), "--",
                 "--spec", os.path.abspath(argv[0]), "--out", out, "--object", S["object"]])
    py = pillow_python(sdir)
    if py:
        r = subprocess.run(py + ["-I", os.path.join(scripts, "pose_sheet.py"), out], capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        print((r.stdout or "") + (r.stderr or ""), end="")
    return made(sdir, os.path.join("rig", "report.json"))


def cmd_uv(sdir, argv):
    """Unwrap the newest stage file of the session (mesh-uv skill)."""
    S = load_session(sdir)
    rigged = os.path.join(sdir, "rig", "rig.blend")
    src = rigged if os.path.exists(rigged) else os.path.join(sdir, S["current"])
    clear_reports(sdir, os.path.join("uv", "report.json"))
    blender_run([src, "--python", os.path.join(SKILLS, "mesh-uv", "scripts", "uv_session.py"), "--",
                 "--out", os.path.join(sdir, "uv"), "--object", S["object"]] + argv)
    return made(sdir, os.path.join("uv", "report.json"))


def cmd_texture(sdir, argv):
    """Paint the unwrapped model from the concept's panels (mesh-texture skill)."""
    S = load_session(sdir)
    maps = []
    while "--map" in argv:
        i = argv.index("--map")
        maps.append(argv[i + 1])
        del argv[i:i + 2]
    extra = ["--map"] + maps if maps else []
    clear_reports(sdir, os.path.join("texture", "report.json"))
    blender_run([os.path.join(sdir, "uv", "uv.blend"), "--python",
                 os.path.join(SKILLS, "mesh-texture", "scripts", "texture_session.py"), "--",
                 "--concept", os.path.abspath(argv[0]), "--out", os.path.join(sdir, "texture"),
                 "--object", S["object"]] + extra + argv[1:])
    return made(sdir, os.path.join("texture", "report.json"))


def cmd_glb(sdir, argv):
    """Export the textured model and verify the file by importing it again (mesh-export skill)."""
    S = load_session(sdir)
    spec = opt(argv, "--spec")
    concept = opt(argv, "--concept")
    height = opt(argv, "--height")
    carry = opt(argv, "--carry")                       # a gripped prop: its socket goes into the skeleton
    clear = []
    while "--see-through" in argv:
        i = argv.index("--see-through")
        clear.append(argv[i + 1])
        del argv[i:i + 2]
    maps = []
    while "--map" in argv:
        i = argv.index("--map")
        maps.append(argv[i + 1])
        del argv[i:i + 2]
    out = os.path.join(sdir, "export")
    extra = (["--spec", os.path.abspath(spec)] if spec else []) + (["--height", height] if height else []) \
        + (["--carry", os.path.abspath(carry)] if carry else [])
    library = os.path.join(sdir, "motions", "library.blend")
    if library_is_stale(sdir):
        sys.exit("[mesh] motions/library.blend is older than the texture: bake the motions again before exporting")
    src = library if os.path.exists(library) else os.path.join(sdir, "texture", "texture.blend")
    clear_reports(sdir, os.path.join("export", "report.json"), os.path.join("export", "fidelity", "compare.json"))
    glb = os.path.join(out, "model.glb")
    old_glb = os.path.getmtime(glb) if os.path.exists(glb) else None
    blender_run([src, "--python",
                 os.path.join(SKILLS, "mesh-export", "scripts", "export_session.py"), "--",
                 "--out", out, "--object", S["object"]] + extra)
    if not os.path.exists(glb) or os.path.getmtime(glb) == old_glb:
        print("[mesh] the export failed: no new export/model.glb")       # checking the old file would pass it
        return False
    blender_run(["--python", os.path.join(SKILLS, "mesh-export", "scripts", "check_glb.py"), "--",
                 os.path.join(out, "model.glb"), os.path.join(out, "report.json")])
    if concept:
        scripts = os.path.join(SKILLS, "concept-fidelity", "scripts")
        blender_run([os.path.join(out, "check.blend"), "--python", os.path.join(scripts, "compare_model.py"), "--",
                     "--concept", os.path.abspath(concept), "--out", os.path.join(out, "fidelity"),
                     "--object", S["object"]] + (["--map"] + maps if maps else [])
                    + (["--see-through"] + clear if clear else []))
        before = read_json(os.path.join(sdir, "fidelity", "compare.json"), encoding="utf-8")
        after = read_json(os.path.join(out, "fidelity", "compare.json"), encoding="utf-8")
        drop = max(before["views"][v]["iou"] - after["views"][v]["iou"] for v in after["views"])
        rp = os.path.join(out, "report.json")
        R = read_json(rp, encoding="utf-8")
        R["iou_drop"] = drop
        with open(rp, "w", encoding="utf-8") as fh_:
            json.dump(R, fh_, ensure_ascii=False, indent=1)
        print(f"[export] silhouette IoU drop after the round trip: {drop:.4f}")
    return made(sdir, os.path.join("export", "report.json"))


def library_is_stale(sdir):
    library = os.path.join(sdir, "motions", "library.blend")
    texture = os.path.join(sdir, "texture", "texture.blend")
    return os.path.exists(library) and os.path.exists(texture) and os.path.getmtime(library) < os.path.getmtime(texture)


def renamed(spec, names):
    """A control written for one rig, with its bone and material names swapped for this rig's."""
    text = json.dumps(spec, ensure_ascii=False)
    for old, new in names.items():
        text = text.replace(f'"{old}"', f'"{new}"')
    return json.loads(text)


def cmd_animate(sdir, argv):
    """Bake one motion, then check its frames with the rig's deformation test (mesh-animate skill).
    Motions collect in SESSION/motions/library.blend; each has its own folder for reports."""
    S = load_session(sdir)
    carry = opt(argv, "--carry")                       # a held weapon: the strike measures its point
    spec_path, rig = os.path.abspath(argv[0]), os.path.abspath(argv[1])
    spec_json = read_json(spec_path, encoding="utf-8")
    name = spec_json.get("name", "motion")
    root = os.path.join(sdir, "motions")
    out = os.path.join(root, name)
    os.makedirs(out, exist_ok=True)
    library = os.path.join(root, "library.blend")
    if library_is_stale(sdir):                         # its mesh is the old one: start again from the texture
        print("[mesh] motions/library.blend is older than the texture: starting it again, bake the other motions too")
        os.remove(library)
    source = library if os.path.exists(library) else os.path.join(sdir, "texture", "texture.blend")
    # results of an earlier bake go first: if this one fails, nothing old is left to pass a gate
    for old in ("report.json", "poses.json", os.path.join("check", "report.json"), os.path.join("prop", "report.json")):
        if os.path.exists(os.path.join(out, old)):
            os.remove(os.path.join(out, old))
    blender_run([source, "--python", os.path.join(SKILLS, "mesh-animate", "scripts", "anim_session.py"), "--",
                 "--spec", spec_path, "--rig", rig, "--out", out, "--library", library, "--object", S["object"]]
                + (["--carry", os.path.abspath(carry)] if carry else []))
    if not os.path.exists(os.path.join(out, "poses.json")):
        print(f"[mesh] the bake of {name} failed: no report")
        return False
    spec = read_json(rig, encoding="utf-8")
    spec["poses"] = read_json(os.path.join(out, "poses.json"), encoding="utf-8")
    handed = {h["bone"] for h in spec_json.get("hand_off", [])}
    if handed:                                         # a lid taken in the hand has left the back on purpose
        carried = {x["part"] for x in spec.get("parts", [])
                   if x.get("bone") in handed or handed & set(x.get("chain", []))}
        spec["attach"] = [pq for pq in spec.get("attach", []) if (pq[0] in carried) == (pq[1] in carried)]
    check = os.path.join(out, "check_spec.json")
    with open(check, "w", encoding="utf-8") as fh_:
        json.dump(spec, fh_)
    blender_run([os.path.join(sdir, S["current"]), "--python", os.path.join(SKILLS, "mesh-rig", "scripts", "rig_session.py"),
                 "--", "--spec", check, "--out", os.path.join(out, "check"), "--object", S["object"], "--res", "240"])
    return True


def carry_args(carry):
    """A carry description as prop_contact arguments. A null handle means the prop does not turn."""
    out = ["--prop", os.path.abspath(carry["prop"])]
    for key in ("mode", "bone", "drop", "swing", "handle", "grip"):
        if carry.get(key) is not None:
            out += ["--" + key, str(carry[key])]
    for key in ("offset", "grip_point", "rotate"):
        if carry.get(key):
            out += ["--" + key.replace("_", "-")] + [str(x) for x in carry[key]]
    return out


def cmd_propcheck(sdir, argv):
    """Measure a carried prop against the body on every frame of a motion, into MOTION/prop. The
    second argument is a carry file: prop, bone, drop, swing, handle, grip."""
    S = load_session(sdir)
    folder = os.path.join(sdir, argv[0])
    carry = read_json(argv[1], encoding="utf-8")
    if os.path.exists(os.path.join(folder, "prop", "report.json")):
        os.remove(os.path.join(folder, "prop", "report.json"))       # a failed measure leaves nothing to pass
    code, _ = blender_run([os.path.join(folder, "motion.blend"), "--python",
                           os.path.join(SKILLS, "mesh-animate", "scripts", "prop_contact.py"), "--"] + carry_args(carry)
                          + ["--report", os.path.join(folder, "report.json"), "--out", os.path.join(folder, "prop"),
                             "--object", S["object"]] + argv[2:])
    return code == 0


def prop_controls(sdir, carry_path):
    """Placements made wrong on purpose must fail the contact gate, or it detects nothing."""
    carry = read_json(carry_path, encoding="utf-8")
    gate = os.path.join(SKILLS, "stage-gate", "scripts", "gate.py")
    ok = True
    spec = os.path.join(SKILLS, "mesh-animate", "assets", "controls_prop", "placements.json")
    for c in read_json(spec, encoding="utf-8") + carry.get("controls", []):
        name = "control_prop_" + c["name"]
        folder = os.path.join(sdir, "motions", name)
        os.makedirs(folder, exist_ok=True)
        for f in ("motion.blend", "report.json"):
            shutil.copy(os.path.join(sdir, "motions", "walk", f), folder)
        trial = os.path.join(folder, "carry.json")
        change = dict(c.get("change", {}))
        if "drop_scale" in c:
            change["drop"] = carry["drop"] * c["drop_scale"]
        with open(trial, "w", encoding="utf-8") as fh_:
            json.dump(dict(carry, **change), fh_)
        cmd_propcheck(sdir, ["motions/" + name, trial])
        r = subprocess.run([sys.executable, "-I", gate, sdir, "prop_contact", "--anim", "motions/" + name, "--note", "negative control"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        failing = [x for x in r.stdout.splitlines() if " FAIL " in x]
        for want in c.get("must_fail", []):
            hit = any(want in x for x in failing)
            ok = ok and hit
            print(f"[controls] {name}: '{want}' {'failed as it should' if hit else 'PASSED: it detects nothing'}")
        if c.get("must_fail_any"):                     # which criterion rejects it depends on the prop's shape
            hit = any(w in x for w in c["must_fail_any"] for x in failing)
            ok = ok and hit
            print(f"[controls] {name}: {'rejected as it should' if hit else 'PASSED: it detects nothing'}")
    return ok


def cmd_controls(sdir, argv):
    """Negative controls: motions made wrong on purpose must fail the criteria they name, or those
    criteria detect nothing. Runs each control in a scratch library and restores the real one."""
    rig = os.path.abspath(argv[0])
    folder = os.path.join(SKILLS, "mesh-animate", "assets", "controls")
    library = os.path.join(sdir, "motions", "library.blend")
    saved = library + ".keep"
    had = os.path.exists(library)
    if had:
        shutil.copy2(library, saved)                   # copy2 keeps its date, which later gates compare
    try:
        ok = run_controls(sdir, rig, folder)
        if "--attack" in argv:
            ok = attack_controls(sdir, rig, os.path.abspath(argv[argv.index("--attack") + 1]),
                                 os.path.abspath(argv[argv.index("--carry") + 1])) and ok
    finally:
        if had:
            shutil.move(saved, library)
        elif os.path.exists(library):                  # made by the controls: it holds only broken motions
            os.remove(library)
    if "--carry" in argv and "--attack" not in argv:
        ok = prop_controls(sdir, argv[argv.index("--carry") + 1]) and ok
    print("[controls] " + ("every control was caught" if ok else "some controls were NOT caught"))
    return ok


def gate_fails(sdir, stage, name, wanted):
    """Run a gate on a control motion; True when every wanted criterion failed."""
    gate = os.path.join(SKILLS, "stage-gate", "scripts", "gate.py")
    r = subprocess.run([sys.executable, "-I", gate, sdir, stage, "--anim", "motions/" + name, "--note", "negative control"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    failing = [x for x in r.stdout.splitlines() if " FAIL " in x]
    ok = True
    for want in wanted:
        hit = any(want in x for x in failing)
        ok = ok and hit
        print(f"[controls] {name}: '{want}' {'failed as it should' if hit else 'PASSED: it detects nothing'}")
    return ok


def inline_poses(spec, path):
    """A spec with the poses it includes copied in, so it can be written anywhere."""
    spec = json.loads(json.dumps(spec))
    extra = spec.pop("include_poses", [])
    for x in ([extra] if isinstance(extra, str) else extra):
        shared = read_json(os.path.join(os.path.dirname(path), x), encoding="utf-8")
        spec["poses"] = {**shared.get("poses", shared), **spec.get("poses", {})}
    return spec


def attack_controls(sdir, rig, attack, carry_path):
    """An attack that passes, broken one way at a time: each break must fail the criterion it breaks,
    or that criterion detects nothing. Run it on an attack the character really plays."""
    base = inline_poses(read_json(attack, encoding="utf-8"), attack)
    st = base["strike"]
    keys = base["keys"]
    top = max((k for k in keys if k["frame"] <= st["from"]), key=lambda k: k["frame"])["pose"]

    k_from = max(k["frame"] for k in keys if k["frame"] <= st["from"])
    k_hit = min((k["frame"] for k in keys if k["frame"] >= st["impact"]), default=st["impact"])

    def later(d):                                      # the strike itself d frames longer, the rest moved on
        s = json.loads(json.dumps(base))
        span = max(k_hit - k_from, 1)

        def moved(f):
            if f <= k_from:
                return f
            if f <= k_hit:
                return k_from + round((f - k_from) * (span + d) / span)
            return f + d
        for k in s["keys"] + s.get("travel", []):
            k["frame"] = moved(k["frame"])
        s["frames"] += d
        s["strike"]["impact"] = moved(st["impact"])
        s["exempt"] = [[moved(a), moved(b)] for a, b in s.get("exempt", [])]
        return s

    calm = [f for f in range(3, base["frames"] - 3)    # a frame away from the hit and any landing
            if not (st.get("from", 0) - 3 <= f <= st["impact"] + 5)
            and not any(a - 3 <= f <= b + 3 for a, b in base.get("exempt", []))]

    def no_wind_up():                                  # the weapon starts at the top of its wind-up
        s = json.loads(json.dumps(base))
        for k in s["keys"]:
            if k["frame"] < st["from"]:
                k["pose"] = top
        return s

    trials = [("slow", later(6), "motion_attack", ["strike, s"]),
              ("early_hit", dict(base, strike=dict(st, impact=st["impact"] - 3)), "motion_attack",
               ["fastest frame from the hit frame"]),
              ("no_wind_up", no_wind_up(), "motion_attack", ["wind-up, s"]),
              ("slide", dict(base, debug_slip=0.03), "animation_oneshot", ["foot slide on the ground"]),
              ("pop", dict(base, debug_pop={"frame": calm[len(calm) // 2] if calm else 1, "offset": [0.03, 0, 0]}),
               "animation_oneshot", ["jump outside the hit"]),
              ("wrong_end", dict(base, end_pose=top), "animation_oneshot", ["end pose against"])]
    ok = True
    for tag, spec, stage, wanted in trials:
        name = "control_attack_" + tag
        path = os.path.join(sdir, "motions", name + ".json")
        with open(path, "w", encoding="utf-8") as fh_:
            json.dump(dict(spec, name=name), fh_, ensure_ascii=False)
        if not cmd_animate(sdir, [path, rig, "--carry", carry_path]):
            print(f"[controls] {name}: the bake failed, so nothing was tested")
            ok = False
            continue
        ok = gate_fails(sdir, stage, name, wanted) and ok
    carry = read_json(carry_path, encoding="utf-8")    # the blade held inside the chest
    name = "control_attack_blade"
    path = os.path.join(sdir, "motions", name + ".json")
    with open(path, "w", encoding="utf-8") as fh_:
        json.dump(dict(base, name=name), fh_, ensure_ascii=False)
    if cmd_animate(sdir, [path, rig, "--carry", carry_path]):
        trial = os.path.join(sdir, "motions", name, "carry.json")
        blade = dict(carry, bone="chest", grip_point=[0, 0, 0.6], rotate=[0, 0, 0], offset=None)
        with open(trial, "w", encoding="utf-8") as fh_:
            json.dump(blade, fh_)
        cmd_propcheck(sdir, ["motions/" + name, trial])
        ok = gate_fails(sdir, "prop_contact", name, ["prop into the body"]) and ok
    else:
        print(f"[controls] {name}: the bake failed, so nothing was tested")
        ok = False
    return ok


def run_controls(sdir, rig, folder):
    gate = os.path.join(SKILLS, "stage-gate", "scripts", "gate.py")
    ok = True
    names = read_json(rig, encoding="utf-8").get("control_names", {})
    for path in sorted(glob.glob(os.path.join(folder, "*.json"))):
        spec = renamed(read_json(path, encoding="utf-8"), names)
        path = os.path.join(sdir, "motions", spec["name"] + ".json")
        with open(path, "w", encoding="utf-8") as fh_:
            json.dump(spec, fh_, ensure_ascii=False)
        if not cmd_animate(sdir, [path, rig]):
            print(f"[controls] {spec['name']}: the bake failed, so nothing was tested")
            ok = False
            continue
        r = subprocess.run([sys.executable, "-I", gate, sdir, spec["gate"], "--anim", "motions/" + spec["name"],
                            "--note", "negative control"], capture_output=True, text=True, encoding="utf-8", errors="replace")
        failing = [x for x in r.stdout.splitlines() if " FAIL " in x]
        for want in spec["must_fail"]:
            hit = any(want in x for x in failing)
            ok = ok and hit
            print(f"[controls] {spec['name']}: '{want}' {'failed as it should' if hit else 'PASSED: it detects nothing'}")
    return ok


def cmd_selftest(argv):
    keep = opt(argv, "--keep")
    only = opt(argv, "--only")
    root = os.path.abspath(keep or os.path.join(os.getcwd(), "mesh_selftest_tmp"))
    files = sorted(glob.glob(os.path.join(HERE, "..", "assets", "selftest", "*.steps.jsonl")))
    if only:
        files = [f for f in files if only in os.path.basename(f)]
    results = []
    for f in files:
        name = os.path.basename(f).replace(".steps.jsonl", "")
        sdir = os.path.join(root, name)
        if os.path.exists(sdir):
            shutil.rmtree(sdir)
        os.makedirs(sdir)
        print(f"[mesh] selftest {name}")
        results.append((name, cmd_run(sdir, f, nosnap=True)))
    for name, ok in results:
        print(f"[mesh] selftest {name}: {'PASS' if ok else 'FAIL'}")
    if not keep and all(ok for _, ok in results) and os.path.exists(root):
        shutil.rmtree(root)
    return all(ok for _, ok in results)


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "selftest":
        return 0 if cmd_selftest(argv[1:]) else 1
    if argv[0] == "compare":
        return subprocess.run([sys.executable, "-I", os.path.join(HERE, "compare_sessions.py")] + argv[1:]).returncode
    if len(argv) < 2:
        print(__doc__)
        return 2
    sdir, op, rest = os.path.abspath(argv[0]), argv[1], argv[2:]
    if op == "run":
        strict = "--strict" in rest
        nosnap = "--no-snap" in rest
        rest = [x for x in rest if x not in ("--strict", "--no-snap")]
        start = opt(rest, "--from", 1, int)
        os.makedirs(sdir, exist_ok=True)
        return 0 if cmd_run(sdir, rest[0], strict, nosnap, start) else 1
    if op == "undo":
        cmd_undo(sdir, int(rest[0]) if rest else 1)
        return 0
    if op == "status":
        cmd_status(sdir)
        return 0
    if op == "export":
        expect = opt(rest, "--expect", "faces")
        cmd_export(sdir, rest[0], expect)
        return 0
    if op == "report":
        return 0 if cmd_report(sdir, rest) else 1
    if op == "finish":
        cmd_finish(sdir, rest)
        return 0
    if op == "fidelity":
        return 0 if cmd_fidelity(sdir, rest) else 1
    if op == "rig":
        return 0 if cmd_rig(sdir, rest) else 1
    if op == "uv":
        return 0 if cmd_uv(sdir, rest) else 1
    if op == "texture":
        return 0 if cmd_texture(sdir, rest) else 1
    if op == "glb":
        return 0 if cmd_glb(sdir, rest) else 1
    if op == "animate":
        return 0 if cmd_animate(sdir, rest) else 1
    if op == "controls":
        return 0 if cmd_controls(sdir, rest) else 1
    if op == "propcheck":
        return 0 if cmd_propcheck(sdir, rest) else 1
    if op == "unreal":
        script = os.path.join(SKILLS, "mesh-export", "scripts", "unreal_session.py")
        return subprocess.run([sys.executable, "-I", script, sdir] + rest).returncode
    if op == "gate":
        gate = os.path.join(SKILLS, "stage-gate", "scripts", "gate.py")
        return subprocess.run([sys.executable, "-I", gate, sdir] + rest).returncode
    os.makedirs(sdir, exist_ok=True)
    args = json.loads(rest[0]) if rest and rest[0] else {}
    return 0 if step(sdir, op, args, rest[1] if len(rest) > 1 else "") else 1


if __name__ == "__main__":
    sys.exit(main())
