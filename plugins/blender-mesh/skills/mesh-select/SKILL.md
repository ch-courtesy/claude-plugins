---
name: mesh-select
description: Select faces, edges, edge rings/loops or vertices of a mesh-session model by geometry (normal direction, position bounds, nearest to a point, edges along an axis) and store the selection under a name for the next operation — the scripted equivalent of clicking in edit mode. Use before any extrude, inset, transform, bevel, loop cut or material step; part of the box-modeling procedure. 메시 요소 선택·이름 붙이기.
---

# Select — say precisely what the next step acts on

An artist clicks; a script must describe. Every edit starts with a named selection.

## Command
```bash
mesh.py <session> select '{"name":"lid_top","domain":"face","where":{...}}'
```
| key | meaning |
|---|---|
| `domain` | `face` (default), `edge`, `vert` |
| `where.normal` + `normal_min_dot` | elements whose normal points this way (default dot ≥ 0.9); an edge uses the mean of its faces' normals, so a 45° rim edge needs `normal_min_dot` ≈ 0.5 |
| `where.min` / `where.max` | centre inside a box, e.g. `"min":[null,null,0.5]` = z ≥ 0.5 |
| `where.along` | edges parallel to an axis (`x`/`y`/`z`) |
| `where.sharp` | (edges) Select Sharp Edges: angle between the two faces >= this many degrees — rims to bevel or crease |
| `where.nearest` + `count` | the N elements whose centre is nearest a point |
| `where.ring` / `where.loop` | (edges) grow the nearest edge into its edge ring / edge loop |
| `where.in` / `where.not_in` | only elements in / not in other named selection(s) (name or list) |
| `where.material` | (faces) only faces using this material, e.g. `"Wood"` |
| `mode` | `set` (default), `add`, `sub`, `and` with the existing selection of that name |
| `grow` | expand by N rings of neighbours |
| `allow_empty` | don't fail on an empty result |

## Choosing
- Prefer **normal + bounds** for faces ("top faces above the lid line"), **nearest + ring**
  for edge rings feeding a loop cut, **nearest + loop** for an edge loop to bevel or crease.
- With a mirror set up, only the +X half exists — select there.
- Name selections after their role (`lid_top`, `band_left`, `lock_plate`), not their order.

## Check
- Automatic: an empty selection fails the step (unless `allow_empty`); put the count you
  expect in `expect` (`{"selected": 3}`) to reject a wrong match.
- Look: the snapshot draws the selection orange — check it is exactly the part you meant.
  Conditions go subtly wrong easily (a face selection converted to edges brings all of its
  border edges; bounds catch small parts you forgot, like a button inside a panel).

## Mistakes
- Bounds that include faces from the other side of the model (use normal too).
- Selecting faces when the next op needs edges (loop cut and bevel take edges).
