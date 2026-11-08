# Segmenting a painted turnaround

`segment_turnaround.py` turns one row of a model sheet into label maps. Every real sheet
needed tuning; this is how to do it quickly instead of guessing thresholds five times.

## Config keys (see `assets/segment_example.json`)
| Key | Meaning |
|---|---|
| `image`, `row` | source image (relative to the config) and the pixel rows of the turnaround strip |
| `views` | x-centre (px) of each view's figure in that strip |
| `reference_view`, `height_m` | the view whose figure height defines scale; its real height in metres |
| `background` | sheet background colour (padding outside the image) |
| `light_lum`, `bg_max_chroma` | background flood fill passes pixels brighter than `light_lum` **and** less saturated than `bg_max_chroma` |
| `dark_lum`, `outline_r`, `dark_label` | thick regions darker than `dark_lum` (survive an opening of radius `outline_r`) become `dark_label` (e.g. a black suit); thin dark lines are outline |
| `outline_lum` | pixels darker than this that are not thick-dark are outline: they take the label of their neighbours |
| `palette` | `{id: {name, rgb}}`; remaining pixels get the nearest palette colour |
| `peel_halo` | `{lum, chroma, max_layers}` — strip a pale "sticker" border from the outside in |
| `open_labels` | `{id: radius}` — remove small specks of a label (e.g. shoe highlights classified as glove white) |
| `halo_mode` | alternatives tried before: `hybrid`, `erode`, `peel_color`; prefer `peel_halo` with `max_layers` |

All views share one pixel scale and the reference view's ground line, so height differences
between views remain measurable.

## Tuning procedure
1. Run once with defaults and put `vis_<view>.png` beside the source crop.
2. If something is wrong, **print pixel values along a short line crossing the problem edge**
   (background → border → outline → fill). Measure lum = 0.299R + 0.587G + 0.114B and chroma =
   max − min. Set thresholds between the measured layers.
3. Re-run and compare again.

## Failure patterns seen
| Symptom | Cause | Fix |
|---|---|---|
| Large parts of the character vanish | saturated fur is brighter than `light_lum` and the outline has gaps, so the background fill leaks in | add `bg_max_chroma` (background is pale **and** unsaturated) |
| A pale ring around everything, labelled as a light part | "sticker" halo 2–3 px wide, same colour as light fur | `peel_halo` with `max_layers` ≈ halo width (bounded, so light parts with weak outlines are only trimmed) |
| Light parts (cream fur, white gloves) erased | unbounded peeling where the outline is light | set `max_layers` |
| Using the outline as a wall leaks | outline is mid-brown (lum ~130–140), not black, and not closed | measure it; do not rely on a closed contour |
| Small parts disappear (bow tie, eyes) | the 3×3 majority vote removes features of a few pixels | accept and note it, or add a label-specific exception |
| White in odd places (shoes, eye whites) | specular highlights / sclera share the glove colour | `open_labels` for specks; note sclera as a known artefact |
| Side view faces right | sheets often show both profiles | use the column that faces left (or mirror) |
| Neighbouring figures in the crop | views are close together | handled: only the component under the view centre is kept |
