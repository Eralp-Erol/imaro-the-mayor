#!/usr/bin/env python3
"""Validate data/library/catalog.json (T-052). Exit 0 = no errors (warnings allowed), 1 = errors.

Checks: schema/required fields, enums, duplicate ids, missing GLBs and generator files, manifest <-> catalog
consistency, catalog values vs fresh GLB measurements (drift), budgets from the manifest, and the approval
ownership rules (approved/rejected are user data: approval_by must be "user" and a date must exist).

Usage: python3 tools/library/validate_catalog.py [--root DIR] [--catalog PATH] [--manifest PATH] [-q]
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_catalog as bc  # noqa: E402
import hero_lods  # noqa: E402
import vegetation_catalog  # noqa: E402
import furniture_catalog  # noqa: E402
import human_catalog  # noqa: E402

ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
REQUIRED = ("id", "category", "family", "era", "tags", "glb", "dimensions_m", "triangles", "source",
            "approval", "approval_by", "approval_date", "user_note")
LODS = ("LOD0", "LOD1", "PROXY")


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def check_entry(e, cats, root, errors, warnings):
    ident = e.get("id", "<no id>")

    def err(msg):
        errors.append("%s: %s" % (ident, msg))

    for key in REQUIRED:
        if key not in e:
            err("missing field '%s'" % key)
    if "id" in e and not (isinstance(e["id"], str) and ID_RE.match(e["id"])):
        err("id must match %s" % ID_RE.pattern)
    if e.get("category") not in cats:
        err("unknown category %r" % e.get("category"))
    if not isinstance(e.get("tags", []), list):
        err("tags must be a list")
    appr = e.get("approval")
    if appr not in bc.APPROVAL_VALUES:
        err("approval %r not in %s" % (appr, "|".join(bc.APPROVAL_VALUES)))
    if not isinstance(e.get("user_note", ""), str):
        err("user_note must be a string")
    by = e.get("approval_by")
    date = e.get("approval_date")
    if date is not None and not (isinstance(date, str) and DATE_RE.match(date)):
        err("approval_date must be YYYY-MM-DD or null")
    if appr in ("approved", "rejected"):
        if by != "user":
            err("%s requires approval_by == 'user' (only the user writes approved/rejected)" % appr)
        if date is None:
            err("%s requires approval_date" % appr)
    elif by is not None:
        err("approval_by must be null unless approval is approved/rejected (got %r)" % by)
    if appr == "approved" and e.get("manifest_present") is False:
        warnings.append("%s: approved but no longer in the kit manifest" % ident)

    glb = e.get("glb")
    if glb is None:
        # Ground textures are PNG-only (no GLB by design), so they stay valid once the user approves/rejects them.
        if appr != "proposed" and (e.get("source") or {}).get("kind") != "texture":
            err("glb may only be null for 'proposed' entries")
    elif not isinstance(glb, str) or not glb.startswith("res://"):
        err("glb must be a res:// path")
    elif not os.path.isfile(os.path.join(root, bc.res_to_path(glb))):
        err("missing GLB file %s" % glb)

    dims = e.get("dimensions_m")
    if dims is not None:
        for key in ("width_x", "depth_z", "height_above_ground"):
            if not _num(dims.get(key)) or dims[key] <= 0:
                err("dimensions_m.%s must be a positive number" % key)
    elif glb is not None:
        err("dimensions_m missing for an entry with a GLB")
    tris = e.get("triangles")
    if isinstance(tris, dict):
        if tris.get("LOD0") is not None and not (isinstance(tris["LOD0"], int) and tris["LOD0"] > 0):
            err("triangles.LOD0 must be a positive integer")
        for lod in LODS:
            v = tris.get(lod)
            if v is not None and not isinstance(v, int):
                err("triangles.%s must be an integer or null" % lod)
    elif tris is not None:
        err("triangles must be an object")

    src = e.get("source")
    if isinstance(src, dict):
        handler = {"hero_vegetation": vegetation_catalog, "hero_furniture": furniture_catalog, "hero_human": human_catalog}.get(src.get("kind"), hero_lods)
        errors.extend(handler.validate_chain(e, root))
    else:
        err("source must be an object")
    if isinstance(src, dict):
        gen = src.get("generator")
        if src.get("kind") == "kit":
            if not gen or not os.path.isfile(os.path.join(root, gen)):
                err("source.generator missing on disk: %r" % gen)
        elif gen and not os.path.isfile(os.path.join(root, gen)) and appr != "proposed":
            err("source.generator missing on disk: %r" % gen)



def validate(catalog, root, manifest):
    """Return (errors, warnings)."""
    errors, warnings = [], []
    if catalog.get("catalog_version") != bc.CATALOG_VERSION:
        errors.append("catalog_version must be %d" % bc.CATALOG_VERSION)
    cats = set(c["id"] for c in catalog.get("categories", []))
    if not cats:
        errors.append("categories missing")
    entries = catalog.get("entries")
    if not isinstance(entries, list) or not entries:
        errors.append("entries missing or empty")
        return errors, warnings
    seen = {}
    for e in entries:
        ident = e.get("id")
        seen[ident] = seen.get(ident, 0) + 1
        check_entry(e, cats, root, errors, warnings)
    for ident, n in seen.items():
        if n > 1:
            errors.append("%s: duplicate id (%d times)" % (ident, n))

    if manifest is not None:
        budgets = manifest.get("budgets", {})
        by_id = {e.get("id"): e for e in entries}
        mod_ids = set()
        for m in manifest.get("modules", []):
            mod_ids.add(m["id"])
            e = by_id.get(m["id"])
            if e is None:
                errors.append("%s: in manifest but not in catalog (run build_catalog.py --write)" % m["id"])
                continue
            if e.get("manifest_present") is not True:
                errors.append("%s: manifest_present should be true" % m["id"])
            # Drift: catalog numbers must equal a fresh measurement of the GLB.
            dims, tris, digest, _mats, problems = bc.measure(m, root)
            for p in problems:
                errors.append("%s: %s" % (m["id"], p))
            if problems:
                continue
            if e.get("glb_sha256") != digest:
                errors.append("%s: glb_sha256 differs from file (catalog stale)" % m["id"])
            if e.get("triangles") != {lod: tris.get(lod) for lod in LODS}:
                errors.append("%s: triangles differ from GLB (catalog stale)" % m["id"])
            if e.get("dimensions_m") != dims:
                errors.append("%s: dimensions differ from GLB (catalog stale)" % m["id"])
            for lod, spec in m["lods"].items():
                if tris.get(lod) != spec.get("tris"):
                    errors.append("%s: manifest says %s=%s tris, GLB has %s" % (m["id"], lod, spec.get("tris"),
                                                                              tris.get(lod)))
            if tris.get("LOD0", 0) > budgets.get("max_lod0_tris", 10 ** 9):
                errors.append("%s: LOD0 %d tris over budget %d" % (m["id"], tris["LOD0"], budgets["max_lod0_tris"]))
            if "PROXY" in tris and tris["PROXY"] > budgets.get("proxy_max_tris", 10 ** 9):
                errors.append("%s: PROXY %d tris over budget %d" % (m["id"], tris["PROXY"],
                                                                    budgets["proxy_max_tris"]))
        for e in entries:
            if isinstance(e.get("source"), dict) and e["source"].get("kind") == "kit" and e.get("id") not in mod_ids:
                if e.get("approval") == "provisional-in-use":
                    errors.append("%s: provisional-in-use but no longer in the manifest" % e["id"])
                else:
                    warnings.append("%s: kit entry no longer in manifest (kept)" % e["id"])
    # GLBs shipped under assets/models that no catalog entry references (warning: library out of sync with assets).
    referenced = set(e.get("glb") for e in entries)
    models = os.path.join(root, "assets", "models")
    for dirpath, _dirs, files in os.walk(models):
        for fn in sorted(files):
            if fn.endswith(".glb"):
                res = "res://" + os.path.relpath(os.path.join(dirpath, fn), root).replace(os.sep, "/")
                if res not in referenced:
                    warnings.append("%s: GLB on disk is not in the catalog (is it missing from the kit manifest?)"
                                    % res)
    return errors, warnings


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=bc.ROOT)
    ap.add_argument("--catalog", default=None)
    ap.add_argument("--manifest", default=None)
    ap.add_argument("-q", action="store_true")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)
    cpath = args.catalog or os.path.join(root, bc.CATALOG)
    mpath = args.manifest or os.path.join(root, bc.MANIFEST)
    try:
        with open(cpath, "r", encoding="utf-8") as fh:
            catalog = json.load(fh)
    except (OSError, ValueError) as ex:
        print("catalog: cannot read %s: %s" % (cpath, ex))
        return 1
    manifest = None
    if os.path.isfile(mpath):
        with open(mpath, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    errors, warnings = validate(catalog, root, manifest)
    for w in warnings:
        print("WARN  " + w)
    for x in errors:
        print("ERROR " + x)
    if not args.q or errors:
        print("catalog: %d entries, %d errors, %d warnings" % (len(catalog.get("entries", [])), len(errors),
                                                               len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
