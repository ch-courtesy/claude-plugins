# Writing a parametric blockout model

## Interface (`scripts/model_template.py`)
- `PARAMS = {name: (guess, lo, hi)}`, `NAMES`, `GUESS`, `LO`, `HI`
- `LABELS = {id: name}` — ids must match the concept's part labels
- `class Model: render(vec, views, frames) -> {view: int16 label image}`
- optional `prior(vec) -> float` — a design-intent penalty added to the loss
- import helpers as `from fid.raster import Canvas`, `from fid.shapes import ...`
  (`fit_model.py` puts the skill's `scripts/` on the import path)

## Primitives (all exact and fast in `fid/raster.py`)
| Primitive | Call | Good for |
|---|---|---|
| rotated ellipsoid | `Canvas.ellipsoids(C, A, Rs, view, label)` | heads, torsos, tails, gloves, shoes |
| sphere chain | `Canvas.spheres(C, R, ...)` with `shapes.chain` | limbs, horns, scarves, curves |
| triangle mesh | `Canvas.triangles(V, F, ...)` with `shapes.leaf_tris`, `shapes.cylinder_tris` | ears, leaves, flat or flat-bottomed parts |

Metaballs (Blender) also work but are ~10x slower per evaluation; use them only when blending
between parts matters for the silhouette. Long thin triangles leave gaps when rasterised —
subdivide them (as `cylinder_tris` does).

## Choosing parameters
- Start from the part-extents table in `feedback.md` (concept_report.py).
- One primitive group per label; give each group the degrees of freedom the views need
  (position in all three axes if the part appears at different places in different views).
- **Bounds are assumptions.** Make them wide enough for every placement the drawing shows.
  A tail tip bounded to "behind the body" could not reach the front where the drawing put it;
  the held-out back view exposed it (part IoU 0.07) and widening the bound gained ~0.1 side IoU.
- Keep the build identical to the proxy: if the fit uses a sphere chain for a leg, the built
  mesh must have the same extent (a flat-capped tube built from the same numbers floated 5 cm).
- If a part must stay mirror-symmetric, constrain it in the parameterisation
  (`shapes.sym_phase` for rings of bumps).

## Design-intent prior
When the fit distorts something the design cares about (proportions of a snout, size of the
eyes), add `prior(vec)` returning `λ · mean(((u - u_guess) / 0.1)^2)` over those parameters.
In practice λ ≈ 0.006 kept a snout within ~5% of its intended proportions for a cost of
~0.004 silhouette IoU (3 seeds each way).

## Speed check
```python
# inside Blender: time ten renders of the fitted views
```
Aim for ≲ 50 ms per two-view render; 3 seeds × 400 generations × ~15 evaluations then take a
few minutes in parallel.
