"""Headless driver of the T-004 building kit (design/specs/art/building-kit-v0.md, section 12 order).

  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python art/blender/generators/build_kit.py -- [--seed 0] [--only res_mid,res_old,...] [--out-root assets/models]

Writes one .glb per module (LOD0 / LOD1 / PROXY objects, single `mat_kit`, UV0 = part id + shade) and the kit
manifest `<out-root>/buildings/kit_manifest.json` (merged with existing entries when --only is used).
Deterministic: same --seed -> same bytes (verified by sha256 over two runs, see tests/art + report).
Pure-Python geometry also runs without Blender: add --dry-run to print triangle counts only.
"""
import argparse
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import kit_buildings as kb  # noqa: E402
import kit_common as kc  # noqa: E402
import kit_props as kp  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

KIT_VERSION = 1
ROW_NAMES = ["W%d" % i for i in range(1, 14)] + ["R%d" % i for i in range(1, 9)]
ACCENT_ROWS = ["A1", "A2", "A3"]
TILE = ["R3", "R4", "R5"]
FLAT = ["R1", "R2"]
METAL = ["R6", "R7"]

FAMILY = {
    # family: (era, wall_rows, {roof_type: roof_rows}, order)
    "res_mid": ("mid", ["W1", "W2", "W3", "W4", "W5", "W6", "W7"], {"flat": FLAT}, 1),
    "res_old": ("old", ["W1", "W2", "W3", "W4", "W8"], {"flat": FLAT, "hip": TILE, "gable": TILE}, 2),
    "res_late": ("late", ["W1", "W5", "W6", "W7", "W9"], {"flat": FLAT, "hip": TILE}, 3),
    "res_house": ("mid", ["W1", "W2", "W3", "W4", "W8"], {"hip": TILE + ["R6"], "gable": TILE + ["R6"]}, 4),
    "ind_shed": ("late", ["W9", "W12", "W13"], {"gable": METAL, "sawtooth": METAL + ["R8"]}, 5),
    "ind_heritage": ("old", ["W10", "W11"], {"gable": ["R4", "R5", "R8"], "sawtooth": ["R7", "R8"]}, 6),
    "civ_hall": ("mid", ["W2", "W8", "W11"], {"flat": FLAT, "hip": ["R8", "R5"]}, 7),
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="build_kit")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--only", default="", help="comma list of families / prop ids; default = all")
    ap.add_argument("--out-root", default=os.path.join(ROOT, "assets", "models"))
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args(argv)


def bbox(m):
    lo, hi = m.aabb()
    return {"min": [round(c, 3) for c in lo], "max": [round(c, 3) for c in hi]}


def building_jobs(seed, only):
    for fam, (fn, table) in kb.BUILDERS.items():
        if only and fam not in only:
            continue
        for v, spec in table.items():
            for gf in ([False, True] if spec.get("gf") else [False]):
                yield fam, v, gf, fn


def build_building(fam, v, gf, fn, seed):
    ident = "bld_%s_%s%s" % (fam, v, "_gf" if gf else "")
    rng = random.Random("%d/%s" % (seed, ident))
    m0, mass = fn(v, gf, rng)
    m0, m1, mp = kb.finish(m0, mass)
    era, wall_rows, roof_map, _ = FAMILY[fam]
    rt = mass["roof_type"]
    top = m0.aabb()[1][1]
    floors = {
        "res_mid": kb.RES_MID, "res_old": kb.RES_OLD, "res_late": kb.RES_LATE, "res_house": kb.RES_HOUSE,
        "ind_heritage": kb.IND_HERITAGE, "civ_hall": kb.CIV_HALL}.get(fam, {}).get(v, {}).get("floors", 1)
    entry = {
        "id": ident, "family": fam, "kind": "building", "variant": v + ("_gf" if gf else ""), "gf": gf,
        "era": era, "floors": floors, "footprint_m": [round(mass["footprint"][0], 2), round(mass["footprint"][1], 2)],
        "eave_height_m": round(mass["eave"], 2), "total_height_m": round(top, 2), "roof_type": rt,
        "palette": {"wall_rows": wall_rows, "roof_rows": roof_map.get(rt, FLAT), "accent_rows": ACCENT_ROWS},
        "lods": {"LOD0": {"node": ident + "_LOD0", "tris": m0.tri_count()},
                 "LOD1": {"node": ident + "_LOD1", "tris": m1.tri_count()},
                 "PROXY": {"node": ident + "_PROXY", "tris": mp.tri_count()}},
        "aabb_lod0_m": bbox(m0),
        "glb": "res://assets/models/buildings/%s/%s.glb" % (fam, ident),
    }
    objs = {ident + "_LOD0": m0, ident + "_LOD1": m1, ident + "_PROXY": mp}
    return entry, objs


