"""Report of a modelling session: what was built, how, and what is still missing.

  python -I session_report.py SESSION [--pick 9] [--steps 4,11,15] [--html] [--out DIR]

Writes DIR/construction.png (a contact sheet of the chosen step snapshots), DIR/report.md
(counts, op mix, check warnings, review result, step table, what was not done) and with
--html DIR/report.html (images embedded, for sharing or an inline chat visual).
DIR defaults to SESSION/report. Needs Pillow.
"""
import argparse
import base64
import collections
import glob
import io
import json
import os
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("session")
ap.add_argument("--pick", type=int, default=9)
ap.add_argument("--steps", default="")
ap.add_argument("--html", action="store_true")
ap.add_argument("--out", default="")
a = ap.parse_args()
sdir = os.path.abspath(a.session)
out = os.path.abspath(a.out or os.path.join(sdir, "report"))
os.makedirs(out, exist_ok=True)
S = json.load(open(os.path.join(sdir, "session.json"), encoding="utf-8"))
steps = S["steps"]
STRUCT = {"primitive", "mirror", "extrude", "inset", "loopcut", "bevel", "subsurf", "transform"}


def snap(n):
    p = os.path.join(sdir, "snaps", f"{n:03d}.png")
    return p if os.path.exists(p) else None


# ---- choose the construction snapshots
if a.steps:
    chosen = [int(x) for x in a.steps.split(",") if x.strip()]
else:
    cand = [s["n"] for s in steps if s["op"] in STRUCT and snap(s["n"])]
    if len(cand) > a.pick:
        cand = sorted({cand[round(i * (len(cand) - 1) / (a.pick - 1))] for i in range(a.pick)})
    last = steps[-1]["n"]
    if snap(last) and last not in cand:
        cand = (cand[:-1] if len(cand) >= a.pick else cand) + [last]
    chosen = cand
chosen = [n for n in chosen if snap(n)]

