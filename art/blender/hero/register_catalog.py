"""T-053/T-054: register hero buildings in data/library/catalog.json as approval=proposed (source.kind="hero").
Keeps existing user fields (approval*, user_note) for ids already present; never touches kit entries.  python3 register_catalog.py [--write]"""
import hashlib
import json
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CAT = os.path.join(ROOT, "data/library/catalog.json")
FAMS = {"bazaar": ("com_bazaar", "old"), "res_mid": ("res_mid", "mid"), "res_late": ("res_late", "late"), "house": ("res_house", "old"),
        "industrial": ("ind_hero", "mid"), "civic": ("civ_hero", "old")}


def glb_stats(path):
    data = open(path, "rb").read()
    jl, _ = struct.unpack("<II", data[12:20])
    j = json.loads(data[20:20 + jl])
    prim = j["meshes"][0]["primitives"][0]
    acc = j["accessors"][prim["attributes"]["POSITION"]]
    tris = (j["accessors"][prim["indices"]]["count"] if "indices" in prim else acc["count"]) // 3
    return tris, acc["min"], acc["max"], len(data)


def entry(eid, family, variant, era, glb_res, gen, rebuild, spec_note):
    path = os.path.join(ROOT, glb_res.replace("res://", ""))
    tris, mn, mx, size = glb_stats(path)
    return {"id": eid, "category": "building", "family": family, "variant": variant, "era": era, "region": None,
            "tags": ["hero", "textured_atlas", "era:" + era], "glb": glb_res,
            "glb_sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(), "materials": ["mat_hero_atlas"],
            "dimensions_m": {"width_x": round(mx[0] - mn[0], 3), "depth_z": round(mx[2] - mn[2], 3), "height_above_ground": round(mx[1], 3),
                             "foundation_skirt_depth": 0.0, "bbox_min": [round(v, 3) for v in mn], "bbox_max": [round(v, 3) for v in mx],
                             "measured_from": "GLB POSITION accessor min/max (glTF +Y up; front faces +Z)"},
            "triangles": {"LOD0": tris, "LOD1": None, "PROXY": None},
            "palette_rows": {"accent_rows": [], "roof_rows": [], "wall_rows": []},
            "source": {"kind": "hero", "generator": gen, "manifest": None, "rebuild": rebuild, "spec": spec_note},
            "approval": "proposed", "approval_by": None, "approval_date": None, "user_note": "",
            "notes": "Hero kanit calismasi; kit manifest'inde YOK, oyuna bagli degil. Dokulu atlas materyali (mat_kit degil)."}


def main():
    cat = json.load(open(CAT))
    old = {e["id"]: e for e in cat["entries"]}
    new = []
    for v in "abc":
        new.append(entry(f"bld_hero_old_core_{v}", "hero_old_core", v, "old", f"res://assets/hero/hero_{v}.glb", "art/blender/hero/hero_building.py",
                         "python3 art/blender/hero/hero_atlas.py assets/hero && Blender --background --factory-startup --python art/blender/hero/hero_building.py -- --atlas assets/hero/hero_atlas_%s.png --layout assets/hero/hero_atlas_layout.json --out assets/hero/hero_%s.glb" % (v, v),
                         "design/specs/art/hero-building/"))
    for fam, (family, era) in FAMS.items():
        for v in "abc":
            new.append(entry(f"bld_hero_{family}_{v}", "hero_" + family, v, era, f"res://assets/hero/fam/hero_{fam}_{v}.glb",
                             "art/blender/hero/fam_build.py", "art/blender/hero/build_families.sh " + fam, "design/specs/art/hero-building/families/" + fam))
    for e in new:
        prev = old.get(e["id"])
        if prev:
            for k in ("approval", "approval_by", "approval_date", "user_note"):
                e[k] = prev.get(k, e[k])
        old[e["id"]] = e
    order = {c["id"]: i for i, c in enumerate(cat["categories"])}
    cat["entries"] = sorted(old.values(), key=lambda e: (order.get(e.get("category"), 99), e["id"]))
    text = json.dumps(cat, indent=2, ensure_ascii=False) + "\n"
    if "--write" in sys.argv:
        open(CAT, "w").write(text)
        print("catalog written; entries:", len(cat["entries"]), "hero:", len(new))
    else:
        print("dry run; would have", len(cat["entries"]), "entries")


main()
