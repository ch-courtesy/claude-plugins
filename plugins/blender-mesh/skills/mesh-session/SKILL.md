---
name: mesh-session
description: Runtime for step-by-step polygon modelling in Blender, the way an artist works in edit mode — one operation per step (primitive, select, transform, extrude, inset, loop cut, bevel, mirror, subdivision, cleanup, material), every step saved as its own .blend with a log line, automatic topology checks and a viewport-style snapshot (front/side/top/3-4, selection in orange); named selections, undo, steps files (replay/batch), session reports, render+review in one command and a regression selftest. Use it whenever you model a mesh with the mesh-* technique skills or the box-modeling procedure, need to start/inspect/undo/replay/render/report a modelling session, or want to show a model's construction history. 단계별 폴리곤 모델링 세션의 실행·검사·기록·스냅샷·되돌리기·재생·보고.
---

# mesh-session — the workbench for step-by-step modelling

Every technique skill (`mesh-primitive`, `mesh-select`, `mesh-transform`, `mesh-extrude`,
`mesh-inset`, `mesh-loopcut`, `mesh-bevel`, `mesh-mirror`, `mesh-subsurf`, `mesh-cleanup`)
runs through one command. This skill explains the session; the technique skills explain
when and how to use each operation.

## What is scripted and what is yours
| scripted (don't do it by hand) | your judgement |
|---|---|
| finding Blender, running a step, saving, logging, snapshots | the plan: parts, sizes, order |
| checks after every step (below) and `expect` assertions | which elements to select (the conditions) |
| replaying a steps file, multi-step undo, status | reading each snapshot: is the shape right? |
| report (counts, op mix, warnings, contact sheet), render + review | whether to undo, what to fix, when it is done |

## The command
```bash
python "<this skill>/scripts/mesh.py" <session_dir> <op> '<json args>' [label]
```
(`mesh.py` below means this.) Standard library only; it finds Blender from `$BLENDER`,
PATH or the usual install folders and runs `meshop.py` inside it. Quote the JSON with
single quotes in bash. Output: one line per step — what changed, cage counts
(quads/tris/n-gons), evaluated triangles, non-manifold edges, active selection — then the
check lines.

| command | does |
|---|---|
| `mesh.py S <op> '<json>' [label]` | one step |
| `mesh.py S run steps.jsonl [--strict] [--no-snap] [--from N]` | run a steps file in **one Blender process** (the 39-step chest: about 8 s, against about 2 minutes step by step); stops at the first error (`--strict`: also at a check warning) and tells you where to resume |
| `mesh.py S undo [N]` | step back N steps; the undone files are deleted |
| `mesh.py S status` | current step, counts, mirror/tier, recent check warnings |
| `mesh.py S export out.jsonl [--expect faces\|full\|none]` | the kept history as a replayable steps file with expectations |
| `mesh.py S report [--pick 9] [--steps 4,11] [--html]` | `S/report/`: report.md, construction.png, report.html |
| `mesh.py S finish [--tier pc] [--res 900] [--exposure 0]` | render + 3d-asset-review inspector + report |
| `mesh.py selftest [--keep DIR] [--only chest]` | replays `assets/selftest/*.steps.jsonl` (no snapshots) and checks every expectation — run after changing meshop.py |
| `mesh.py S fidelity CONCEPT_DIR [--map Brass=buckle]` | measure the current step against a concept turnaround (concept-fidelity): IoU, part IoU, gaps per part, comparison sheet in `S/fidelity/` |
| `mesh.py compare A B [--exact]` | two sessions step by step: same shape, or (`--exact`) the same cage element by element |

Steps file: one JSON object per line, `{"op": "...", "args": {...}, "label": "...", "expect": {...}}`;
`#` lines are comments; `undo` works inside a file. Use it for replays, regression and for
runs of steps you have already verified — new modelling still goes one step at a time with
a look at each snapshot.

A `run` keeps the model in memory between steps but still saves, logs and snapshots each
one, so the session is the same as if the steps had been run singly (`compare --exact`
shows no difference), and a failed step leaves the last good step on disk. Element order is
canonical after topology changes, so a replay reproduces the same cage every time.

## Automatic checks (every step)
Printed as `[meshop]   check <kind>: ...` and stored in the log; `checks: ok` when clean.

| kind | meaning |
|---|---|
| `non_manifold` | holes, internal or doubled faces (the open mirror seam is not counted) |
| `tris` / `ngons` | new triangles / n-gons in the cage — pinches under subdivision |
| `mirror_cross` | vertices moved past the mirror plane (overlap the mirrored copy) |
| `degenerate` | zero-length edges / zero-area faces |
| `winding` | neighbouring faces with opposite normals |
| `budget` | evaluated triangles over the session tier budget (tier from `primitive`/`note` `"tier"`) |
| `loopcut_span` | the `at` plane does not cross some ring edges (wrong ring or value) |
| `inset_thick` | inner faces collapsed or flipped — thickness too large |
| `zero_extrude` | extrude distance 0 (duplicate faces) |
| `individual_adjacent` | adjacent faces extruded individually (back-to-back walls) |
| `bevel_seam` / `bevel_none` | seam edges skipped / nothing bevelled |
| `merged` | cleanup merged vertices — an earlier step left duplicates |

`expect` (in args or in a steps-file line): `{"faces": 287, "non_manifold": 0, "selected": [1, null], "warnings": 0}` —
stats, the op's result keys or `warnings`; exact or `[min, max]`. A failed expectation
**rejects the step**: nothing is saved and the session stays where it was.

## Session layout
```
<session_dir>/session.json   current step, mirror axis, tier, active selection
<session_dir>/log.jsonl      one JSON line per step (op, args, result, counts, checks) — includes undone steps
<session_dir>/steps/NNN_<op>[_label].blend
<session_dir>/snaps/NNN.png  viewport snapshot (and NNN.json data)
<session_dir>/report/        report.md, construction.png, report.html
```
To branch, copy the session directory.

## Conventions
- Z up, the model faces **−Y** (front view looks along +Y), X is the model's left.
- With `mesh-mirror` set up you edit only the **+X half**; the snapshot shows the mirrored
  whole. Like Blender's mirror clipping, seam vertices stay on x = 0 through every
  operation, and a median pivot of a selection touching the seam sits on the mirror plane.
- Selections are named (`"sel": "lid"`). Operations that create geometry store their result
  under a name (`"result": ...`) and make it the active selection, so the next step can use it.
- What a name covers as the mesh changes: faces split by a loop cut and inset rims stay in
  the selections of the face they came from; an extruded cap keeps its source's names (it is
  the same face, moved — so `lid` follows the top of the last extrusion); new extrude walls
  belong only to `<result>_sides`. A whole part is therefore cap + every `*_sides` of its
  segments, listed in `where.in`.