sheet_path = None
if chosen:
    W = 420
    tiles = []
    for n in chosen:
        im = Image.open(snap(n)).convert("RGB")
        tiles.append(im.resize((W, int(im.height * W / im.width)), Image.LANCZOS))
    cols = min(3, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    th = max(t.height for t in tiles)
    sheet = Image.new("RGB", (cols * W + (cols + 1) * 6, rows * th + (rows + 1) * 6), (24, 24, 28))
    for k, t in enumerate(tiles):
        sheet.paste(t, (6 + (k % cols) * (W + 6), 6 + (k // cols) * (th + 6)))
    sheet_path = os.path.join(out, "construction.png")
    sheet.save(sheet_path)

# ---- facts
first, last = steps[0]["stats"], steps[-1]["stats"]
ops = collections.Counter(s["op"] for s in steps)
warned = [(s["n"], s["op"], c) for s in steps for c in s.get("checks", [])]
materials = []
for s in steps:
    if s["op"] == "material" and s["args"].get("name") not in materials:
        materials.append(s["args"].get("name"))
review = None
for cand in sorted(glob.glob(os.path.join(sdir, "review*", "report.json")), key=os.path.getmtime, reverse=True):
    review = (os.path.relpath(cand, sdir), json.load(open(cand, encoding="utf-8")))
    break
renders = sorted(glob.glob(os.path.join(sdir, "render*.png")), key=os.path.getmtime)
missing = []
if S.get("mirror"):
    missing.append(f"mirror ({S['mirror']}) not applied")
if not any(s["op"] == "uv" for s in steps):
    missing.append("no UVs")
if not materials:
    missing.append("no materials")
missing.append("no textures (colour only)")
if not any(s["op"] == "subsurf" for s in steps):
    missing.append("no subdivision")

# ---- report.md
L = [f"# Session report: {os.path.basename(sdir)}", ""]
L.append(f"- steps: **{len(steps)}** — " + ", ".join(f"{k} {v}" for k, v in ops.most_common()))
L.append(f"- cage: {first['faces']} → **{last['faces']} faces** ({last['quads']} quads, {last['tris']} tris, "
         f"{last['ngons']} n-gons), {last['verts']} verts; non-manifold **{last['non_manifold']}**")
L.append(f"- evaluated (modifiers on): **{last['tris_eval']} triangles**" + (f"; tier {S['tier']}" if S.get("tier") else ""))
L.append(f"- materials: {', '.join(materials) if materials else '—'}")
L.append(f"- automatic check warnings in the kept history: **{len(warned)}**")
for n, op, c in warned:
    L.append(f"  - {n:03d} {op} · {c['kind']}: {c['msg']}")
if review:
    w = review[1].get("warnings", {})
    L.append(f"- 3d-asset-review ({review[0]}): **{sum(len(v) for v in w.values())} warnings** "
             + ", ".join(f"{k} {len(v)}" for k, v in w.items()))
else:
    L.append("- 3d-asset-review: not run")
L.append(f"- not done: {'; '.join(missing)}")
if renders:
    L.append(f"- renders: {', '.join(os.path.basename(r) for r in renders)}")
L += ["", "## Construction", ""]
if sheet_path:
    L.append(f"![construction](construction.png)  \nsteps shown: {', '.join(f'{n:03d}' for n in chosen)}")
L += ["", "## Steps", "", "| # | op | label | result | faces | eval tris | checks |", "|---|---|---|---|---|---|---|"]
ROWS = []
for s in steps:
    info = ", ".join(f"{k} {v}" for k, v in (s.get("info") or {}).items() if not isinstance(v, (dict, list)))
    chk = "; ".join(c["kind"] for c in s.get("checks", [])) or ""
    ROWS.append([f"{s['n']:03d}", s["op"], s.get("label", ""), info, str(s["stats"]["faces"]),
                 str(s["stats"]["tris_eval"]), chk])
    L.append("| " + " | ".join(ROWS[-1]) + " |")
open(os.path.join(out, "report.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")


# ---- report.html (self-contained)
def uri(path, w):
    im = Image.open(path).convert("RGB")
    im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, "JPEG", quality=72)
    return "data:image/jpeg;base64," + base64.b64encode(b.getvalue()).decode()


if a.html:
    import html as H
    figs = "".join(f'<figure><img src="{uri(snap(n), 360)}"><figcaption>step {n:03d}</figcaption></figure>' for n in chosen)
    rfig = "".join(f'<figure><img src="{uri(r, 420)}"><figcaption>{H.escape(os.path.basename(r))}</figcaption></figure>'
                   for r in renders[-3:])
    facts = "".join(f"<li>{H.escape(x[2:])}</li>" for x in L[2:] if x.startswith("- "))
    rows = "".join("<tr>" + "".join(f"<td>{H.escape(c)}</td>" for c in r) + "</tr>" for r in ROWS)
    page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
body{{margin:0;padding:12px;font:13px system-ui,sans-serif;background:var(--background,#fff);color:var(--foreground,#111)}}
h3{{margin:8px 0;font-size:14px}} ul{{margin:0 0 10px;padding-left:18px}}
.g{{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:12px}}
figure{{margin:0;border:1px solid var(--border,#ccc);border-radius:6px;overflow:hidden}}
img{{width:100%;display:block}} figcaption{{padding:3px 8px;color:var(--muted-foreground,#666)}}
table{{border-collapse:collapse;font-size:12px}} td{{border-top:1px solid var(--border,#ddd);padding:2px 6px}}
</style></head><body><h3>{H.escape(os.path.basename(sdir))}</h3><ul>{facts}</ul>
<h3>Construction</h3><div class="g">{figs}</div>{'<h3>Renders</h3><div class="g">' + rfig + '</div>' if rfig else ''}
<details><summary>All steps</summary><table>{rows}</table></details></body></html>"""
    open(os.path.join(out, "report.html"), "w", encoding="utf-8").write(page)

print(f"[report] {len(steps)} steps, {last['faces']} faces, {last['tris_eval']} eval tris, "
      f"{len(warned)} check warnings; wrote {os.path.relpath(out)}{os.sep}report.md"
      + (" + construction.png" if sheet_path else "") + (" + report.html" if a.html else ""))
