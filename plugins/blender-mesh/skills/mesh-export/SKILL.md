---
name: mesh-export
description: Export a finished mesh-session model to GLB with its skin, texture and a pose animation, then prove the file survived — read the bytes against the glTF 2.0 rules without any 3D software, import it into an empty scene, and compare triangles, joints, influences, height, silhouette and every test pose with the original. Use when a model must go to a game engine or another tool, when asked for glTF/GLB, or to check that an exported file really works; last stage of the stage-gate pipeline. glTF/GLB 내보내기와 왕복 검증.
---

# Export — a file is finished when it has been read back

```bash
mesh.py <session> glb --spec rig.json --concept <concept_dir> --map Brass=buckle
mesh.py <session> gate export
mesh.py <session> unreal
mesh.py <session> gate engine_unreal
```
Writes `<session>/export/`: `model.glb`, `check.blend` (the file imported again), `report.json`,
`fidelity/`. Runs on `motions/library.blend` when present, otherwise `texture/texture.blend`.
Without a rig, leave out `--spec` and give the height: `mesh.py S glb --height 0.30 --concept <dir>`.
Skin and pose checks are then skipped. With a rig, the expected height is `height` in `rig.json`.

## What happens
1. The subdivision is applied; only the armature stays live.
2. The spec's poses become one animation, `PoseTour`, 16 frames apart, helper bones included.
3. `check_glb.py` reads the file with no 3D software: chunks, buffer ranges, accessor sizes, index
   and joint ranges, weight sums, unit normals, inverse bind matrices, sampler lengths, image
   signatures. An exporter and importer from one project can share a mistake; this cannot.
4. The file goes into an empty scene and is compared with the original, pose by pose.

Existing baked motion actions travel beside `PoseTour`. Check their names and duration in the
delivered GLB as well. Clear the active animation **and reset bone bases** before measuring rest
height and ground contact, both before export and after import: clearing an action alone leaves
its evaluated pose behind and can falsely fail height checks.

## Reading the results
- **An error of exactly 0 needs a second look.** Two unposed models also match perfectly, so the
  report gives `pose_motion_mm`, how far the poses really moved the surface.
- **Rig for the target.** glTF skinning is linear. Dual quaternions and constraints do not travel;
  helper bones do, as baked keys. A custom animation must key helper bones too (half the rotation
  of the bone they follow), or joints lose volume in the engine.
- Vertex count rises in the file (split at UV seams and hard edges); triangles must not.

Blender writes one texture entry per material even when they share an image, and an engine imports
one copy for each: 11 copies here. The export merges them, and `duplicate_textures` must be 0.

## Unreal
`mesh.py S unreal [--engine DIR] [--warm 30] [--ddc DIR]` finds the installed engine, makes a scratch
project in `export/unreal/project`, imports the GLB in one editor run, renders it, starts a Play
session and plays every action. Writes `export/unreal/report.json`, `albedo_front.png` and one
picture per pose. It takes about a minute.

| measure | what it proves |
|---|---|
| joint distances against `gltf_pose.py`, 9 moments per action | the asset holds the motion the file defines; a wrong moment must differ (`pose_check_power_mm`) |
| `played_motion_mm` | a running component really moved, read back from it: bones at 25% and 60% of each action. A calm idle can pass its own gate (3 to 30 mm) and still move under 10 mm here |
| `albedo_delta_e_median` | albedo capture against Blender's `texture/flat_front.png` |
| bones, actions, lengths, height, materials, texture copies, import log | everything arrived |

Things that decide whether this works, each learned by a false result:
- **Import inside the editor, not a commandlet.** A commandlet import leaves actions without bone
  compression settings and logs warnings; the same file in the editor is clean.
- **Only a game world plays.** With no viewport the editor world does not tick, so a component stays
  in its rest pose. Use a Play session.
- **Load assets before Play starts.** `EditorAssetLibrary.load_asset` returns `None` during a session,
  and `play_animation(None)` reports that it is playing at position 0.
- **Set `ALWAYS_TICK_POSE_AND_REFRESH_BONES`.** Nothing is on screen, and bones are otherwise only
  refreshed for a rendered mesh.
- **The Play session has its own render target.** Reading the editor's copy returns the last picture.
- **Turn texture streaming off** with `r.TextureStreaming 0`, or low mips are measured: colour dE
  read 7.3 with streaming and 1.2 without.
- **Base colour captures are linear.** Encode to sRGB before comparing.
- **Keep the cache off a small system drive.** The launcher sets `UE-LocalDataCachePath` for its own
  process only, in `_ue/ddc` beside the session folder and shared by the sessions there. `--ddc` moves it.
- `LogAutomationTest: Error: Condition failed` lines at startup are the engine's own
  `UnifiedErrorTest`, not the model.
- Bones arrive with `.` changed to `_`, and action names gain the file name as a prefix.

## Not covered
Unity and other engines. The lit pictures use the level's lights with a weak fill from below, because
a scene capture has no bounce light: judge colour from `albedo_front.png`. Carried props are separate GLBs: nothing attaches the lantern to the hand in
the engine yet. Import settings a project may choose differently are not tested.
