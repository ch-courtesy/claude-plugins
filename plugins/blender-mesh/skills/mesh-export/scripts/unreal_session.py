"""Open an exported GLB in Unreal Engine and measure what arrived (system Python and Pillow).

  python unreal_session.py SESSION [--engine UE_DIR] [--warm 30] [--ddc DIR]

Writes SESSION/export/unreal/: report.json, albedo_front.png, one picture per action pose, and a
scratch project. Unreal's cache is kept beside the session (--ddc), not on the system drive.
"""
import json
import glob
import os
import re
import shutil
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gltf_pose  # noqa: E402

argv = sys.argv[1:]


def opt(name, default=None):
    if name in argv:
        i = argv.index(name)
        v = argv[i + 1]
        del argv[i:i + 2]
        return v
    return default


def find_engine():
    manifest = os.path.join(os.environ.get("PROGRAMDATA", r"C:\ProgramData"), "Epic", "UnrealEngineLauncher",
                            "LauncherInstalled.dat")
    if os.path.exists(manifest):
        rows = json.load(open(manifest, encoding="utf-8"))["InstallationList"]
        dirs = sorted({r["InstallLocation"] for r in rows if re.fullmatch(r"UE_\d+\.\d+", r["AppName"])}, reverse=True)
        for d in dirs:
            if os.path.exists(os.path.join(d, "Engine", "Binaries", "Win64", "UnrealEditor-Cmd.exe")):
                return d
    sys.exit("[unreal] no engine found: give --engine")


engine = opt("--engine") or find_engine()
warm = float(opt("--warm", "30"))
session = os.path.abspath(argv[0])
ddc = os.path.abspath(opt("--ddc", os.path.join(os.path.dirname(session), "_ue", "ddc")))
out = os.path.join(session, "export", "unreal")
project_dir = os.path.join(out, "project")
glb = os.path.join(session, "export", "model.glb")
os.makedirs(project_dir, exist_ok=True)
os.makedirs(ddc, exist_ok=True)
for old in glob.glob(os.path.join(out, "*.png")) + glob.glob(os.path.join(out, "*.json")):
    os.remove(old)
project = os.path.join(project_dir, "Check.uproject")
json.dump({"FileVersion": 3, "Description": "Scratch project for testing exported GLB files.",
           "Plugins": [{"Name": n, "Enabled": True} for n in
                       ("PythonScriptPlugin", "EditorScriptingUtilities", "Interchange", "InterchangeEditor", "InterchangeAssets")]},
          open(project, "w", encoding="utf-8"), indent=1)
shutil.copy(os.path.join(HERE, "ue_check.py"), os.path.join(project_dir, "ue_check.py"))
script = os.path.join(project_dir, "ue_check.py").replace("\\", "/")

G, binary = gltf_pose.load(glb)
joints, parents = gltf_pose.skeleton(G)
actions = [a["name"] for a in G["animations"]]
lengths = {n: gltf_pose.action_length(G, binary, n) for n in actions}
FPS = 24
times = {n: [round(k * lengths[n] / 8 * FPS) / FPS for k in range(9)] for n in actions}
play = {n: [round(lengths[n] * x * FPS) / FPS for x in (0.25, 0.6)] for n in actions}
TRACK = [b for b in ("hand.L", "hand.R", "head", "foot.L", "foot.R", "tail3") if b in parents]
config = os.path.join(out, "config.json")


def run(phase, exe, args, log):
    json.dump({"phase": phase, "glb": glb, "dest": "/Game/Check", "out": out, "parents": parents, "times": times,
               "play": play, "track": TRACK, "warm_seconds": warm}, open(config, "w", encoding="utf-8"))
    env = dict(os.environ, MESH_UE_CONFIG=config)
    env["UE-LocalDataCachePath"] = ddc
    cmd = [os.path.join(engine, "Engine", "Binaries", "Win64", exe), project, "-unattended", "-nosplash", "-nop4", "-nosound",
           "-NoZenAutoLaunch", "-ddc=InstalledNoZenLocalFallback", f"-LocalDataCachePath={ddc}", f"-log={log}"] + args
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=1200)
    path = os.path.join(project_dir, "Saved", "Logs", log)
    text = open(path, encoding="utf-8", errors="replace").read() if os.path.exists(path) else r.stdout
    if "Critical error" in text:
        print(text[text.index("Critical error") - 200:][:900])
    return text


log1 = run("all", "UnrealEditor.exe", [f"-ExecCmds=py {script}", "-RenderOffscreen"], "check.log")
if not os.path.exists(os.path.join(out, "import.json")):
    print(log1[-1500:])
    sys.exit("[unreal] the import step left no result")
info = json.load(open(os.path.join(out, "import.json"), encoding="utf-8"))
played = json.load(open(os.path.join(out, "played.json"), encoding="utf-8")) if os.path.exists(os.path.join(out, "played.json")) else {}
if "error" in played:
    print(played["error"])

