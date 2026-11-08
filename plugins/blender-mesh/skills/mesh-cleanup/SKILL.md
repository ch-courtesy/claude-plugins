---
name: mesh-cleanup
description: Clean the topology of a mesh-session model — merge coincident vertices, dissolve degenerate (zero-length/zero-area) geometry, delete loose vertices, recalculate normals outward. Use after extrusions with zero distance, after many edits, before subdivision/apply/export, and whenever the log shows non-manifold edges or a later operation behaves oddly; part of the box-modeling procedure. 겹친 정점·퇴화 면·법선 정리.
---

# Cleanup — keep the mesh healthy as you go

## Command
```bash
mesh.py <session> cleanup '{"merge":0.0001,"dissolve_degenerate":true,"delete_loose":true,"recalc_normals":true}'
```
All keys default to on; `merge` is the merge distance in metres.

## When
- After an accidental zero-distance extrude or a failed step you didn't undo.
- Before `mesh-subsurf` apply, `mesh-mirror` apply, UV work or export.
- When the log shows non-manifold edges, or loop cuts stop early (a hidden duplicate
  vertex breaks the ring).

## Check
- Automatic: `merged` warns whenever vertices were merged (an earlier step left
  duplicates — find it in the snapshots/log); `non_manifold`, `degenerate`, `winding` run
  after every step anyway.
- `mesh.py <session> finish` runs the 3d-asset-review inspector for the full hygiene report.

## Mistakes
- A merge distance larger than the smallest intended detail (collapses bevels and thin parts).
