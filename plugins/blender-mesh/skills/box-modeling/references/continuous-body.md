# Joining parts that bend together (continuous body)

Added 2026-11-13 from the second build of a stocky character (Musoe v2: its plan_steps.py, rig_spec.py and a joined variant).

## The rule
Parts that bend together must be one surface: torso and trousers, the two trouser legs at the crotch, and where
it can work, torso and sleeve. Parts that only overlap cannot blend across the joint, so a hip or shoulder either
stays rigid or opens. Seams are allowed only at real clothing borders (cuff, hem, sash, collar), hidden by an overlap.
Checked by a craft rubric's M1 (borders that bend together joined into one piece): v1 Musoe had 0 of 3 such borders joined.

## One-piece trousers grown from the torso (works; passed every gate)
1. Build the torso as usual on the mirror, with a grid on its bottom cap (2 x 3 on Musoe).
2. Extrude the bottom cap down ring by ring as the seat (`extrude` + `transform outline` per ring, half rings with
   their ends on the seam). No inner wall at the seam: the mirror joins the halves.
3. At the crotch, outline the last cap so its inner column is a narrow strip (Musoe: 3.4 cm half width) running from
   the front seam to the back seam, and select the outer column as the leg top.
4. Extrude the leg top down ring by ring. After the mirror is applied the strip joins the legs across the middle: a
   crotch of quads with loops running through it from front to back.
5. Select the seat walls, leg walls, hem cap and strip as a region (`trousers`), the strip alone as `crotch`.
Cost: the joined seat and legs took a few more faces than two closed halves; Musoe dropped one seat ring that lay
within 5 mm of the line between its neighbours to stay under the pc budget.
Rig (mesh-rig): a region rule for the trousers with `side_blend`, the crotch on its own leaf bone.

## A limb grown out of the body (`scripts/joins.py`)
```python
import joins
hole = joins.armhole(section, yc, zc, dy, dz, n=8)          # an ellipse on the body's surface
tube = joins.TubeRings(origin, axis, [(s, ring), ...])       # the drawn limb rings
rings = joins.loft(hole, drawn[0], tube, 2, at=[0.2, 0.55], min_step=0.05,
                   inside=joins.inside_section(section, z_lo, z_hi)) + drawn
faces = joins.patch_steps(step, "sleeve", patch_where, 4, hole, rings, vec)
```
The hole goes on a 2 x 2 patch of the body's faces (8 border vertices, the limb ring's count); pick body rings so
the patch spans the hole's height, or vertices are dragged across a ring and the faces fold. The lofted rings stay on
the drawn surface where it bulges (a deltoid), never go inside the body (`inside`), and keep `min_step` apart on the
short side of a limb that leaves at an angle (without it the armpit rings bunched into a crease).
Musoe's silhouette held (front IoU 0.970, side 0.967). The first rigs failed (the armpit at 1.8–3.7 times the
stretch bound), and the 2026-11-13 conclusion was that an A-posed arm cannot be joined. That was wrong: an arm lab
(Musoe's torso and one arm, 2026-11-16) passed every test pose to 170 degrees once the geometry stopped feeding the
stretch into a few tiny faces. Build the hole and rings so:
- **Keep the hole clear of the body's rings**, about 3 cm or more above and below. A hole whose top and bottom ran to
  5 mm off the rings at its patch's border left sliver rows at the armpit's apex and the shoulder top; those rows
  took the whole shoulder's stretch (4 times over). Musoe: half height 0.12 → 0.09 between rings 1.15 and 1.40.
- **Space the lofted rings evenly** (`at=[0.2, 0.4, 0.6, 0.8]`); a first ring at 0.15 sat 1.8 cm from the hole on
  the short underside.
- **Give the rig room**: name an armpit region of body faces round the hole that also takes the shoulder top, so
  the weights can spread the turn over the flank and the shoulder (mesh-rig, "Joined joints").
The rig settings that go with it are in mesh-rig.

## Elbow and knee at a cuff or hem
A cuff or hem on the joint can be one tube with the limb: model it as a bulge of the same rings. What failed on
Musoe v3 (110–150%, then 2.7 times the bound at 90 degrees) was the ring spacing: rings 1.7–5 cm apart round the
pivot (the cuff's bulge and lip) put the bend into the shortest walls. Rings about 4 cm apart across the joint, the
bulge kept, passed to 140 degrees. Name the joint's region one wall wider than the blend at each end (mesh-rig keeps
those walls rigid), so the faces outside it never see a moving ring.