- Units are metres. Decide sizes from the reference/concept before modelling (concept-fidelity's
  part-extents table, or measurements you write down).

## Working rhythm (like an artist at the viewport)
1. Before a step, know what it should change and roughly the numbers (put them in `expect`
   when you know them exactly).
2. Run it; read the log line and the check lines.
3. Look at the snapshot after every structural step (primitive, mirror, extrude, loop cut,
   bevel, subdivision) and at least every ~5 steps otherwise — the checks catch broken
   topology, not a wrong shape. If it is wrong, `undo` rather than patching on top.
4. At milestones and at the end: `mesh.py S finish`.

## Other operations
- `material` — `{"sel": "<faces>", "name": "Wood", "color": [r,g,b], "metallic": 0, "roughness": 0.6}`
  assigns a Principled material to the selected faces (metallic 0 or 1). Without `sel`:
  a material new to the model goes on every face (the base material); an existing one is
  only **retuned** (colour/metallic/roughness change, assignments kept). `"sel":"*"` forces
  all faces. Extruded/inset faces inherit their source face's material.
  `"alpha": 0.35` makes it see-through (blended, and it survives glTF); `"emission": 3` makes it glow.
- `note` — saves a step with a snapshot and no change (checkpoints; `{"tier":"pc"}` sets the tier).

## Render only
```bash
"<blender>" -b --python "<this skill>/scripts/render_session.py" -- <session_dir> <out.png> [--res 1000] [--exposure 0] [--fill 0.85]
```
Studio lights calibrated so albedo 0.18 renders near mid-grey, a camera framed on the
model, Cycles; keeps the modifier stack (mirror, subdivision) of the current step.
`--fill` sets how much of the frame the model fills (default 0.85); `--view front|side|back` gives an orthographic turnaround view on a plain background, to set beside a concept sheet. `finish` calls it for you.
`--blend FILE` renders another saved file, `--pose JSON` poses its rig, and `--attach`, `--attach-bone`,
`--attach-drop`, `--attach-handle`, `--attach-light` hang a prop from a bone.

`mesh.py <session> finish` takes `--tier`, `--res`, `--samples`, `--exposure`, and `--asymmetric` for a model
with no left-right symmetry. A `run` that stops leaves `stopped.txt` in the session, and every gate refuses
to score until a run finishes. Build scripts pipe into `grep`, which hides the exit code, so this is what
stops a half-built model from scoring.

`selftest` writes into `mesh_selftest_tmp` in the working folder unless given `--keep DIR`. `compare` needs each
step's saved file, so it cannot read a session built with `--no-snap`.
