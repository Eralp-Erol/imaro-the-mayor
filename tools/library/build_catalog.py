#!/usr/bin/env python3
"""Derive data/library/catalog.json from the kit manifest and the GLB files (T-052).

Idempotent: same manifest + same GLBs + same existing catalog -> byte-identical output.
Measured, never invented: dimensions and triangle counts come from the GLB files (tools/library/glb_info.py).

Ownership rule (CAN-03 / T-052 criterion 1): the fields `approval`, `approval_by`, `approval_date` and `user_note`
(and any `user_*` key) are USER data. This script only sets them when it creates a NEW kit entry
(`provisional-in-use`, approval_by null). For an existing entry they are copied through untouched. The values
`approved` and `rejected` are never written by this script. Entries that are not derived from the kit manifest
(source.kind != "kit", e.g. agent proposals added later) are kept verbatim.

Usage: python3 tools/library/build_catalog.py [--write] [--check] [--date YYYY-MM-DD]
  (default) print a summary and what would change; --write writes the file; --check exits 1 if the file is stale.
"""
import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glb_info  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MANIFEST = "assets/models/buildings/kit_manifest.json"
CATALOG = "data/library/catalog.json"
CATALOG_VERSION = 1

# Order = sheet/page order. label_tr is display text only.
CATEGORIES = [
    ("building", "Bina"),
    ("roof_equipment", "Cati / ekipman"),
    ("vegetation", "Bitki"),
    ("vehicle", "Arac"),
    ("human", "Insan"),
    ("road_section", "Yol kesiti"),
    ("ground", "Zemin / kent dokusu"),
    ("street_furniture", "Sokak donatisi"),
    ("marking", "Isaret / cizgi"),
]
APPROVAL_VALUES = ("proposed", "approved", "rejected", "provisional-in-use")
USER_FIELDS = ("approval", "approval_by", "approval_date", "user_note")

# family -> generator file (verified by the validator: file must exist).
GEN_BUILDINGS = "art/blender/generators/kit_buildings.py"
GEN_INDUSTRY = "art/blender/generators/kit_industry.py"
GEN_PROPS = "art/blender/generators/kit_props.py"
FAMILY_GENERATOR = {
    "res_mid": GEN_BUILDINGS, "res_old": GEN_BUILDINGS, "res_old_town": GEN_BUILDINGS, "res_late": GEN_BUILDINGS,
    "res_house": GEN_BUILDINGS, "ind_shed": GEN_BUILDINGS, "ind_heritage": GEN_BUILDINGS, "civ_hall": GEN_BUILDINGS,
    "ind_vault": GEN_INDUSTRY, "ind_depot": GEN_INDUSTRY, "ind_yard": GEN_INDUSTRY,
    "lmk_clocktower": GEN_PROPS, "prop_chimney": GEN_PROPS, "prop_human": GEN_PROPS, "veh_car": GEN_PROPS,
    "veg_olive": GEN_PROPS, "veg_palm": GEN_PROPS, "veg_pine": GEN_PROPS, "veg_plane": GEN_PROPS,
}
FAMILY_CATEGORY = {"prop_chimney": "roof_equipment", "prop_human": "human", "veh_car": "vehicle"}
KIND_CATEGORY = {"building": "building", "landmark": "building", "vegetation": "vegetation"}


def category_of(module):
    fam = module["family"]
    if fam in FAMILY_CATEGORY:
        return FAMILY_CATEGORY[fam]
    if module["kind"] in KIND_CATEGORY:
        return KIND_CATEGORY[module["kind"]]
    raise SystemExit("build_catalog: no category rule for kind=%r family=%r (add it explicitly)"
                     % (module["kind"], fam))


def res_to_path(res):
    if not res.startswith("res://"):
        raise SystemExit("build_catalog: glb path is not res://: %s" % res)
    return res[len("res://"):]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def r3(v):
    return round(v + 0.0, 3)


def measure(module, root):
    """Measure the GLB of a manifest module. Returns (dimensions, triangles, sha256, materials, problems)."""
    rel = res_to_path(module["glb"])
    path = os.path.join(root, rel)
    problems = []
    if not os.path.isfile(path):
        return None, None, None, [], ["missing GLB: %s" % rel]
    info = glb_info.inspect(path)
    nodes = info["nodes"]
    tris = {}
    for lod, spec in module["lods"].items():
        node = nodes.get(spec["node"])
        if node is None:
            problems.append("%s: node %s missing in GLB" % (module["id"], spec["node"]))
            continue
        tris[lod] = node["tris"]
    lod0 = nodes.get(module["lods"]["LOD0"]["node"])
    dims = None
    if lod0 is not None:
        lo, hi = lod0["min"], lod0["max"]
        dims = {
            "width_x": r3(hi[0] - lo[0]),
            "depth_z": r3(hi[2] - lo[2]),
            "height_above_ground": r3(max(hi[1], 0.0)),
            "foundation_skirt_depth": r3(max(-lo[1], 0.0)),
            "bbox_min": [r3(v) for v in lo],
            "bbox_max": [r3(v) for v in hi],
            "measured_from": "LOD0 POSITION accessor min/max in the GLB",
        }
    return dims, tris, sha256_file(path), info["materials"], problems


