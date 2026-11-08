---
name: mesh-loopcut
description: Add edge loops to a mesh-session model by cutting across a quad edge ring (one or several cuts, or one cut at an exact coordinate) — to add resolution where the form bends, separate parts (lid line), place joint loops, and add support loops that keep edges sharp under subdivision. Use whenever more edges are needed in a region; part of the box-modeling procedure. 루프 컷(폴리곤 분할)으로 해상도·관절·지지 루프 추가.
---

# Loop cut — put edges exactly where the form needs them

## Command
```bash
mesh.py <session> loopcut '{"at":{"axis":"z","value":0.42},"result":"lid_line"}'
mesh.py <session> loopcut '{"where":{"along":"y","nearest":[0.5,0,0.7]},"cuts":3,"result":"arch_loops"}'
```
| key | meaning |
|---|---|
| `at` alone | **easiest**: every edge ring whose edges run along `axis` and cross `axis` = `value` is cut there; `value` may be a list (several loops, e.g. support loops on both sides of an edge) |
| `within` | with `at` alone: only rings seeded from edges matching this mesh-select `where` (one part) |
| `where` | picks the **edge ring** explicitly: the edge nearest `nearest` among edges parallel to `along`; the ring is grown from it (needed for `cuts` > 1) |
| `ring` | instead of `where`, an existing named edge selection |
| `cuts` | number of loops, evenly spaced |
| `at` | (one cut) place the loop where `axis` = `value` on every ring edge |
| `fraction` | (one cut) position along the ring edges, measured from the low end (smaller coordinate) of the edge picked by `where`, on that same side all the way round (default 0.5) |
| `result` | name for the new edge loop |

The ring stops at triangles/n-gons and at open borders (the mirror seam) — keep the mesh
quads where you want loops to run through.

## at or fraction
`at` puts the loop on a plane, which suits a ring whose edges all cross it. A ring can run
through parts of different widths (a head ring continues down a narrower neck into the
torso); `at` then misses those edges and `loopcut_span` warns. Use `where` + `fraction`
there: it keeps one proportion across every width. Rings run as far as the quads do, so
expect such a loop to cut the parts it passes through; `within` only chooses which rings
are cut, not how far they go.

## Where loops go (craft)
- **Form changes**: wherever the silhouette bends you need a loop (an arch needs ≥ 2–3).
- **Part lines**: a loop at the lid/body split, collar, belt.
- **Joints** (characters): 2–3 loops around elbows, knees, shoulders; circular loops around
  eyes and mouth come from insets, not loop cuts.
- **Support loops**: a loop close to a hard edge (2–5% of the face width) keeps that edge
  sharp after subdivision; the closer, the sharper. Use `at` with value = edge coordinate ±
  a small offset.

## Check
- Automatic: `loopcut_span` (the plane does not cross some ring edges — wrong ring/value),
  new `tris`/`ngons`; an `at` plane that crosses nothing fails the step.
- Log: `rings`, `new_verts` = ring edges × cuts. Look: the orange loop runs all the way
  around (or to the seam) where intended, and only around the parts you meant.

## Mistakes
- Picking the wrong ring direction (`along` is the direction of the edges being cut, not of
  the new loop).
- Many evenly spaced cuts everywhere — density belongs where the shape or deformation needs it.
