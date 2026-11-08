# Reading fidelity results

## Metrics (per view)
- **IoU** — silhouette overlap (intersection / union of non-background pixels).
- **Part IoU** — mean over labels of per-label IoU; sensitive to parts in the wrong place.
- **Contour distance** — symmetric mean distance between outlines, in cm.
- Parameter values are **not** a quality measure: in a perfect round trip (concept rendered
  from the model itself) silhouettes reached ~0.98 IoU while only 18 of 27 parameters came
  back — the rest (e.g. a chest buried inside the belly) do not affect the appearance.

## Held-out views
Fit on front+side, score back/top. With front only, the fitted front reached 0.992 IoU while
the unseen side was 0.869 with 2.5 cm contour error; adding views shrank held-out error.
A held-out part IoU far below the fitted views means a part is placed wrongly in depth.

## Where does the remaining gap come from?
Separate three causes before changing anything:

| Test | Reading |
|---|---|
| Fit each view alone (start from the joint fit) | the single-view score is the **ceiling** of the current model: 1 − ceiling ≈ modelling-vocabulary limit (+ optimiser) |
| Joint score vs single-view ceilings | the difference is the **cost of the drawing's contradictions** (both views cannot be satisfied at once) |
| Same run with 3 seeds | spread = optimiser luck; differences smaller than ~2 sd are not findings |

On a drawn concept, ~80% of the silhouette gap was modelling vocabulary and the
contradiction cost concentrated in a few parts (a scarf drawn hanging in one view and flying
in the other; spiral horns drawn face-on in both views, which no single plane allows).

## Typical fixes
| Finding | Fix |
|---|---|
| part unreachable in one view | widen its bounds; add the missing degree of freedom |
| part shape cannot match (crescent tail from one ellipsoid) | add a primitive (middle segment), not more generations |
| fitted part looks wrong though scores rose | design-intent prior on its parameters |
| contradiction in the drawing | report heights/positions to the artist; pick an interpretation and say so |
| results differ between runs | more seeds; report mean ± sd |

## Honesty rules
- Report seeds, means and ranges; a single lucky run reversed two conclusions in practice.
- Say which views were held out.
- Distinguish drawing contradictions, segmentation artefacts and occlusion; the 2D height check
  alone cannot tell occlusion from contradiction.
