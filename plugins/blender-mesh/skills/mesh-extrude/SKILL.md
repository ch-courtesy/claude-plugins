---
name: mesh-extrude
description: Extrude selected faces of a mesh-session model along their normal or a vector (as one region or as individual faces) to grow new volume — limbs, lids, bands, handles, studs — the core move of box modelling. Use when a part must grow out of existing faces. 면 돌출(익스트루드)로 부피 키우기.
---

# Extrude — grow form out of the surface

## Command
```bash
mesh.py <session> extrude '{"sel":"top","distance":0.25,"result":"lid"}'
```
| key | meaning |
|---|---|
| `sel` | named face selection |
| `distance` | metres along the average normal (negative pushes in) |
| `vector` | [x,y,z] instead of distance |
| `individual` | extrude each face separately along its own normal (studs, rivets, panels) |
| `along` | `"normals"`: keep the region connected but move each vertex along its own normal (shrink/fatten) — for strips that wrap around a form (bands, belts, rims) |
| `result` | name for the new cap faces; `<result>_sides` names the new side faces |

## Choosing
- Extrude a **region** for one continuous part (a lid, a limb); `individual` for repeated
  bumps.
- Short extrusions plus later shaping beat one long extrusion: you get loops where the form
  changes (e.g. extrude an arm in 2–3 segments: shoulder, elbow, wrist).
- Inset first, then extrude, when the new part must sit inside the face's border (a raised
  plate, a button) — extruding the whole face moves its edges with it.
- With a mirror set up, faces on the seam do not create a wall on x = 0 (like Blender's
  mirror clipping).

## Check
- Automatic: `zero_extrude`, `individual_adjacent`, `non_manifold`, new `tris`/`ngons`,
  `mirror_cross`.
- Log: cap and side face counts. Look: the part grew in the right direction in every view.

## Mistakes
- Extruding with distance 0 and forgetting it (hidden duplicate faces — flagged; undo).
- Individually extruding faces that touch each other: their walls end up back to back.
  Inset them individually first (mesh-inset `individual`), then extrude individually.
- Extruding faces that share the mirror seam outward along X (creates a gap at the seam).