def build_tower(seed):
    ident = "bld_lmk_clocktower"
    m0 = kp.build_clocktower()
    m1, mp = kp.tower_mass()
    top = m0.aabb()[1][1]
    entry = {
        "id": ident, "family": "lmk_clocktower", "kind": "landmark", "variant": "a", "gf": False, "era": "old",
        "floors": 0, "footprint_m": [9.0, 9.0], "eave_height_m": round(top, 2), "total_height_m": round(top, 2),
        "roof_type": "special",
        "palette": {"wall_rows": ["W2", "W11"], "roof_rows": ["R8"], "accent_rows": ACCENT_ROWS},
        "lods": {"LOD0": {"node": ident + "_LOD0", "tris": m0.tri_count()},
                 "LOD1": {"node": ident + "_LOD1", "tris": m1.tri_count()},
                 "PROXY": {"node": ident + "_PROXY", "tris": mp.tri_count()}},
        "aabb_lod0_m": bbox(m0),
        "glb": "res://assets/models/buildings/lmk_clocktower/%s.glb" % ident,
    }
    return entry, {ident + "_LOD0": m0, ident + "_LOD1": m1, ident + "_PROXY": mp}


PROPS = {
    "prop_human": ("prop", "props", "human"),
    "veh_car": ("vehicle", "vehicles", "car"),
    "veg_plane": ("vegetation", "vegetation", "plane"),
    "prop_chimney": ("prop", "props", "chimney"),
}


def build_prop(ident, seed):
    kind, folder, _ = PROPS[ident]
    objs = {}
    if ident == "prop_human":
        objs[ident + "_LOD0"] = kp.build_human()
        wall = ["W2", "W5", "W6", "W7", "W9", "W3"]
        roof = ["R2", "R7", "R5", "R1"]
    elif ident == "veh_car":
        objs[ident + "_LOD0"] = kp.build_car()
        wall = ["W5", "W7", "W9", "W2", "W6", "W1", "W12"]
        roof = ["R2"]
    elif ident == "veg_plane":
        objs[ident + "_LOD0"] = kp.build_plane_tree(seed, 0)
        objs[ident + "_LOD1"] = kp.build_plane_tree(seed, 1)
        wall = ["W1"]
        roof = ["P2", "P3", "P4"]
    else:
        objs[ident + "_LOD0"] = kp.build_chimney()
        wall = ["W10"]
        roof = ["R2"]
    m0 = objs[ident + "_LOD0"]
    top = m0.aabb()[1][1]
    lo, hi = m0.aabb()
    entry = {
        "id": ident, "family": ident, "kind": kind, "variant": "a", "gf": False, "era": "none", "floors": 0,
        "footprint_m": [round(hi[0] - lo[0], 2), round(hi[2] - lo[2], 2)], "eave_height_m": round(top, 2),
        "total_height_m": round(top, 2), "roof_type": "special",
        "palette": {"wall_rows": wall, "roof_rows": roof, "accent_rows": ACCENT_ROWS},
        "lods": {k.split("_")[-1]: {"node": k, "tris": mm.tri_count()} for k, mm in objs.items()},
        "aabb_lod0_m": bbox(m0),
        "glb": "res://assets/models/%s/%s.glb" % (folder, ident),
    }
    return entry, objs


def main():
    args = parse_args()
    only = set(x for x in args.only.split(",") if x)
    jobs = []
    for fam, v, gf, fn in building_jobs(args.seed, only):
        jobs.append(("b", fam, v, gf, fn))
    if not only or "lmk_clocktower" in only:
        jobs.append(("t", "lmk_clocktower", "a", False, None))
    for ident in PROPS:
        if not only or ident in only:
            jobs.append(("p", ident, "a", False, None))
    entries = []
    for typ, fam, v, gf, fn in jobs:
        if typ == "b":
            entry, objs = build_building(fam, v, gf, fn, args.seed)
        elif typ == "t":
            entry, objs = build_tower(args.seed)
        else:
            entry, objs = build_prop(fam, args.seed)
        path = os.path.join(args.out_root, entry["glb"].replace("res://assets/models/", ""))
        if args.dry_run:
            print("%-28s %s" % (entry["id"], {k: v2["tris"] for k, v2 in entry["lods"].items()}))
        else:
            kc.export_glb(path, objs)
            entry["sha256"] = kc.sha256_file(path)
            print("built %s tris=%s" % (entry["id"], {k: v2["tris"] for k, v2 in entry["lods"].items()}))
        entries.append(entry)
    if args.dry_run:
        return
    manifest_path = os.path.join(args.out_root, "buildings", "kit_manifest.json")
    old = {}
    if only and os.path.exists(manifest_path):
        import json
        with open(manifest_path) as f:
            old = {e["id"]: e for e in json.load(f).get("modules", [])}
    for e in entries:
        old[e["id"]] = e
    modules = [old[k] for k in sorted(old)]
    kc.write_json(manifest_path, {
        "kit_version": KIT_VERSION, "seed": args.seed, "spec": "design/specs/art/building-kit-v0.md",
        "units": "metre", "forward": "+Z (glTF)", "material": "mat_kit", "pivot": "footprint centre, y=0, skirt to -2.5",
        "uv0": "x=(part_id+0.5)/16, y=shade", "palette": "res://assets/kit/kit_palette.json",
        "budgets": {"max_lod0_meshes": 40, "max_lod0_tris": 1500, "proxy_max_tris": 14, "skirt_m": 2.5},
        "modules": modules})
    print("manifest: %d modules -> %s" % (len(modules), manifest_path))


main()
