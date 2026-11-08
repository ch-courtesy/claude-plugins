---
name: mesh-inset
description: Inset selected faces of a mesh-session model (as a region or individually), creating a rim of quads and an inner face — the clean way to add panels, plates, sockets, frames, buttons and keyholes without pinching. Use before extruding detail that must stay inside a face's border; part of the box-modeling procedure. 면 인셋으로 패널·소켓·테두리 만들기.
---

# Inset — make room for detail inside a face

## Command
```bash
mesh.py <session> inset '{"sel":"front_panel","thickness":0.04,"depth":0.0,"result":"plate"}'
```
| key | meaning |
|---|---|
| `sel` | named face selection |
| `thickness` | rim width (m) |
| `depth` | push the inner face in (negative) or out (positive) |
| `individual` | inset each face separately |
| `result` | name for the inner faces; `<result>_rim` names the rim faces |

## Choosing
- Typical sequence: inset → extrude the inner face out (raised plate) or in (socket, keyhole).
- Thickness: big enough to read after subdivision (≥ 2× any later bevel width); small
  enough to leave the inner face usable.
- Inset also acts as **support** for subdivision: the rim keeps the panel's edge crisp.

## Check
- Automatic: `inset_thick` (inner face collapsed or flipped).
- Log: inner and rim counts (a quad face gives 1 inner + 4 rim, 3 when one side is on the
  mirror seam). Look: an even border.

## Mistakes
- Region inset across faces at sharp angles produces uneven rims — inset per side instead.
- Faces touching the mirror seam get no rim along the seam (the seam is an open border),
  so the inset panel runs continuously across the centre — usually what you want; if you
  need a border there, inset after applying the mirror.
