"""Contact sheet: review renders + the report's numbers, grouped by discipline.

  python -I sheet.py INSPECT_DIR OUT_PNG [BEAUTY_PNG]
(system Python with Pillow; no numpy needed)
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


src, out = sys.argv[1], sys.argv[2]
beauty = sys.argv[3] if len(sys.argv) > 3 else None
TILE = 480


def font(size):
    for f in ("C:/Windows/Fonts/consola.ttf", "C:/Windows/Fonts/arial.ttf",
              "/System/Library/Fonts/Menlo.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


R = read_json(os.path.join(src, "report.json"), encoding="utf-8")
tiles = [("FRONT", "front.png"), ("SIDE", "side.png"), ("BACK", "back.png"),
         ("TOP", "top.png"), ("WIRE (base cage)", "wire.png")]
if beauty:
    tiles.append(("BEAUTY", beauty))
tiles = [(l, f if os.path.exists(f) else os.path.join(src, f)) for l, f in tiles]
tiles = [(l, f) for l, f in tiles if os.path.exists(f)]

lines = []
for name, i in R["meshes"].items():
    if i["verts"] < 300:
        continue
    s = (f"{name}: {i['faces']} faces (q {i['quads']} t {i['tris']} n {i['ngons']}) | islands {i['islands']} "
         f"| non-manifold e/v {i['non_manifold_edges']}/{i['non_manifold_verts']} | dup {i['duplicate_verts']}")
    if "symmetry_max" in i:
        s += f" | sym {i['symmetry_max']}"
    if "bones" in i:
        s += f" | bones {i['bones']}, unweighted {i['unweighted_verts']}, max infl {i['max_bone_influences']}"
    lines.append(("", s))
b = R["budget"]
lines.append(("", f"budget [{R['tier']}]: base cage {b['tris_base_cage']} tris, render {b['tris_render']} tris, "
                  f"LOD0 max {b['lod0_tris_max']}"))
for name, u in R["uv"].items():
    lines.append(("", f"UV {name}: islands {u['islands']}, {u['texel_density_px_per_m']} px/m, density CV "
                      f"{u['texel_density_cv']}, used {u['utilisation'] * 100:.0f}%, overlap {u['overlap_fraction'] * 100:.1f}%"))
for disc, ws in R["warnings"].items():
    lines.append(("warn" if ws else "ok", f"{disc.upper():9} " + ("; ".join(ws) if ws else "ok")))

cols, pad = 3, 8
rows = (len(tiles) + cols - 1) // cols
text_h = 24 * len(lines) + 16
W = cols * TILE + (cols + 1) * pad
H = rows * (TILE + 24) + (rows + 1) * pad + text_h
sheet = Image.new("RGB", (W, H), (24, 26, 30))
d = ImageDraw.Draw(sheet)
f_label, f_text = font(18), font(14)
for k, (label, path) in enumerate(tiles):
    im = Image.open(path).convert("RGB")
    im.thumbnail((TILE, TILE), Image.LANCZOS)
    x = pad + (k % cols) * (TILE + pad)
    y = pad + (k // cols) * (TILE + 24 + pad)
    d.text((x + 4, y + 2), label, fill=(220, 220, 220), font=f_label)
    sheet.paste(im, (x + (TILE - im.width) // 2, y + 24))
y = H - text_h + 8
colour = {"": (200, 210, 200), "warn": (255, 170, 120), "ok": (140, 220, 150)}
for kind, ln in lines:
    d.text((pad + 4, y), ln[:200], fill=colour[kind], font=f_text)
    y += 24
sheet.save(out)
print("sheet:", out, sheet.size)
