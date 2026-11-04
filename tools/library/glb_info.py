"""Minimal stdlib GLB reader for the asset library (T-052).

Measures what the file really contains (no values are copied from the manifest): per-node triangle counts and the
POSITION bounding box in metres. Only handles what the kit exporter emits (triangle primitives, indexed or not,
optional node translation/scale; rotations are not supported and raise).
"""
import json
import struct

GLB_MAGIC = 0x46546C67  # "glTF"


def read_gltf_json(path):
    with open(path, "rb") as fh:
        head = fh.read(12)
        if len(head) < 12:
            raise ValueError("%s: not a GLB (too short)" % path)
        magic, version, _length = struct.unpack("<III", head)
        if magic != GLB_MAGIC or version != 2:
            raise ValueError("%s: not a glTF 2.0 binary" % path)
        chunk_head = fh.read(8)
        clen, ctype = struct.unpack("<II", chunk_head)
        if ctype != 0x4E4F534A:  # "JSON"
            raise ValueError("%s: first chunk is not JSON" % path)
        return json.loads(fh.read(clen).decode("utf-8"))


def _mesh_triangles(gltf, mesh_index):
    tris = 0
    for prim in gltf["meshes"][mesh_index]["primitives"]:
        if prim.get("mode", 4) != 4:
            raise ValueError("non-triangle primitive")
        if "indices" in prim:
            count = gltf["accessors"][prim["indices"]]["count"]
        else:
            count = gltf["accessors"][prim["attributes"]["POSITION"]]["count"]
        tris += count // 3
    return tris


def _mesh_bbox(gltf, mesh_index, node):
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    if node.get("rotation") not in (None, [0, 0, 0, 1], [0.0, 0.0, 0.0, 1.0]):
        raise ValueError("node rotation not supported")
    scale = node.get("scale", [1.0, 1.0, 1.0])
    trans = node.get("translation", [0.0, 0.0, 0.0])
    for prim in gltf["meshes"][mesh_index]["primitives"]:
        acc = gltf["accessors"][prim["attributes"]["POSITION"]]
        for i in range(3):
            lo[i] = min(lo[i], acc["min"][i] * scale[i] + trans[i])
            hi[i] = max(hi[i], acc["max"][i] * scale[i] + trans[i])
    return lo, hi


def inspect(path):
    """Return {'nodes': {name: {'tris': int, 'min': [x,y,z], 'max': [x,y,z]}}, 'materials': [names]}."""
    gltf = read_gltf_json(path)
    nodes = {}
    for node in gltf.get("nodes", []):
        if "mesh" not in node:
            continue
        lo, hi = _mesh_bbox(gltf, node["mesh"], node)
        nodes[node.get("name", "mesh%d" % node["mesh"])] = {
            "tris": _mesh_triangles(gltf, node["mesh"]), "min": lo, "max": hi}
    mats = [m.get("name", "") for m in gltf.get("materials", [])]
    return {"nodes": nodes, "materials": mats}
