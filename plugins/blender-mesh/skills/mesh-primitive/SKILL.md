---
name: mesh-primitive
description: Start a step-by-step modelling session with a primitive (cube, cylinder, UV sphere, plane) sized to the reference — the first move of box modelling. Use when beginning a mesh-session model or restarting a part's blockout; part of the box-modeling procedure. 박스 모델링의 시작 도형 만들기.
---

# Primitive — choose the starting block

Box modelling starts from the simplest shape that matches the object's main mass; detail
is added later by cutting and extruding, so start **low-resolution**.

## Command (see mesh-session)
```bash
mesh.py <session> primitive '{"type":"cube","size":[w,d,h],"location":[0,0,h/2]}' <label>
```
| type | arguments |
|---|---|
| cube | `size` [x,y,z] |
| cylinder | `radius`, `depth`, `segments` (8–16 for blockouts) |
| sphere | `radius`, `segments`, `rings` |
| plane | `size` [x,y,1] |
| ball | `size` [x,y,z], `cuts` (default 3): a quad ball (subdivided cube on a sphere): all quads, no poles, cut cleanly by a mirror |
| tube | `path` [[x,y,z], ...], `radius`, `sides` (default 6): a quad tube along a path, like a bevelled curve converted to a mesh: rims, straps, piping. With a mirror the ends stay open, so start and end on the plane heading along X; without one they are closed with quads (`sides` must be even) |
plus `location`, `rotate` [x,y,z] degrees, and optionally `"tier": "mobile"|"pc"|"film"` (turns on the triangle-budget
check for the session). Creates the object and the face selection `all`.

## Adding a part
`"add": true` adds the shape to the existing mesh as a separate part, like Shift+A in edit
mode, and stores its faces under `"result"`. With a mirror, a part crossing the plane is cut
there and a part on the +X side is mirrored. Use it when parts overlap rather than grow from
each other (head inside a hood, a sleeve into a torso, a boot under a trouser leg): loop cuts
then stay inside the part (`"within":{"in":"<result>"}`). Each part must be a closed volume.

## Choosing
- Match the **bounding proportions** of the main mass (body of a chest, torso of a character).
  Put the base on the ground: `location.z = height/2`.
- Cube for boxy or limb-based forms (torso, chest, building), cylinder for round forms
  (barrel, lantern, trunk) — choose segments as a multiple of 4 if it will be mirrored.
- Starting with many segments makes later loop cuts and extrusions dense everywhere — keep it
  coarse; the subdivision modifier will smooth it.

## Check
- Automatic: counts in the log (8 verts / 6 faces for a cube); `expect` them if you like.
- Look: proportions against the reference in the front and side snapshots.

## Tubes
A tube's closed ends soften its whole first segment under subdivision, so thin bars turn into needles: add a ring
about 1.5 mm from each end. A closed ring is two half tubes under a mirror, which weld at the plane. The first
primitive has no mirror yet, so run its path just past the plane.
