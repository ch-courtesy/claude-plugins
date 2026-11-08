# Worked plan: treasure chest (verified, 39 steps)

An original prop built with mesh-session on Blender 5.2 (session `work/chest`). Every step
below ran as written; the log line after each one is summarised on the right. Final cage:
304 verts / 287 faces, all quads, non-manifold 0 at every step. Rendered at subsurf 2:
18,368 triangles. 3d-asset-review (pc tier): 0 warnings.

Command prefix for every line: `python <skills>/mesh-session/scripts/mesh.py work/chest OP '<json>' LABEL`.
The whole sequence is also a steps file — `mesh-session/assets/selftest/chest.steps.jsonl`
(with the expected face count after every step) — replayed by `mesh.py selftest`. Today
steps 5–6, 12–13, 16–17, 20–23 and 33–34 could each be written as `{"at":{...}}` alone,
without the `where`/`nearest` point (loop cut finds the ring by the plane).

## Brief (stage 0)
Wooden chest with a barrel-arched lid, two iron bands that wrap the body and the lid, an
iron lock plate at front centre, and a recessed lid line.
W 1.00 (x) · D 0.60 (y) · body H 0.45 · lid +0.25 · arch sagitta 0.12. Tier: pc.

## Steps

| # | op | arguments | why / result |
|---|---|---|---|
| 1 | primitive | `{"type":"cube","size":[1.0,0.6,0.45],"location":[0,0,0.225]}` | body, base on the ground |
| 2 | mirror | `{"axis":"x"}` | keep +X half; 4 seam verts |
| 3 | select | `{"name":"top","domain":"face","where":{"normal":[0,0,1]}}` | 1 face |
| 4 | extrude | `{"sel":"top","distance":0.25,"result":"lid"}` | lid mass; 3 side faces (no seam wall) |
| 5 | loopcut | `{"where":{"along":"z","nearest":[0.5,-0.3,0.2]},"at":{"axis":"z","value":0.42}}` | lid line, lower support |
| 6 | loopcut | `{"where":{"along":"z","nearest":[0.5,-0.3,0.6]},"at":{"axis":"z","value":0.48}}` | lid line, upper support |
| 7 | loopcut | `{"where":{"along":"y","nearest":[0.5,0,0.7]},"cuts":3}` | 3 loops across the lid for the arch |
| 8–9 | select + transform | verts `min [null,-0.16,0.69] max [null,0.16,null]` → `translate [0,0,0.093]` | lift the inner rows |
| 10–11 | select + transform | verts `|y|≤0.01, z≥0.69` → `translate [0,0,0.027]` | crown: total 0.12 = circular arch |
| 12 | loopcut | `{"where":{"along":"x","nearest":[0.25,-0.3,0]},"at":{"axis":"x","value":0.40}}` | band edge |
| 13 | loopcut | `{"where":{"along":"x","nearest":[0.2,-0.3,0]},"at":{"axis":"x","value":0.30}}` | band edge |
| 14 | select | faces `min [0.3,null,null] max [0.4,null,null]` | the ring of band faces (16) |
| 15 | extrude | `{"sel":"band","distance":0.012,"along":"normals","result":"band_top"}` | band wraps the arch; 32 side faces |
| 16 | loopcut | `along x, nearest [0.1,-0.3,0], at x 0.07` | lock plate edge |
| 17 | loopcut | `along z, nearest [0.2,-0.3,0.2], at z 0.30` | lock plate bottom |
| 18 | select | faces `normal [0,-1,0], max [0.07,null,0.48], min [null,null,0.30]` | 3 front faces |
| 19 | extrude | `{"sel":"lock","distance":0.02,"result":"lock_plate"}` | plate; 5 sides (seam side removed) |
| 20–23 | loopcut ×4 | at x 0.48, y −0.28, y 0.28, z 0.02 (each `nearest` a face of that ring) | support loops 2–4 cm from the outer edges |
| 24 | subsurf | `{"levels":2}` | preview: 13,376 tris |
| 25 | cleanup | `{}` | merged 0, loose 0 |
| 26 | material | `{"name":"Wood","color":[0.33,0.17,0.07],"metallic":0,"roughness":0.62}` | new material, no sel → base on all faces |
| 27–30 | material | `{"sel":"band_top"/"band_top_sides"/"lock_plate"/"lock_plate_sides","name":"Iron","metallic":1,...}` | the selections named by the extrudes |
| 31–32 | subsurf | `{"levels":2,"crease":{"sel":"band_top_sides","value":0.85}}`, same for `lock_plate_sides` | crisp band and plate edges |
| 33–34 | loopcut | at z 0.44 and z 0.46 (nearest a body face at that height) | the groove's two edges |
| 35 | select | faces `min z 0.44, max z 0.46, "material":"Wood"` | 26 faces; **bands and plate excluded** |
| 36 | extrude | `{"sel":"groove","distance":-0.008,"along":"normals","result":"groove_in"}` | recessed lid line |
| 37 | material | `{"name":"Wood","color":[0.15,0.065,0.025]}` | retune only (existing material, no sel) |
| 38–39 | material | Iron `[0.36,…]` then `[0.53,0.51,0.49]`, roughness 0.55 | 38 failed review (metal albedo too dark); 39 fixes it |

## What went wrong on the way (and is now in the skills)
- **Groove through the bands.** First attempt selected every face at z 0.44–0.46; the groove
  cut into the iron bands and the lock plate and left spiky pinches at the junctions under
  subsurf. Fix: select by `"material":"Wood"` (or `"not_in": [...]`) so the cut stops at the
  other parts. Lesson: assign part materials *before* late details, then select by material.
- **Retuning a material reassigned every face.** A `material` step without `sel` used to put
  the material on all faces, wiping the iron. Now an existing material without `sel` is only
  retuned.
- **Pale render.** The studio lights were ~1.2 stops hot (albedo 0.18 ground rendered at
  sRGB 171). Lights lowered; `render_session.py --exposure` added.
- **Dark metal.** Darkening iron to make it "read as iron" broke PBR (metal albedo must stay
  bright); the inspector caught it. Dark, worn iron is a texturing job (dirt/rust masks),
  not a base-colour change.

## Not done (separate stages)
Mirror not applied; no UVs or textures (wood grain, rust); the iron reads as light grey
under the plain studio; no hinges, handles or rivets.
