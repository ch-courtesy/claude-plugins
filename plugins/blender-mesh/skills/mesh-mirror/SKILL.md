---
name: mesh-mirror
description: Set up symmetric modelling on a mesh-session model (cut it at the mirror plane, keep the +X half, add a Mirror modifier with clipping and merge) and later apply it — so every edit is made once and mirrored, as artists do for characters and symmetric props. Use right after the primitive for symmetric objects, and apply before asymmetric details or export; part of the box-modeling procedure. 미러(대칭) 모델링 설정·적용.
---

# Mirror — model half, get the whole

## Command
```bash
mesh.py <session> mirror '{"axis":"x","mode":"setup"}'
mesh.py <session> mirror '{"axis":"x","mode":"apply"}'
```
`setup`: bisects at the plane, deletes the negative side, snaps seam vertices onto the plane,
adds a Mirror modifier (clipping, merge 1 mm) and records the axis in the session so later
operations keep the seam closed. `apply`: bakes the modifier into the mesh.

## When
- Set up **early** (right after the primitive) for anything symmetric — characters, chests,
  vehicles. Edits then cost half and stay symmetric.
- Apply **late**: before asymmetric details (a scar, a lock on one side, a raised arm) and
  before UV/export.

## Craft notes
- Edit only on the +X side. Faces on the seam extrude without creating an inner wall.
- Keep seam vertices exactly on x = 0 (handled), or the mirrored halves gap or overlap.
- Bevels skip seam edges automatically; insets touching the seam run across the centre
  without a rim there.

## Check
- Automatic: `mirror_cross` while mirroring; `non_manifold` after apply (a gap at the seam
  shows up here).
- Log after apply: faces exactly double, vertices double minus the seam vertices.
- Look: the full shape in the snapshot, wireframe now on both halves.
