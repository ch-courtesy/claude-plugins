"""Read a GLB's structure directly, with no 3D software involved (needs numpy: run it in
Blender's Python, or any Python with numpy).

  python check_glb.py MODEL.glb [REPORT.json]

Exporter and importer from one project can share a mistake; this reads the bytes against the
glTF 2.0 rules that an engine depends on: chunks, buffer ranges, accessor sizes, index ranges,
joint indices, weight sums, unit normals, inverse bind matrices, animation sampler lengths.
Prints the errors and, with REPORT.json, adds "structure_errors" and "structure_checked" to it.
"""
import json
import struct
import sys

import numpy as np

SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
DTYPE = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def check(path):
    errors, checked = [], 0
    data = open(path, "rb").read()
    magic, version, length = struct.unpack("<4sII", data[:12])
    if magic != b"glTF" or version != 2 or length != len(data):
        errors.append(f"header: magic {magic}, version {version}, length {length} of {len(data)}")
    n, kind = struct.unpack("<I4s", data[12:20])
    G = json.loads(data[20:20 + n])
    p = 20 + n
    binary = b""
    if p < len(data):
        m, kind2 = struct.unpack("<I4s", data[p:p + 8])
        binary = data[p + 8:p + 8 + m]
        if kind2 != b"BIN\x00":
            errors.append(f"second chunk is {kind2}")

    views = G.get("bufferViews", [])
    for i, v in enumerate(views):
        checked += 1
        if v.get("byteOffset", 0) + v["byteLength"] > len(binary):
            errors.append(f"bufferView {i} runs past the binary chunk")

    def read(a):
        acc = G["accessors"][a]
        v = views[acc["bufferView"]]
        k = COMPONENTS[acc["type"]]
        size = SIZE[acc["componentType"]] * k
        stride = v.get("byteStride", size)
        start = v.get("byteOffset", 0) + acc.get("byteOffset", 0)
        end = start + stride * (acc["count"] - 1) + size
        if end > v.get("byteOffset", 0) + v["byteLength"]:
            errors.append(f"accessor {a} runs past its bufferView")
            return np.zeros((0, k))
        raw = np.frombuffer(binary, np.uint8, end - start, start)
        if stride == size:
            return raw.view(DTYPE[acc["componentType"]]).reshape(acc["count"], k)
        rows = np.lib.stride_tricks.as_strided(raw, (acc["count"], size), (stride, 1))
        return np.ascontiguousarray(rows).view(DTYPE[acc["componentType"]]).reshape(acc["count"], k)

    joints = [len(s["joints"]) for s in G.get("skins", [])]
    for s in G.get("skins", []):
        checked += 1
        if "inverseBindMatrices" in s and G["accessors"][s["inverseBindMatrices"]]["count"] != len(s["joints"]):
            errors.append("inverse bind matrices do not match the joints")
        for j in s["joints"]:
            if j >= len(G["nodes"]):
                errors.append(f"joint node {j} does not exist")
    for mi, mesh in enumerate(G.get("meshes", [])):
        for pi, prim in enumerate(mesh["primitives"]):
            at = prim["attributes"]
            where = f"mesh {mi} primitive {pi}"
            pos = read(at["POSITION"])
            acc = G["accessors"][at["POSITION"]]
            checked += 1
            if "min" not in acc or "max" not in acc:
                errors.append(f"{where}: POSITION has no bounds")
            elif not (np.allclose(pos.min(0), acc["min"], atol=1e-4) and np.allclose(pos.max(0), acc["max"], atol=1e-4)):
                errors.append(f"{where}: POSITION bounds do not match the data")
            if not np.isfinite(pos).all():
                errors.append(f"{where}: POSITION has non-finite values")
            if "indices" in prim:
                idx = read(prim["indices"])
                checked += 1
                if idx.size % 3 or (idx.size and idx.max() >= len(pos)):
                    errors.append(f"{where}: indices out of range")
            if "NORMAL" in at:
                nrm = read(at["NORMAL"]).astype(np.float64)
                checked += 1
                if len(nrm) != len(pos) or np.abs(np.linalg.norm(nrm, axis=1) - 1).max() > 0.01:
                    errors.append(f"{where}: normals are not unit length")
            if "TEXCOORD_0" in at:
                checked += 1
                if len(read(at["TEXCOORD_0"])) != len(pos):
                    errors.append(f"{where}: TEXCOORD_0 count differs")
            if "JOINTS_0" in at:
                jo, we = read(at["JOINTS_0"]), read(at["WEIGHTS_0"])
                checked += 1
                if joints and jo.max() >= joints[0]:
                    errors.append(f"{where}: joint index out of range")
                w = we.astype(np.float64)
                if G["accessors"][at["WEIGHTS_0"]]["componentType"] != 5126:
                    w /= 255.0 if G["accessors"][at["WEIGHTS_0"]]["componentType"] == 5121 else 65535.0
                if np.abs(w.sum(1) - 1).max() > 0.01:
                    errors.append(f"{where}: weights do not sum to 1 (worst {np.abs(w.sum(1) - 1).max():.3f})")
    for ai, anim in enumerate(G.get("animations", [])):
        for si, s in enumerate(anim["samplers"]):
            checked += 1
            i, o = G["accessors"][s["input"]], G["accessors"][s["output"]]
            per = 3 if s.get("interpolation") == "CUBICSPLINE" else 1
            if i["count"] * per != o["count"]:
                errors.append(f"animation {ai} sampler {si}: {i['count']} times for {o['count']} values")
        for c in anim["channels"]:
            checked += 1
            if c["target"].get("node", 0) >= len(G["nodes"]):
                errors.append(f"animation {ai}: a channel targets a missing node")
    for im in G.get("images", []):
        checked += 1
        if "bufferView" in im:
            v = views[im["bufferView"]]
            head = binary[v.get("byteOffset", 0):v.get("byteOffset", 0) + 8]
            if head[:4] not in (b"\x89PNG", b"\xff\xd8\xff\xe0", b"\xff\xd8\xff\xe1", b"\xff\xd8\xff\xdb"):
                errors.append(f"image data is neither PNG nor JPEG: {head[:4]}")
    return errors, checked


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    errors, checked = check(argv[0])
    for e in errors[:20]:
        print("[check_glb]", e)
    print(f"[export] structure: {checked} checks, {len(errors)} errors")
    if len(argv) > 1:
        R = json.load(open(argv[1], encoding="utf-8"))
        R["structure_errors"], R["structure_checked"] = len(errors), checked
        json.dump(R, open(argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
