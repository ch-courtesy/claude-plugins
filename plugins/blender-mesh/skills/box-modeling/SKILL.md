---
name: box-modeling
description: Model a 3D object or character the way an artist does in Blender — step by step from a low-poly box, using the mesh-* technique skills in the standard order (measure → primitive → mirror → major masses by extrude and loop cuts → shape with transforms → details with inset/extrude → edge definition with support loops/bevels → subdivision → cleanup → materials → review), looking at a viewport snapshot after each structural step. Use whenever the user wants a model built "properly", "by hand", "polygon by polygon", "like a modeller would", or asks for box modelling/hard-surface/low-poly modelling, even if they only say "make a treasure chest/robot/character in Blender". 사람이 하듯 단계별 박스 모델링 절차.
---

# Box modelling — the procedure

Use the technique skills through `mesh-session` (`mesh.py <session> <op> '<json>'`). Each
numbered stage lists the skills it uses. Write a short **plan** first (`<session>/plan.md`:
stages, part list, key measurements), then work through it one operation at a time,
keeping the plan updated with what actually happened.

The mechanical parts are scripted — don't spend attention on them: every step is checked
automatically (non-manifold, new triangles/n-gons, mirror crossing, loop-cut span, inset
thickness, budget …), `expect` turns a number you know into an assertion, `finish`
renders, reviews and reports, and `export` turns the session into a replayable steps file.
Your attention goes to the plan, the selection conditions and the snapshots.

## 0. Brief and measurements
- What it is, main masses, 3–5 signature features, real size in metres. For characters:
  original design (no franchise characters); see 3d-modeling's design notes.
- Write the numbers you will use (widths, heights, where part lines are). With a concept
  turnaround, take them from concept-fidelity's part-extents table.
- For a character, get a concept **first**. Without one the model drifts from the brief and
  nothing notices: every check can be clean while the silhouette is far from what was meant.
  If the user has none, have a separate agent draw a turnaround from the brief, then measure
  with `mesh.py <session> fidelity <concept_dir>` at milestones and at the end.
- With a concept, follow `references/plan-from-concept.md` instead of stages 3–5: overlapping
  parts built ring by ring from the concept's cross-section table.
- Re-measure total height after any change to the legs or a move of the whole model.
- Decide the tier (mobile / pc / film) — it sets how many loops you can afford.

## 1. Blockout primitive — `mesh-primitive`
The main mass, coarse, base on the ground.

## 2. Symmetry — `mesh-mirror` (setup)
Right away for symmetric objects. From now on edit the +X half.

## 3. Major masses — `mesh-select` → `mesh-extrude`, `mesh-loopcut`
Grow protrusions (lid, limbs, head, handles) by extruding faces in short segments; cut part
lines (lid/body, waist, collar) with loop cuts at exact coordinates. Check the snapshot
against the brief after each mass.

## 4. Resolution where the form bends — `mesh-loopcut`
Add loops only where a curve, a joint or a later detail needs them.

## 5. Shape — `mesh-transform`
Move whole loops (arches, tapers, bulges); proportional editing for soft curves. Compare
front and side snapshots with the measurements; undo rather than over-correct.

## 6. Secondary details — `mesh-inset` → `mesh-extrude`
Panels, plates, sockets, bands, buttons: inset to make a border, extrude in or out.
`mesh-extrude` with `"along":"normals"` for strips that wrap around a form.

## 7. Edge definition — `mesh-loopcut` (support loops) / `mesh-bevel`
Decide which edges stay crisp. Support loops 2–5% from the edge, or a 2-segment bevel.

## 8. Smooth — `mesh-subsurf`
Level 2; look for pinches (triangles/n-gons in the cage) and soft edges that need support.

## 9. Clean — `mesh-cleanup`
Merge, degenerate, loose, normals. Log must show non-manifold 0 and no n-gons where the
surface deforms or subdivides.

## 10. Materials — `mesh-session` `material` op
Select faces by role (bands, plates, wood) and assign. Metallic 0 or 1. Doing this before
the last details pays off: later selections can use `"material":"Wood"` so a groove or
panel line stops at other parts instead of cutting through them. Retune colours with a
`material` step without `sel`; keep metal albedo bright (worn/dark metal is texturing).

## 11. Finish and review
- `mesh-mirror` apply if asymmetric details follow or for export.
- `mesh.py <session> finish --tier <tier>`: render, 3d-asset-review inspector (hygiene,
  budget, PBR values) and `report/` (report.md, construction.png, report.html). Fix what it
  finds and run it again. Read the render yourself — the inspector cannot judge the look.

## Rhythm and honesty
- One operation per step; read the log line and the check lines every time; look at the
  snapshot after every structural step and at least every ~5 steps. Checks catch broken
  topology, not a wrong shape.
- If a step's result is wrong, `undo` and redo it with corrected arguments.
- Put numbers you are sure of in `expect` (selection counts especially — a wrong selection
  is the most common mistake and the checks cannot see intent). When several steps go in
  one command, give each `"expect":{"warnings":0}` so the first bad step stops the rest.
- Judge the subsurf preview and the first render as a whole before polishing: proportions
  are cheap to change at that point, and the render shows what the checks cannot.
- A run of steps you have already verified (a replay, a repeated pattern) can go through
  `mesh.py <session> run steps.jsonl`; new modelling stays one step at a time.
- Report from `report/report.md` and `construction.png`: step count, final counts, check
  and review warnings, what was not done (it lists mirror/UV/texture status).

## Worked plans
- `references/plan-treasure-chest.md` — a verified 39-step hard-surface prop, with the
  mistakes made on the way. Replayable: `mesh.py <session> run
  <mesh-session>/assets/selftest/chest.steps.jsonl`.
- `references/plan-from-concept.md` — a character built from a turnaround, silhouette IoU
  0.964 / 0.949: the method, the passes and the lessons. Read it first when there is a
  concept. `references/lampkeeper_plan_steps.py` is its plan script,
  `references/lantern_plan_steps.py` a hard-surface prop done the same way.
- `references/plan-character-lampkeeper.md` — the same character from one cube and a text
  brief, 118 steps, IoU 0.705 / 0.624: how limbs and head were ordered, what went wrong and
  why a concept matters. Replayable from `hero.steps.jsonl`.
