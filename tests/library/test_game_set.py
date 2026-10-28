"""T-062 A0: game tables (build_game_set.py). Mutations run on a tmp copy of the catalog; the real one is never written.

Run: python3 -m unittest discover -s tests/library -p 'test_game_set.py' -q
"""
import copy
import json
import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "library"))
import apply_approvals as aa  # noqa: E402
import build_game_set as bgs  # noqa: E402

REAL = os.path.join(ROOT, bgs.CATALOG)


def load():
    with open(REAL, "r", encoding="utf-8") as fh:
        return json.load(fh)


HERO_KIND = {"building": "hero", "vegetation": "hero_vegetation", "street_furniture": "hero_furniture"}


def expected_ids(catalog, category):
    """Independent re-derivation from the catalog: approved + recorded hashes == current hashes."""
    out = set()
    for e in catalog["entries"]:
        if e.get("category") != category or e.get("approval") != "approved":
            continue
        if category in HERO_KIND and (e.get("source") or {}).get("kind") != HERO_KIND[category]:
            continue
        if e.get(aa.SHA_FIELD) and e[aa.SHA_FIELD] == aa.content_hashes(e):
            out.add(e["id"])
    return out


class GameSetTest(unittest.TestCase):
    def build(self, mutate=None):
        cat = load()
        if mutate:
            mutate(cat)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "catalog.json")
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(cat, fh, indent=1)
            texts, errors = bgs.build_sets(path, ROOT)
        return {k: json.loads(v) for k, v in texts.items()}, errors

    def ids(self, docs):
        return ({m["id"] for m in docs["game_buildings.json"]["modules"]},
                {m["id"] for m in docs["game_ground.json"]["layers"]})

    def reasons(self, docs, name="game_buildings.json"):
        return {x["id"]: x["reason"] for x in docs[name]["unapproved"]["entries"]}

    # --- derivation -------------------------------------------------------------------------------------------
    def test_ids_derived_from_catalog_not_embedded(self):
        docs, errors = self.build()
        self.assertEqual([], errors)
        b, g = self.ids(docs)
        cat = load()
        self.assertEqual(expected_ids(cat, "building"), b)
        self.assertEqual(expected_ids(cat, "ground"), g)
        self.assertEqual(21, len(b))
        self.assertEqual(14, len(g))
        with open(os.path.join(ROOT, "tools/library/build_game_set.py"), encoding="utf-8") as fh:
            src = fh.read()
        self.assertIsNone(re.search(r"bld_hero_|gnd_tex_", src), "no embedded id list allowed")

    def test_included_plus_excluded_cover_the_category(self):
        docs, _ = self.build()
        cat = load()
        for name, category in (("game_buildings.json", "building"), ("game_ground.json", "ground")):
            n = sum(1 for e in cat["entries"] if e["category"] == category)
            d = docs[name]
            self.assertEqual(n, d["included_count"] + d["unapproved"]["count"], name)
            self.assertEqual(d["unapproved"]["count"], sum(d["unapproved"]["by_reason"].values()))
        self.assertEqual({"not_approved": 42}, docs["game_buildings.json"]["unapproved"]["by_reason"])

    def test_rejected_kit_never_in_output(self):
        docs, _ = self.build()
        text = json.dumps(docs["game_buildings.json"]["modules"])
        for bad in ("bld_civ_hall", "bld_res_old", "bld_lmk_clocktower", "bld_ind_shed", "bld_ind_heritage",
                    "assets/models/buildings"):
            self.assertNotIn(bad, text)
        self.assertEqual("rejected", next(x["detail"] for x in docs["game_buildings.json"]["unapproved"]["entries"]
                                          if x["id"] == "bld_civ_hall_a"))

    # --- negative: gate ---------------------------------------------------------------------------------------
    def entry(self, cat, ident):
        return next(e for e in cat["entries"] if e["id"] == ident)

    def test_proposed_rejected_hold_are_excluded(self):
        for state in ("proposed", "rejected", "hold", "provisional-in-use"):
            def mut(cat, s=state):
                self.entry(cat, "bld_hero_res_mid_a")["approval"] = s
                self.entry(cat, "gnd_tex_gravel")["approval"] = s
            docs, _ = self.build(mut)
            b, g = self.ids(docs)
            self.assertNotIn("bld_hero_res_mid_a", b, state)
            self.assertNotIn("gnd_tex_gravel", g, state)
            self.assertEqual("not_approved", self.reasons(docs)["bld_hero_res_mid_a"])
            self.assertEqual("not_approved", self.reasons(docs, "game_ground.json")["gnd_tex_gravel"])
            self.assertEqual(20, len(b))
            self.assertEqual(13, len(g))

    def test_missing_approved_hash_is_excluded(self):
        def mut(cat):
            del self.entry(cat, "bld_hero_old_core_b")[aa.SHA_FIELD]
        docs, _ = self.build(mut)
        self.assertNotIn("bld_hero_old_core_b", self.ids(docs)[0])
        self.assertEqual("no_approved_hash", self.reasons(docs)["bld_hero_old_core_b"])

    def test_content_hash_drift_is_excluded(self):
        # catalog content hash moved after approval (e.g. LOD1 regenerated): recorded != current
        def mut(cat):
            e = self.entry(cat, "bld_hero_ind_hero_c")
            e["lod_chain"]["levels"]["LOD1"]["sha256"] = "0" * 64
            e = self.entry(cat, "gnd_tex_beach_sand")
            e["png_sha256"] = "1" * 64
        docs, _ = self.build(mut)
        b, g = self.ids(docs)
        self.assertNotIn("bld_hero_ind_hero_c", b)
        self.assertNotIn("gnd_tex_beach_sand", g)
        self.assertEqual("hash_drift", self.reasons(docs)["bld_hero_ind_hero_c"])
        self.assertIn("lod_chain/levels/LOD1/sha256",
                      next(x["detail"] for x in docs["game_buildings.json"]["unapproved"]["entries"]
                           if x["id"] == "bld_hero_ind_hero_c"))
        self.assertEqual("hash_drift", self.reasons(docs, "game_ground.json")["gnd_tex_beach_sand"])
        self.assertEqual(20, len(b))

    def test_file_drift_is_excluded_even_if_catalog_and_approval_agree(self):
        def mut(cat):
            e = self.entry(cat, "bld_hero_res_late_b")
            e["glb_sha256"] = "2" * 64
            e[aa.SHA_FIELD]["glb"] = "2" * 64
        docs, _ = self.build(mut)
        self.assertNotIn("bld_hero_res_late_b", self.ids(docs)[0])
        self.assertEqual("file_drift", self.reasons(docs)["bld_hero_res_late_b"])

    def test_catalog_hash_change_changes_source_digest(self):
        a, _ = self.build()
        b, _ = self.build(lambda c: self.entry(c, "bld_hero_res_mid_a").__setitem__("user_note", "x"))
        self.assertNotEqual(a["game_buildings.json"]["source_catalog_sha256"],
                            b["game_buildings.json"]["source_catalog_sha256"])

    # --- determinism / committed files ------------------------------------------------------------------------
    def test_two_builds_are_byte_equal(self):
        t1, e1 = bgs.build_sets(REAL, ROOT)
        t2, e2 = bgs.build_sets(REAL, ROOT)
        self.assertEqual((t1, e1), (t2, e2))
        self.assertEqual([], e1)
        for text in t1.values():
            self.assertTrue(text.endswith("}\n"))
            self.assertNotRegex(text, r"20\d\d-\d\d-\d\dT")  # no timestamps

    def test_committed_tables_equal_fresh_build(self):
        texts, _ = bgs.build_sets(REAL, ROOT)
        for name, text in texts.items():
            with open(os.path.join(ROOT, bgs.OUT_DIR, name), "r", encoding="utf-8") as fh:
                self.assertEqual(text, fh.read(), name + " is stale (python3 tools/library/build_game_set.py --write)")

    # --- content ---------------------------------------------------------------------------------------------
    def test_building_records(self):
        docs, _ = self.build()
        mods = {m["id"]: m for m in docs["game_buildings.json"]["modules"]}
        self.assertEqual(sorted(mods), [m["id"] for m in docs["game_buildings.json"]["modules"]])
        floors = {f: mods["bld_hero_%s_a" % f]["generator_params"]["floors"]
                  for f in ("old_core", "com_bazaar", "res_house", "res_mid", "res_late", "civ_hero", "ind_hero")}
        self.assertEqual(dict(old_core=4, com_bazaar=3, res_house=2, res_mid=6, res_late=8, civ_hero=3,
                              ind_hero="unknown"), floors)
        for m in mods.values():
            self.assertEqual(["LOD0", "LOD1", "PROXY"], sorted(m["lods"]))
            b = m["lods"]["LOD0"]["aabb_m"]
            self.assertAlmostEqual(-(b["min"][0] + b["max"][0]) / 2, m["pivot_offset_m"][0], places=4)
            self.assertAlmostEqual(-(b["min"][2] + b["max"][2]) / 2, m["pivot_offset_m"][2], places=4)
            self.assertAlmostEqual(b["max"][2] - b["min"][2], m["footprint_m"][1], places=3)
            self.assertGreater(m["generator_params"]["eave_height_m"], 0)
            self.assertIn(m["generator_params"]["roof_type"], ("hip", "flat", "gable"))
            self.assertFalse(any(l["import"]["generate_lods"] for l in m["lods"].values()))
            self.assertEqual("mat_hero_atlas", m["atlas"]["material"])
            self.assertEqual([256, 256], m["proxy_atlas"]["size_px"])
            self.assertEqual([1024, 1024], m["atlas"]["size_px"])
            self.assertGreater(m["triangles"]["LOD0"], m["triangles"]["LOD1"])
            self.assertGreater(m["triangles"]["LOD1"], m["triangles"]["PROXY"])

    def test_ground_records(self):
        docs, _ = self.build()
        for l in docs["game_ground.json"]["layers"]:
            self.assertTrue(l["import"]["mipmaps_generate"])
            self.assertEqual([512, 512], l["size_px"])
            self.assertTrue(l["size_matches_catalog"])
            self.assertEqual(10, l["import"]["mip_levels"])

    # --- import contract (real .import files) ----------------------------------------------------------------
    def test_real_imports_follow_contract(self):
        docs, errors = self.build()
        self.assertEqual([], errors)
        for m in docs["game_buildings.json"]["modules"]:
            for l in m["lods"].values():
                p = bgs.import_params(ROOT, l["glb"])
                self.assertEqual("false", p["meshes/generate_lods"], l["glb"])
        for l in docs["game_ground.json"]["layers"]:
            self.assertEqual("true", bgs.import_params(ROOT, l["png"])["mipmaps/generate"], l["png"])

    def test_generate_lods_true_is_a_contract_error(self):
        real = bgs.import_params
        try:
            bgs.import_params = lambda root, res: dict(real(root, res), **{"meshes/generate_lods": "true"})
            _docs, errors = self.build()
        finally:
            bgs.import_params = real
        self.assertTrue(errors and all("generate_lods" in e for e in errors))

    def test_mipmaps_off_is_a_contract_error(self):
        real = bgs.import_params
        try:
            bgs.import_params = lambda root, res: dict(real(root, res), **{"mipmaps/generate": "false"})
            _docs, errors = self.build()
        finally:
            bgs.import_params = real
        self.assertTrue(any("mipmaps" in e for e in errors))


