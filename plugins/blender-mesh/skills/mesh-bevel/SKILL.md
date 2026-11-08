---
name: mesh-bevel
description: Bevel selected edges of a mesh-session model (width, segments, profile) to round or chamfer hard edges so they catch highlights and read as real, manufactured objects — or to act as support geometry before subdivision. Use on hard-surface edges, panel borders, rims; part of the box-modeling procedure. 모서리 베벨로 하이라이트·지지 지오메트리 만들기.
---

# Bevel — no real object has a perfectly sharp edge

## Command
```bash
mesh.py <session> bevel '{"sel":"rim_edges","offset":0.015,"segments":2,"profile":0.5,"result":"rim_bevel"}'
```
| key | meaning |
|---|---|
| `sel` | named selection (edges; faces/verts are converted to their edges) |
| `offset` | bevel width (m) |
| `segments` | 1 = chamfer, 2–3 = rounded |
| `profile` | 0.5 round, < 0.5 concave, > 0.5 convex-flat |
| `result` | name for the new bevel faces |

## Choosing
- Width relative to the object: small props 3–10 mm, furniture/chests 10–20 mm.
- For **subdivision** models, a 2-segment bevel (or support loops) on edges that must stay
  defined; leave soft areas unbevelled.
- Bevel **after** the main shape is final; bevelling early multiplies every later cut.
- Weighted normals improve shading of bevelled hard-surface meshes but do not replace the
  bevel geometry.

## Check
- Automatic: `bevel_seam` (seam edges are skipped), `bevel_none`, new `tris`/`ngons`
  (corners where several bevelled edges meet), `non_manifold`.
- Log: bevel face count = edges × segments. Look: even width, no overlap at corners.

## Mistakes
- Selecting more edges than meant (it happened in testing: a button's edges came along
  with the rim and the corners turned into triangles and n-gons). Use `where.sharp` plus
  bounds/`not_in`, `expect` the edge count, and check the orange edges before bevelling.
- Width larger than neighbouring faces (collapsed, overlapping geometry).
