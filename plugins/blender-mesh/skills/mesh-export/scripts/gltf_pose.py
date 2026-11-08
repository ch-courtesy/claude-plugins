"""Read a GLB's skeleton and animations with no 3D software or NumPy, and tidy its texture table.

An engine's result is compared with what the file says, so this reads the file on its own: joint
positions of any action at any time, and each action's length.
"""
import json
import math
import struct


def read_file(*args, **kwargs):
    """The whole of a file, closed again."""
    with open(*args, **kwargs) as fh:
        return fh.read()


SIZES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = read_file(path, "rb")
    n = struct.unpack_from("<I", data, 12)[0]
    G = json.loads(data[20:20 + n])
    start = 20 + n
    m = struct.unpack_from("<I", data, start)[0]
    return G, data[start + 8:start + 8 + m]


def floats(G, binary, index):
    """A float accessor as a list of tuples."""
    a = G["accessors"][index]
    if a["componentType"] != 5126:
        raise ValueError(f"accessor {index} is not float")
    view = G["bufferViews"][a["bufferView"]]
    size = SIZES[a["type"]]
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", size * 4)
    return [struct.unpack_from(f"<{size}f", binary, start + i * stride) for i in range(a["count"])]


def slerp(a, b, t):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b, dot = tuple(-x for x in b), -dot
    if dot > 0.9995:
        q = [x + (y - x) * t for x, y in zip(a, b)]
    else:
        w = math.acos(min(1.0, dot))
        s = math.sin(w)
        q = [x * math.sin((1 - t) * w) / s + y * math.sin(t * w) / s for x, y in zip(a, b)]
    n = math.sqrt(sum(x * x for x in q))
    return tuple(x / n for x in q)


def sample(times, values, t, path):
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    lo, hi = 0, len(times) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if times[mid] <= t:
            lo = mid
        else:
            hi = mid
    u = (t - times[lo]) / (times[hi] - times[lo])
    if path == "rotation":
        return slerp(values[lo], values[hi], u)
    return tuple(x + (y - x) * u for x, y in zip(values[lo], values[hi]))


def matrix(translation, rotation, scale):
    x, y, z, w = rotation
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[i][j] * scale[j] for j in range(3)] + [translation[i]] for i in range(3)] + [[0, 0, 0, 1]]


def multiply(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def parents(G):
    out = {}
    for i, node in enumerate(G["nodes"]):
        for child in node.get("children", []):
            out[child] = i
    return out


def skeleton(G):
    """Joint names in order and each joint's parent joint (None at the root)."""
    joints = G["skins"][0]["joints"]
    up = parents(G)
    inside = set(joints)
    return [G["nodes"][j]["name"] for j in joints], {
        G["nodes"][j]["name"]: (G["nodes"][up[j]]["name"] if up.get(j) in inside else None) for j in joints}


def action_length(G, binary, name):
    action = next(a for a in G["animations"] if a["name"] == name)
    return max(floats(G, binary, s["input"])[-1][0] for s in action["samplers"])


def joint_positions(G, binary, name, t):
    """World position of every joint of action `name` at time t, as the file defines it."""
    trs = {}
    for i, node in enumerate(G["nodes"]):
        trs[i] = {"translation": tuple(node.get("translation", (0, 0, 0))),
                  "rotation": tuple(node.get("rotation", (0, 0, 0, 1))), "scale": tuple(node.get("scale", (1, 1, 1)))}
    action = next(a for a in G["animations"] if a["name"] == name)
    for channel in action["channels"]:
        sampler = action["samplers"][channel["sampler"]]
        path = channel["target"]["path"]
        times = [x[0] for x in floats(G, binary, sampler["input"])]
        trs[channel["target"]["node"]][path] = sample(times, floats(G, binary, sampler["output"]), t, path)
    up = parents(G)
    world = {}

    def get(i):
        if i not in world:
            m = matrix(trs[i]["translation"], trs[i]["rotation"], trs[i]["scale"])
            world[i] = multiply(get(up[i]), m) if i in up else m
        return world[i]

    return {G["nodes"][j]["name"]: tuple(get(j)[k][3] for k in range(3)) for j in G["skins"][0]["joints"]}


def repeated_textures(G):
    """Texture entries that repeat another: same image, same sampler."""
    entries = G.get("textures", [])
    return len(entries) - len({json.dumps(t, sort_keys=True) for t in entries})


def merge_textures(path):
    """Blender writes one texture entry per material even when they share an image, and an engine
    imports one copy for each entry. Points every material at one entry. Returns how many went."""
    data = read_file(path, "rb")
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    n, kind = struct.unpack_from("<I4s", data, 12)
    G = json.loads(data[20:20 + n])
    first, keep, moved = {}, [], {}
    for i, entry in enumerate(G.get("textures", [])):
        key = json.dumps(entry, sort_keys=True)
        if key not in first:
            first[key] = len(keep)
            keep.append(entry)
        moved[i] = first[key]
    gone = len(G.get("textures", [])) - len(keep)
    if not gone:
        return 0

    def walk(x):
        if isinstance(x, dict):
            for k, v in x.items():
                if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                    v["index"] = moved[v["index"]]
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)

    walk(G.get("materials", []))
    G["textures"] = keep
    text = json.dumps(G, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    text += b" " * (-len(text) % 4)
    rest = data[20 + n:]
    head = struct.pack("<4sII", magic, version, 20 + len(text) + len(rest)) + struct.pack("<I4s", len(text), kind)
    with open(path, "wb") as fh:
        fh.write(head + text + rest)
    return gone
