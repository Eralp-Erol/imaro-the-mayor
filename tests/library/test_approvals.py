"""Approval-system tests (apply_approvals.py). Work on a tmp copy of the catalog; the real one is never written.

Run: python3 -m unittest discover -s tests/library -p 'test_approvals.py' -q
"""
import copy
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "library"))
import apply_approvals as aa  # noqa: E402
import build_catalog as bc  # noqa: E402

REAL = os.path.join(ROOT, bc.CATALOG)
TARGET_FIELDS = {"approval", "approval_by", "approval_date", "user_note", aa.SHA_FIELD}


class ApprovalTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.cat = os.path.join(self.tmp, "catalog.json")
        shutil.copyfile(REAL, self.cat)
        with open(self.cat, "rb") as fh:
            self.orig_bytes = fh.read()
        self.orig = json.loads(self.orig_bytes.decode("utf-8"))
        self.entries = {e["id"]: e for e in self.orig["entries"]}
        # drift-free pick by data, not by a fixed id list
        self.a, self.b = [e["id"] for e in self.orig["entries"] if e["approval"] != "approved"][:2]

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def doc(self, *decs, **over):
        d = {"schema": aa.SCHEMA, "decided_by": "user", "decided_at": "2026-10-27T12:00:00Z", "decisions": list(decs)}
        d.update(over)
        return d

    def dec(self, ident, decision="approved", note="", sha=None):
        return {"id": ident, "decision": decision, "note": note,
                "sha256": aa.content_hashes(self.entries[ident]) if sha is None else sha}

    def run_doc(self, doc, write=True):
        out = io.StringIO()
        rc = aa.run(doc, self.cat, ROOT, write, out=out)
        return rc, out.getvalue()

    def current(self):
        with open(self.cat, "r", encoding="utf-8") as fh:
            return json.load(fh)

    def assert_untouched(self):
        with open(self.cat, "rb") as fh:
            self.assertEqual(fh.read(), self.orig_bytes)

    def test_real_catalog_roundtrips_byte_equal(self):
        self.assertEqual(bc.dumps(self.orig).encode("utf-8"), self.orig_bytes)
        self.assertEqual(len(self.orig["entries"]), len(self.entries))

    def test_every_entry_has_content_hash(self):
        for e in self.orig["entries"]:
            self.assertTrue(aa.content_hashes(e), e["id"])

    def test_valid_approval_changes_only_target_fields(self):
        rc, out = self.run_doc(self.doc(self.dec(self.a, "approved", "iyi")))
        self.assertEqual(rc, 0, out)
        new = self.current()
        self.assertEqual(len(new["entries"]), len(self.orig["entries"]))
        for o, n in zip(self.orig["entries"], new["entries"]):
            if o["id"] != self.a:
                self.assertEqual(o, n, o["id"])
                continue
            self.assertEqual(n["approval"], "approved")
            self.assertEqual(n["approval_by"], "user")
            self.assertEqual(n["approval_date"], "2026-10-27")
            self.assertEqual(n["user_note"], "iyi")
            self.assertEqual(n[aa.SHA_FIELD], aa.content_hashes(o))
            for k in set(o) | set(n):
                if k not in TARGET_FIELDS:
                    self.assertEqual(o.get(k), n.get(k), k)
        self.assertEqual({k: v for k, v in new.items() if k != "entries"},
                         {k: v for k, v in self.orig.items() if k != "entries"})

    def test_rejection_applies(self):
        rc, _ = self.run_doc(self.doc(self.dec(self.a, "rejected")))
        self.assertEqual(rc, 0)
        e = [x for x in self.current()["entries"] if x["id"] == self.a][0]
        self.assertEqual((e["approval"], e["approval_by"]), ("rejected", "user"))

    def test_agent_signed_rejected(self):
        for who in ("agent", "claude", None, "User"):
            rc, out = self.run_doc(self.doc(self.dec(self.a), decided_by=who))
            self.assertNotEqual(rc, 0)
            self.assertIn("decided_by", out)
        self.assert_untouched()

    def test_wrong_schema_rejected(self):
        rc, _ = self.run_doc(self.doc(self.dec(self.a), schema="x/1"))
        self.assertNotEqual(rc, 0)
        self.assert_untouched()

    def test_unknown_id(self):
        rc, out = self.run_doc(self.doc({"id": "nope_zzz", "decision": "approved", "sha256": {"glb": "0"}}))
        self.assertNotEqual(rc, 0)
        self.assertIn("unknown id", out)
        self.assert_untouched()

    def test_invalid_decision(self):
        d = self.dec(self.a)
        d["decision"] = "maybe"
        rc, out = self.run_doc(self.doc(d))
        self.assertNotEqual(rc, 0)
        self.assertIn("decision must be", out)
        self.assert_untouched()

    def test_sha_drift_rejected(self):
        sha = dict(aa.content_hashes(self.entries[self.a]))
        k = sorted(sha)[0]
        sha[k] = "0" * 64
        rc, out = self.run_doc(self.doc(self.dec(self.a, sha=sha)))
        self.assertNotEqual(rc, 0)
        self.assertIn("re-review", out)
        self.assert_untouched()

    def test_missing_sha_rejected(self):
        d = self.dec(self.a)
        del d["sha256"]
        rc, _ = self.run_doc(self.doc(d))
        self.assertNotEqual(rc, 0)
        self.assert_untouched()

    def test_hold_changes_only_note(self):
        rc, _ = self.run_doc(self.doc({"id": self.a, "decision": "hold", "note": "sonra bakarim"}))
        self.assertEqual(rc, 0)
        new = {e["id"]: e for e in self.current()["entries"]}
        o, n = self.entries[self.a], new[self.a]
        self.assertEqual(n["user_note"], "sonra bakarim")
        for k in set(o) | set(n):
            if k != "user_note":
                self.assertEqual(o.get(k), n.get(k), k)

    def test_hold_without_note_is_noop(self):
        rc, out = self.run_doc(self.doc({"id": self.a, "decision": "hold"}))
        self.assertEqual(rc, 0)
        self.assertIn("no changes", out)
        self.assert_untouched()

    def test_dry_run_writes_nothing(self):
        rc, out = self.run_doc(self.doc(self.dec(self.a)), write=False)
        self.assertEqual(rc, 0)
        self.assertIn("DRY", out)
        self.assert_untouched()

    def test_multiple_decisions_all_or_nothing(self):
        bad = self.dec(self.b)
        bad["sha256"] = {"glb": "deadbeef"}
        rc, _ = self.run_doc(self.doc(self.dec(self.a), bad))
        self.assertNotEqual(rc, 0)
        self.assert_untouched()

    def test_multiple_valid_decisions_apply_together(self):
        rc, _ = self.run_doc(self.doc(self.dec(self.a), self.dec(self.b, "rejected")))
        self.assertEqual(rc, 0)
        new = {e["id"]: e for e in self.current()["entries"]}
        self.assertEqual((new[self.a]["approval"], new[self.b]["approval"]), ("approved", "rejected"))
        changed = [i for i in new if new[i] != self.entries[i]]
        self.assertEqual(sorted(changed), sorted([self.a, self.b]))

    def test_duplicate_id_rejected(self):
        rc, _ = self.run_doc(self.doc(self.dec(self.a), self.dec(self.a, "rejected")))
        self.assertNotEqual(rc, 0)
        self.assert_untouched()

    def test_reapproval_with_different_sha_refused(self):
        self.assertEqual(self.run_doc(self.doc(self.dec(self.a)))[0], 0)
        # simulate content drift after approval: catalog hash changes, user re-submits current hash
        cat = self.current()
        e = [x for x in cat["entries"] if x["id"] == self.a][0]
        key = "glb_sha256" if "glb_sha256" in e else "png_sha256"
        e[key] = "f" * 64
        with open(self.cat, "w", encoding="utf-8") as fh:
            fh.write(bc.dumps(cat))
        self.entries = {x["id"]: x for x in cat["entries"]}
        with open(self.cat, "rb") as fh:
            before = fh.read()
        rc, out = self.run_doc(self.doc(self.dec(self.a)))
        self.assertNotEqual(rc, 0)
        self.assertTrue("different content hash" in out or "invalid" in out, out)
        with open(self.cat, "rb") as fh:
            self.assertEqual(fh.read(), before)

    def test_same_sha_reapproval_is_idempotent(self):
        self.assertEqual(self.run_doc(self.doc(self.dec(self.a)))[0], 0)
        with open(self.cat, "rb") as fh:
            before = fh.read()
        self.entries = {e["id"]: e for e in self.current()["entries"]}
        rc, _ = self.run_doc(self.doc(self.dec(self.a)))
        self.assertEqual(rc, 0)
        with open(self.cat, "rb") as fh:
            self.assertEqual(fh.read(), before)

    def test_rejected_entry_not_reusable(self):
        self.assertEqual(self.run_doc(self.doc(self.dec(self.a, "rejected")))[0], 0)
        self.entries = {e["id"]: e for e in self.current()["entries"]}
        rc, out = self.run_doc(self.doc(self.dec(self.a, "approved")))
        self.assertNotEqual(rc, 0)
        self.assertIn("rejected", out)

    def test_cli_dry_run_exit_codes(self):
        p = os.path.join(self.tmp, "d.json")
        with open(p, "w") as fh:
            json.dump(self.doc(self.dec(self.a)), fh)
        self.assertEqual(aa.main([p, "--catalog", self.cat, "--root", ROOT]), 0)
        self.assert_untouched()
        with open(p, "w") as fh:
            json.dump(self.doc(self.dec(self.a), decided_by="agent"), fh)
        self.assertEqual(aa.main([p, "--catalog", self.cat, "--root", ROOT, "--write"]), 1)
        self.assert_untouched()


if __name__ == "__main__":
    unittest.main()
