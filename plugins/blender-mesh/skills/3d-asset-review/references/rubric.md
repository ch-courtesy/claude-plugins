# 3D asset rubric

How to judge a 3D asset (typically a stylised game character) without lumping
everything into "does it look good". Each discipline is split into
**quantitative** checks (measured by `scripts/inspect_model.py`, or by a named
procedure) and **qualitative** checks (human judgement, deferred until the
quantitative layer is clean).

## Contents
1. Principles
2. Target tiers
3. Modeling
4. Texturing
5. UV and baking
6. Rigging and deformation
7. Render / look-dev
8. Concept fidelity
9. Qualitative review
10. Reporting rules
11. Sources

## 1. Principles

- **Quantitative metrics are proxies.** Optimising one in isolation can make the
  asset worse (seen in practice: a fit raised its silhouette score while turning a
  snout into a beak). Pair every optimised number with a look at the images, and
  encode design intent as a constraint when it matters (e.g. keep snout proportions
  near the design, accept a small score cost).
- **Metrics conflict.** Lower UV stretch usually means more seams; lower shape
  error usually means more polygons. Treat budgets as constraints and compare the
  rest together instead of maximising one.
- **Thresholds depend on the use case.** Published budgets differ by 5x between
  sources. Pick a tier (section 2) per project rather than trusting one number.
- **Where there is no standard, test.** There is no agreed loop count per joint;
  the agreed practice is to pose the mesh and look. Prefer outcome tests (pose,
  bake, render) over structural rules when practitioners disagree.
- **The builder should not be the only judge.** Qualitative review is more
  trustworthy from someone (or an agent) that only sees the outputs.

## 2. Target tiers (`assets/tiers.json`)

| Tier | LOD0 triangles (hero character) | Max bone influences | Texture size |
|---|---|---|---|
| mobile | ~1.5k–10k in published guides; default limit 10k | 4 | 1024 |
| pc / console | ~15k–80k in published guides; default limit 50k | 8 | 2048 |
| film / offline | not budgeted | — | 4096 |

Budgets apply to the **base cage** (what a game engine receives). Subdivision used
only for rendering is reported separately (`tris_render`) and does not count.

## 3. Modeling (polygon construction)

| Check | Measure | Default pass | Auto |
|---|---|---|---|
| Hygiene | non-manifold edges/verts, coincident duplicate verts, zero-area faces, inward normals | all zero | yes |
| Islands | loose parts per object | as designed (1 for a unified body) | yes (reported) |
| Topology mix | quads / tris / n-gons | deforming meshes quad-dominant, no n-gons | yes (reported, n-gons warned) |
| Budget | base-cage triangles | ≤ tier LOD0 | yes |
| Ground contact | lowest point of the model | within ±1 cm of z=0 | yes |
| Rest symmetry | max mirror error about X=0 | ≤ 1 cm (if designed symmetric) | yes |
| Edge flow | loops/rings continuous, following the form; no pinching or swirls | — | no (wireframe render to review) |
| Support loops | hard edges held by nearby loops under subdivision | — | no |
| Shape fidelity | silhouette/part IoU against the concept, held-out views | see section 8 | via concept-fidelity skill |

Notes from practice: automatic retopology (e.g. Quadriflow) produces uniform,
symmetric quads but does not follow anatomy; it is fine for static or stylised
blobs and weak for faces and joints. Voxel remeshing can leave coincident
duplicate vertices that make Quadriflow refuse the mesh — merge by distance first.

## 4. Texturing (colour and surface)

| Check | Measure | Default pass | Auto |
|---|---|---|---|
| Metalness | Principled `Metallic` value per material | 0 or 1 (±0.05); in-between values are not physically plausible | yes (unlinked values) |
| Roughness | `Roughness` value | 0.1–0.9 | yes |
| Albedo range | sRGB luminance of non-metal base colour | 0.03–0.95 (avoid pure black/white) | yes |
| Metal albedo | brightest sRGB channel of metal base colour | ≥ 0.70 (~180/255) | yes |
| Colour space | non-colour maps (roughness, normal, AO) read as Non-Color | — | no |
| Noise defects | speckle / stripe artefacts in the beauty render | none visible | no (review renders) |
| Texture memory | resolution × channels × count | within project budget | no |

Values driven by texture maps are not inspected (only unlinked defaults). Stylised
hand-painted work may deliberately break PBR rules; record it as a design decision
instead of silently ignoring the warning.

## 5. UV and baking (model ↔ texture)

