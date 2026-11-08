---
name: mesh-rig
description: Rig a mesh-session character built from parts — bones from a spec, computed weights (a part rigid on one bone, or blended along a bone chain), then bend it through test poses and measure the damage (volume change, edge stretch, face squash, gaps opening between parts) with a contact sheet of the poses. Use when a modelled character needs an armature, when weights or joints deform badly, or to test whether a model's joints hold up; part of the stage-gate pipeline after modeling. 캐릭터 리깅, 웨이트, 포즈 변형 시험.
---

# Rig — bones, computed weights, and a bend test

```bash
mesh.py <session> rig rig.json        # writes <session>/rig/: rig.blend, report.json, poses.png
mesh.py <session> gate rigging
```
Apply the mirror first (`mirror` with `"mode":"apply"`, last line of the plan). A worked spec is
`box-modeling/references/lampkeeper_rig.json`.

## Spec
| key | meaning |
|---|---|
| `bones` | `name`, `head`, `tail`, `parent`; `"mirror": true` makes `name.L` at +x and `name.R` at −x |
| `parts` | `part` (a named selection; every connected piece holding it) with `bone` (rigid) or `chain` + `blend` (metres each joint blends over) |
| `split` in a part | instead of `chain`: `low`, `high`, `at`, `width` blend two bones by height, for a foot that must stay rigid; `helper` adds a joint helper, `fade` [axis, from, to] keeps the upper bone off what sticks out, like a toe |
| `attach` | pairs of parts that must stay together; the report gives the largest gap opened |
| `poses` | `name`, `rot`: `bone`, world `axis`, `deg`; `.L` entries are mirrored to `.R` unless `"mirror": false` |
| `preserve_volume` | dual quaternion skinning on the Armature modifier. Leave it off for game engines: glTF skinning is linear, so the effect would not survive export |
| a bone's `follows` + `share` | a helper bone at a joint that takes a share of another bone's rotation; a part names it as `"helper"` to blend parent → helper → child |

Weights are computed, not bone-heat: automatic weights are unreliable on overlapping separate
parts, and this way they are predictable and exactly symmetric.

## What to do with the report
Every pose names its worst part for each measure. Read `poses.png` as well: a fold, a limb
through the body and a stiff pose are for your eyes.
- **Volume loss at a joint**: too few rings. Rings around the joint did more than anything else
  (elbow 16% to 3%). Add 2–3 in the plan; `preserve_volume` helps a little.
- **Volume loss under linear skinning**: blended positions follow the chord, not the arc, so the
  middle of a joint bent by θ keeps only cos(θ/2) of its radius. A helper bone taking half the
  rotation lifts that to cos(θ/4). Measure with the skinning the target uses: dual quaternions
  passed this gate here, then failed at 15% when the engine's linear skinning was measured.
- **Stretch**: widen `blend` until it spans most of the limb; stretch at the middle of a joint is
  about r·θ/blend. Joint steps are linear by default (`"blend_profile"`): a smoothstep is 1.5 times
  steeper in the middle. Read the per-part figure: over the whole body a wider blend looks worse,
  because more edges stretch a little, while the worst stretch on the limb falls by half.
- **A bone dragging too much**: move where the chain starts. Starting a hood's tail behind the
  head instead of on it took the hood's volume change from 10.7% to 0.2%.

## How the bend is judged
A limb of radius r bent by θ over length L stretches its outer side by about r·θ/L however good
the rig is. So stretch is judged against that bound: each part may reach max(35%, 1.2 × r·θ/L),
and `stretch_excess` is the worst share of that allowance. On a stubby character the bound
is high (elbow 58%, knee over 100%), which is geometry, not a rig fault.

Folds are counted directly: an edge folds when its faces were within 60° of each other at rest
and are over 120° apart in the pose. `fold_share` is the worst part's share of folded edges; 1%
allows one crease line. Face area is reported but not gated: it recovers once faces fold over.

Test the rig again after any change to the model.

## Short, deep legs
`height` in the spec is the expected model height, read by the export. On a leg deeper than it is long, stretch
and volume can conflict at every blend width: one leg .41 m deep and .32 m long failed one or the other at any
blend, and moving the knee down 2 cm passed both. Try the joint's position before the blend.
