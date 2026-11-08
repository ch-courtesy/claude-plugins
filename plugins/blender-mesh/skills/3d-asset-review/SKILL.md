---
name: 3d-asset-review
description: Review and score a 3D asset (Blender .blend, usually a game/stylised character) against a discipline-split rubric — modeling (mesh hygiene, topology, triangle budget, ground contact, symmetry), texturing (PBR value validity), UV/bake (texel density spread, overlap, utilisation), rigging (binding, bone influences) and render — producing clay/wireframe review renders, a JSON report and a contact sheet, then a written review that separates measured facts from judgement. Use this whenever the user asks to check, inspect, QA, grade, critique or "is this model good / game-ready / done?" for a 3D model or character, wants clay or wireframe views, asks about poly count, topology, UVs, PBR values or rigging problems, or before you declare your own Blender modelling work finished — even if they never say "rubric". 3D 모델 검사, 품질 평가, 루브릭 채점, 토폴로지·UV·텍스처·리깅 점검, "이 모델 괜찮아?" 같은 요청에 사용.
---

# 3D asset review

Judge a 3D asset by discipline instead of by overall impression. The quantitative
layer is measured by a script; the qualitative layer is a short, explicit human-style
review on top. Read `references/rubric.md` for what each check means and why its
threshold is set where it is.

## 1. Find Blender

Headless Blender 4.x/5.x is required. Look for it in this order and remember the path
for the rest of the task:

- `blender` on PATH (`Get-Command blender` / `which blender`)
- Windows: `C:\Program Files\Blender Foundation\Blender <ver>\blender.exe` (pick the newest)
- macOS: `/Applications/Blender.app/Contents/MacOS/Blender`

The scripts use only Blender's bundled Python (it has numpy). `sheet.py` needs a system
Python with Pillow.

## 2. Pick the target tier

Budgets and limits depend on where the asset goes: `mobile`, `pc` (default) or `film`
(see `assets/tiers.json`). Use what the user said; if nothing, use `pc` and say so in the
report. Published budgets disagree a lot, so a tier is a project decision, not a fact.

## 3. Run the inspector and build the contact sheet

```bash
"<blender>" -b "<model.blend>" --python "<skill>/scripts/inspect_model.py" -- "<out_dir>" --tier pc
python "<skill>/scripts/sheet.py" "<out_dir>" "<out_dir>/sheet.png" ["<beauty.png>"]
```

- Use absolute paths. `--no-render` gives numbers only (seconds instead of ~30 s).
- Objects named `ENV_*` and large flat sheets (ground, backdrop) are excluded
  automatically; `report.json` lists what was excluded — check it is really scenery.
- Outputs: `report.json` (all numbers, warnings grouped by discipline), `front/side/back/top.png`
  (clay), `wire.png` (base cage), `sheet.png`.

## 4. Look at the images, not only the numbers

Open `sheet.png` (and a beauty render if there is one). The script cannot see edge flow,
stripes or speckles in paint, washed-out emissive colours, faces that read wrong, or a
silhouette that resembles something else. Several real defects in past work were visible
only in renders (paint leaking along a surface, coplanar planes z-fighting black) and one
was invisible to numbers entirely (an optimised snout turning into a beak).

## 5. Write the review

Use this structure so measured facts, judgement and gaps stay separate:

```markdown
# Review: <asset> (tier: <tier>)
## Verdict
<one or two sentences: usable as-is / usable after listed fixes / not yet>
## Measured (from report.json)
| Discipline | Result | Warnings |
|---|---|---|
| Modeling | <tris base/render vs budget, hygiene, ground, symmetry> | <n or "none"> |
| Texturing | <material checks> | ... |
| UV / bake | <density CV, utilisation, overlap — or "no UVs"> | ... |
| Rigging | <unweighted, max influences — or "no rig"> | ... |
## Seen in the renders (judgement)
- <edge flow, silhouette, paint defects, emission, appeal …>
## Not checked
- <rubric items with no measurement yet: padding, bake quality, pose test, seams …>
## Fixes, in order
1. <highest impact first, with the concrete operation, e.g. "merge by distance 1e-4">
```

Keep numbers exactly as measured; do not round a warning away. If a rule is broken on
purpose (e.g. stylised PBR), say so rather than hiding the warning.

## 6. Common findings and what to do

| Warning | Usual cause | Fix |
|---|---|---|
| coincident duplicate verts | voxel remesh / metaball conversion | merge by distance (~1e-4) before retopology |
| Quadriflow cancelled ("needs to be manifold") | the duplicates above | same |
| floats above / sinks below ground | proxy vs built geometry differ, unparented props | rebuild contact parts from the same geometry used for fitting; check `lowest_objects` |
| asymmetric at rest | retopology symmetry is approximate; asymmetric procedural layout | accept small values for remeshed bodies; snap symmetric layouts |
| metalness neither 0 nor 1 | "a bit metallic" shortcuts | use 0 or 1 and express wear/paint with roughness or separate materials |
| no UV layers | built with vertex colours only | unwrap before any texture or bake work (UV/bake discipline cannot be scored) |
| verts not bound to any bone | auto-weights failed (bad mesh) | fix hygiene, re-run automatic weights |

## 7. Blender headless notes

Read `references/blender-headless.md` before writing your own Blender scripts for a fix or
a re-render — it lists API changes in Blender 5.x and Windows pitfalls that cost time before.
