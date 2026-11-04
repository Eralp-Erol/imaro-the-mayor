"""T-055 zemin kontak sayfasi (doku basina etiketli, 1 m ve 10 m olcek cubuklu). Pillow+numpy.
Kullanim: python3 art/blender/ground/ground_sheet.py [--tex assets/ground/tex] [--out design/library/sheets]
Her satir: sol = 4 m x 4 m yakin gorunum (1 m cubuk), sag = 16 m x 16 m uzak gorunum (10 m cubuk; tile'in tekrar ettigi gorunur).
Not: bu sayfa DOKU kontagidir (duz); oyun/lab render karesi icin design/specs/art/ground/ altindaki yan yana kiyaslara bakin.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

PANEL = 360


def font(sz):
    for p in ("/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default(sz)


def view(img, tile_m, span_m):
    """span_m x span_m bolgeyi PANEL piksele cizer (tile'i tekrarlar)."""
    n = img.shape[0]
    reps = int(np.ceil(span_m / tile_m))
    big = np.tile(img, (reps, reps, 1))
    px = int(round(span_m / tile_m * n))
    crop = big[:px, :px]
    return Image.fromarray(crop).resize((PANEL, PANEL), Image.LANCZOS if px > PANEL else Image.BICUBIC)


def bar(d, x, y, meters, span_m, label, f):
    L = int(round(meters / span_m * PANEL))
    d.rectangle([x, y, x + L, y + 7], fill=(250, 250, 245), outline=(20, 20, 20))
    d.rectangle([x, y, x + L // 2, y + 7], fill=(20, 20, 20))
    d.text((x + L + 6, y - 5), label, fill=(250, 250, 245), font=f, stroke_width=2, stroke_fill=(20, 20, 20))


def main():
    a = sys.argv[1:]
    tex = a[a.index("--tex") + 1] if "--tex" in a else "assets/ground/tex"
    out = a[a.index("--out") + 1] if "--out" in a else "design/library/sheets"
    meta = json.load(open(os.path.join(tex, "ground_layers.json")))
    layers = meta["layers"]
    f, fs = font(17), font(13)
    cols = 2
    rows = (len(layers) + cols - 1) // cols
    cw, ch = PANEL * 2 + 30, PANEL + 52
    sheet = Image.new("RGB", (cols * cw + 20, rows * ch + 60), (166, 169, 170))
    d = ImageDraw.Draw(sheet)
    d.text((20, 14), "T-055 zemin doku seti | 512 px tile | sol 4 m x 4 m, sag 16 m x 16 m | unlit duz gosterim (oyun isigi degil)", fill=(20, 20, 20), font=f)
    for i, L in enumerate(layers):
        img = np.asarray(Image.open(os.path.join(tex, L["file"])).convert("RGB"))
        cx, cy = 20 + (i % cols) * cw, 50 + (i // cols) * ch
        sheet.paste(view(img, L["tile_m"], 4.0), (cx, cy + 26))
        sheet.paste(view(img, L["tile_m"], 16.0), (cx + PANEL + 8, cy + 26))
        d2 = ImageDraw.Draw(sheet)
        h = L["hsv"]
        d2.text((cx, cy + 2), "%s  [%s %s]  tile=%.0f m  v=%.2f s=%.2f h=%.0f" % (L["id"], L["palette_zone"], L["palette_ref"], L["tile_m"], h["v_mean"], h["s_mean"], h["h_mean_deg"]), fill=(20, 20, 20), font=fs)
        bar(d2, cx + 10, cy + 26 + PANEL - 20, 1.0, 4.0, "1 m", fs)
        bar(d2, cx + PANEL + 18, cy + 26 + PANEL - 20, 10.0, 16.0, "10 m", fs)
    os.makedirs(out, exist_ok=True)
    p = os.path.join(out, "ground-textures.png")
    sheet.save(p)
    print(p, sheet.size)


if __name__ == "__main__":
    main()
