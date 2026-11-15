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
| bone `"bend_max": deg` | the most the joint at this bone's head may close: degrees between the bone and its parent, 0 = in line. The bake reports how far past it any frame goes, and the animation gates fail on any excess (`joint_range_excess_deg`) | an elbow folded past what the arm allows hides inside overlapping parts but cannot be skinned. Give the forearm and the shin one: Musoe uses elbow 140, knee 150 |
| bone `"bend_toward": [x, y, z]` (with `bend_max`) | the joint is a hinge: at rest, the world direction this bone swings when the joint closes (mirrored in x on .R). The bend is then signed about the hinge axis, which rides on the parent, so a parent turned about itself turns the hinge with it; `"bend_min"` (default −10) limits a bend the wrong way and `"side_max"` (default 20) a fold out of the hinge's plane | an IK that aims each bone the shortest way leaves the parent's own turn to chance: Musoe's arms had elbows bent 112° backwards and 78° sideways, unseen with rigid parts. With it the bake also keeps hinges in their plane (see mesh-animate) |

The pose rules live in `scripts/pose_rules.py` so every script that poses a rig (an animation bake, a measuring
script) can apply them the same way; rig_session applies them to every spec pose, never to baked frames. A pose
report gains `auto_raise_deg` when the spec uses the rule.

A script that solves a limb by IK (a pose kit that places a hand) should turn the limb's root about itself with
`pose_rules.align_hinge(rig, child, toward, p × u, update)` after aiming it, where p is the pole (the side the
elbow or knee points to) and u the root-to-end line: the hinge is then p × u however far the limb is bent, so a
nearly straight limb gets a defined turn too. `hinge_roll` gives the turn without making it; keep it within what
the joint allows (about ±90° for a shoulder) by swinging the pole round u. `scripts/test_pose_rules.py` checks the
rules on a two-bone arm (`blender -b --factory-startup --python test_pose_rules.py`).

**Measuring a joined piece.** With region parts, stretch, folds and area are measured per (region, side): a body
measured as one piece would hide an armpit in the average. Volume stays per piece. The symmetry check compares a
vertex's X.L with its mirror's X.R, since a vertex in a side band legitimately holds both.

**Joined joints (arm lab, 2026-11-16).** A limb joined to the body bends as one skin when the weights obey three
rules; Musoe's v2 and v3 attempts, and eight variants of their weights, failed only for want of them.
1. *Blend only inside the joint's region, one rigid wall short of each end.* Subdivision moves a face from the cage
   rings round it, so a face just outside a blend stretches with it while its own part's bound has no bend: v3's
   elbow failed at 2.7 times the bound in the sleeve at 90 degrees. A chain blend 0.10 m wide, 3.25 cm past the
   pivot, with the half-turn helper, inside an elbow region of five 4 cm walls: 0.6–0.8 from 60 to 140 degrees.
2. *Let the shoulder's turn spread over the body.* The armpit region (body faces round the hole, and the shoulder top)
   solved with `harmonic`, its `conduct` 0.1 against the sleeve's 1, so the blend runs out over the flank instead of
   gathering at the apex; the shoulder pivot 2.5 cm below the arm's axis; `auto_raise` gentle (0.1, 6 degrees: more
   lifted the apex with the clavicle); the torso's spine-to-chest step below the armpit, so a chest twist turns the
   flank with it. With the geometry of box-modeling's continuous-body reference, the lab's worst pose was 0.94.
3. *Find the faces, not the part.* Each pose's `stretch_at` lists the worst part's five most strained edges with their
   rest midpoints and lengths. A part's name alone sent the earlier attempts to tune weights for faults that were
   5 mm sliver rows and border faces.

Keys of the joined-joint rules (part keys unless noted; a spec without them rigs as before):
| key | meaning |
|---|---|
| `"harmonic": 1` (2: biharmonic) | the region's weights solved along the surface between its neighbours' (each vertex the mean of its cage neighbours) |
| `"helper"` + `"child"` with `harmonic` | the solved blend split parent → half-turn helper → child |
| `"free_arc": [lo, hi]` | only the stretch of the rule's chain between lo and hi metres is solved; the rest keeps the chain's weights |
| `"pivot"`, `"pivot_power"` | edges conduct in proportion to (distance from that bone's head) ** power: the blend gathers near the joint (power 1 was best for a shoulder; negative is worse) |
| `"conduct"` | a factor on the conductance of the region's own edges: below 1 the region takes more of the blend |
| bone `"follows"` + `"twist_share"` | the helper takes `share` of its source's swing and `twist_share` of its twist (a forearm turned 180° about itself must not twist the elbow) |

**What joining cost before (Musoe v2, 2026-11-13).** Grown out of the torso of an A-posed arm (40° down), with rings
bunched at the armhole and a blend reaching its region's borders, the sleeve stretched 3.7 times the bound; a deep
sleeve overlap bent on the clavicle lost 26–39% of its volume. Both are superseded by the rules above.

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