def tags_of(module):
    tags = []
    if module["era"] != "none":
        tags.append("era:" + module["era"])
    if module["roof_type"] != "special":
        tags.append("roof:" + module["roof_type"])
    if module.get("gf"):
        tags.append("ground-floor-shop")
    if module["kind"] == "landmark":
        tags.append("landmark")
    return tags


def derived_entry(module, root):
    dims, tris, digest, mats, problems = measure(module, root)
    if problems:
        raise SystemExit("build_catalog: " + "; ".join(problems))
    fam = module["family"]
    if fam not in FAMILY_GENERATOR:
        raise SystemExit("build_catalog: no generator mapping for family %r" % fam)
    entry = {
        "id": module["id"],
        "category": category_of(module),
        "family": fam,
        "variant": module["variant"],
        "era": module["era"],
        "region": None,
        "tags": tags_of(module),
        "glb": module["glb"],
        "glb_sha256": digest,
        "materials": mats,
        "dimensions_m": dims,
        "triangles": {lod: tris.get(lod) for lod in ("LOD0", "LOD1", "PROXY")},
        "palette_rows": module.get("palette", {}),
        "source": {
            "kind": "kit",
            "generator": FAMILY_GENERATOR[fam],
            "manifest": MANIFEST,
            "rebuild": "art/blender/rebuild_kit.sh --only " + fam,
            "spec": "design/specs/art/building-kit-v1.md",
        },
        "manifest_present": True,
    }
    return entry


def new_user_fields(date):
    return {"approval": "provisional-in-use", "approval_by": None, "approval_date": date, "user_note": ""}


def merge(manifest, existing, root, date):
    """Return the new catalog dict. `existing` is the previous catalog dict or None."""
    old = {}
    if existing:
        for e in existing.get("entries", []):
            old[e["id"]] = e
    out = {}
    seen = set()
    for module in manifest["modules"]:
        if module["id"] in seen:
            raise SystemExit("build_catalog: duplicate manifest id %s" % module["id"])
        seen.add(module["id"])
        entry = derived_entry(module, root)
        prev = old.get(module["id"])
        if prev is None:
            entry.update(new_user_fields(date))
        else:
            for key in USER_FIELDS:
                entry[key] = prev.get(key, new_user_fields(date)[key])
            for key in prev:
                if key.startswith("user_") and key not in entry:
                    entry[key] = prev[key]
        out[entry["id"]] = entry
    # Entries not (or no longer) in the manifest: keep verbatim; kit-derived ones are flagged as orphans.
    for ident, prev in old.items():
        if ident in out:
            continue
        kept = dict(prev)
        if kept.get("source", {}).get("kind") == "kit":
            kept["manifest_present"] = False
        out[ident] = kept
    order = {c: i for i, (c, _l) in enumerate(CATEGORIES)}
    entries = sorted(out.values(), key=lambda e: (order.get(e.get("category"), 99), e["id"]))
    return {
        "catalog_version": CATALOG_VERSION,
        "schema": "data/library/SCHEMA.md",
        "generated_by": "tools/library/build_catalog.py",
        "generated_from": MANIFEST,
        "kit_version": manifest.get("kit_version"),
        "palette": manifest.get("palette"),
        "categories": [{"id": c, "label_tr": label} for c, label in CATEGORIES],
        "entries": entries,
    }


def dumps(catalog):
    return json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def run(root, manifest_path, catalog_path, date, write, check):
    manifest = load_json(manifest_path)
    existing = load_json(catalog_path) if os.path.isfile(catalog_path) else None
    text = dumps(merge(manifest, existing, root, date))
    current = None
    if os.path.isfile(catalog_path):
        with open(catalog_path, "r", encoding="utf-8") as fh:
            current = fh.read()
    stale = current != text
    if write and stale:
        os.makedirs(os.path.dirname(catalog_path), exist_ok=True)
        with open(catalog_path, "w", encoding="utf-8") as fh:
            fh.write(text)
    return stale, text


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--write", action="store_true", help="write catalog.json")
    ap.add_argument("--check", action="store_true", help="exit 1 if catalog.json is stale")
    ap.add_argument("--date", default=None, help="date for NEW entries (default: today)")
    ap.add_argument("--root", default=ROOT)
    args = ap.parse_args(argv)
    import datetime
    date = args.date or datetime.date.today().isoformat()
    root = os.path.abspath(args.root)
    stale, text = run(root, os.path.join(root, MANIFEST), os.path.join(root, CATALOG), date, args.write, args.check)
    n = len(json.loads(text)["entries"])
    if args.write:
        print("catalog: %d entries, %s" % (n, "written" if stale else "already up to date"))
    else:
        print("catalog: %d entries, %s" % (n, "STALE (run with --write)" if stale else "up to date"))
    return 1 if (args.check and stale) else 0


if __name__ == "__main__":
    sys.exit(main())
