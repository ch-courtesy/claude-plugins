---
name: mesh-transform
description: Move, rotate or scale a named selection of a mesh-session model, optionally with proportional editing (smooth falloff to neighbours) — how an artist shapes, tapers, arches and rounds forms after the topology is in place. Use for shaping steps in box modelling (taper a limb, arch a lid, push a loop out). 이동·회전·스케일·비례 편집으로 형태 다듬기.
---

# Transform — shape what the topology allows

## Command
```bash
mesh.py <session> transform '{"sel":"lid_arc","translate":[0,0,0.08],"proportional":0.25}'
```
| key | meaning |
|---|---|
| `sel` | named selection (faces/edges/verts all move their vertices) |
| `translate` | [x,y,z] metres |
| `scale` | [x,y,z] factors about the pivot |
| `rotate` | [x,y,z] degrees about the pivot |
| `pivot` | `median` (default), `origin`, or [x,y,z] |
| `proportional` | radius (m); unselected vertices within it follow with a falloff |
| `falloff` | `smooth` (default), `sphere`, `linear` |
| `outline` | [[x,y,z], ...]: put the boundary of the selected faces on these points, in order round the loop (one point per boundary vertex; the seam is not part of the boundary). Inner vertices follow. Like LoopTools Circle, to any shape and any tilt |

## Choosing
- **Shape with loops, not single vertices**: move whole edge loops so the surface stays even.
- Arches and bulges: add 1–2 loop cuts first (mesh-loopcut), then lift the middle loop(s);
  a proportional radius about half the span gives a smooth curve.
- Tapers: scale an end loop/face down about its own median (`pivot` median).
- With a mirror, seam vertices slide on the plane (clipping) and a median pivot of a
  selection that touches the seam sits on the plane, so scaling acts on the whole symmetric
  part.

- With a concept, use `outline` to set each ring from the cross-section table
  (concept-fidelity's `concept_profile.py`): extrude the cap, then give the ring its measured
  shape. A plan script that writes these steps can be tuned and replayed in seconds.

## Check
- Automatic: `mirror_cross` (vertices pushed past the seam), `degenerate`, `winding`.
- Look: front/side snapshots against the reference; the log counts moved vertices
  (proportional editing moves more than the selection — make sure it didn't reach parts
  that should stay).

## Mistakes
- Large proportional radius dragging the opposite side or the base.
- Rotating a selection that touches the seam about an axis other than the mirror normal —
  the seam vertices are held on the plane, so the part shears; rotate parts away from the seam.
