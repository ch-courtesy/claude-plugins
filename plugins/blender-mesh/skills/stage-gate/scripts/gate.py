"""Score a stage of an asset against fixed thresholds (system Python, standard library).

  python gate.py SESSION STAGE [--gates gates.json] [--note "what changed"]
  python gate.py SESSION --history [STAGE]

Reads the stage's measurement files inside SESSION, prints every criterion with its value and
margin, appends the result to SESSION/scores.jsonl and exits 0 when all criteria pass. A
measurement file counts as missing when it is stale: when the file it measures, or anything that file
was made from up to the model, is newer than what was made from it (see out_of_order).
A criterion: {"name", "file", "path", "min" | "max"}. `path` is dotted ("views.front.iou");
"count": true sums the lengths of the lists found at path (a dict of lists, or a list).
"""
import json
import os
import sys
import time


def read_file(*args, **kwargs):
    """The whole of a file, closed again."""
    with open(*args, **kwargs) as fh:
        return fh.read()


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


def read_lines(*args, **kwargs):
    """A file's lines, closed again."""
    with open(*args, **kwargs) as fh:
        return fh.readlines()


for s in (sys.stdout, sys.stderr):
    try:
        s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[1:]


def opt(name, default=None):
    if name in argv:
        i = argv.index(name)
        if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
            sys.exit(f"[gate] {name} needs a value")
        v = argv[i + 1]
        del argv[i:i + 2]
        return v
    return default


gates_path = opt("--gates", os.path.join(HERE, "..", "assets", "gates.json"))
note = opt("--note", "")
anim = opt("--anim", "")                               # a motion's folder, for the anim/ paths in the gates
session = argv[0]
log = os.path.join(session, "scores.jsonl")

if "--history" in argv:
    want = argv[argv.index("--history") + 1] if len(argv) > argv.index("--history") + 1 else None
    rows = [json.loads(x) for x in read_lines(log, encoding="utf-8")] if os.path.exists(log) else []
    for r in rows:
        if want in (None, r["stage"]):
            state = "PASS" if r["passed"] else f"{r['failed']} failing"
            print(f"{r['time']}  {r['stage']:9s} {state:10s} {r.get('note', '')}")
    sys.exit(0)

stage = argv[1]
G = read_json(gates_path, encoding="utf-8")
if stage not in G:
    sys.exit(f"[gate] no stage '{stage}' in {gates_path}: {', '.join(k for k in G if not k.startswith('_'))}")


def lookup(data, path):
    for key in path.split("."):
        data = data[key] if isinstance(data, dict) else data[int(key)]
    return data


stopped = os.path.join(session, "stopped.txt")
if os.path.exists(stopped):
    why = read_file(stopped, encoding="utf-8").strip()
    print(f"[gate] {stage}: the build did not finish, nothing is scored: {why}")
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"time": time.strftime("%Y-%m-%d %H:%M:%S"), "stage": stage, "passed": False, "failed": 1,
                             "note": "build stopped: " + why, "scores": {}}, ensure_ascii=False) + "\n")
    sys.exit(1)

SAVED = {"rig/rig.blend": ("session.json",),                 # each file a stage saves, and the files it is
         "uv/uv.blend": ("rig/rig.blend", "session.json"),   # made from (a prop has no rig: its UV comes
         "texture/texture.blend": ("uv/uv.blend",),          # from the model itself)
         "motions/library.blend": ("texture/texture.blend",),
         "export/model.glb": ("texture/texture.blend", "motions/library.blend")}
MEASURES = (("export/", "export/model.glb"), ("texture/", "texture/texture.blend"),   # the file a stage's
            ("uv/", "uv/uv.blend"), ("rig/", "rig/rig.blend"))                       # reports measure


def inputs_of(rel):
    """The session files that `rel` (a path inside the session) is made from, one stage up."""
    if rel in SAVED:
        return SAVED[rel]
    parts = rel.split("/")
    if parts[0] == "motions" and len(parts) > 2:     # a motion's bake, and its reports, which measure the bake
        bake = f"motions/{parts[1]}/motion.blend"
        return ("texture/texture.blend",) if rel == bake else (bake,)
    for prefix, measured in MEASURES:
        if rel.startswith(prefix):
            return (measured,)
    return () if rel == "session.json" else ("session.json",)   # anything else measures the model


def out_of_order(rel):
    """Why `rel` is stale, or None: every file in the chain it was made from, up to the model, must be
    no newer than what was made from it. A stage redone at any depth, a stage run on an old input, or a
    file saved again without being measured again all break the chain."""
    t = os.path.getmtime(os.path.join(session, rel))
    for f in inputs_of(rel):
        fp = os.path.join(session, f)
        if not os.path.exists(fp):
            continue                                 # a stage this asset does not have
        if os.path.getmtime(fp) > t:
            return f"{rel} is older than {f}"
        why = out_of_order(f)
        if why:
            return why
    return None


cache, rows, failed = {}, [], 0
for c in G[stage]:
    rel = c["file"].replace("anim/", anim.strip("/\\").replace("\\", "/") + "/", 1) if anim else c["file"]
    fp = os.path.join(session, rel)
    if fp not in cache:
        cache[fp] = read_json(fp, encoding="utf-8") if os.path.exists(fp) else None
        if cache[fp] is not None:
            why = out_of_order(rel)
            prop = cache[fp].get("prop") if isinstance(cache[fp], dict) else None   # a carried prop's own file
            if not why and prop and os.path.exists(prop) and os.path.getmtime(prop) > os.path.getmtime(fp):
                why = f"{rel} is older than {prop}"
            if why:
                print(f"[gate] {why}: measure again")
                cache[fp] = None
    try:
        if cache[fp] is None:
            raise KeyError(c["file"])
        v = lookup(cache[fp], c["path"])
        if c.get("count"):
            v = sum(len(x) for x in v.values()) if isinstance(v, dict) else len(v)
    except (KeyError, IndexError, TypeError, ValueError):
        v = None
    limit = c.get("min", c.get("max"))
    ok = v is not None and (v >= c["min"] if "min" in c else v <= c["max"])
    failed += 0 if ok else 1
    rows.append({"name": c["name"], "value": v, "limit": limit, "kind": "min" if "min" in c else "max", "ok": ok})

print(f"[gate] {stage}: " + ("PASS" if not failed else f"{failed} of {len(rows)} failing"))
for r in rows:
    sign = ">=" if r["kind"] == "min" else "<="
    val = "missing" if r["value"] is None else (f"{r['value']:.3f}" if isinstance(r["value"], float) else r["value"])
    print(f"[gate]   {'ok  ' if r['ok'] else 'FAIL'} {r['name']}: {val}  ({sign} {r['limit']})")
with open(log, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"time": time.strftime("%Y-%m-%d %H:%M:%S"), "stage": stage, "passed": not failed, "failed": failed,
                         "note": (f"[{anim}] " if anim else "") + note, "scores": {r["name"]: r["value"] for r in rows}}, ensure_ascii=False) + "\n")
sys.exit(1 if failed else 0)
