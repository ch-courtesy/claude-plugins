---
name: mesh-uv
description: Unwrap a mesh-session model into one UV layout and measure it — apply the subdivision, Smart UV Project to find islands, angle-based unwrap of each island, one texel density, packing — reporting density spread, overlap, utilisation and stretch (by triangle, by area and per material). Use when a model needs UVs before texturing, or when a layout stretches, overlaps or wastes space; part of the stage-gate pipeline after rigging. UV 펼치기와 레이아웃 측정.
---

# UV — unwrap the surface that gets painted

```bash
mesh.py <session> uv [--angle 66] [--margin 0.002]   # writes <session>/uv/: uv.blend, report.json, layout.png
mesh.py <session> gate uv
```
Runs on `rig/rig.blend` if there is one, otherwise the current step.

## How it unwraps
The subdivision is applied first and the dense mesh itself is unwrapped. Smart UV Project finds
the islands, their borders become seams, and each island is flattened with the angle-based unwrap.

Unwrapping the cage and letting the modifier interpolate the UVs is the obvious route and a poor
one: the subdivided surface moves away from the cage, most of all around support loops.

| route | character stretch p95 | lantern stretch p95 |
|---|---|---|
| projection only, on the cage | 1.84 | 7.4 |
| angle-based on the cage, using subsurf data | 1.47 | 3.4 |
| **angle-based on the applied subdivision** | **1.04** | **1.04** |

`--keep-subsurf` unwraps the cage instead, if the subdivision must stay live; the subsurf must then
come first in the stack or `use_subsurf_data` silently does nothing (the script handles that).

## Adjusting
- Utilisation jumps with small changes, in both `--angle` and `--margin`, and with the geometry: one prop read
  .554, .60 and .558 at three margins, and a cage fell from .517 to .429 when its bars thickened. If it fails,
  sweep angles from 35 to 75 at two margins; it takes a few minutes. Keep `--margin` at a texel or more
  (.0005 at 2048), or neighbouring islands bleed into each other.
- A prop of thin bars makes long thin islands and packs badly: gate it with `uv_wire`. `--method` and `--res`
  set the unwrap method and the size the layout is measured at.
- `--angle`: with the angle-based unwrap, larger islands pack better and stretch hardly changes. 66
  gave the best utilisation on both models.
- `--margin`: smaller packs tighter; leave room for the texture's gutter.
- `stretch_p95_by_material` says where it hurts. `stretch_p95_area` weighs by surface: a high count
  of tiny faces can dominate the plain p95.

## Look at
`layout.png`: red is overlap. Seam placement is not chosen here, so a hand-painted texture would
want seams moved to hidden places. A texture baked from 3D positions, as mesh-texture does, does
not show them.
