# Modelling a character from a concept turnaround (verified)

The route that took the same character from silhouette IoU 0.705 / 0.624 (front / side, built
from a text brief) to 0.964 / 0.949 (built from the concept), contour error 0.5–0.6 cm. The
worked example is `lampkeeper_plan_steps.py` in this folder; its steps are
`mesh-session/assets/selftest/lampkeeper.steps.jsonl`.

## Method
1. **Read the drawing as numbers.** `concept_profile.py <concept> --step 0.05 --half-front`
   prints, at each height, where every part sits in the front and side views. Use a finer
   step for curved parts. `concept_report.py` gives the extents.
2. **Split into parts that overlap**, not one growing mass: tunic, hood, head, sleeve, mitten,
   trouser leg, boot. `primitive` with `"add": true`. Parts keep their loop cuts to themselves
   and each can have its own ring density. Parts on the +X side are mirrored; parts crossing
   the plane are cut there. Where two parts must read as one smooth surface, such as a seat
   and the two trouser legs, extrude one from the other instead: overlapping pieces leave a
   crease and a block at the crotch that no ring placement removes.
3. **Build each part ring by ring.** A cube with loop cuts gives caps with 8 outline points
   (10 when off the seam). Then repeat: extrude the cap, `transform` with `outline` to give
   that ring its measured shape. Rings can tilt: a bent hood tip is a stack of rings between an
   upper and a lower outline point.
4. **Write the plan as a small script** with the ring table at the top; it prints one step per
   action. Each step is still one modelling action with its log line and snapshot, but a
   number can be corrected and the whole model replayed in about 15 seconds.
5. **Set materials when a part is added**: extrusions inherit them.
6. **Measure after every pass**: `mesh.py <session> fidelity <concept> --map Brass=buckle`.
   Read `compare.md` (gaps per part), then look at the render: both, every time.

## What each pass fixed
| pass | change | front / side IoU | front / side part IoU |
|---|---|---|---|
| 1 | every part from the table | 0.964 / 0.939 | 0.826 / 0.698 |
| 2 | closer rings at the brim, hood rim tube, bigger head, thumb attached | 0.964 / 0.951 | 0.826 / 0.683 |
| 3 | rim path from the side view, eyes moved out of the larger head | 0.964 / 0.948 | 0.859 / 0.703 |
| 4 | trouser top inside the tunic, eye sockets pressed into the face | 0.964 / 0.949 | 0.847 / 0.758 |

Later passes, driven by the modeling gate, took it to 0.967 / 0.950 and part IoU 0.884 / 0.834:
belt rings, brim height, a slimmer sleeve end so the mitten shows in front, and a deeper socket.
Rigging then asked for three rings at each elbow and knee, so the rig fed back into this plan.

## The same method on a prop
`lantern_plan_steps.py` applies this to a hard-surface lantern (silhouette IoU 0.957 / 0.956, part
IoU 0.90, contour 0.2 cm from the first full build). What changed:
- Square rings with points close to the corners to keep them crisp; round rings where a form turns.
- **No mirror** when something breaks the symmetry: the bail hangs corner to corner, and a mirror
  would have made two hoops. Declare it in the review: `mesh.py S finish --asymmetric`.
- Tubes for bars and wire; their ends close with quads when there is no mirror. Extend bars well into
  what they join, because subdivision rounds the ends back.
- See-through glass needs `--see-through Glass` wherever the model is compared, or it hides the flame.
- Keep emission low: at strength 4 the flame washed out to pink; 1.2 keeps the colour.

## Lessons
- **The render finds what IoU cannot.** A floating thumb cost almost nothing in IoU, and the
  hem's jagged edge only showed as a 2.5 cm gap in a list; both were obvious on sight.
- **Subdivision moves things.** A ball loses about 2 cm on a 35 cm height; a cube-based ball
  with `cuts` 1 loses more. Steps need rings close together or they round off (the brim).
- **A closing part needs margin.** The top of a trouser leg, hidden inside the tunic, poked
  through at the hem because subdivision had pulled the tunic in. Keep hidden ends well inside.
- **Budget small parts.** `ball` with the default 3 cuts is 96 faces; eyes and thumbs need 24.
- **A drawing can show what a solid cannot.** A side view often shows an eye that a convex
  face would hide. Pressing a socket got side eye IoU from 0.02 to 0.42; the rest is drawing
  convention, not a modelling error. Say which in the report.
- **A high score here is not independent proof.** The numbers were taken from the same maps
  they are scored on, and a symmetric back view adds nothing. It shows the drawing was
  followed, not that the design is good; that judgement is the concept artist's and yours.

## Reading sizes from labels
- A label run is rounded to whole pixels, so a thin part can read up to a pixel off. Where `design.md` gives a
  size, use it: the comparison reads pixels at their centres as the labels are, so wires can stay at design size.
- A subdivided ring shrinks to r x (2/3 + cos(2 pi / n) / 3) for n vertices. Correct radii you measured on the
  final surface, not radii from a table: correcting a table's radii lowered a prop's side part IoU from .964 to .920.
- A subdivided cube keeps nearly its full size, unlike a ring or a ball. Size each from its own shrink: eyes sized
  for a ball's shrink on a cube came out twice too large, and passed the silhouette gates. Look at them.