| Check | Measure | Default pass | Auto |
|---|---|---|---|
| UVs exist | active UV layer on textured meshes | present | yes |
| Texel density spread | area-weighted CV of relative texel density | ≤ 0.25 | yes |
| Texel density | px per metre at tier texture size | consistent across assets | reported |
| Utilisation | share of 0–1 UV space covered | ≥ 50% | yes |
| Overlap | texels claimed by more than one island | ≤ 1% unless mirroring/tiling is intended | yes |
| Seams | on hard edges, material breaks or hidden areas | — | no (review) |
| Padding | gap between islands at target resolution | enough for mip filtering | not yet measured |
| Bake quality | ray misses / artefacts of high→low normal and AO bakes | none visible | not yet automated |
| Lightmap UVs | separate non-overlapping set if the engine needs one | — | no |

Draw calls come from material count, not from seams.

## 6. Rigging and deformation

| Check | Measure | Default pass | Auto |
|---|---|---|---|
| Binding | vertices with no bone weight | 0 | yes |
| Influences | max bones per vertex | ≤ tier limit | yes |
| Joint topology | loops around elbows, knees, shoulders, hips; circular loops around eyes and mouth | — | no |
| Pose test | volume loss / collapse / self-intersection at extreme poses | no visible collapse | no (render poses and look) |

## 7. Render / look-dev

| Check | Measure | Default pass | Auto |
|---|---|---|---|
| Emissive colour | glowing parts keep their hue | not washed to white | no |
| Exposure | clipped highlights / crushed shadows | small | no |
| Noise | render noise after denoising | none visible | no |

Lesson from practice (Blender AgX view transform): bright emission desaturates to
white. Use a pure emission shader (black base, no specular), moderate strength, and
a bloom pass instead of raising strength.

## 8. Concept fidelity

Use the `concept-fidelity` skill. Report per view: silhouette IoU, mean part IoU,
mean contour distance (cm). Always include at least one **held-out view** (a view
not used for fitting): it is what reveals wrong 3D placement that front/side fits
hide. Concept inconsistencies (same part at different heights in different views)
are reported separately so modelling errors and drawing errors are not mixed up.

## 9. Qualitative review (deferred, but never skipped)

Ask an independent reviewer to look at: silhouette readability (a small black
silhouette is still recognisable), appeal and personality, style coherence, edge
flow aesthetics on the wireframe, and whether the result still matches the design
intent after optimisation. Note any rule broken on purpose (e.g. stylised PBR).

## 10. Reporting rules

- Optimisation results (fits, searches): at least **3 seeds**, report mean ± sd and
  the range. A single run can be lucky — in practice one lucky run produced two wrong
  conclusions that three seeds reversed.
- State which numbers were measured, which were judged by eye, and which were not
  checked.
- Keep the report and the images together (contact sheet) so a number can be
  checked against what it describes.

## 11. Sources (practitioner guides; conventions, not formal standards)

- Edge flow and box/subdivision modelling: [TurboSquid CheckMate edge flow](https://blog.turbosquid.com/2013/09/09/checkmate-pro-v2-specification-checking-edge-flow/), [Adobe – box modelling](https://www.adobe.com/uk/products/substance3d/discover/box-modeling.html), [Polycount – support loops](https://polycount.com/discussion/comment/1070194)
- High→low workflow and baking: [Blender Artists](https://blenderartists.org/t/game-character-workflow-when-to-texture-and-bake-normals/640366), [Polycount](https://polycount.com/discussion/206872/new-to-baking-normal-maps-for-games-objects)
- Hard surface: [Morphic glossary](https://morphic.com/3d-glossary/hard-surface-modeling), [SEELE weighted normals guide](https://www.seeles.ai/features/tools/dcc-weighted-normals-hard-surface-bevel-guide)
- Deformation topology: [NovEdge](https://novedge.com/blogs/design-news/zbrush-tip-anatomy-driven-retopology-for-predictable-deformation), [Shoot First](https://www.shootfirst.art/toplogy), [IRPR glossary](https://3d.irpr.agency/glossary/edge-loop/)
- UVs: [IRPR glossary](https://3d.irpr.agency/glossary/uv-unwrapping/), [Polycount](https://polycount.com/discussion/comment/1826777)
- PBR values: [Microsoft PbrMaterial](https://learn.microsoft.com/en-us/cpp/api/remote-rendering/pbrmaterial), [BlenderKit](https://www.blenderkit.com/docs/tutorials/most-common-upload-problems/material-pbr-incorrect), [Cocos PBR](https://docs.cocos.com/creator/manual/en/shader/effect-builtin-pbr.html)
- Budgets and LOD: [CRYENGINE character budgets](https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1114113/pages/1310905), [Futureverse polycount](https://docs.futureverse.com/dev/build-an-asset/asset-creation/resource-creation/resource-creation-guidelines/modeling/polycount), [Neural4D](https://blog.neural4d.com/user-guide/polygon-count-for-3d-game-assets/)
