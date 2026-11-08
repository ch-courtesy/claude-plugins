---
name: concept-fidelity
description: Turn 2D concept art (a character turnaround / model sheet / 원화 with front and side views) into a measured 3D blockout and tell how faithfully it matches — segment the painted sheet into per-view part labels, check the drawing's own front-vs-side consistency, fit a parametric blockout with CMA-ES on silhouette and part IoU, score held-out views, repeat over seeds, and report what is a drawing contradiction versus a modelling limit. Use whenever the user has concept art or a turnaround and wants a 3D model/blockout built from it, asks whether a model matches its concept, wants a turnaround checked for inconsistencies between views, or wants to compare blockout versions numerically — even if they only say "make this drawing 3D" or "does my model look like the 원화". 원화→3D, 턴어라운드 피팅, 원화 충실도·일관성 검사에 사용.
---

# Concept fidelity

Measure, then improve, how well a 3D blockout reproduces a 2D turnaround. Silhouettes and
part placement are quantitative; appeal is not — keep a human look at the end (an
optimisation once raised its score while turning a snout into a beak).

All scripts are in `scripts/`. Blender (4.x/5.x, headless) runs the ones that need numpy;
`concept_report.py`, `fit_sheet.py`, `compare_sheet.py`, `summarize_runs.py` need only system Python + Pillow.
Use absolute paths. For Blender pitfalls see the 3d-asset-review skill's
`references/blender-headless.md` if it is installed alongside.

## Pipeline

### 1. Concept → part-label maps
A label map is a PNG per view whose pixel value is a part id (0 = background), plus
`concept.json` with the window of each view (`size` m, `res` px, `frames.{view} = [u, v]`
centre) and `parts {id: {name, rgb}}`. Views: `front` (u = x), `side` (camera on +X, the
character faces **left**), `back`, optional `top`.

- **Painted sheet** → `segment_turnaround.py` with a config (`assets/segment_example.json`):
  ```bash
  "<blender>" -b --factory-startup --python scripts/segment_turnaround.py -- <config.json>
  ```
  It writes `labels_*.png`, `vis_*.png` and `concept.json`. **Look at `vis_*.png` next to the
  source crops before going on** — read `references/segmentation.md`; every sheet so far
  needed its thresholds set from measured edge pixels, not guesses.
- **Drawn by you** (a new original concept): draw the label maps directly in code and write
  `concept.json` yourself.
- Pick the side view that faces left; a right-facing profile must be mirrored or swapped for
  its counterpart column.

### 2. Check the drawing before modelling
```bash
python -I scripts/concept_report.py <concept_dir> "" 1.5
```
Writes `feedback.md` / `feedback.png`: parts whose top/bottom/centre height differ between
front and side by more than the tolerance, plus a **part-extents table** to seed the model.
Height gaps can be real contradictions *or* occlusion / segmentation noise (a big tail hiding
legs, eye whites classified as glove white) — say which, don't report raw gaps as errors.

### 3. Write the parametric model
Copy `scripts/model_template.py` next to the concept and edit it (`references/models.md`):
one primitive group per label, first guesses from the extents table, **bounds wide enough to
reach what every view shows**. Smoke-test speed: one render of two views should take
≲ 50 ms; analytic ellipsoids/sphere chains are ~10x faster than metaballs.

### 4. Fit with several seeds
```bash
"<blender>" -b --factory-startup --python scripts/fit_model.py -- \
  --model <model.py> --concept <concept_dir> --out <runs>/s1 --gens 400 --seed 1
```
Run seeds 1–3 (in parallel — each is one process) and summarise:
```bash
python -I scripts/summarize_runs.py <runs>/s1 <runs>/s2 <runs>/s3
```
Fitting uses front+side by default; `back`/`top` maps, when present, are **held out** and only
scored — they reveal wrong depth or wrong 3D placement that the fitted views hide.

### 5. Look at where it is wrong
```bash
"<blender>" -b --factory-startup --python scripts/overlays.py -- <runs>/s1/fit.npz <runs>/s1/img <concept_dir>/concept.json
python -I scripts/fit_sheet.py <runs>/s1 <runs>/s1/img <runs>/s1/sheet.png
```
Red = missing, blue = extra, orange = wrong part. Read `references/interpretation.md` to
decide whether a gap is a modelling assumption (fix bounds/vocabulary), a contradiction in the
drawing (report it to the artist) or an optimiser/seed effect (more seeds).

### 6. Improve and re-measure
Change one thing at a time (widen a bound, add a primitive, add a design-intent `prior()`),
rerun ≥ 3 seeds, compare means. Build the final 3D only from the same primitives the fit used,
then review it with the 3d-asset-review skill.

## Measure a finished model
Steps 3–6 fit a blockout. To measure a mesh that already exists (for instance one built with
the box-modeling skill), project it into the concept's views instead of fitting anything:
```bash
"<blender>" -b <model.blend> --python scripts/compare_model.py -- --concept <concept_dir> --out <dir> \
    [--object Model] [--map Brass=buckle]
python -I scripts/compare_sheet.py <dir>
```
For a mesh-session model, `mesh.py <session> fidelity <concept_dir> [--map Brass=buckle]` does
both on the current step and writes to `<session>/fidelity/`. Materials stand for parts of the
same name; `--map` renames. Nothing is aligned, so a wrong size or position counts. Output:
per-view IoU, part IoU and contour distance, per-part extents, the largest gaps as a list
(`compare.md`) and a concept | model | difference sheet.

- To model from a concept, print its cross-sections first:
  `python -I scripts/concept_profile.py <concept_dir> --step 0.05 --half-front` lists, per
  height, where each part sits in each view. The box-modeling skill's
  `references/plan-from-concept.md` builds rings from these numbers.
- Known answers: a model against its own label maps (`--export`) gives IoU 1.000; a concept
  moved up 5 cm gives gaps of exactly −5.0 cm. The contour figures sample points at random,
  so read them to about 1 cm on the maximum, 0.1 cm on the mean.
- **The concept must come first, or from someone who has not seen the model.** A concept
  drawn afterwards by whoever built the model only repeats the model and proves nothing;
  brief a separate agent with the text brief alone and keep it away from the model files.
- A gap is a question, not a verdict: the concept may be the better design, or the model may
  have improved on it. Decide per gap, then edit the steps file and replay.

## Report format

```markdown
# Concept fidelity: <character> (<n> seeds)
| View | IoU | Part IoU | Contour cm |   (mean ± sd; mark held-out views)
## Drawing consistency
- real contradictions (with heights) / occlusion or segmentation artefacts
## What limits the fit
- modelling assumptions found (bound, missing primitive) / drawing contradictions / noise
## Next change and expected effect
```

State what was measured, what was judged from images, and what was not checked. Typical
numbers seen so far: a self-consistent drawn concept fits to ~0.91–0.93 silhouette IoU; a
real painted sheet with heavy occlusion to ~0.83–0.87; a perfect round-trip (concept rendered
from the model itself) to ~0.98.

## Rights
Fitting someone else's character is a private exercise unless their licence allows more.
Record the source and licence next to the sheet (an `ATTRIBUTION.md`), and do not publish
derived models of other people's characters without permission.
