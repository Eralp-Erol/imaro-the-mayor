#!/usr/bin/env python3
"""Build the game-facing library tables (T-062 A0, ADR-0006 section 2.1a).

Only entries with approval == "approved" whose recorded content hashes (`user_approved_sha256`) equal the catalog's
CURRENT content hashes AND the files on disk are written to `data/library/game_*.json`. Everything else is excluded
and listed with its reason (the game counts these as `unapproved`). Deterministic: sorted, fixed format, no clocks.

  python3 tools/library/build_game_set.py            # dry run: what would change
  python3 tools/library/build_game_set.py --write    # write data/library/game_buildings.json, game_ground.json,
                                                     # game_plants.json, game_furniture.json (T-062 B0)
  python3 tools/library/build_game_set.py --check    # exit 1 if committed files differ / import contract broken

Floors / eave / roof / ground-floor fields are read from the Blender generator parameter modules
(art/blender/hero/fam_layout.py, hero_layout.py), never guessed; unreadable fields are the string "unknown".
Pivot: the game table pivot is the footprint centre; hero GLBs are authored with the pivot on the facade line, so
`pivot_offset_m` (to ADD to every vertex of every LOD) = -(LOD0 bbox XZ centre).

Vehicles / humans (T-050, D-012/D-013): same gate. `game_vehicles.json` holds the approved kit car (`veh_car`, single
LOD0, kit GLB, kit palette material: there is no LOD chain / atlas for it, reported in `known_constraints`);
`game_humans.json` holds ONLY the user-selected human style (HUMAN_GAME_STYLE = "block", D-013); the other approved
human styles stay listed as `style_not_selected` and never reach the game table.

Plants / street furniture (T-062 B0): same gate. Their GLBs are authored with the origin at the trunk / object base
(y = 0 ground contact), so NO pivot shift is written; `reach_m` (largest XZ extent from the origin) and `footprint_m`
(LOD0 bbox XZ) are measured from the GLB for placement clearance. The kit `veg_plane` is approved but is NOT a game
plant (kit / mat_kit path): it is excluded as `not_in_this_table`; the hero plane (family hero_plane) is used instead.
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
PLANT_LEVELS = ("LOD0", "LOD1", "PROXY")  # PROXY only where the catalog chain has it (palms)
FURNITURE_LEVELS = ("LOD0", "LOD1")
PLANT_KIND = "hero_vegetation"
FURNITURE_KIND = "hero_furniture"
HUMAN_KIND = "hero_human"
VEHICLE_IDS = ("veh_car",)  # D-012: the only approved vehicle template
HUMAN_GAME_STYLE = "block"  # D-013 (user decision): block figure; pawn/facet stay approved in the catalog, unused in game
HUMAN_LEVELS = ("LOD0", "LOD1")
# Origin must sit inside the LOD0 XZ bbox and ground contact near y = 0 (hero plants/furniture authoring contract).
GROUND_TOL_M = 0.15


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


def _lod_records(entry, root, level_names, contract_errors):
    """lods{} for plants/furniture + the shared origin/ground contract checks (appends to contract_errors)."""
    chain = entry["lod_chain"]
    lods = {}
    for lvl in level_names:
        node = (chain.get("levels") or {}).get(lvl)
        if node is None:
            continue
        tris, lo, hi, mats = _measure(root, node["glb"])
        imp = import_params(root, node["glb"])
        gl = imp.get("meshes/generate_lods")
        if gl != "false":
            contract_errors.append("%s %s: meshes/generate_lods must be false (got %s)" % (entry["id"], lvl, gl))
        lods[lvl] = {"glb": node["glb"], "sha256": node["sha256"], "tris": tris,
                     "aabb_m": {"min": [_r(v) for v in lo], "max": [_r(v) for v in hi]}, "materials": sorted(mats),
                     "import": {"generate_lods": False}}
    b0 = lods["LOD0"]["aabb_m"]
    if not (b0["min"][0] <= 0.0 <= b0["max"][0] and b0["min"][2] <= 0.0 <= b0["max"][2]):
        contract_errors.append("%s: origin is outside the LOD0 XZ bbox (pivot contract)" % entry["id"])
    if b0["min"][1] < -GROUND_TOL_M or b0["min"][1] > GROUND_TOL_M:
        contract_errors.append("%s: LOD0 bbox min y %.3f not near ground (pivot contract)" % (entry["id"], b0["min"][1]))
    return lods


def _object_geometry(lods):
    b0 = lods["LOD0"]["aabb_m"]
    reach = max(abs(b0["min"][0]), abs(b0["max"][0]), abs(b0["min"][2]), abs(b0["max"][2]))
    return {
        "footprint_m": [_r(b0["max"][0] - b0["min"][0]), _r(b0["max"][2] - b0["min"][2])],
        "footprint_note": "LOD0 bbox XZ extent (m, scale 1)",
        "reach_m": _r(reach),
        "reach_note": "largest XZ distance from the GLB origin to the LOD0 bbox (conservative clearance radius, scale 1)",
        "height_m": _r(b0["max"][1]),
        "ground_skirt_m": _r(max(0.0, -b0["min"][1])),
        "pivot_authored": "GLB origin = trunk/object base, y = 0 ground contact",
        "pivot_offset_m": [0.0, 0.0, 0.0],
        "pivot_note": "no shift: place the origin on the ground point; apply yaw about Y and uniform scale",
    }


def _atlas_record(chain, root, material):
    atlas_png = res_to_path(root, chain["atlas"]["path"])
    return {"path": chain["atlas"]["path"], "sha256": chain["atlas"]["sha256"], "size_px": png_size(atlas_png),
            "material": material, "layout": chain["atlas"].get("layout"),
            "layout_sha256": chain["atlas"].get("layout_sha256")}


def build_plant(entry, root, contract_errors):
    chain = entry["lod_chain"]
    lods = _lod_records(entry, root, PLANT_LEVELS, contract_errors)
    species = entry["family"].replace("hero_", "", 1)
    rec = {
        "id": entry["id"], "kind": "vegetation", "species": species, "family": entry["family"],
        "variant": entry["variant"], "label_tr": entry.get("label_tr", ""), "generator": entry["source"]["generator"],
        "lods": lods, "triangles": {l: lods[l]["tris"] for l in lods},
    }
    rec.update(_object_geometry(lods))
    rec.update({
        "atlas": _atlas_record(chain, root, "mat_vegetation_atlas"),
        "material_policy": chain.get("material_policy", {}),
        "far_representation": ("PROXY (catalog chain; palms keep the 40-tri proxy, T-057 decision 5)"
                               if "PROXY" in lods else "none per tree: cell blob/HLOD (T-057 decision 5)"),
        "lod_distances_m": {"LOD0_max": chain["distances_m"].get("LOD0_max"),
                            "LOD1_max": chain["distances_m"].get("LOD1_max"),
                            "status": chain["distances_m"].get("status"),
                            "note": "working-model-not-integrated (T-057 decision 5); measure before use (ADR-0006 s4)"},
        "q018": "open: palm species/season is NOT a selected user decision; placement must stay parametric",
    })
    return rec


def build_furniture(entry, root, contract_errors):
    chain = entry["lod_chain"]
    lods = _lod_records(entry, root, FURNITURE_LEVELS, contract_errors)
    types = [t.split(":", 1)[1] for t in entry.get("tags", []) if t.startswith("type:")]
    rec = {
        "id": entry["id"], "kind": "street_furniture", "type": types[0] if types else UNKNOWN,
        "family": entry["family"], "variant": entry["variant"], "label_tr": entry.get("label_tr", ""),
        "generator": entry["source"]["generator"], "lods": lods, "triangles": {l: lods[l]["tris"] for l in lods},
    }
    rec.update(_object_geometry(lods))
    dist = chain.get("distances_m") or {}
    rec.update({
        "atlas": _atlas_record(chain, root, "mat_furniture_atlas"),
        "material_policy": chain.get("material_policy", {}),
        "lod_distances_m": {"LOD0_max": dist.get("LOD0_max"), "LOD1_max": dist.get("LOD1_max"),
                            "beyond_lod1": dist.get("beyond_lod1"), "distance_class": dist.get("distance_class"),
                            "status": dist.get("status"), "note": "working value, not an integration decision"},
        "q018": "open: furniture style / placement is not a user decision",
    })
    return rec


def build_vehicle(entry, root, contract_errors):
    """Kit vehicle (veh_car): one GLB, no LOD chain / atlas. Material = kit palette (mat_kit via KitMaterial)."""
    glb = entry["glb"]
    tris, lo, hi, mats = _measure(root, glb)
    imp = import_params(root, glb)
    if imp.get("meshes/generate_lods") != "false":
        contract_errors.append("%s: meshes/generate_lods must be false (got %s)" % (entry["id"], imp.get("meshes/generate_lods")))
    lods = {"LOD0": {"glb": glb, "sha256": entry["glb_sha256"], "tris": tris,
                     "aabb_m": {"min": [_r(v) for v in lo], "max": [_r(v) for v in hi]}, "materials": sorted(mats),
                     "import": {"generate_lods": False}}}
    b0 = lods["LOD0"]["aabb_m"]
    if not (b0["min"][0] <= 0.0 <= b0["max"][0] and b0["min"][2] <= 0.0 <= b0["max"][2]):
        contract_errors.append("%s: origin is outside the LOD0 XZ bbox (pivot contract)" % entry["id"])
    if b0["min"][1] < -GROUND_TOL_M or b0["min"][1] > GROUND_TOL_M:
        contract_errors.append("%s: LOD0 bbox min y %.3f not near ground (pivot contract)" % (entry["id"], b0["min"][1]))
    pal = entry.get("palette_rows") or {}
    rec = {
        "id": entry["id"], "kind": "vehicle", "family": entry["family"], "variant": entry["variant"],
        "generator": entry["source"]["generator"], "lods": lods, "triangles": {"LOD0": tris},
        "material": {"kind": "kit_palette", "name": "mat_kit",
                     "note": "kit palette ShaderMaterial (KitMaterial); per-instance rows come from palette.* below"},
        "palette": {"wall_rows": list(pal.get("wall_rows", [])), "roof_rows": list(pal.get("roof_rows", [])),
                    "accent_rows": list(pal.get("accent_rows", []))},
        "known_constraints": ["single LOD (no LOD1/PROXY/atlas in the catalog): far representation is distance culling",
                              "colour identity and number of vehicle types are OPEN (D-012, Q-018)"],
    }
    rec.update(_object_geometry(lods))
    rec["pivot_note"] = "no shift: GLB origin = vehicle centre on the ground (bbox y from ~0); length along Z"
    return rec


def build_human(entry, root, contract_errors):
    chain = entry["lod_chain"]
    lods = _lod_records(entry, root, HUMAN_LEVELS, contract_errors)
    style = [t.split(":", 1)[1] for t in entry.get("tags", []) if t.startswith("style:")]
    ratio = [t.split(":", 1)[1] for t in entry.get("tags", []) if t.startswith("ratio:")]
    rec = {
        "id": entry["id"], "kind": "human", "style": style[0] if style else UNKNOWN,
        "ratio": ratio[0] if ratio else UNKNOWN, "family": entry["family"], "variant": entry["variant"],
        "label_tr": entry.get("label_tr", ""), "generator": entry["source"]["generator"], "lods": lods,
        "triangles": {l: lods[l]["tris"] for l in lods},
    }
    rec.update(_object_geometry(lods))
    dist = chain.get("distances_m") or {}
    rec.update({
        "atlas": _atlas_record(chain, root, "mat_human_atlas"),
        "material_policy": chain.get("material_policy", {}),
        "lod_distances_m": {"LOD0_max": dist.get("LOD0_max"), "LOD1_max": dist.get("LOD1_max"),
                            "beyond_lod1": dist.get("beyond_lod1"), "status": dist.get("status"),
                            "note": "working value, not an integration decision"},
        "q018": "open: body-type count, clothing variety, uniformed staff and named characters (D-013 scope note)",
    })
    return rec


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


def exclusions(entries, category, included_ids, root, ok_reason=None):
    out = []
    for e in entries:
        if e.get("category") != category or e["id"] in included_ids:
            continue
        ok, reason, detail = gate(e, root)
        if ok:  # approved + current but not a game kind handled by this table (e.g. old kit): report as such
            reason, detail = "not_in_this_table", e.get("source", {}).get("kind", "")
            if ok_reason is not None:
                reason, detail = ok_reason
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

    bld, gnd, veg, fur, veh, hum = [], [], [], [], [], []
    for e in sorted(entries, key=lambda x: x["id"]):
        kind = (e.get("source") or {}).get("kind")
        is_hero = e.get("category") == "building" and e.get("family") in FAMILY_MAP and kind == "hero"
        is_gnd = e.get("category") == "ground" and e.get("png")
        is_veg = e.get("category") == "vegetation" and kind == PLANT_KIND
        is_fur = e.get("category") == "street_furniture" and kind == FURNITURE_KIND
        is_veh = e.get("category") == "vehicle" and e["id"] in VEHICLE_IDS and e.get("glb")
        is_hum = (e.get("category") == "human" and kind == HUMAN_KIND
                  and ("style:" + HUMAN_GAME_STYLE) in e.get("tags", []))
        if not (is_hero or is_gnd or is_veg or is_fur or is_veh or is_hum):
            continue
        ok, _r1, _d = gate(e, root)
        if not ok:
            continue
        levels = e.get("lod_chain", {}).get("levels", {})
        if is_hero and all(l in levels for l in LEVELS):
            bld.append(build_building(e, root, specs, errors))
        elif is_gnd:
            gnd.append(build_ground(e, root, layers, errors))
        elif is_veg and "LOD0" in levels and "LOD1" in levels:
            veg.append(build_plant(e, root, errors))
        elif is_fur and "LOD0" in levels and "LOD1" in levels:
            fur.append(build_furniture(e, root, errors))
        elif is_veh:
            veh.append(build_vehicle(e, root, errors))
        elif is_hum and all(l in levels for l in HUMAN_LEVELS):
            hum.append(build_human(e, root, errors))
    add_constraints(bld)

    record_keys = {"building": "modules", "ground": "layers", "vegetation": "plants", "street_furniture": "items",
                   "vehicle": "items", "human": "items"}

    def doc(table, items, category):
        ids = {m["id"] for m in items}
        ok_reason = ("style_not_selected", "D-013: only style:%s is used in game" % HUMAN_GAME_STYLE) \
            if category == "human" else None
        ex = exclusions(entries, category, ids, root, ok_reason)
        d = {"format": FORMAT, "table": table, "source_catalog": CATALOG, "source_catalog_sha256": digest,
             "gate": "approval == approved AND user_approved_sha256 == current catalog content hashes AND files match",
             "included_count": len(items), "unapproved": ex, record_keys[category]: items}
        if category == "vegetation":
            d["notes"] = ["veg_plane (kit, mat_kit) is approved but not a game plant: the hero plane (family hero_plane) "
                          "carries the role (ADR-0006 s4)."]
        return d

    out = {
        "game_buildings.json": doc("buildings", bld, "building"),
        "game_ground.json": doc("ground", gnd, "ground"),
        "game_plants.json": doc("vegetation", veg, "vegetation"),
        "game_furniture.json": doc("furniture", fur, "street_furniture"),
        "game_vehicles.json": doc("vehicles", veh, "vehicle"),
        "game_humans.json": doc("humans", hum, "human"),
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