ISSUE = re.compile(r"Log(Interchange\w*|GLTF\w*|SkeletalMesh\w*|Animation\w*|AnimSequence\w*|Skeleton\w*): (Error|Warning): (.*)")
issues = sorted({(m.group(2), m.group(3).strip()[:200]) for m in ISSUE.finditer(log1)})
errors = [x[1] for x in issues if x[0] == "Error"]
warnings = [x[1] for x in issues if x[0] == "Warning"]


def distances(pose, scale):
    names = sorted(pose)
    out_ = {}
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            out_[a, b] = sum((p - q) ** 2 for p, q in zip(pose[a], pose[b])) ** 0.5 * scale
    return out_


worst, motion, length_error, power = 0.0, {}, 0.0, 0.0
for name, data in info["actions"].items():
    length_error = max(length_error, abs(data["length"] - lengths[name]))
    biggest = 0.0
    for t, pose in zip(times[name], data["poses"]):
        here = distances(pose, 10.0)                   # engine centimetres to millimetres
        want = distances(gltf_pose.joint_positions(G, binary, name, t), 1000.0)
        worst = max(worst, max(abs(here[k] - want[k]) for k in want))
        # the same comparison against a different moment must show a difference, or it proves nothing
        other = distances(gltf_pose.joint_positions(G, binary, name, (t + lengths[name] / 4) % lengths[name]), 1000.0)
        power = max(power, max(abs(here[k] - other[k]) for k in other))
        first = data["poses"][0]
        biggest = max(biggest, max(sum((p - q) ** 2 for p, q in zip(pose[b], first[b])) ** 0.5 * 10 for b in pose))
    motion[name] = biggest


def played_motion(rows):
    if len(rows) < 2:
        return 0.0
    return max(sum((p - q) ** 2 for p, q in zip(rows[0]["bones"][b], rows[1]["bones"][b])) ** 0.5 * 10 for b in rows[0]["bones"])


moved = {n: played_motion(played.get(n, [])) for n in actions}


# ---------------------------------------------------------------- colour against Blender's flat render
def srgb(v):
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


def linear(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def lab(rgb):
    r, g, b = (linear(c / 255) for c in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))


def crop(path, encode):
    im = Image.open(path).convert("RGB")
    if encode:
        im = im.point([round(255 * srgb(i / 255)) for i in range(256)] * 3)
    box = im.point(lambda v: 255 if v > 8 else 0).convert("L").getbbox()
    return im.crop(box).resize((256, 256), Image.LANCZOS) if box else None


colour = None
ue_flat = os.path.join(out, "albedo_front.png")
blender_flat = os.path.join(session, "texture", "flat_front.png")
if os.path.exists(ue_flat):                            # a capture writes alpha 0 everywhere: keep the colour only
    Image.open(ue_flat).convert("RGB").save(ue_flat)
if os.path.exists(ue_flat) and os.path.exists(blender_flat):
    a, b = crop(ue_flat, True), crop(blender_flat, False)
    if a and b:
        pa, pb = a.load(), b.load()
        rows = []
        for y in range(256):
            for x in range(256):
                if sum(pa[x, y]) > 24 and sum(pb[x, y]) > 24:
                    la, lb = lab(pa[x, y]), lab(pb[x, y])
                    rows.append(sum((p - q) ** 2 for p, q in zip(la, lb)) ** 0.5)
        rows.sort()
        colour = rows[len(rows) // 2] if rows else None

expected = json.load(open(os.path.join(session, "export", "report.json"), encoding="utf-8"))
images = len(G.get("images", []))
R = {"engine": info["engine"], "engine_dir": engine, "import_errors": len(errors), "import_warnings": len(warnings),
     "errors": errors, "warnings": warnings, "skeletal_meshes": info["skeletal_meshes"],
     "bones_missing": len(set(parents) - set(info["actions"][next(iter(info["actions"]))]["poses"][0])) if info["actions"] else len(parents),
     "actions_found": sorted(info["actions"]), "actions_missing": len(set(actions) - set(info["actions"])),
     "length_error_s": length_error, "pose_error_mm": worst, "pose_check_power_mm": power, "action_motion_mm": min(motion.values()) if motion else 0.0,
     "action_motion": motion, "played_motion_mm": min(moved.values()) if moved else 0.0, "played_motion": moved,
     "height_m": info.get("height_m"), "height_error_m": abs(info.get("height_m", 0) - expected["height"]),
     "materials": info["materials"], "materials_untextured": info["materials_untextured"], "textures": info["textures"],
     "texture_copies": max(0, info["textures"] - images), "albedo_delta_e_median": colour}
json.dump(R, open(os.path.join(out, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"[unreal] {R['engine']}: {R['skeletal_meshes']} mesh, {len(info['actions'])}/{len(actions)} actions, joints off by "
      f"{worst:.4f} mm (a wrong moment gives {power:.0f}), played {R['played_motion_mm']:.0f} mm, textures {info['textures']}, colour dE {colour}, "
      f"errors {len(errors)}, warnings {len(warnings)}")
