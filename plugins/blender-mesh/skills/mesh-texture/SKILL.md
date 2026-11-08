---
name: mesh-texture
description: Texture a UV-unwrapped mesh-session model from its concept turnaround — project the painted front, side and back panels onto the model texel by texel, using a panel only where the texel faces that view, is visible there and lands on the same part, falling back to the material colour elsewhere — then measure a real unlit render of the saved file against the painting. Use when a model that follows a concept needs its painted detail (faces, folds, laces), or to check that a texture really reaches the renderer; part of the stage-gate pipeline after UV. 원화 투영 텍스처와 측정.
---

# Texture — the concept painted onto the model

```bash
mesh.py <session> texture <concept_dir> --map Brass=buckle [--facing 0.05] [--erode 6] [--ink-facing 0.5]
mesh.py <session> gate texture          # a prop with no face: gate texture_prop
```
Writes `<session>/texture/`: `albedo.png`, `texture.blend`, `flat_<view>.png`, `report.json`.

The concept folder needs `panel_<view>.png`: the painting alone, in the same window as the
label maps, with no guide lines or text. Materials stand for parts as in concept-fidelity.

## Why it works, and when it does not
Projection needs a model that follows the concept closely; here the contour error was 0.5 cm. Do
this after the modeling gate has passed. Each texel takes paint only if it faces the view, is the
nearest surface there and lands on its own part, so a hood's colour cannot leak onto a face.
## Where two panels meet
The panel that sees a texel most squarely wins: weights are facing to the power `--blend-power` (8), and each
panel fades out over `--feather` panel pixels (12) where its part ends in the drawing, such as behind a ladle.
Averaging by facing squared showed rivets and drops twice on a robot, because the two drawings place marks
a few degrees apart. `mixed_disagreement` in the report is the share of painted texels where two panels that
disagree by dE 10 or more each give 30% or more; the gate allows 5%. Right on the boundary one mark can still
show twice; a higher power cuts it in half instead and pushes paint off edge-on surfaces.
A small part facing the front, like an eye, reads worse from the side as the power rises, because the front panel
paints its edge too: a hare's eye went from 5.0 to 6.04 at 8, and `--blend-power 6 --feather 6` gave 5.47.

- `--facing` is the least facing a panel needs to paint. Raise it when a panel smears marks across surfaces it
  sees edge-on (a robot's foot rivets at 0.15, a bucket at 0.35); `--ink-facing` below it does nothing.
- `--erode` counts panel pixels. A label pixel can be four panel pixels, so the seam can jump between 3 and 4.
- `--turn front side` names the panels to turn; `--turn` alone turns them all.

## Where no panel reaches
Texels no panel reaches take their colour from the paint on the same part: beside it they continue it across the
UV, and further off they take a colour made in space, which ignores where UV islands end. Paint fades out as a
panel sees the surface edge-on (`--fade`), because a drawing darkens towards its outline.

- `--turn front`: only that panel paints the far side. With `--one-side` this suits a body that is symmetric
  apart from one attachment: the back gets the front's planks, and the attachment is not printed on the far end.
- `--turn-skip base`: a turned panel leaves that part alone, for a one-off mark on its front.
- `--one-side`: the side panel paints its own side only. Use it on an asymmetric model: mirroring prints the
  far side with a hole the shape of whatever stands in front, such as a spout.
- `seam` in the report: painted against filled texels of a part, inside one small cube, facing the same way.
  The gate takes the median: p95 picks up strong contrast the drawing really has, like a gold edge on a dark
  roof. `--no-fill` exists to prove the measure can fail: it read 10.5 to 77 on four models, against 2 to 3.
- `seam` also gives `by_side` and `worst_at`. Read them before turning a setting: `--fade` and `--fill-cells`
  did nothing for a lantern's cap, and by_side showed the sides painted through `--turn` were the ones at fault.
- A thin band between a bright edge and painted shading reads high with nothing to see: the strip `--erode` empties
  lies between two painted colours, and most of a lantern cap's cubes sit on that band. It fails at 8.1, and a
  higher `--erode` that passes fails painted share and ink instead. Mark the empty texels and look before chasing it.
- The seam measure sees a jump, not a wrong colour: a smooth smudge scores well. `unseen_<side>.png` shows
  sides with no panel, and no score looks at those pictures, so look at them yourself.
- The seam depends on `--erode` in steps, not steadily: one prop failed at 2 to 6 and passed at 0 and 1. Try the
  whole range on a prop with strong painted edges. At 0, the panel's white background can reach thin parts.

Panels and labels may have any size ratio. On thin parts the default `--erode 6` removes the paint:
a thin figure needed `--erode 3 --ink-facing 0.6`, small props `--erode 1` or `2`.
Pixels within `--erode` of a part border are skipped because they hold the outline. The side
panel serves both sides of a symmetric character. Everything else keeps the material colour:
surfaces no view shows, and tops and undersides.

The painting's shading comes along. That suits a stylised, hand-painted look and is wrong for
PBR albedo: light it softly, or use a concept painted without shading.

Dark lines are taken only from a view the surface faces well (`--ink-facing`, default 0.5): on a
glancing surface a thin outline stretches into a blot. The `ink` figures in the report compare the
share of dark pixels with the drawing's; they catch far too much ink, not a few misplaced blots, so
still look at the sleeves and other surfaces that no view faces squarely.

## Options for what a concept does not show
| option | for |
|---|---|
| `--turn` | a model that looks the same turned 180° about Z, with no back view: surfaces facing away from a view take the panel as if turned round. A mirror would not do for a part hung corner to corner |
| `--see-through Glass` | parts that do not hide what is behind them, for projection and for the flat render |
| `--keep Glass` | materials that take no paint |
| `--emit Flame` | the painted colour also drives the glow |

Apply `--turn` per surface, by which way it faces, not by which half it is in: a hoop's far half
faces the camera and must be painted directly (bail colour error 6.6 became 1.3).

`--ink-facing` trades blots against lost detail. It is worth a small sweep: on the lantern 0.5 left
too much ink on the flame, 0.7 wiped the dark wrap off the handle, 0.54 passed.

Depth maps are rasterised exactly. Point sampling leaves holes on long thin faces, which read as
"hidden" and came out as stripes on the lantern's eave.

## Measure the real thing
The score comes from an unlit render of the saved `texture.blend`, not from the computed texels.
Scoring the texels gave a face correlation of 0.93 while the saved image was upside down and the
model rendered as camouflage. **Render it and look before believing any score.**

A median colour difference near 0 means little: the texture came from the same panels. The useful
figures are the worst part, the face correlation and how much of the visible surface got paint.

`seen_fraction` is how much of the surface any view shows; `painted_of_seen` is the share of that
painted. On a model of overlapping parts a third of the texels can be hidden.