class PlantFurnitureSetTest(unittest.TestCase):
    """T-062 B0: game_plants.json / game_furniture.json (same gate; unapproved never enters)."""

    build = GameSetTest.build
    entry = GameSetTest.entry

    def plants(self, docs):
        return {m["id"]: m for m in docs["game_plants.json"]["plants"]}

    def items(self, docs):
        return {m["id"]: m for m in docs["game_furniture.json"]["items"]}

    def test_ids_derived_from_catalog(self):
        docs, errors = self.build()
        self.assertEqual([], errors)
        cat = load()
        self.assertEqual(expected_ids(cat, "vegetation"), set(self.plants(docs)))
        self.assertEqual(expected_ids(cat, "street_furniture"), set(self.items(docs)))
        self.assertEqual(10, len(self.plants(docs)))
        self.assertEqual(8, len(self.items(docs)))
        self.assertEqual(sorted(self.plants(docs)), [m["id"] for m in docs["game_plants.json"]["plants"]])

    def test_kit_plane_is_not_a_game_plant_but_is_listed(self):
        docs, _ = self.build()
        self.assertNotIn("veg_plane", self.plants(docs))
        self.assertIn("veg_hero_plane_a", self.plants(docs))
        ex = {x["id"]: x["reason"] for x in docs["game_plants.json"]["unapproved"]["entries"]}
        self.assertEqual({"veg_plane": "not_in_this_table"}, ex)
        d = docs["game_plants.json"]
        self.assertEqual(11, d["included_count"] + d["unapproved"]["count"])

    def test_unapproved_plants_and_furniture_never_enter(self):
        for state in ("proposed", "rejected", "hold", "provisional-in-use"):
            def mut(cat, s=state):
                self.entry(cat, "veg_hero_palm_date_a")["approval"] = s
                self.entry(cat, "veg_hero_pine_stone_a")["approval"] = s
                self.entry(cat, "fur_hero_bench_a")["approval"] = s
            docs, _ = self.build(mut)
            self.assertNotIn("veg_hero_palm_date_a", self.plants(docs), state)
            self.assertNotIn("veg_hero_pine_stone_a", self.plants(docs), state)
            self.assertNotIn("fur_hero_bench_a", self.items(docs), state)
            self.assertEqual(8, len(self.plants(docs)))
            self.assertEqual(7, len(self.items(docs)))
            ex = {x["id"]: x["reason"] for x in docs["game_plants.json"]["unapproved"]["entries"]}
            self.assertEqual("not_approved", ex["veg_hero_palm_date_a"])

    def test_hash_drift_and_missing_hash_are_excluded(self):
        def mut(cat):
            self.entry(cat, "veg_hero_olive_open_a")["lod_chain"]["levels"]["LOD1"]["sha256"] = "0" * 64
            del self.entry(cat, "veg_hero_hedge_a")[aa.SHA_FIELD]
            self.entry(cat, "fur_hero_kiosk_a")["lod_chain"]["atlas"]["sha256"] = "1" * 64
        docs, _ = self.build(mut)
        ex = {x["id"]: x["reason"] for x in docs["game_plants.json"]["unapproved"]["entries"]}
        self.assertEqual("hash_drift", ex["veg_hero_olive_open_a"])
        self.assertEqual("no_approved_hash", ex["veg_hero_hedge_a"])
        self.assertNotIn("fur_hero_kiosk_a", self.items(docs))
        self.assertEqual(8, len(self.plants(docs)))

    def test_file_drift_is_excluded(self):
        def mut(cat):
            e = self.entry(cat, "veg_hero_maquis_a")
            e["glb_sha256"] = "2" * 64
            e[aa.SHA_FIELD]["glb"] = "2" * 64
        docs, _ = self.build(mut)
        self.assertNotIn("veg_hero_maquis_a", self.plants(docs))

    def test_plant_records(self):
        docs, _ = self.build()
        plants = self.plants(docs)
        species = {m["species"] for m in plants.values()}
        self.assertEqual({"cypress", "hedge", "maquis", "olive_open", "olive_twisted", "palm_date", "palm_slender",
                          "pine_brutia", "pine_stone", "plane"}, species)
        for m in plants.values():
            self.assertIn("LOD0", m["lods"])
            self.assertIn("LOD1", m["lods"])
            self.assertEqual("mat_vegetation_atlas", m["atlas"]["material"])
            self.assertEqual([1024, 1024], m["atlas"]["size_px"])
            self.assertFalse(any(l["import"]["generate_lods"] for l in m["lods"].values()))
            self.assertEqual([0.0, 0.0, 0.0], m["pivot_offset_m"])
            self.assertGreater(m["reach_m"], 0.0)
            self.assertGreater(m["height_m"], 0.0)
            b = m["lods"]["LOD0"]["aabb_m"]
            self.assertLessEqual(b["min"][0], 0.0)
            self.assertGreaterEqual(b["max"][0], 0.0)
            self.assertEqual(m["triangles"], {k: v["tris"] for k, v in m["lods"].items()})
            self.assertEqual(m["reach_m"], max(abs(b["min"][0]), abs(b["max"][0]), abs(b["min"][2]), abs(b["max"][2])))
        self.assertEqual({"palm_date", "palm_slender"}, {m["species"] for m in plants.values() if "PROXY" in m["lods"]})
        self.assertTrue(all(plants[i]["lods"]["PROXY"]["tris"] == 40 for i in plants if "PROXY" in plants[i]["lods"]))
        self.assertIn("open", plants["veg_hero_palm_date_a"]["q018"])

    def test_furniture_records(self):
        docs, _ = self.build()
        items = self.items(docs)
        self.assertEqual({"bench", "bike_rack", "bin", "bollard", "bus_stop", "kiosk", "lamp_street", "planter"},
                         {m["type"] for m in items.values()})
        for m in items.values():
            self.assertEqual(["LOD0", "LOD1"], sorted(m["lods"]))
            self.assertEqual("mat_furniture_atlas", m["atlas"]["material"])
            self.assertFalse(any(l["import"]["generate_lods"] for l in m["lods"].values()))
            self.assertGreater(m["reach_m"], 0.0)

    def test_origin_outside_bbox_is_a_contract_error(self):
        real = bgs._measure
        try:
            bgs._measure = lambda root, res: (10, [5.0, 0.0, 5.0], [6.0, 2.0, 6.0], ["m"])
            _docs, errors = self.build()
        finally:
            bgs._measure = real
        self.assertTrue(any("origin is outside" in e for e in errors))

    def test_generate_lods_true_on_plants_is_a_contract_error(self):
        real = bgs.import_params
        try:
            bgs.import_params = lambda root, res: dict(real(root, res), **{"meshes/generate_lods": "true"})
            _docs, errors = self.build()
        finally:
            bgs.import_params = real
        self.assertTrue(any("veg_hero_" in e and "generate_lods" in e for e in errors))
        self.assertTrue(any("fur_hero_" in e and "generate_lods" in e for e in errors))

    def test_committed_plant_tables_equal_fresh_build_and_are_deterministic(self):
        t1, e1 = bgs.build_sets(REAL, ROOT)
        t2, _ = bgs.build_sets(REAL, ROOT)
        self.assertEqual(t1, t2)
        self.assertEqual([], e1)
        for name in ("game_plants.json", "game_furniture.json"):
            with open(os.path.join(ROOT, bgs.OUT_DIR, name), "r", encoding="utf-8") as fh:
                self.assertEqual(t1[name], fh.read(), name + " is stale (python3 tools/library/build_game_set.py --write)")

    def test_no_embedded_plant_id_list(self):
        with open(os.path.join(ROOT, "tools/library/build_game_set.py"), encoding="utf-8") as fh:
            src = fh.read()
        self.assertIsNone(re.search(r"veg_hero_|fur_hero_", src), "no embedded id list allowed")


if __name__ == "__main__":
    unittest.main()
