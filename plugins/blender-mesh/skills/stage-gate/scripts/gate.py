"""Score a stage of an asset against fixed thresholds (system Python, standard library).

  python gate.py SESSION STAGE [--gates gates.json] [--note "what changed"]
  python gate.py SESSION --history [STAGE]

Reads the stage's measurement files inside SESSION, prints every criterion with its value and
margin, appends the result to SESSION/scores.jsonl and exits 0 when all criteria pass. A
measurement file older than the session's model counts as missing, so a stale report cannot pass.
A criterion: {"name", "file", "path", "min" | "max"}. `path` is dotted ("views.front.iou");
"count": true sums the lengths of the lists found at path (a dict of lists, or a list).
"""
import json
import os
import sys
import time

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
    rows = [json.loads(x) for x in open(log, encoding="utf-8")] if os.path.exists(log) else []
    for r in rows:
        if want in (None, r["stage"]):
            state = "PASS" if r["passed"] else f"{r['failed']} failing"
            print(f"{r['time']}  {r['stage']:9s} {state:10s} {r.get('note', '')}")
    sys.exit(0)

stage = argv[1]
G = json.load(open(gates_path, encoding="utf-8"))
if stage not in G:
    sys.exit(f"[gate] no stage '{stage}' in {gates_path}: {', '.join(k for k in G if not k.startswith('_'))}")


def lookup(data, path):
    for key in path.split("."):
        data = data[key] if isinstance(data, dict) else data[int(key)]
    return data


stopped = os.path.join(session, "stopped.txt")
if os.path.exists(stopped):
    why = open(stopped, encoding="utf-8").read().strip()
    print(f"[gate] {stage}: the build did not finish, nothing is scored: {why}")
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"time": time.strftime("%Y-%m-%d %H:%M:%S"), "stage": stage, "passed": False, "failed": 1,
                             "note": "build stopped: " + why, "scores": {}}, ensure_ascii=False) + "\n")
    sys.exit(1)

def source_of(name):
    """The file a report was made from, when that is newer than the model."""
    if anim and name.startswith(("anim/prop/", "anim/check/")):
        return os.path.join(session, anim, "motion.blend")
    if name.startswith("export/unreal/"):
        return os.path.join(session, "export", "model.glb")
    return None


model_time = os.path.getmtime(os.path.join(session, "session.json"))
cache, rows, failed = {}, [], 0
for c in G[stage]:
    fp = os.path.join(session, c["file"].replace("anim/", anim + "/", 1) if anim else c["file"])
    if fp not in cache:
        cache[fp] = json.load(open(fp, encoding="utf-8")) if os.path.exists(fp) else None
        sources = [source_of(c["file"])] + ([cache[fp].get("prop")] if isinstance(cache[fp], dict) else [])
        made_from = max([model_time] + [os.path.getmtime(x) for x in sources if x and os.path.exists(x)])
        if cache[fp] is not None and os.path.getmtime(fp) < made_from:
            print(f"[gate] {c['file']} is older than what it measures: measure again")
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
