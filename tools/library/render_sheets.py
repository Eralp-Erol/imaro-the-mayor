#!/usr/bin/env python3
"""Library contact sheets (T-052): catalog.json -> design/library/sheets/<category>-NN.png (+ index.json).

Pipeline: (1) pick assets per category from the catalog, (2) render 4 views per asset with Blender headless
(tools/library/blender_render_views.py, real game palette, fixed sun, 1.75 m human reference), cached in
artifacts/library/views/, (3) compose labelled pages with Pillow.

Needs: Blender 4.5 (env BLENDER or /Applications/Blender.app) and Pillow (python3 -m pip install pillow).
Usage: python3 tools/library/render_sheets.py [--category building ...] [--force] [--rows 6] [--size 288]
"""
import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CATALOG = os.path.join(ROOT, "data", "library", "catalog.json")
PALETTE = os.path.join(ROOT, "assets", "kit", "kit_palette.json")
HUMAN_GLB = os.path.join(ROOT, "assets", "models", "props", "prop_human.glb")
SHEETS = os.path.join(ROOT, "design", "library", "sheets")
CACHE = os.path.join(ROOT, "artifacts", "library", "views")
WORKER = os.path.join(HERE, "blender_render_views.py")
VIEWS = ("front", "fr34", "rl34", "top", "scale")
VIEW_TITLES = {"front": "ön görünüş", "fr34": "3/4 ön-sağ", "rl34": "3/4 arka-sol", "top": "tepeden (ön = aşağı)",
               "scale": "ölçek: kare 7 m, insan 1,75 m"}
TIERS = (14, 18, 24, 30, 36, 44, 52, 64, 80, 96, 128)
BG = (139, 144, 148)  # == BG_SRGB in the Blender worker (0.545, 0.565, 0.58)
PAGE_BG = (38, 40, 43)
INK = (232, 232, 228)
DIM = (160, 163, 166)
WARN = (232, 168, 84)

# Pages are grouped by family so neighbours are comparable (and share a scale). Unknown families go last.
GROUPS = {
    "building": [("res_old", "res_old_town"), ("res_mid",), ("res_late", "res_house"),
                 ("ind_shed", "ind_heritage", "ind_vault", "ind_depot", "ind_yard"), ("civ_hall", "lmk_clocktower")],
}
CATEGORY_TITLES = {"building": "Bina", "roof_equipment": "Çatı / ekipman", "vegetation": "Bitki",
                   "vehicle": "Araç", "human": "İnsan", "road_section": "Yol kesiti", "ground": "Zemin / kent dokusu",
                   "street_furniture": "Sokak donatısı", "marking": "İşaret / çizgi"}
FONT_DIRS = ["/System/Library/Fonts/Supplemental", "/Library/Fonts", "/usr/share/fonts/truetype/dejavu"]


