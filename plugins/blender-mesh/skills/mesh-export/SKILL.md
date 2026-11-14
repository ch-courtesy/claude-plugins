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
mesh.py <session> glb --spec rig.json --carry carry.json        # a weapon held in grip mode
mesh.py <session> unreal --prop-glb <prop_session>/export/model.glb
mesh.py <session> gate engine_unreal_weapon
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

### A weapon on a socket
A weapon is its own GLB (the prop's session exports it with `export_prop`). `glb --carry carry.json`,
for a carry in grip mode, puts two bones into the character's skeleton: `prop_socket` (or the carry's
`socket`), whose frame is the prop's own, and `prop_socket_tip` at the carry's `tip`. The motions do not
key them; they follow the hand. `unreal --prop-glb` imports the weapon as a static mesh, attaches it to
the socket and measures, on every sampled pose, how far its point lands from the tip marker
(`weapon_point_error_mm`, gate `engine_unreal_weapon`).

- **The engine keeps joint frames on the file's axes and turns a static mesh to Z-up.** Attached with
  no rotation, the cleaver's point landed 1.25 m from its marker. The check finds the mesh's axes by
  matching its bounding box to the file's (the prop's three sizes must differ), attaches it turned back by
  the inverse, proves the turn on the marker, and reports it as `weapon_socket_rotation` (roll, pitch,
  yaw), the rotation a game's socket needs. For the cleaver it is roll 90.
- **Start every run from an empty content folder.** Assets deleted in the editor and imported again at
  once came back without their static mesh; the launcher now removes `Content/Check` before the editor starts.

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
- **Frame the captures to the character.** They were framed for a 1.2 m character; a 1.85 m one lost its
  head and read colour dE 19. Above 1.2 m the camera now moves back and up in proportion.
- **Keep the cache off a small system drive.** The launcher sets `UE-LocalDataCachePath` for its own
  process only, in `_ue/ddc` beside the session folder and shared by the sessions there. `--ddc` moves it.
- `LogAutomationTest: Error: Condition failed` lines at startup are the engine's own
  `UnifiedErrorTest`, not the model.
- Bones arrive with `.` changed to `_`, and action names gain the file name as a prefix.
- **The engine guesses each action's frame rate from its length.** glTF has no frame rate. On
  2026-11-14 a 24-frame action at 24 fps (1.000 s) and a 136-frame one (5.667 s = 170/30) both came in at
  30 fps, while 23 frames (0.958 s) stayed at 24. The engine then resamples, and the 24 fps key times fall
  between its frames.
  - A fast swing read 10.8 mm off at the cleaver's tip, 0.885 m from the hand, against a 5 mm limit.
  - A slow one read only 1.8 mm.
  - `report.json` lists such actions in `resampled_actions`, and the run prints a warning.
  - The fix is to keep an action's length off a whole number of 1/30 s (for example, add or drop a frame).

## Not covered
Unity and other engines. The lit pictures use the level's lights with a weak fill from below, because
a scene capture has no bounce light: judge colour from `albedo_front.png`. A prop carried in hang mode
(a lantern that swings) is a separate GLB that nothing attaches in the engine yet; a weapon in grip mode
is attached on its socket (above). Import settings a project may choose differently are not tested.
