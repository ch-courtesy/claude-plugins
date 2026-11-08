---
name: stage-gate
description: Run a 3D asset through its stages (modeling, rigging, UV, texture) as a loop — measure, compare with fixed thresholds, change one thing, measure again, and move to the next stage only when the current one passes — recording every score. Use whenever the user wants an asset improved until it reaches a score, asks to keep iterating or "repeat until good enough", wants to know whether a stage is done, or asks to continue a character or prop through its pipeline. 단계별 채점·반복 개선, 기준 통과 후 다음 단계 진행.
---

# Stage gate — improve by measurement, advance by threshold

## The loop
1. **Fix the thresholds first**, in `assets/gates.json`, before the stage's first measurement.
2. Measure (each stage has its command, below), then `mesh.py <session> gate <stage> --note "<what changed>"`.
3. If it fails: pick the failing criterion with the most to gain, find its cause in the stage's
   report, change **one thing**, measure again. Keep the change only if the score improved
   and the render still looks right.
4. If it passes: **look at the result yourself**, then go to the next stage. A pass with
   something visibly wrong is not a pass: add a criterion that would have caught it.
5. Stop and tell the user after 5 passes without improvement, or when the remaining gap is a
   limit of the source (say what it is) rather than of the work.

## Rules
- Never lower a limit to get a pass. If a limit proves wrong, say so and let the user decide.
- A gate only knows what it measures. Every stage also needs a human look: renders, poses.
- A change upstream invalidates what follows: after editing the model, repeat the later stages.
- `mesh.py <session> gate --history` lists every attempt; quote it when reporting.

## Stages
| stage | measure with | reports |
|---|---|---|
| modeling | `mesh.py S finish`, `mesh.py S fidelity <concept>` | `fidelity/compare.json`, `review/report.json` |
| rigging | `mesh.py S rig rig.json` (mesh-rig) | `rig/report.json`, `rig/poses.png` |
| uv | `mesh.py S uv` (mesh-uv) | `uv/report.json`, `uv/layout.png` |
| uv_wire | the same, for a prop made mostly of thin bars or wire: the same limits with utilisation .5 | `uv/report.json` |
| texture | `mesh.py S texture <concept>` (mesh-texture) | `texture/report.json`, `texture/flat_*.png` |
| animation | `mesh.py S animate motion.json rig.json`, then `gate animation --anim motions/<name>` (mesh-animate) | `motions/<name>/report.json`, `motions/<name>/check/report.json` |
| motion_walk / motion_idle / motion_action | same bake, then `gate <motion_stage> --anim motions/<name>` | `motions/<name>/report.json` |
| prop_contact | `mesh.py S propcheck motions/<name> carry.json`, then `gate prop_contact --anim motions/<name>` (mesh-animate) | `motions/<name>/prop/report.json` |
| export | `mesh.py S glb --spec rig.json --concept <concept>` (mesh-export) | `export/report.json` |
| engine_unreal | `mesh.py S unreal` (mesh-export) | `export/unreal/report.json`, `export/unreal/*.png` |

A prop with no rig or face skips rigging and uses `texture_prop` and `export_prop`: the same limits
without the criteria that cannot apply. Worked pipelines: `box-modeling/references/lampkeeper_pipeline.sh` and
`lantern_pipeline.sh`, with their `*_build.sh` and plans. They were written for sessions `work/lampkeeper` and
`work/lantern` beside concept folders, so read the paths as an example; each rebuilt everything in minutes.

A new stage gets its thresholds in `gates.json` before its first measurement. Measurement files
older than the model count as missing, so a stale report cannot pass.

An animation passes both its common `animation` mechanics gate and its motion-specific gate.
Run `mesh.py S controls rig.json --carry carry.json` to prove that the animation and contact criteria
reject deliberately broken motions and placements. The overlap metric compares rest-relative bone
rotations, agreed with the user on 2026-11-06 together with a minimum rotation range. Old
absolute-position lag scores are not comparable. Reports identify this with `quality.overlap_space`.

## When the skills count as stable
Agreed with the user on 2026-11-06: the skills may move to the plugin when a character and a prop from
a concept they have never seen pass every gate with no change to skill code, and every selftest passes.

## What this loop has taught
- **Work out what a limit can reach before fixing it.** A stretch limit on a limb thicker than
  it is long, and a share of all texels when a third are hidden, were both set blind. Estimate
  the physical bound or the denominator first.
- **Measure the delivered file, not an intermediate.** A texture scored 0.93 while the saved
  image was upside down, because the score read the computed texels.
- **Measure under the target's conditions.** A rig passed with dual quaternions, then lost 15% of
  a joint's volume under the linear skinning engines use. Helper bones fixed it.
- **Check that a test can fail.** A pose error of exactly 0 proves nothing until the poses are
  shown to have moved the surface. A new criterion that passes before the fix does not detect
  the fault: ink share passed while sleeve blots were plain to see.
- **Look at the scope of a measure.** Stretch over the whole body hid 165% on one sleeve and
  pointed the wrong way on blend width; per part, wide linear blends were clearly better.
- **A score that drops is information.** Stretch rising after joint rings were added showed where
  the bend was concentrating.
- **Try the method on something different.** A prop found what the character could not: extrude left
  wire edges without a mirror, UVs on the cage fail on hard edges, depth maps have holes on thin
  faces. The fix for the prop's UVs also took the character from 1.47 to 1.04.
- **When a setting stops helping, the cause is elsewhere.** UV stretch did not move with the angle
  limit, which showed the islands were not the problem.
- **Pictures hide what is behind things.** The lantern sat 59 mm inside the belly and 48 mm inside the
  hood while every render looked fine. Anything two objects must not do to each other needs a measure.
- **Ask why a search finds nothing.** 4 of 210 arm poses cleared the body. Listing what blocked them
  named the real fault, a fixed handle, and correcting the grip opened 75 of 245.
- **A one-frame spike in a smooth motion is the instrument.** 25 mm on one frame and 0 on both sides
  was a ray grazing an edge, not a collision. Three rays that vote fixed it.
- **Presence is not playback.** Five actions imported with the right lengths while the component
  stayed in its rest pose. Read the result from the thing that is running.
- **A check's own conditions can cause its warnings.** Importing without an editor window left
  compression settings empty; in the editor they were right. Find that out before patching around it.
- **A high percentile of contrast measures the drawing.** p95 across a seam failed four clean models,
  because a gold edge on a dark roof is contrast too. The median split them from unfilled ones, 2-3 against
  10-77. Changing a measure after seeing it fail is the user's decision, with the numbers both ways.
- **Find where a number comes from before turning settings.** Two settings moved nothing on a lantern's
  cap. Splitting the value by side named the cause in one run.
- **When models bend to fit a score, suspect the score.** A cage passed only with bars thinner than its design,
  and a comparison that read thin parts a pixel wide was the reason. Fixing it raised seven of eight models,
  and the eighth, which had been helped by the error, needed its hood raised 1 cm.
- **Check that a new test fails on the old code.** A regression test for a mirror bug passed on the buggy
  code, because one selected vertex made the wrong index happen to be right.
- **Never call a gap a limit of the source before trying.** The side-view eye was put down to
  drawing convention at 0.42; a deeper socket took it to 0.69.