def find_font(names, size):
    from PIL import ImageFont
    for d in FONT_DIRS:
        for n in names:
            p = os.path.join(d, n)
            if os.path.isfile(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def blender_exe():
    exe = os.environ.get("BLENDER") or "/Applications/Blender.app/Contents/MacOS/Blender"
    if not os.path.isfile(exe):
        sys.exit("render_sheets: Blender not found (%s); set BLENDER=/path/to/Blender" % exe)
    return exe


def tier_for(entry):
    d = entry["dimensions_m"]
    w, dd, h = d["width_x"] + 3.0, d["depth_z"] + 3.0, d["height_above_ground"]
    # extents of the 4 camera setups (front 14 deg, 3/4 at 38 deg az / 30 deg pitch, top); human included via +3 m
    a = math.radians(38.0)
    horiz = w * math.cos(a) + dd * math.sin(a)
    vert = h * math.cos(math.radians(30.0)) + (w * math.sin(a) + dd * math.cos(a)) * 0.5
    need = max(w, dd, h * 1.05 + dd * 0.25, horiz, vert) * 1.14
    for t in TIERS:
        if need <= t:
            return t
    return TIERS[-1]


def rows_of(entry):
    pr = entry.get("palette_rows", {})

    def first(key, default):
        v = pr.get(key) or [default]
        return v[0]
    return {"wall": first("wall_rows", "W1"), "roof": first("roof_rows", "R1"), "accent": first("accent_rows", "A1")}


def pages_for(category, entries, per_page):
    """Return [(title_suffix, [entries])] pages; groups by family, chunked by per_page."""
    groups = GROUPS.get(category, [])
    used = set()
    pages = []
    for fams in groups:
        sel = [e for e in entries if e.get("family") in fams]
        used.update(id(e) for e in sel)
        for i in range(0, len(sel), per_page):
            chunk = sel[i:i + per_page]
            if chunk:
                pages.append((", ".join(sorted(set(e["family"] for e in chunk))), chunk))
    rest = [e for e in entries if id(e) not in used]
    for i in range(0, len(rest), per_page):
        chunk = rest[i:i + per_page]
        pages.append((", ".join(sorted(set(e["family"] for e in chunk))), chunk))
    return pages


def cache_key(entry, tier, size):
    h = hashlib.sha256()
    with open(WORKER, "rb") as fh:
        h.update(fh.read())
    h.update(json.dumps([entry.get("glb_sha256"), rows_of(entry), tier, size], sort_keys=True).encode())
    with open(HUMAN_GLB, "rb") as fh:
        h.update(fh.read())
    with open(PALETTE, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()[:16]


def render_views(jobs, size, force):
    """jobs: [(entry, tier)]. Renders missing/stale ones in a single Blender session."""
    os.makedirs(CACHE, exist_ok=True)
    todo = []
    for entry, tier in jobs:
        key = cache_key(entry, tier, size)
        meta = os.path.join(CACHE, entry["id"] + ".meta")
        ok = (not force and os.path.isfile(meta) and open(meta).read().strip() == key
              and all(os.path.isfile(os.path.join(CACHE, "%s__%s.png" % (entry["id"], v))) for v in VIEWS))
        if not ok:
            todo.append((entry, tier, key))
    if not todo:
        print("views: all %d cached" % len(jobs))
        return
    job = {"palette": PALETTE, "human_glb": HUMAN_GLB, "out_dir": CACHE, "size": size, "assets": [
        {"id": e["id"], "glb": os.path.join(ROOT, e["glb"][len("res://"):]), "rows": rows_of(e), "tier_m": t,
         "views": list(VIEWS)} for e, t, _k in todo]}
    with tempfile.TemporaryDirectory() as tmp:
        jp = os.path.join(tmp, "job.json")
        with open(jp, "w") as fh:
            json.dump(job, fh)
        print("views: rendering %d of %d with Blender" % (len(todo), len(jobs)))
        cmd = [blender_exe(), "--background", "--factory-startup", "--python", WORKER, "--", "--job", jp]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        if res.returncode != 0 or res.stdout.count("rendered ") != len(todo):
            sys.stderr.write(res.stdout[-3000:])
            sys.exit("render_sheets: Blender render failed (rc=%s)" % res.returncode)
    for e, _t, key in todo:
        with open(os.path.join(CACHE, e["id"] + ".meta"), "w") as fh:
            fh.write(key + "\n")


def compose_page(category, suffix, entries, tier, page_no, page_total, size):
    from PIL import Image, ImageDraw
    f_title = find_font(["Arial Bold.ttf", "DejaVuSans-Bold.ttf"], 26)
    f_id = find_font(["Arial Bold.ttf", "DejaVuSans-Bold.ttf"], 21)
    f_txt = find_font(["Arial.ttf", "DejaVuSans.ttf"], 16)
    f_small = find_font(["Arial.ttf", "DejaVuSans.ttf"], 14)
    label_w = 330
    head_h = 96
    col_h = 28
    pad = 6
    w = label_w + len(VIEWS) * (size + pad) + pad
    h = head_h + col_h + len(entries) * (size + pad) + pad + 30
    img = Image.new("RGB", (w, h), PAGE_BG)
    dr = ImageDraw.Draw(img)
    dr.text((14, 10), "İmaro kütüphanesi · %s · sayfa %02d/%02d" % (CATEGORY_TITLES.get(category, category), page_no,
                                                                   page_total), font=f_title, fill=INK)
    dr.text((14, 46), "aileler: %s" % suffix, font=f_txt, fill=DIM)
    dr.text((14, 68), "ÖLÇEK: her görselin kenarı = %d m (bu sayfada hepsi aynı) · yanındaki figür = 1,75 m insan · "
            "renkler = gerçek oyun paleti" % tier, font=f_txt, fill=WARN)
    for i, v in enumerate(VIEWS):
        dr.text((label_w + i * (size + pad) + 8, head_h + 4), VIEW_TITLES[v], font=f_txt, fill=INK)
    y = head_h + col_h
    for e in entries:
        dr.rectangle([0, y - 2, w, y + size + 2], fill=(46, 48, 52))
        d = e["dimensions_m"]
        t = e["triangles"] or {}
        tri = "üçgen LOD0 %s · LOD1 %s · PROXY %s" % (t.get("LOD0", "-"), t.get("LOD1") or "-", t.get("PROXY") or "-")
        lines = [(e["id"], f_id, INK),
                 (" · ".join([e.get("family", ""), e.get("era", "")] + [x for x in e.get("tags", [])
                                if x.startswith("roof:") or x in ("ground-floor-shop", "landmark")]), f_txt, DIM),
                 ("gen. %.1f × der. %.1f m, yük. %.1f m" % (d["width_x"], d["depth_z"], d["height_above_ground"]), f_txt,
                  INK),
                 (tri, f_txt, INK),
                 ("onay: %s" % e["approval"], f_txt, WARN if e["approval"] == "provisional-in-use" else INK),
                 ("(onaylı DEĞİL — geçici kullanımda)" if e["approval"] == "provisional-in-use" else "", f_small,
                  WARN)]
        ty = y + 10
        for text, font, color in lines:
            if text:
                dr.text((12, ty), text, font=font, fill=color)
            ty += 30 if font is f_id else 24
        if e.get("user_note"):
            dr.text((12, ty + 4), "not: " + e["user_note"][:40], font=f_small, fill=INK)
        for i, v in enumerate(VIEWS):
            cell = Image.open(os.path.join(CACHE, "%s__%s.png" % (e["id"], v))).convert("RGB")
            x0 = label_w + i * (size + pad)
            img.paste(cell, (x0, y))
            if v == "top":  # 10 m scale bar on the plan view
                px = size / float(tier)
                bx, by = x0 + 10, y + size - 16
                dr.rectangle([bx, by, bx + 10 * px, by + 5], fill=(30, 30, 30))
                dr.text((bx + 10 * px + 6, by - 8), "10 m", font=f_small, fill=(30, 30, 30))
        y += size + pad
    dr.text((14, h - 26), "Üretim: tools/library/render_sheets.sh · kaynak: data/library/catalog.json · "
            "renk = kit paletinin ilk satırları (örnek renk yolu); oyunda örnek başına değişir", font=f_small,
            fill=DIM)
    return img


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--category", action="append", help="category id (default: all with entries)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--rows", type=int, default=6)
    ap.add_argument("--size", type=int, default=288)
    args = ap.parse_args(argv)
    try:
        import PIL  # noqa: F401
    except ImportError:
        sys.exit("render_sheets: Pillow missing (python3 -m pip install pillow)")
    with open(CATALOG, "r", encoding="utf-8") as fh:
        catalog = json.load(fh)
    cats = args.category or [c["id"] for c in catalog["categories"]]
    plan = []
    for cat in cats:
        entries = [e for e in catalog["entries"] if e["category"] == cat and e.get("glb") and e.get("dimensions_m")
                   and e.get("manifest_present", True)]
        if not entries:
            continue
        pages = pages_for(cat, entries, args.rows)
        plan.append((cat, pages))
    jobs = []
    page_tier = {}
    for cat, pages in plan:
        for n, (_suffix, chunk) in enumerate(pages, 1):
            tier = max(tier_for(e) for e in chunk)
            page_tier[(cat, n)] = tier
            jobs.extend((e, tier) for e in chunk)
    render_views(jobs, args.size, args.force)
    os.makedirs(SHEETS, exist_ok=True)
    index_path = os.path.join(SHEETS, "index.json")
    index = {}
    if os.path.isfile(index_path):
        with open(index_path, "r", encoding="utf-8") as fh:
            index = json.load(fh)
    written = []
    for cat, pages in plan:
        for name in os.listdir(SHEETS):  # drop stale pages of this category
            if name.startswith(cat + "-") and name.endswith(".png"):
                os.remove(os.path.join(SHEETS, name))
        for k in [k for k, v in index.items() if v["sheet"].startswith(cat + "-")]:
            del index[k]
        for n, (suffix, chunk) in enumerate(pages, 1):
            img = compose_page(cat, suffix, chunk, page_tier[(cat, n)], n, len(pages), args.size)
            fn = "%s-%02d.png" % (cat, n)
            img.save(os.path.join(SHEETS, fn))
            written.append(fn)
            for row, e in enumerate(chunk, 1):
                index[e["id"]] = {"sheet": fn, "row": row, "scale_m_per_image": page_tier[(cat, n)]}
    with open(index_path, "w", encoding="utf-8") as fh:
        json.dump(dict(sorted(index.items())), fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("sheets: " + ", ".join(written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
