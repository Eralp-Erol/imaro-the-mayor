#!/usr/bin/env python3
"""Apply USER approval decisions (from the approval page) to data/library/catalog.json.

Input: decisions JSON (file or stdin), schema "imaro-approval-decisions/1", decided_by == "user".
Default is DRY-RUN; --write applies. All decisions are validated first; any error => nothing is written (exit 1).

Only these fields of the targeted entry change: approval, approval_by, approval_date, user_note,
user_approved_sha256 (content hashes the user actually reviewed; the "user_" prefix makes every catalog
regenerator preserve it). 'hold' changes only user_note. Nothing is wired into the game.

Usage: apply_approvals.py [decisions.json | -] [--write] [--catalog PATH] [--root PATH]
"""
import argparse
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_catalog as bc  # noqa: E402
import validate_catalog as vc  # noqa: E402

SCHEMA = "imaro-approval-decisions/1"
DECISIONS = ("approved", "rejected", "hold")
SHA_FIELD = "user_approved_sha256"
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}")


def content_hashes(entry):
    """Flat {name: sha256} of every content hash the catalog records for an entry."""
    out = {}
    for key, name in (("glb_sha256", "glb"), ("png_sha256", "png")):
        if isinstance(entry.get(key), str):
            out[name] = entry[key]

    def walk(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                if isinstance(v, str) and (k == "sha256" or k.endswith("_sha256")):
                    out["/".join(path + [k])] = v
                else:
                    walk(v, path + [k])
    walk(entry.get("lod_chain"), ["lod_chain"])
    return out


def validate_input(doc, entries):
    """Return (errors, plan). plan = list of (entry, decision dict)."""
    errors, plan = [], []
    if not isinstance(doc, dict):
        return ["input is not a JSON object"], plan
    if doc.get("schema") != SCHEMA:
        errors.append("schema must be %r (got %r)" % (SCHEMA, doc.get("schema")))
    if doc.get("decided_by") != "user":
        errors.append("decided_by must be 'user' (agents cannot write approvals; got %r)" % (doc.get("decided_by"),))
    when = doc.get("decided_at")
    if not (isinstance(when, str) and DATE_RE.match(when)):
        errors.append("decided_at must be an ISO date/time string")
    decs = doc.get("decisions")
    if not isinstance(decs, list) or not decs:
        errors.append("decisions must be a non-empty list")
        return errors, plan
    by_id = {e["id"]: e for e in entries}
    seen = set()
    for i, d in enumerate(decs):
        if not isinstance(d, dict):
            errors.append("decisions[%d]: not an object" % i)
            continue
        ident = d.get("id")
        tag = "decisions[%d] %s" % (i, ident)
        if ident not in by_id:
            errors.append("%s: unknown id" % tag)
            continue
        if ident in seen:
            errors.append("%s: duplicate id" % tag)
            continue
        seen.add(ident)
        if d.get("decision") not in DECISIONS:
            errors.append("%s: decision must be one of %s (got %r)" % (tag, "|".join(DECISIONS), d.get("decision")))
            continue
        note = d.get("note", "")
        if note is not None and not isinstance(note, str):
            errors.append("%s: note must be a string" % tag)
            continue
        e = by_id[ident]
        sha = d.get("sha256")
        cur = content_hashes(e)
        if d["decision"] != "hold":
            if not isinstance(sha, dict) or not sha:
                errors.append("%s: sha256 map required for approved/rejected" % tag)
                continue
            if sha != cur:
                diff = sorted(k for k in set(sha) | set(cur) if sha.get(k) != cur.get(k))
                errors.append("%s: file changed since review (drift in %s); re-review" % (tag, ", ".join(diff)))
                continue
            if e.get("approval") == "approved" and e.get(SHA_FIELD) != cur:
                errors.append("%s: already approved with a different content hash; no silent re-approval" % tag)
                continue
            if e.get("approval") == "rejected":
                errors.append("%s: already rejected; identity is not reused (new proposal = new variant)" % tag)
                continue
        plan.append((e, d))
    return errors, plan


def apply_plan(plan, date):
    """Mutate entries in place; return list of (id, {field: (old, new)})."""
    changes = []
    for e, d in plan:
        before = {k: e.get(k) for k in ("approval", "approval_by", "approval_date", "user_note", SHA_FIELD)}
        note = (d.get("note") or "").strip()
        if d["decision"] != "hold":
            e["approval"] = d["decision"]
            e["approval_by"] = "user"
            e["approval_date"] = date
            e[SHA_FIELD] = content_hashes(e)
        if note:
            e["user_note"] = note
        after = {k: e.get(k) for k in before}
        diff = {k: (before[k], after[k]) for k in before if before[k] != after[k]}
        if diff:
            changes.append((e["id"], diff))
    return changes


def run(doc, catalog_path, root, write, out=sys.stdout):
    with open(catalog_path, "r", encoding="utf-8") as fh:
        catalog = json.load(fh)
    errors, plan = validate_input(doc, catalog.get("entries", []))
    if errors:
        for x in errors:
            print("REJECT " + x, file=out)
        print("nothing applied (%d error(s))" % len(errors), file=out)
        return 1
    date = doc["decided_at"][:10]
    changes = apply_plan(plan, date)
    manifest_path = os.path.join(root, bc.MANIFEST)
    manifest = None
    if os.path.isfile(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    verrs, _w = vc.validate(catalog, root, manifest)
    if verrs:
        for x in verrs[:10]:
            print("REJECT catalog invalid after apply: " + x, file=out)
        print("nothing applied (catalog would be invalid)", file=out)
        return 1
    for ident, diff in changes:
        print("%s %s" % ("WRITE" if write else "DRY  ", ident), file=out)
        for k, (old, new) in diff.items():
            if k == SHA_FIELD:
                print("    %s: %d hash(es)" % (k, len(new)), file=out)
            else:
                print("    %s: %r -> %r" % (k, old, new), file=out)
    if not changes:
        print("no changes", file=out)
    if write and changes:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(catalog_path)), suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(bc.dumps(catalog))
            os.replace(tmp, catalog_path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    print("%s: %d record(s) %s" % ("written" if write else "dry-run", len(changes),
                                   "changed" if write else "would change"), file=out)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", nargs="?", default="-")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--root", default=bc.ROOT)
    ap.add_argument("--catalog", default=None)
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    cpath = args.catalog or os.path.join(root, bc.CATALOG)
    try:
        if args.input == "-":
            text = sys.stdin.read()
        else:
            with open(args.input, "r", encoding="utf-8") as fh:
                text = fh.read()
        doc = json.loads(text)
    except (OSError, ValueError) as ex:
        print("REJECT cannot read decisions: %s" % ex)
        return 1
    return run(doc, cpath, root, args.write)


if __name__ == "__main__":
    sys.exit(main())
