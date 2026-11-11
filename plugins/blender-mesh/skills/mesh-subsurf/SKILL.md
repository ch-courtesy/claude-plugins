---
name: mesh-subsurf
description: Add or change a Subdivision Surface modifier on a mesh-session model (levels, edge creases, smooth shading, optional apply) to turn a low-poly cage into a smooth form while support loops, bevels and creases keep chosen edges defined. Use to preview smoothness during box modelling and for the final smooth surface; part of the box-modeling procedure. 서브디비전 서피스와 크리스로 매끈하게 만들기.
---

# Subdivision — model the cage, see the surface

## Command
```bash
mesh.py <session> subsurf '{"levels":2}'
mesh.py <session> subsurf '{"levels":2,"crease":{"sel":"lid_edges","value":0.8}}'
mesh.py <session> subsurf '{"levels":2,"apply":true}'
```
| key | meaning |
|---|---|
| `levels` | 1–2 for preview, 2 for final renders (each level ×4 faces) |
| `crease` | `sel` (edges) + `value` 0–1: sharpen edges without extra loops |
| `shade_smooth` | default true; parts added later with `primitive` `"add": true` follow the model's shading |
| `apply` | bake into the mesh (only at the end or before export) |

## Craft
- Turn it on **early** as a preview and keep modelling the cage — the cage decides the shape.
- Where an edge must stay sharp choose: support loop (mesh-loopcut close to the edge),
  bevel (mesh-bevel, 2 segments), or crease (quickest, but game engines usually ignore
  creases — prefer geometry for exported assets).
- Triangles and n-gons subdivide into pinches; keep the cage quads (the log reports them).
- Budget: evaluated triangles grow ×4 per level; check against the target tier.

## Check
- Automatic: `budget` (evaluated triangles over the session tier; set the tier in
  `primitive` or `note`), `tris`/`ngons` in the cage.
- Look: no pinches or ripples; edges that should be crisp are crisp.
