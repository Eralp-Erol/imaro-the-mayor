"""T-055: zemin dokularini data/library/catalog.json'a approval=proposed kaydeder (category ground, source.kind texture).
Kullanici alanlarini (approval*, user_note) korur; kit/hero kayitlarina dokunmaz.  python3 register_catalog.py [--write]"""
import hashlib
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CAT = os.path.join(ROOT, "data/library/catalog.json")
TEX = os.path.join(ROOT, "assets/ground/tex")


def main():
    cat = json.load(open(CAT))
    meta = json.load(open(os.path.join(TEX, "ground_layers.json")))
    old = {e["id"]: e for e in cat["entries"]}
    n = 0
    for L in meta["layers"]:
        path = os.path.join(TEX, L["file"])
        eid = "gnd_tex_" + L["id"]
        e = {"id": eid, "category": "ground", "family": "gnd_tex", "variant": L["id"], "era": "none", "region": None,
             "tags": ["texture", "tileable", "palette:" + L["palette_zone"]],
             "png": "res://assets/ground/tex/" + L["file"], "glb": None,
             "png_sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(), "materials": ["ground_lab.gdshader"],
             "dimensions_m": None, "triangles": None,
             "texture": {"tile_m": L["tile_m"], "size_px": meta["size_px"], "measured_from": "ground_layers.json"},
             "palette_rows": {"accent_rows": [], "roof_rows": [], "wall_rows": [], "ground_rows": [L["palette_zone"]]},
             "hsv": L["hsv"],
             "source": {"kind": "texture", "generator": "art/blender/ground/ground_tex.py", "manifest": "assets/ground/tex/ground_layers.json",
                        "rebuild": "python3 art/blender/ground/ground_tex.py", "spec": "design/specs/art/ground/"},
             "approval": "proposed", "approval_by": None, "approval_date": None, "user_note": "",
             "notes": "T-055 lab dokusu; oyuna bagli degil. Seamless 512 px, tile_m dunya boyutu."}
        prev = old.get(eid)
        if prev:
            for k in ("approval", "approval_by", "approval_date", "user_note"):
                e[k] = prev.get(k, e[k])
        old[eid] = e
        n += 1
    order = {c["id"]: i for i, c in enumerate(cat["categories"])}
    cat["entries"] = sorted(old.values(), key=lambda e: (order.get(e.get("category"), 99), e["id"]))
    if "--write" in sys.argv:
        open(CAT, "w").write(json.dumps(cat, indent=2, ensure_ascii=False) + "\n")
        print("written", n)
    else:
        print("dry", n)


main()
