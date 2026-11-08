# Worked plan: stylised character from one cube (verified, 118 steps)

An original hooded lamp-keeper built with mesh-session on Blender 5.2. Final cage: 355 verts /
326 faces, all quads, non-manifold 0 at every step; 20,864 triangles at subsurf 2;
3d-asset-review (pc tier): 0 warnings. Every step is in
`mesh-session/assets/selftest/hero.steps.jsonl` (`mesh.py <session> run` rebuilds it, with
snapshots, in about 30 s). Read that file for exact arguments; this page explains the order.

## Order that worked
| stage | what | steps |
|---|---|---|
| Torso | cube, mirror, grid loops chosen so cells become limb roots: x 0.05 / 0.17, y ±0.07, z 0.50 / 0.62 / 0.72 | 1–5 |
| Legs | the cell under the hip, extruded in short segments (thigh, knee, shin); the short segment is the joint | 6–9 |
| Boots | flare the cap, extrude to the ground, extrude the two front faces into a toe | 10–16 |
| Arms | side cell; first extrusion, then **rotate the cap 40°**, after which `distance` follows the new normal | 17–24 |
| Hands | flare, extrude, taper the tip; thumb = inset the side face, then extrude the inner face | 25–35 |
| Head | top cell at the seam: neck, then a short extrusion scaled out for the jaw, then cheek, brow, crown | 36–44 |
| Hood | extrude with a `vector` going up and back, rotating and shrinking each cap | 45–50 |
| Face | columns by `fraction`, rows by `at`; inset + extrude in = hood opening; eye and nose inside it | 51–67 |
| Preview | subsurf 2, then judge the silhouette **before** detailing further | 68 |
| Reshape | shorter, thicker legs; belly out; shoulders in; then drop the whole model back to the ground | 69–81 |
| Belt | two loops limited with `within`, extrude along normals; buckle extruded from the belt's front cells | 82–86 |
| Materials | by part; crease belt and buckle; cleanup | 87–106 |
| Polish | after the render: bigger eyes, sharper hood tip, rounder shoulders, clean sleeve edge | 107–118 |

## Lessons (each cost a redo)
- **`at` needs edges that all cross the plane.** A ring on the head also runs through the
  narrower neck and into the torso, so a coordinate misses part of it (`loopcut_span`).
  Use `fraction`: it keeps the same proportion across widths.
- **Rings travel.** Those face columns also cut the torso. Normal, and cheap, but expect it;
  `within` chooses which rings are cut, not how far they run.
- **Don't chain past a warning.** One script ran eight steps after an inset had collapsed,
  and all of them had to be undone. Put `"expect":{"warnings":0}` on each step of a chain:
  the first bad step is then rejected.
- **Bounds lie on tilted limbs.** Selecting the hand by `x >= 0.455` gave a stepped sleeve
  edge, because the faces of one tilted ring have different centres. For a part boundary use
  the extrusion names (`palm_sides`, `wrist_sides`); keep bounds for axis-aligned parts.
- **Check the size of what a name returns.** A ring of `*_sides` is 4 faces; 29 exposed a
  bug in the runtime that a good-looking render had hidden.
- **Thin cells collapse.** An inset row left the top eye cell 6 mm tall. Plan part rows so
  that later insets fit, or move the row first.
- **Subdivision shrinks small recesses.** The eye socket needed its walls in the eye
  material and a larger opening to read at render size.

## Measured against a concept afterwards
This model was built from a text brief, with no concept. A separate agent then drew a
turnaround from the same brief without seeing the model (`fidelity/concept_lampkeeper/`), and
`mesh.py <session> fidelity` scored the model against it: silhouette IoU 0.705 front, 0.624
side; part IoU about 0.2. All automatic checks and the review had been clean, because those
measure mesh hygiene, not design. Against the brief itself the model also fell short: 1.235 m
tall instead of 1.3 (legs were shortened and the height never re-measured), and the head,
nose, boots and hood droop are all weaker than "big", "round", "heavy" and "flops". Some of
the gap is the concept's own invention (a shoulder cape), not a model error.

## Not done
No rig, so the knee and elbow loops have never been bent; no UVs or textures; mirror not
applied; the lamp itself is not modelled. The torso is still rather boxy.
