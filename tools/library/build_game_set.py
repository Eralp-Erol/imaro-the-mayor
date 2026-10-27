#!/usr/bin/env python3
"""Build the game-facing library tables (T-062 A0, ADR-0006 section 2.1a).

Only entries with approval == "approved" whose recorded content hashes (`user_approved_sha256`) equal the catalog's
CURRENT content hashes AND the files on disk are written to `data/library/game_*.json`. Everything else is excluded
and listed with its reason (the game counts these as `unapproved`). Deterministic: sorted, fixed format, no clocks.

  python3 tools/library/build_game_set.py            # dry run: what would change
  python3 tools/library/build_game_set.py --write    # write data/library/game_buildings.json, game_ground.json
  python3 tools/library/build_game_set.py --check    # exit 1 if committed files differ / import contract broken

Floors / eave / roof / ground-floor fields are read from the Blender generator parameter modules
(art/blender/hero/fam_layout.py, hero_layout.py), never guessed; unreadable fields are the string "unknown".
Pivot: the game table pivot is the footprint centre; hero GLBs are authored with the pivot on the facade line, so
`pivot_offset_m` (to ADD to every vertex of every LOD) = -(LOD0 bbox XZ centre).
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import apply_approvals as aa  # noqa: E402
import glb_info  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CATALOG = "data/library/catalog.json"
OUT_DIR = "data/library"
FORMAT = "imaro-game-set/1"
UNKNOWN = "unknown"
LEVELS = ("LOD0", "LOD1", "PROXY")
FAMILY_MAP = {"hero_old_core": "old_core", "hero_com_bazaar": "bazaar", "hero_res_mid": "res_mid",
              "hero_res_late": "res_late", "hero_res_house": "house", "hero_ind_hero": "industrial",
              "hero_civ_hero": "civic"}
LAYOUT_SRC = {"old_core": "art/blender/hero/hero_layout.py"}  # all others: fam_layout.py FAMILIES[name]()
FAM_LAYOUT = "art/blender/hero/fam_layout.py"


def _r(v, n=4):
    return round(float(v), n) + 0.0


def res_to_path(root, res):
    return os.path.join(root, res.replace("res://", "", 1))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for blk in iter(lambda: fh.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def png_size(path):
    with open(path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        raise ValueError("%s: not a PNG" % path)
    return list(struct.unpack(">II", head[16:24]))


def import_params(root, res):
    """`[params]` of `<res>.import` as {key: raw string}; {} if missing."""
    path = res_to_path(root, res) + ".import"
    out = {}
    if not os.path.isfile(path):
        return out
    on = False
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith("["):
                on = line == "[params]"
            elif on and "=" in line:
                k, v = line.split("=", 1)
                out[k] = v
    return out


def _load_module(root, rel, name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(root, rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def generator_specs(root):
    """family key -> dict(floors source) read from the generator parameter modules (pure python, no bpy)."""
    specs = {}
    try:
        fam = _load_module(root, FAM_LAYOUT, "fam_layout_t062")
        for key, fn in fam.FAMILIES.items():
            s = fn()
            specs[key] = dict(
                src=FAM_LAYOUT + ":FAMILIES[%r]" % key, nf=s["NF"], gf_h=s["GF"], fl_h=s["FL"], wall_h=s["H"],
                roof=dict(s["roof"]),
                shopfront=any(h.get("kind") == "shop" for h in s["holes"]))
    except Exception as ex:  # unreadable -> unknown, reported
        specs["_fam_error"] = str(ex)
    try:
        old = _load_module(root, LAYOUT_SRC["old_core"], "hero_layout_t062")
        specs["old_core"] = dict(
            src=LAYOUT_SRC["old_core"] + ":GF,FL,NF,H,PITCH_DEG,OVER", nf=old.NF, gf_h=old.GF, fl_h=old.FL,
            wall_h=old.H, roof=dict(kind="hip", pitch=old.PITCH_DEG, over=old.OVER),
            shopfront=any(h.get("kind") == "shop" for h in old.front_holes()))
    except Exception as ex:
        specs["_old_error"] = str(ex)
    return specs


def entry_file_hashes(entry):
    """[(hash_key, res_path, recorded_sha)] for every hash that names a file on disk."""
    out = []
    if isinstance(entry.get("glb"), str) and isinstance(entry.get("glb_sha256"), str):
        out.append(("glb", entry["glb"], entry["glb_sha256"]))
    if isinstance(entry.get("png"), str) and isinstance(entry.get("png_sha256"), str):
        out.append(("png", entry["png"], entry["png_sha256"]))
    chain = entry.get("lod_chain") or {}
    for name in ("atlas", "proxy_atlas"):
        node = chain.get(name)
        if isinstance(node, dict) and "path" in node and "sha256" in node:
            out.append(("lod_chain/%s/sha256" % name, node["path"], node["sha256"]))
    for lvl, node in sorted((chain.get("levels") or {}).items()):
        if isinstance(node, dict) and "glb" in node and "sha256" in node:
            out.append(("lod_chain/levels/%s/sha256" % lvl, node["glb"], node["sha256"]))
    return out


def gate(entry, root):
    """(ok, reason, detail). ok only if approved + recorded hashes == current catalog hashes + files match."""
    appr = entry.get("approval")
    if appr != "approved":
        return False, "not_approved", str(appr)
    rec = entry.get(aa.SHA_FIELD)
    if not isinstance(rec, dict) or not rec:
        return False, "no_approved_hash", "approved without user_approved_sha256"
    cur = aa.content_hashes(entry)
    if rec != cur:
        keys = sorted(k for k in set(rec) | set(cur) if rec.get(k) != cur.get(k))
        return False, "hash_drift", ",".join(keys)
    for key, res, sha in entry_file_hashes(entry):
        path = res_to_path(root, res)
        if not os.path.isfile(path):
            return False, "file_missing", res
        if sha256_file(path) != sha:
            return False, "file_drift", res
    return True, "", ""


def _measure(root, res):
    info = glb_info.inspect(res_to_path(root, res))
    nodes = list(info["nodes"].values())
    lo = [min(n["min"][i] for n in nodes) for i in range(3)]
    hi = [max(n["max"][i] for n in nodes) for i in range(3)]
    return sum(n["tris"] for n in nodes), lo, hi, info["materials"]


def build_building(entry, root, specs, contract_errors):
    fam_key = FAMILY_MAP[entry["family"]]
    spec = specs.get(fam_key)
    chain = entry["lod_chain"]
    lods = {}
    for lvl in LEVELS:
        node = chain["levels"][lvl]
        tris, lo, hi, mats = _measure(root, node["glb"])
        imp = import_params(root, node["glb"])
        gl = imp.get("meshes/generate_lods")
        if gl != "false":
            contract_errors.append("%s %s: meshes/generate_lods must be false (got %s)" % (entry["id"], lvl, gl))
        lods[lvl] = {"glb": node["glb"], "sha256": node["sha256"], "tris": tris,
                     "aabb_m": {"min": [_r(v) for v in lo], "max": [_r(v) for v in hi]}, "materials": sorted(mats),
                     "import": {"generate_lods": False}}
    b0 = lods["LOD0"]["aabb_m"]
    if spec is None:
        gen = {k: UNKNOWN for k in ("floors", "upper_floors", "eave_height_m", "roof_type", "gf")}
        gen["source"] = UNKNOWN
        gen["error"] = specs.get("_old_error") or specs.get("_fam_error") or "family not in generator specs"
    else:
        nf, gf_h = spec["nf"], spec["gf_h"]
        roof = spec["roof"]
        has_floors = gf_h > 0
        gen = {
            "source": spec["src"],
            "upper_floors": nf,
            "floors": nf + 1 if has_floors else UNKNOWN,
            "floors_note": ("ground floor + upper floors (SPEC GF>0)" if has_floors else
                            "single-volume hall: SPEC GF=0 and NF=0, no storey structure in the generator"),
            "eave_height_m": _r(spec["wall_h"]),
            "eave_note": "wall top (SPEC H); roof overhang/parapet above, see roof",
            "roof_type": roof["kind"],
            "roof": {k: v for k, v in sorted(roof.items()) if k != "kind"},
            "gf": {"height_m": _r(gf_h), "storey_height_m": _r(spec["fl_h"]), "shopfront": bool(spec["shopfront"])},
        }
    cx = (b0["min"][0] + b0["max"][0]) / 2
    cz = (b0["min"][2] + b0["max"][2]) / 2
    atlas_png = res_to_path(root, chain["atlas"]["path"])
    proxy_png = res_to_path(root, chain["proxy_atlas"]["path"])
    a = entry["dimensions_m"]
    return {
        "id": entry["id"],
        "kind": "building",
        "family": entry["family"],
        "variant": entry["variant"],
        "era": entry.get("era"),
        "generator": entry["source"]["generator"],
        "lods": lods,
        "triangles": {l: lods[l]["tris"] for l in LEVELS},
        "footprint_m": [_r(b0["max"][0] - b0["min"][0]), _r(b0["max"][2] - b0["min"][2])],
        "footprint_note": "LOD0 bbox XZ (conservative, includes awnings/balconies)",
        "height_m": _r(b0["max"][1]),
        "pivot_authored": "facade line (front = +Z); bbox z in [-depth, +overhang]",
        "pivot_offset_m": [_r(-cx, 6), 0.0, _r(-cz, 6)],
        "pivot_note": "ADD to every vertex of LOD0/LOD1/PROXY so the pivot is the LOD0 bbox XZ centre",
        "foundation_skirt_m": a.get("foundation_skirt_depth", 0.0),
        "generator_params": gen,
        "atlas": {"path": chain["atlas"]["path"], "sha256": chain["atlas"]["sha256"], "size_px": png_size(atlas_png),
                  "material": "mat_hero_atlas"},
        "proxy_atlas": {"path": chain["proxy_atlas"]["path"], "sha256": chain["proxy_atlas"]["sha256"],
                        "size_px": png_size(proxy_png)},
        "palette": {"wall_rows": [], "roof_rows": [], "accent_rows": [], "note": "hero carries no palette rows"}
        if not any(entry.get("palette_rows", {}).values()) else entry["palette_rows"],
        "lod_distances_m": {"value": UNKNOWN, "note": "catalog distances_m are 'working-model-not-integrated'"},
    }


def add_constraints(modules):
    """Known limits derived from the data itself (no prose guesses)."""
    by_fam = {}
    for m in modules:
        by_fam.setdefault(m["family"], []).append(m)
    for fam, ms in by_fam.items():
        ref = ms[0]
        for m in ms:
            c = ["one floor count per family (variants differ in style only)"]
            if m["footprint_m"] != ref["footprint_m"]:
                c.append("footprint differs from variant %s of the same family (%s vs %s)"
                         % (ref["variant"], m["footprint_m"], ref["footprint_m"]))
            c.append("LOD0 %d tris: far above kit LOD0 band (ADR-0006 section 1)" % m["triangles"]["LOD0"]
                     if m["triangles"]["LOD0"] > 1000 else "")
            m["known_constraints"] = [x for x in c if x]


def build_ground(entry, root, layers, contract_errors):
    path = res_to_path(root, entry["png"])
    size = png_size(path)
    declared = entry.get("texture", {}).get("size_px")
    imp = import_params(root, entry["png"])
    mip = imp.get("mipmaps/generate")
    if mip != "true":
        contract_errors.append("%s: mipmaps/generate must be true (got %s)" % (entry["id"], mip))
    base = os.path.basename(path)
    layer = layers.get(base)
    mips = int(math.floor(math.log2(max(size)))) + 1
    rec = {
        "id": entry["id"], "kind": "ground_texture", "variant": entry["variant"], "png": entry["png"],
        "png_sha256": entry["png_sha256"], "size_px": size,
        "size_matches_catalog": declared is None or [declared, declared] == size,
        "tile_m": entry.get("texture", {}).get("tile_m", UNKNOWN),
        "palette_rows": entry.get("palette_rows", {}).get("ground_rows", []),
        "import": {"mipmaps_generate": True, "mip_levels": mips, "compress_mode": imp.get("compress/mode", UNKNOWN)},
        "layer_index": layer["index"] if layer else UNKNOWN,
        "layer_note": "index in assets/ground/tex/ground_layers.json (terrain layer order)" if layer else
        "not in ground_layers.json",
        "generator": entry["source"]["generator"],
    }
    return rec


def exclusions(entries, category, included_ids, root):
    out = []
    for e in entries:
        if e.get("category") != category or e["id"] in included_ids:
            continue
        ok, reason, detail = gate(e, root)
        if ok:  # approved + current but not a game kind handled by this table (e.g. old kit): report as such
            reason, detail = "not_in_this_table", e.get("source", {}).get("kind", "")
        out.append({"id": e["id"], "reason": reason, "detail": detail})
    out.sort(key=lambda x: x["id"])
    by = {}
    for x in out:
        by[x["reason"]] = by.get(x["reason"], 0) + 1
    return {"count": len(out), "by_reason": dict(sorted(by.items())), "entries": out}


def build_sets(catalog_path, root):
    """-> (dict filename -> text, contract_errors). Pure function of catalog + files."""
    with open(catalog_path, "rb") as fh:
        raw = fh.read()
    catalog = json.loads(raw.decode("utf-8"))
    entries = catalog["entries"]
    digest = hashlib.sha256(raw).hexdigest()
    errors = []
    specs = generator_specs(root)
    layers = {}
    lp = os.path.join(root, "assets/ground/tex/ground_layers.json")
    if os.path.isfile(lp):
        with open(lp, "r", encoding="utf-8") as fh:
            layers = {l["file"]: l for l in json.load(fh)["layers"]}

    bld, gnd = [], []
    for e in sorted(entries, key=lambda x: x["id"]):
        is_hero = e.get("category") == "building" and e.get("family") in FAMILY_MAP and \
            (e.get("source") or {}).get("kind") == "hero"
        is_gnd = e.get("category") == "ground" and e.get("png")
        if not (is_hero or is_gnd):
            continue
        ok, _r1, _d = gate(e, root)
        if not ok:
            continue
        if is_hero and "lod_chain" in e and all(l in e["lod_chain"].get("levels", {}) for l in LEVELS):
            bld.append(build_building(e, root, specs, errors))
        elif is_gnd:
            gnd.append(build_ground(e, root, layers, errors))
    add_constraints(bld)

    def doc(table, items, category):
        ids = {m["id"] for m in items}
        ex = exclusions(entries, category, ids, root)
        return {"format": FORMAT, "table": table, "source_catalog": CATALOG, "source_catalog_sha256": digest,
                "gate": "approval == approved AND user_approved_sha256 == current catalog content hashes AND files match",
                "included_count": len(items), "unapproved": ex, "modules" if category == "building" else "layers": items}

    out = {
        "game_buildings.json": doc("buildings", bld, "building"),
        "game_ground.json": doc("ground", gnd, "ground"),
    }
    texts = {k: json.dumps(v, indent=1, ensure_ascii=False) + "\n" for k, v in out.items()}
    return texts, errors


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--catalog", default=None)
    ap.add_argument("--out-dir", default=None)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    root = os.path.abspath(a.root)
    cat = a.catalog or os.path.join(root, CATALOG)
    out_dir = a.out_dir or os.path.join(root, OUT_DIR)
    texts, errors = build_sets(cat, root)
    rc = 0
    for e in errors:
        print("ERROR " + e)
        rc = 1
    for name, text in texts.items():
        path = os.path.join(out_dir, name)
        cur = open(path, "r", encoding="utf-8").read() if os.path.isfile(path) else None
        d = json.loads(text)
        print("%s: %d included, %d excluded (%s)%s" % (name, d["included_count"], d["unapproved"]["count"],
                                                       json.dumps(d["unapproved"]["by_reason"]),
                                                       "" if cur == text else " [DIFFERS]"))
        if a.write and not errors:
            os.makedirs(out_dir, exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
        elif a.check and cur != text:
            print("ERROR %s stale (run build_game_set.py --write)" % name)
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
