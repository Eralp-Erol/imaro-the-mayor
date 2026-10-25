"""Catalog validator + builder tests (T-052). Stdlib only.

Run: python3 -I -m unittest discover -s tests/library -p "test_*.py" -t .   (from the repo root)
or:  python3 -I tests/library/test_catalog.py
"""
import copy
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "library"))
import build_catalog as bc  # noqa: E402
import validate_catalog as vc  # noqa: E402


def _load(rel):
    with open(os.path.join(ROOT, rel), "r", encoding="utf-8") as fh:
        return json.load(fh)


class CatalogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = _load(bc.MANIFEST)
        cls.catalog = _load(bc.CATALOG)

    def fresh(self):
        return copy.deepcopy(self.catalog)

    def validate(self, catalog, manifest=None):
        return vc.validate(catalog, ROOT, manifest if manifest is not None else self.manifest)

    def test_committed_catalog_is_valid(self):
        errors, _warnings = self.validate(self.catalog)
        self.assertEqual(errors, [])

    def test_every_manifest_module_is_cataloged(self):
        ids = set(e["id"] for e in self.catalog["entries"])
        for m in self.manifest["modules"]:
            self.assertIn(m["id"], ids)

    def test_all_kit_entries_are_provisional_in_use_and_not_user_approved(self):
        for e in self.catalog["entries"]:
            if e["source"]["kind"] == "kit" and e["approval_by"] is None:
                self.assertEqual(e["approval"], "provisional-in-use", e["id"])

    def test_missing_required_field(self):
        c = self.fresh()
        del c["entries"][0]["category"]
        errors, _ = self.validate(c)
        self.assertTrue(any("missing field 'category'" in x for x in errors), errors)

    def test_bad_enum_value(self):
        c = self.fresh()
        c["entries"][0]["approval"] = "maybe"
        errors, _ = self.validate(c)
        self.assertTrue(any("approval 'maybe'" in x for x in errors), errors)

    def test_duplicate_id(self):
        c = self.fresh()
        c["entries"].append(copy.deepcopy(c["entries"][0]))
        errors, _ = self.validate(c)
        self.assertTrue(any("duplicate id" in x for x in errors), errors)

    def test_missing_glb(self):
        c = self.fresh()
        c["entries"][0]["glb"] = "res://assets/models/buildings/nope/does_not_exist.glb"
        errors, _ = self.validate(c)
        self.assertTrue(any("missing GLB file" in x for x in errors), errors)

    def test_missing_generator(self):
        c = self.fresh()
        c["entries"][0]["source"]["generator"] = "art/blender/generators/not_there.py"
        errors, _ = self.validate(c)
        self.assertTrue(any("source.generator missing" in x for x in errors), errors)

    def test_manifest_module_missing_from_catalog(self):
        c = self.fresh()
        removed = c["entries"].pop(0)["id"]
        errors, _ = self.validate(c)
        self.assertTrue(any(removed in x and "not in catalog" in x for x in errors), errors)

    def test_kit_entry_removed_from_manifest(self):
        m = copy.deepcopy(self.manifest)
        gone = m["modules"].pop(0)["id"]
        errors, _ = self.validate(self.catalog, m)
        self.assertTrue(any(gone in x and "no longer in the manifest" in x for x in errors), errors)

    def test_drift_detection(self):
        c = self.fresh()
        c["entries"][0]["triangles"]["LOD0"] += 1
        c["entries"][1]["dimensions_m"]["width_x"] += 1.0
        errors, _ = self.validate(c)
        self.assertTrue(any("triangles differ" in x for x in errors), errors)
        self.assertTrue(any("dimensions differ" in x for x in errors), errors)

    def test_manifest_triangle_disagreement(self):
        m = copy.deepcopy(self.manifest)
        m["modules"][0]["lods"]["LOD0"]["tris"] += 5
        errors, _ = self.validate(self.catalog, m)
        self.assertTrue(any("manifest says LOD0" in x for x in errors), errors)

    def test_budget_exceeded(self):
        m = copy.deepcopy(self.manifest)
        m["budgets"]["max_lod0_tris"] = 10
        errors, _ = self.validate(self.catalog, m)
        self.assertTrue(any("over budget" in x for x in errors), errors)

    def test_approved_requires_user_author_and_date(self):
        c = self.fresh()
        c["entries"][0]["approval"] = "approved"
        errors, _ = self.validate(c)
        self.assertTrue(any("requires approval_by == 'user'" in x for x in errors), errors)
        c["entries"][0]["approval_by"] = "user"
        c["entries"][0]["approval_date"] = None
        errors, _ = self.validate(c)
        self.assertTrue(any("requires approval_date" in x for x in errors), errors)
        c["entries"][0]["approval_date"] = "2026-10-26"
        errors, _ = self.validate(c)
        self.assertEqual(errors, [])

    def test_agent_cannot_claim_user_authorship_on_provisional(self):
        c = self.fresh()
        c["entries"][0]["approval_by"] = "user"
        errors, _ = self.validate(c)
        self.assertTrue(any("approval_by must be null" in x for x in errors), errors)

    def test_proposed_entry_without_glb_is_allowed(self):
        c = self.fresh()
        c["entries"].append({
            "id": "hum_pedestrian_proposal", "category": "human", "family": "human", "era": "none", "tags": [],
            "glb": None, "dimensions_m": None, "triangles": None, "source": {"kind": "template"},
            "approval": "proposed", "approval_by": None, "approval_date": "2026-10-25", "user_note": ""})
        errors, _ = self.validate(c)
        self.assertEqual(errors, [])

    def test_measurements_match_independent_inspection(self):
        # The human model is 1.75 m by spec; this guards the GLB reader against drifting from reality.
        e = next(x for x in self.catalog["entries"] if x["id"] == "prop_human")
        self.assertAlmostEqual(e["dimensions_m"]["height_above_ground"], 1.75, places=2)


class BuilderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = _load(bc.MANIFEST)

    def build(self, existing):
        return bc.merge(self.manifest, existing, ROOT, "2026-10-25")

    def test_fresh_build_never_writes_approved_or_rejected(self):
        cat = self.build(None)
        for e in cat["entries"]:
            self.assertEqual(e["approval"], "provisional-in-use")
            self.assertIsNone(e["approval_by"])
            self.assertEqual(e["user_note"], "")

    def test_idempotent(self):
        once = self.build(None)
        twice = self.build(json.loads(bc.dumps(once)))
        self.assertEqual(bc.dumps(once), bc.dumps(twice))

    def test_committed_catalog_is_up_to_date(self):
        existing = _load(bc.CATALOG)
        self.assertEqual(bc.dumps(self.build(existing)), bc.dumps(existing),
                         "catalog.json stale: run python3 tools/library/build_catalog.py --write")

    def test_user_fields_survive_regeneration(self):
        base = self.build(None)
        a, b, c = base["entries"][0], base["entries"][1], base["entries"][2]
        a.update(approval="approved", approval_by="user", approval_date="2026-11-01", user_note="tamam")
        b.update(approval="rejected", approval_by="user", approval_date="2026-11-02", user_note="cok yuksek",
                 user_extra="x")
        c.update(approval="proposed", user_note="gozden gecir")
        again = self.build(json.loads(bc.dumps(base)))
        by_id = dict((e["id"], e) for e in again["entries"])
        for e in (a, b, c):
            got = by_id[e["id"]]
            for key in ("approval", "approval_by", "approval_date", "user_note"):
                self.assertEqual(got[key], e[key], "%s.%s" % (e["id"], key))
        self.assertEqual(by_id[b["id"]]["user_extra"], "x")
        approved = [e for e in again["entries"] if e["approval"] in ("approved", "rejected")]
        self.assertEqual(len(approved), 2)

    def test_non_kit_entries_are_kept_verbatim(self):
        base = self.build(None)
        extra = {"id": "veh_bus_proposal", "category": "vehicle", "source": {"kind": "template"},
                 "approval": "proposed", "approval_by": None, "approval_date": "2026-10-25", "user_note": "?"}
        base["entries"].append(extra)
        again = self.build(json.loads(bc.dumps(base)))
        got = next(e for e in again["entries"] if e["id"] == "veh_bus_proposal")
        self.assertEqual(got, extra)

    def test_entry_dropped_from_manifest_is_kept_and_flagged(self):
        base = self.build(None)
        m = copy.deepcopy(self.manifest)
        gone = m["modules"].pop(0)["id"]
        again = bc.merge(m, json.loads(bc.dumps(base)), ROOT, "2026-10-25")
        got = next(e for e in again["entries"] if e["id"] == gone)
        self.assertIs(got["manifest_present"], False)
        self.assertEqual(got["approval"], "provisional-in-use")


if __name__ == "__main__":
    unittest.main()
