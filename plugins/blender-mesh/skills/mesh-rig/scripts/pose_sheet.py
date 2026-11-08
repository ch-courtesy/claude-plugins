"""Contact sheet of the pose renders with their measurements (system Python + Pillow).

  python -I pose_sheet.py RIG_DIR
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def read_json(*args, **kwargs):
    """json.load that closes its file."""
    with open(*args, **kwargs) as fh:
        return json.load(fh)


d = sys.argv[1]
R = read_json(os.path.join(d, "report.json"), encoding="utf-8")


def font(size):
    for f in ("C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/arial.ttf",
              "/System/Library/Fonts/AppleSDGothicNeo.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


names = list(R["poses"])
T, cols = 300, 4
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (T + 6) + 6, rows * (T + 46) + 6), (248, 247, 244))
g = ImageDraw.Draw(sheet)
for k, n in enumerate(names):
    x, y = 6 + (k % cols) * (T + 6), 6 + (k // cols) * (T + 46)
    sheet.paste(Image.open(os.path.join(d, f"pose_{n}.png")).convert("RGB").resize((T, T), Image.LANCZOS), (x, y))
    s = R["poses"][n]
    g.text((x + 2, y + T + 2), n, fill=(40, 40, 46), font=font(14))
    g.text((x + 2, y + T + 22), f"vol {s['volume_change'] * 100:.1f}%  strain {s['strain_p99'] * 100:.0f}%  "
           f"area {s['area_ratio_p001']:.2f}  gap {s['gap_open_cm']:+.1f}cm", fill=(100, 100, 108), font=font(11))
sheet.save(os.path.join(d, "poses.png"))
print("[rig] sheet", os.path.join(d, "poses.png"))
