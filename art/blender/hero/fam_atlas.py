"""T-054 family atlases (Pillow+numpy, deterministic). python3 fam_atlas.py <outdir> [family]  -> <outdir>/<family>_<v>.png + <family>_layout.json
Reuses the T-053 helpers (hero_atlas.py): noise/fbm/roof_field/small_textures."""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_atlas as H  # noqa: E402
import fam_layout as FL  # noqa: E402
from hero_atlas import hexrgb, fbm, smooth, mix, to_img, noise  # noqa: E402

EXTRA_FLAT = ["wood", "glass_rail", "earth", "gravel", "hedge", "grass", "brickflat", "concrete", "pallet", "steel", "cont1f", "cont2f", "roofm", "parapet", "slab", "stonecap"]
EXTRA_TEX = {"glass_wide": (0, 944, 128, 64), "sheet": (128, 944, 128, 64), "clock": (256, 944, 64, 64), "cont_a": (320, 944, 96, 64),
             "cont_b": (416, 944, 96, 64), "brick": (512, 944, 64, 64), "roofmetal": (576, 944, 96, 64), "wall_wood": (672, 944, 64, 64)}
BASE_RECTS = dict(H.RECTS)


def rects_for(spec):
    r = {k: v for k, v in BASE_RECTS.items() if k not in ("front", "side")}
    r["roof"] = (0, 640, 512, 240)
    for i, n in enumerate(EXTRA_FLAT):
        r["f_" + n] = (i % 16 * 16, 912 + i // 16 * 16, 16, 16)
    r.update(EXTRA_TEX)
    x, y, w, _ = spec["rect_front"]
    r["front"] = (x, y, w, int(round(spec["H"] * w / spec["W"])))
    x, y, w, _ = spec["rect_side"]
    r["side"] = (x, y, w, int(round(spec["H"] * w / spec["D"])))
    return r


def wall_field2(wpx, hpx, wm, hm, v, rng, spec, holes, kind):
    ppx, ppy = wpx / wm, hpx / hm
    X = ((np.arange(wpx) + 0.5) / ppx)[None, :].repeat(hpx, 0)
    Z = (hm - (np.arange(hpx) + 0.5) / ppy)[:, None].repeat(wpx, 1)
    style = spec["style"]
    base, alt, trim, stone = hexrgb(v["wall"]), hexrgb(v["wall_alt"]), hexrgb(v["trim"]), hexrgb(v["stone"])
    img = np.ones((hpx, wpx, 3), np.float32) * base
    t = fbm(hpx, wpx, rng, 3, 5) - 0.5
    img *= (1 + 0.20 * t)[..., None]
    img = mix(img, alt, smooth(fbm(hpx, wpx, rng, 2, 3), 0.55, 0.68) * 0.35)
    img *= (1 - 0.14 * np.exp(-Z / 1.7))[..., None]
    img *= (1 - 0.10 * np.exp(-(hm - Z) / 0.7))[..., None]
    col = 0.4 + 1.2 * noise(1, wpx, 1, max(wpx // 3, 2), rng)[0][None, :]
    for h in holes:
        if h["kind"] in ("shop", "door", "gate", "dock"):
            continue
        reg = (X > h["x0"] - 0.06) & (X < h["x1"] + 0.06) & (Z < h["z0"])
        img *= (1 - 0.18 * reg * np.exp(-np.clip(h["z0"] - Z, 0, None) / 1.5) * col)[..., None]
    pm = smooth(fbm(hpx, wpx, rng, 6, 3), 0.60, 0.67) * np.exp(-Z / 6.0)
    img = mix(img, base * np.array([0.84, 0.79, 0.74], np.float32), pm * 0.6)
    bm_ = smooth(fbm(hpx, wpx, rng, 10, 3), 0.72, 0.76) * np.exp(-Z / 3.0)
    img = mix(img, np.array([0.60, 0.40, 0.32], np.float32), bm_ * 0.6)
    pl = spec["plinth"]
    if style == "industrial":
        bh = 2.4
        rows = np.floor(Z / 0.11).astype(int)
        bi = np.floor((X + (rows % 2) * 0.12) / 0.25).astype(int)
        tone = rng.normal(0, 0.07, (60, 160)).astype(np.float32)[rows % 60, bi % 160]
        brick = hexrgb(v["brick"])[None, None, :] * (1 + tone[..., None])
        mort = (((Z / 0.11) % 1.0) < 0.14) | ((((X + (rows % 2) * 0.12) / 0.25) % 1.0) < 0.07)
        brick = np.where(mort[..., None], brick * 0.7 + 0.12, brick)
        brick = brick * (1 - 0.15 * np.exp(-Z / 1.2))[..., None]
        img = np.where((Z < bh)[..., None], brick, img)
        rib = 0.94 + 0.06 * np.sin(X * 2 * np.pi / 0.2)
        img = np.where((Z >= bh)[..., None], img * rib[..., None], img)
        cap = (Z >= bh) & (Z < bh + 0.15)
        img = np.where(cap[..., None], stone * 1.05, img)
        for px_ in np.arange(0.0, wm + 0.1, 5.0 if wm < 20 else 6.0):
            pil = (np.abs(X - px_) < 0.35) | (X < 0.35) | (X > wm - 0.35)
            img = np.where((pil & (Z > bh))[..., None], brick * 0.95, img)
    else:
        if pl > 0:
            rows = np.floor(Z / 0.34).astype(int)
            off = (rows * 0.37) % 0.9
            bi = np.floor((X + off) / 0.9).astype(int)
            tone = rng.normal(0, 0.06, (40, 40)).astype(np.float32)[rows % 40, bi % 40]
            blk = stone[None, None, :] * (1 + tone[..., None]) * 0.96
            mort = ((((X + off) / 0.9) % 1.0) < 0.025) | (((Z / 0.34) % 1.0) < 0.07)
            blk = np.where(mort[..., None], blk * 0.72, blk)
            img = np.where((Z < pl)[..., None], blk, img)
            img = np.where(((Z > pl) & (Z < pl + 0.08))[..., None], stone * 0.82, img)
        if spec["quoins"]:
            qrow = np.floor((Z - pl - 0.1) / 0.5).astype(int)
            qw = np.where(qrow % 2 == 0, 0.52, 0.34)
            qz = ((Z - pl - 0.1) / 0.5) % 1.0
            for edge in ("l", "r"):
                d = X if edge == "l" else wm - X
                q = (d < qw) & (Z > pl + 0.1)
                img = np.where(q[..., None], stone * 1.07 * (1 + 0.04 * np.sin(qrow * 2.3))[..., None], img)
                img = np.where(((np.abs(d - qw) < 0.018) & (Z > pl + 0.1))[..., None], img * 0.78, img)
                img = np.where(((qz < 0.06) & q)[..., None], img * 0.82, img)
    for h in holes:
        a, b, z0, z1 = h["x0"], h["x1"], h["z0"], h["z1"]
        k = h["kind"]
        if k in ("win", "door_win", "wide"):
            e = 0.15 if style != "modern" else 0.08
            reg = (X > a - e) & (X < b + e) & (Z > z0 - 0.02) & (Z < z1 + e + 0.04)
            tc = trim if style != "modern" else stone * 1.05
            img = np.where(reg[..., None], img * 0.12 + tc * 0.88, img)
            out = reg & ~((X > a - e + 0.02) & (X < b + e - 0.02) & (Z > z0 - 0.02) & (Z < z1 + e + 0.02))
            img = np.where(out[..., None], img * 0.84, img)
        elif k in ("shop", "door", "gate", "dock"):
            e = 0.20
            reg = (X > a - e) & (X < b + e) & (Z > max(z0, 0)) & (Z < z1 + e)
            img = np.where(reg[..., None], stone * 1.05, img)
            out = reg & ~((X > a - e + 0.025) & (X < b + e - 0.025) & (Z < z1 + e - 0.025))
            img = np.where(out[..., None], img * 0.80, img)
    for (sx0, sx1, sz0, sz1) in (spec.get("signs", []) if kind == "front" else []):
        sx0, sx1 = sx0 + wm / 2, sx1 + wm / 2
        sreg = (X > sx0) & (X < sx1) & (Z > sz0) & (Z < sz1)
        img = np.where(sreg[..., None], hexrgb(v["sign"]), img)
        bd = sreg & ~((X > sx0 + 0.05) & (X < sx1 - 0.05) & (Z > sz0 + 0.05) & (Z < sz1 - 0.05))
        img = np.where(bd[..., None], trim * 0.92, img)
    if style == "plaster":
        for zc in spec["courses"]:
            band = (Z > zc - 0.10) & (Z < zc + 0.10)
            img = np.where(band[..., None], trim * 0.9, img)
            sh = (Z > zc - 0.19) & (Z <= zc - 0.10)
            img = np.where(sh[..., None], img * 0.86, img)
        if spec["dentils"]:
            img = np.where((Z > hm - 0.56)[..., None], trim * 0.93, img)
            dent = (Z > hm - 0.46) & (Z < hm - 0.30) & ((X % 0.2) < 0.10)
            img = np.where(dent[..., None], trim * 0.62, img)
    if style == "modern":
        for k in range(spec["NF"] + 1):
            zc = spec["GF"] + k * spec["FL"]
            band = (Z > zc - 0.18) & (Z < zc + 0.05)
            img = np.where(band[..., None], img * 0.90, img)
        fin = (np.abs(((X + 0.0) % 2.8) - 1.4) > 1.25) & (Z > spec["GF"])
        img = np.where(fin[..., None], img * 0.92, img)
    for h in holes:
        reg = (X > h["x0"]) & (X < h["x1"]) & (Z > h["z0"]) & (Z < h["z1"])
        img = np.where(reg[..., None], np.array([0.16, 0.18, 0.20], np.float32), img)
        mull = reg & ((np.abs(X - (h["x0"] + h["x1"]) / 2) < 0.03) | (np.abs(Z - (h["z0"] + h["z1"]) * 0.5) < 0.03))
        img = np.where(mull[..., None], trim * 0.9, img)
    img = img * (1 + 0.035 * (rng.random((hpx, wpx)) - 0.5))[..., None]
    return img


def extras(v, rng, canvas, rects):
    d = ImageDraw.Draw(canvas)
    sw = dict(wood=v["wood"], glass_rail="#9AA19A", earth="#8A7258", gravel="#A59C8C", hedge="#5E6F4C", grass="#7A8A56", brickflat=v.get("brick", "#9C6850"),
              concrete="#A8A399", pallet="#9A7B52", steel="#4A5056", cont1f=v.get("cont1", "#6F8579"), cont2f=v.get("cont2", "#9A6A4C"),
              roofm=v["roof"], parapet=v["wall_alt"], slab=v["trim"], stonecap=v["stone"])
    for n in EXTRA_FLAT:
        x, y, w, h = rects["f_" + n]
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=tuple(int(c * 255) for c in hexrgb(sw[n])))

    def ribs(name, colhex, period, dark=0.75):
        x, y, w, h = rects[name]
        X = np.arange(w)[None, :].repeat(h, 0)
        c = hexrgb(colhex)[None, None, :] * (1 + 0.1 * (fbm(h, w, rng, 3, 3) - 0.5))[..., None]
        ph = (X % period) / period
        c = c * (dark + (1 - dark) * (0.5 + 0.5 * np.sin(ph * 2 * np.pi)))[..., None]
        rust = smooth(fbm(h, w, rng, 4, 3), 0.62, 0.72)
        c = mix(c.astype(np.float32), hexrgb("#8A5E43"), rust * 0.25)
        canvas.paste(to_img(c), (x, y))
    ribs("sheet", v["wall_alt"], 8)
    ribs("roofmetal", v["roof"], 8, 0.7)
    ribs("cont_a", v.get("cont1", "#6F8579"), 6, 0.7)
    ribs("cont_b", v.get("cont2", "#9A6A4C"), 6, 0.7)
    x, y, w, h = rects["glass_wide"]
    gy = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    gl = np.stack([0.19 + 0.13 * (1 - gy), 0.21 + 0.13 * (1 - gy), 0.23 + 0.13 * (1 - gy)], -1).astype(np.float32)
    X = np.arange(w)[None, :].repeat(h, 0)
    Y = np.arange(h)[:, None].repeat(w, 1)
    gl = mix(gl, np.array([0.80, 0.76, 0.66], np.float32), ((X > w * 0.55) & (X < w * 0.8) & (Y < h * 0.7)) * 0.4)
    sash = (X < 3) | (X > w - 4) | (Y < 3) | (Y > h - 4) | (np.abs(X - w // 3) < 2) | (np.abs(X - 2 * w // 3) < 2)
    gl = np.where(sash[..., None], hexrgb("#D6D0C0"), gl)
    canvas.paste(to_img(gl), (x, y))
    x, y, w, h = rects["brick"]
    Y = np.arange(h)[:, None].repeat(w, 1)
    X = np.arange(w)[None, :].repeat(h, 0)
    rows = Y // 6
    bi = (X + (rows % 2) * 6) // 12
    tone = rng.normal(0, 0.07, (20, 20)).astype(np.float32)[rows % 20, bi % 20]
    b = hexrgb(v.get("brick", "#9C6850"))[None, None, :] * (1 + tone[..., None])
    m = ((Y % 6) < 1) | (((X + (rows % 2) * 6) % 12) < 1)
    canvas.paste(to_img(np.where(m[..., None], b * 0.7 + 0.12, b)), (x, y))
    x, y, w, h = rects["clock"]
    im = Image.new("RGB", (w, h), tuple(int(c * 255) for c in hexrgb(v["stone"])))
    dd = ImageDraw.Draw(im)
    dd.ellipse([4, 4, w - 5, h - 5], fill=(78, 70, 60))
    dd.ellipse([8, 8, w - 9, h - 9], fill=(232, 224, 205))
    for k in range(12):
        a = k * math.pi / 6
        r0, r1 = (w / 2 - 12), (w / 2 - 8)
        dd.line([w / 2 + r0 * math.sin(a), h / 2 - r0 * math.cos(a), w / 2 + r1 * math.sin(a), h / 2 - r1 * math.cos(a)], fill=(60, 52, 44), width=2)
    dd.line([w / 2, h / 2, w / 2 + 12 * math.sin(2.1), h / 2 - 12 * math.cos(2.1)], fill=(40, 34, 30), width=3)
    dd.line([w / 2, h / 2, w / 2 + 18 * math.sin(0.5), h / 2 - 18 * math.cos(0.5)], fill=(40, 34, 30), width=2)
    canvas.paste(im, (x, y))
    x, y, w, h = rects["wall_wood"]
    X = np.arange(w)[None, :].repeat(h, 0)
    wc = hexrgb(v["wood"])[None, None, :] * (1 + 0.12 * (fbm(h, w, rng, 6, 3) - 0.5))[..., None]
    wc = wc * np.where(((X % 8) < 1)[..., None], 0.7, 1.0)
    canvas.paste(to_img(wc.astype(np.float32)), (x, y))


def build(key, vk):
    spec = FL.FAMILIES[key]()
    v = FL.VARIANTS[key][vk]
    rng = np.random.default_rng(v["seed"])
    rects = rects_for(spec)
    H.RECTS = rects
    canvas = Image.new("RGB", (1024, 1024), (128, 128, 128))
    v2 = dict(v)
    for k_ in ("awn1", "awn2", "door", "shutter", "trim", "stone", "wall", "wall_alt", "roof", "sign"):
        v2.setdefault(k_, "#888888")
    H.small_textures(v2, rng, canvas)
    x, y, w, h = rects["front"]
    holes_f = [dict(hh, x0=hh["x0"] + spec["W"] / 2, x1=hh["x1"] + spec["W"] / 2) for hh in spec["holes"]]
    canvas.paste(to_img(wall_field2(w, h, spec["W"], spec["H"], v, rng, spec, holes_f, "front")), (x, y))
    x, y, w, h = rects["side"]
    canvas.paste(to_img(wall_field2(w, h, spec["D"], spec["H"], v, rng, spec, spec["side"], "side")), (x, y))
    x, y, w, h = rects["roof"]
    canvas.paste(to_img(H.roof_field(w, h, v, rng)), (x, y))
    extras(v, rng, canvas, rects)
    return canvas, rects


def main():
    out = sys.argv[1]
    only = sys.argv[2] if len(sys.argv) > 2 else None
    os.makedirs(out, exist_ok=True)
    for key in FL.FAMILIES:
        if only and key != only:
            continue
        rects = None
        for vk in FL.VARIANTS[key]:
            im, rects = build(key, vk)
            im.save(os.path.join(out, f"{key}_{vk}.png"), optimize=True)
        json.dump(dict(size=1024, rects=rects), open(os.path.join(out, f"{key}_layout.json"), "w"), indent=1, sort_keys=True)
        print("atlas", key)


if __name__ == "__main__":
    main()
