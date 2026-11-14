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
| skeleton | for a game character give a `root` on the ground (parent of the hips) and `clavicle` bones between chest and upper arm: engines take travel from the root, and an arm with no clavicle cannot lift the shoulder |
| a bone's `follows` + `share` | a helper bone at a joint that takes a share of another bone's rotation; a part names it as `"helper"` to blend parent → helper → child |

### Keys for joined bodies and game skeletons (added 2026-11-13; a spec without them rigs exactly as before)
| key | meaning | why |
|---|---|---|
| part `"region": true` | the rule weights only the vertices of its own faces, not the whole piece; whole-piece rules claim pieces first, then region rules claim vertices (first in the spec wins a border vertex) | a torso joined to its trousers (or sleeves) is one piece but needs different chains in each region |
| part `"smooth": n` | a border between two rules of one piece is averaged over n rings of edges (the larger n of the two; 0 keeps it sharp) | a jump in weights at a region border stretches one row of faces. Keep n at 1 on a cage with rings 5–15 cm apart: 2 carried trouser weights up into the armpit |
| part `"side_blend": m` | each vertex is weighted on its own side (evaluated mirrored with the .L bones); within m metres of x = 0 the sides mix | a piece that crosses the middle (one-piece trousers, an apron on two bone columns) has no single side. Outside the band a vertex keeps only its own side's bones |
| part `"blends": [...]`, `"shifts": [...]` | blend width per joint of a chain; each step moved that far past its joint | a hip needs 0.5 m, a knee 0.1 m; a step can sit just outside an overlap instead of on the pivot |
| part `"helper_joint": i` | with `helper` on a chain of 3+ bones: the joint the helper sits at (0 = first) | the 2-bone helper behaviour is unchanged |
| part `"measure_as": part` | measure this region's stretch with another region | a rigid strip (a crotch on its own bone) has no bend bound of its own; its stretch belongs to the trouser legs it joins |
| bone `"auto_raise": {"arm", "from_deg", "ratio", "max_deg", "soft_deg", "keep_arm"}` | a clavicle lifts by `ratio` of the angle the arm's elbow is above `from_deg` past the horizontal, easing in over `soft_deg` (default 20) and saturating towards `max_deg` (tanh), so neither end kinks; with keep_arm (default) the arm is turned back so it keeps its pose direction | shoulders rise when arms go overhead; measured from the elbow, not the hand, as riggers do. Musoe: 0.35, 18° → the shoulder top rises 2.7 cm at 170° |
| bone `"driven_by": [{"bone", "share"}]` | a corrective leaf bone takes `share` of each source's world rotation (negative turns against it) | a crotch bone between both thighs. One share cannot serve one leg and both legs: Musoe's crotch line moved 3.6 cm at share 0 and 2.5 cm at −0.1, but −0.05 already over-stretched the squat |

The pose rules live in `scripts/pose_rules.py` so every script that poses a rig (an animation bake, a measuring
script) can apply them the same way; rig_session applies them to every spec pose, never to baked frames. A pose
report gains `auto_raise_deg` when the spec uses the rule.

**Measuring a joined piece.** With region parts, stretch, folds and area are measured per (region, side): a body
measured as one piece would hide an armpit in the average. Volume stays per piece. The symmetry check compares a
vertex's X.L with its mirror's X.R, since a vertex in a side band legitimately holds both.

**What joining costs (Musoe v2, 2026-11-13).** One-piece trousers joined to the torso passed every gate. A sleeve
grown out of the torso of an A-posed arm (40° down) did not: raising it 120–170° must stretch the armpit about 90% on
average however the weights are spread (the hand travels ~0.5 m against ~0.3 m of skin), and the per-region
stretch reached 3.7 times the bound. Bending a deep sleeve overlap on the clavicle instead lost 26–39% of the
sleeve's volume. A blend across a rolled cuff or gathered hem that sits on the joint stretched it 110–150%. For such
a design keep the overlap at the clothing border, rigid on each side, and let the clavicle carry the sleeve.

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
