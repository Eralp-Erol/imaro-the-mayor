"""T-053 hero building facade atlas (procedural, deterministic, Pillow+numpy). 1024x1024 sRGB PNG per variant.

Usage: python3 hero_atlas.py <outdir>      -> hero_atlas_{a,b,c}.png + hero_atlas_layout.json
Rect layout (px, top-left origin) is shared with hero_building.py through the JSON.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_layout as L  # noqa: E402

S = 1024
RECTS = {
    "front": (0, 0, 480, 640),
    "side": (480, 0, 448, 512),
    "roof": (0, 640, 512, 240),
    "shutter": (512, 640, 64, 144),
    "glass_win": (576, 640, 80, 144),
    "glass_shop": (656, 640, 128, 128),
    "kepenk": (784, 640, 128, 128),
    "awning": (912, 640, 96, 64),
    "door": (912, 704, 64, 128),
}
FLAT = ["frame", "jamb", "wood_dark", "metal", "chimney", "soffit", "trim", "cornice", "stone", "dark", "balcony_top",
        "rail", "wall", "wall_dark", "tile", "ridge", "fascia", "sill", "panel", "tank", "ac", "awn_side", "step", "white"]
for i, n in enumerate(FLAT):
    RECTS["f_" + n] = (0 + (i % 16) * 16, 880 + (i // 16) * 16, 16, 16)


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


def noise(h, w, ch, cw, rng):
    a = rng.random((max(ch, 2), max(cw, 2))).astype(np.float32)
    im = Image.fromarray((a * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255.0


def fbm(h, w, rng, base=3, octs=5):
    acc = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octs):
        acc += amp * noise(h, w, base * 2 ** o, int(base * 2 ** o * w / h) + 1, rng)
        tot += amp
        amp *= 0.55
    return acc / tot  # ~0.5 centred


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def mix(img, col, m):
    return img * (1 - m[..., None]) + np.asarray(col, np.float32) * m[..., None]


def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))


def wall_field(wpx, hpx, wm, hm, v, rng, holes, kind):
    ppx, ppy = wpx / wm, hpx / hm
    X = ((np.arange(wpx) + 0.5) / ppx)[None, :].repeat(hpx, 0)
    Z = (hm - (np.arange(hpx) + 0.5) / ppy)[:, None].repeat(wpx, 1)
    base, alt, trim, stone = hexrgb(v["wall"]), hexrgb(v["wall_alt"]), hexrgb(v["trim"]), hexrgb(v["stone"])
    img = np.ones((hpx, wpx, 3), np.float32) * np.minimum(base * 1.02 + 0.005, 1.0) * np.array([1.0, 0.995, 1.0], np.float32)
    t = fbm(hpx, wpx, rng, 3, 5) - 0.5
    img *= (1 + 0.20 * t)[..., None]
    m = smooth(fbm(hpx, wpx, rng, 2, 3), 0.55, 0.68) * 0.35          # repainted patches
    img = mix(img, alt, m)
    img *= (1 - 0.14 * np.exp(-Z / 1.7))[..., None]                  # ground splash / damp
    img *= (1 - 0.12 * np.exp(-(hm - Z) / 0.7))[..., None]           # dirt under cornice
    # rain streaks under sills
    col = noise(1, wpx, 1, max(wpx // 3, 2), rng)[0]
    col = 0.4 + 1.2 * col[None, :]
    for h in holes:
        if h["kind"] in ("shop", "door"):
            continue
        a, b = h["x0"], h["x1"]
        reg = (X > a - 0.06) & (X < b + 0.06) & (Z < h["z0"])
        fade = np.exp(-np.clip(h["z0"] - Z, 0, None) / 1.5)
        img *= (1 - 0.18 * reg * fade * col)[..., None]
    # peeling / damp patches that expose darker undercoat
    pm = smooth(fbm(hpx, wpx, rng, 6, 3), 0.60, 0.67) * np.exp(-Z / 6.0)
    img = mix(img, base * np.array([0.80, 0.74, 0.68], np.float32), pm * 0.8)
    bm_ = smooth(fbm(hpx, wpx, rng, 8, 3), 0.69, 0.73) * np.exp(-Z / 3.5) * (1 - 0.0 * Z)
    img = mix(img, np.array([0.60, 0.40, 0.32], np.float32) * (0.9 + 0.2 * t[..., None] * 2), bm_ * 0.85)   # exposed brick under flaked plaster
    # stone plinth
    rows = np.floor(Z / 0.34).astype(int)
    off = (rows * 0.37) % 0.9
    bi = np.floor((X + off) / 0.9).astype(int)
    tone = rng.normal(0, 0.06, (40, 40)).astype(np.float32)[rows % 40, bi % 40]
    plinth = Z < 0.72
    blk = stone[None, None, :] * (1 + tone[..., None]) * 0.96
    fr = ((X + off) / 0.9) % 1.0
    fz_ = (Z / 0.34) % 1.0
    mortar = (fr < 0.025) | (fz_ < 0.07)
    blk = np.where(mortar[..., None], blk * 0.72, blk)
    img = np.where(plinth[..., None], blk, img)
    if kind == "front":
        img = np.where(((Z > 0.72) & (Z < 0.80))[..., None], stone * 0.82, img)  # plinth cap
    # corner quoins
    qrow = np.floor((Z - 0.8) / 0.5).astype(int)
    qw = np.where(qrow % 2 == 0, 0.52, 0.34)
    qz = ((Z - 0.8) / 0.5) % 1.0
    for edge in ("l", "r") if kind == "front" else ("l", "r"):
        d = X if edge == "l" else wm - X
        q = (d < qw) & (Z > 0.8)
        qt = stone * 1.07 * (1 + 0.04 * rng.normal(0, 1, (40,))[qrow % 40])[:, :, None] if False else stone * 1.07
        img = np.where(q[..., None], qt * (1 + 0.04 * np.sin(qrow * 2.3))[..., None], img)
        edge_line = (np.abs(d - qw) < 0.018) & (Z > 0.8)
        img = np.where(edge_line[..., None], img * 0.78, img)
        hl = (qz < 0.06) & q
        img = np.where(hl[..., None], img * 0.82, img)
    # window / door surrounds (architrave)
    for h in holes:
        a, b, z0, z1 = h["x0"], h["x1"], h["z0"], h["z1"]
        if h["kind"] == "win" or h["kind"] == "door_win":
            e = 0.15
            reg = (X > a - e) & (X < b + e) & (Z > z0 - 0.02) & (Z < z1 + e + 0.04)
            img = np.where(reg[..., None], img * 0.12 + trim * 0.88 * (1 + 0.02 * np.sin(X * 40)[..., None]), img)
            out = reg & ~((X > a - e + 0.02) & (X < b + e - 0.02) & (Z > z0 - 0.02) & (Z < z1 + e + 0.02))
            img = np.where(out[..., None], img * 0.84, img)
        elif h["kind"] in ("shop", "door"):
            e = 0.20 if h["kind"] == "shop" else 0.17
            reg = (X > a - e) & (X < b + e) & (Z > z0 - 0.0) & (Z < z1 + e)
            img = np.where(reg[..., None], stone * 1.05, img)
            out = reg & ~((X > a - e + 0.025) & (X < b + e - 0.025) & (Z < z1 + e - 0.025))
            img = np.where(out[..., None], img * 0.80, img)
    # shop riser panel under glass + signboards
    if kind == "front":
        for h in holes:
            if h["kind"] == "shop":
                reg = (X > h["x0"] - 0.2) & (X < h["x1"] + 0.2) & (Z > 0.72) & (Z < h["z0"])
                img = np.where(reg[..., None], stone * 0.90, img)
                # signboard (blank: no marks, per VIS-07)
                sx0, sx1, sz0, sz1 = h["x0"] - 0.35, h["x1"] + 0.35, 3.08, 3.60
                sreg = (X > sx0) & (X < sx1) & (Z > sz0) & (Z < sz1)
                sc = hexrgb(v["sign"]) * (1 + 0.05 * (fbm(hpx, wpx, rng, 4, 3) - 0.5))[..., None]
                img = np.where(sreg[..., None], sc, img)
                border = sreg & ~((X > sx0 + 0.05) & (X < sx1 - 0.05) & (Z > sz0 + 0.05) & (Z < sz1 - 0.05))
                img = np.where(border[..., None], trim * 0.92, img)
        # string courses
    for zc in L.STRING_COURSES if kind in ("front", "side") else []:
        band = (Z > zc - 0.10) & (Z < zc + 0.10)
        img = np.where(band[..., None], trim * 0.9 * (1 + 0.03 * t[..., None]), img)
        sh = (Z > zc - 0.19) & (Z <= zc - 0.10)
        img = np.where(sh[..., None], img * (0.80 + 0.10 * (Z[..., None] - (zc - 0.19)) / 0.09), img)
    # cornice zone: frieze + dentils
    fr_ = (Z > hm - 0.56)
    img = np.where(fr_[..., None], trim * 0.93, img)
    dent = (Z > hm - 0.46) & (Z < hm - 0.30) & ((X % 0.2) < 0.10)
    img = np.where(dent[..., None], trim * 0.62, img)
    # opening interiors: never visible (geometry cuts them) but painted dark so the atlas reads as a window grid
    for h in holes:
        reg = (X > h["x0"]) & (X < h["x1"]) & (Z > h["z0"]) & (Z < h["z1"])
        img = np.where(reg[..., None], np.array([0.16, 0.18, 0.20], np.float32), img)
        cx_ = (h["x0"] + h["x1"]) / 2
        mull = reg & ((np.abs(X - cx_) < 0.03) | (np.abs(Z - (h["z0"] + h["z1"]) * 0.5) < 0.03))
        img = np.where(mull[..., None], hexrgb(v["trim"]) * 0.9, img)
    # fine grain
    img *= (1 + 0.035 * (rng.random((hpx, wpx)) - 0.5))[..., None]
    return img


def roof_field(w, h, v, rng):
    ppm = 40.0
    X = (np.arange(w) + 0.5)[None, :].repeat(h, 0)
    Y = (np.arange(h) + 0.5)[:, None].repeat(w, 1)   # y = v (down-slope distance from eave) in px
    cp, cw = 14.0, 8.0
    cu = (Y / cp)
    ci = np.floor(cu).astype(int)
    t = cu - ci
    col = X / cw
    cj = np.floor(col).astype(int)
    c = col - cj
    base = hexrgb(v["roof"])
    img = np.ones((h, w, 3), np.float32) * base
    tone = rng.normal(0, 0.07, (80, 120)).astype(np.float32)[ci % 80, cj % 120]
    out = rng.random((80, 120))[ci % 80, cj % 120]
    tone = np.where(out > 0.97, tone + 0.18, tone)
    tone = np.where(out < 0.025, tone - 0.20, tone)
    img *= (1 + tone)[..., None]
    lip = np.where(t < 0.18, 1.08, 1.0 - 0.28 * smooth(t, 0.18, 1.0))
    shade = (0.82 + 0.28 * np.sin(np.pi * c)) * (1 - 0.30 * np.exp(-np.minimum(c, 1 - c) * 14))
    img *= (lip * shade)[..., None]
    n = fbm(h, w, rng, 2, 4)
    img *= (0.88 + 0.26 * n)[..., None]
    lich = smooth(fbm(h, w, rng, 5, 3), 0.62, 0.70)
    img = mix(img, np.array([0.45, 0.43, 0.30], np.float32) * (0.9 + 0.2 * n[..., None]), lich * 0.28)
    img *= (1 - 0.0 * Y)[..., None]
    return img


def small_textures(v, rng, canvas):
    d = ImageDraw.Draw(canvas)
    def rr(n):
        return RECTS[n]
    # shutter: louvres
    x, y, w, h = rr("shutter")
    sc = hexrgb(v["shutter"])
    im = np.ones((h, w, 3), np.float32) * sc
    Y = np.arange(h)[:, None].repeat(w, 1)
    X = np.arange(w)[None, :].repeat(h, 0)
    ph = (Y % 6) / 6.0
    im *= (0.78 + 0.35 * (1 - ph))[..., None] * (1 + 0.06 * (fbm(h, w, rng, 3, 3) - 0.5))[..., None]
    stile = (X < 5) | (X > w - 6) | (Y < 5) | (Y > h - 6) | (np.abs(Y - h // 2) < 2)
    im = np.where(stile[..., None], sc * 1.12, im)
    im = np.where((((X == 5) | (X == w - 6)) & ~stile)[..., None], sc * 0.6, im)
    canvas.paste(to_img(im), (x, y))
    # window glass: dark interior, curtain, sash cross
    x, y, w, h = rr("glass_win")
    gy = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    gl = np.stack([0.19 + 0.13 * (1 - gy), 0.21 + 0.13 * (1 - gy), 0.23 + 0.13 * (1 - gy)], -1)
    X = np.arange(w)[None, :].repeat(h, 0)
    Y = np.arange(h)[:, None].repeat(w, 1)
    cur = ((X < w * 0.30) & (Y < h * 0.80 - X * 0.5)) | ((X > w * 0.72) & (Y < h * 0.65))
    gl = mix(gl.astype(np.float32), np.array([0.82, 0.78, 0.68], np.float32), cur * 0.55)
    fr = hexrgb("#DCD4C0")
    sash = (X < 4) | (X > w - 5) | (Y < 4) | (Y > h - 5) | (np.abs(X - w // 2) < 2) | (np.abs(Y - int(h * 0.38)) < 2)
    gl = np.where(sash[..., None], fr, gl)
    canvas.paste(to_img(gl), (x, y))
    # shop glass
    x, y, w, h = rr("glass_shop")
    gy = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    sg = np.stack([0.20 + 0.10 * gy, 0.19 + 0.08 * gy, 0.17 + 0.06 * gy], -1).astype(np.float32)
    Y = np.arange(h)[:, None].repeat(w, 1)
    X = np.arange(w)[None, :].repeat(h, 0)
    for sy in (44, 78, 104):
        sg = np.where(((np.abs(Y - sy) < 2))[..., None], hexrgb("#8C7458") * 0.75, sg)
        for k in range(10):
            cx = int(rng.random() * w)
            cc = [hexrgb("#B5654A"), hexrgb("#C8B070"), hexrgb("#6F8A7A"), hexrgb("#D9D0BE")][k % 4] * 0.7
            sg = np.where(((np.abs(X - cx) < 5) & (Y > sy - 12) & (Y < sy - 2))[..., None], cc, sg)
    glow = smooth(1 - np.abs(X / w - 0.5) * 2, 0.0, 1.0) * np.exp(-Y / 40.0) * 0.18
    sg = sg + glow[..., None] * np.array([1.0, 0.85, 0.6], np.float32)
    mull = (np.abs(X - w // 2) < 2) | (Y < 5) | (Y > h - 5) | (X < 3) | (X > w - 4)
    sg = np.where(mull[..., None], hexrgb("#2F2A25"), sg)
    canvas.paste(to_img(sg), (x, y))
    # kepenk (rolling shutter)
    x, y, w, h = rr("kepenk")
    Y = np.arange(h)[:, None].repeat(w, 1)
    kc = hexrgb("#7C847B")
    kp = np.ones((h, w, 3), np.float32) * kc * (1 + 0.1 * (fbm(h, w, rng, 3, 3) - 0.5))[..., None]
    ph = (Y % 5) / 5.0
    kp *= (0.72 + 0.36 * (1 - ph))[..., None]
    rust = smooth(fbm(h, w, rng, 4, 3), 0.6, 0.7)
    kp = mix(kp, hexrgb("#8A5E43"), rust * 0.5)
    canvas.paste(to_img(kp), (x, y))
    # awning stripes
    x, y, w, h = rr("awning")
    X = np.arange(w)[None, :].repeat(h, 0)
    Y = np.arange(h)[:, None].repeat(w, 1)
    stripe = ((X // 12) % 2 == 0)
    aw = np.where(stripe[..., None], hexrgb(v["awn1"]), hexrgb(v["awn2"])).astype(np.float32)
    aw *= (1 + 0.10 * np.sin(X * 0.9))[..., None] * (1 + 0.05 * (fbm(h, w, rng, 3, 3) - 0.5))[..., None]
    canvas.paste(to_img(aw), (x, y))
    # door: planks + panels + transom glass
    x, y, w, h = rr("door")
    X = np.arange(w)[None, :].repeat(h, 0)
    Y = np.arange(h)[:, None].repeat(w, 1)
    dc = hexrgb(v["door"])
    dr = np.ones((h, w, 3), np.float32) * dc * (1 + 0.1 * (fbm(h, w, rng, 4, 3) - 0.5))[..., None]
    dr *= (1 - 0.18 * ((X % 11) < 1))[..., None]
    gl_ = (Y > 8) & (Y < 40) & (X > 10) & (X < w - 10)
    dr = np.where(gl_[..., None], hexrgb("#2D3840"), dr)
    pan = ((Y > 52) & (Y < 118) & (X > 9) & (X < w - 9))
    dr = np.where((pan & ((X < 12) | (X > w - 13) | (Y < 55) | (Y > 115)))[..., None], dr * 0.7, dr)
    canvas.paste(to_img(dr), (x, y))
    # flat swatches
    sw = dict(frame="#E0D8C4", jamb=v["trim"], wood_dark="#3A2E27", metal="#3C4147", chimney="#A5917B", soffit="#5A4B3F",
              trim=v["trim"], cornice=v["trim"], stone=v["stone"], dark="#23211F", balcony_top="#8F887C", rail="#2C2E30",
              wall=v["wall"], wall_dark=v["wall_alt"], tile=v["roof"], ridge="#7E4C38", fascia="#5F4638", sill="#CFC4AC",
              panel="#34414A", tank="#D8D6CE", ac="#D9D9D3", awn_side="#4A3C34", step="#9C9486", white="#E9E5DA")
    for n in FLAT:
        x, y, w, h = RECTS["f_" + n]
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=tuple(int(c * 255) for c in hexrgb(sw[n])))
    # tile swatch matches roof mean, ridge slightly darker than roof
    rc = hexrgb(v["roof"]) * 0.86
    x, y, w, h = RECTS["f_ridge"]
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=tuple(int(c * 255) for c in rc))


def build(variant, key):
    v = L.VARIANTS[key]
    rng = np.random.default_rng(v["seed"])
    canvas = Image.new("RGB", (S, S), (128, 128, 128))
    # front field
    x, y, w, h = RECTS["front"]
    holes = [dict(h, x0=h["x0"] + L.W / 2, x1=h["x1"] + L.W / 2) for h in L.front_holes()]
    canvas.paste(to_img(wall_field(w, h, L.W, L.H, v, rng, holes, "front")), (x, y))
    x, y, w, h = RECTS["side"]
    canvas.paste(to_img(wall_field(w, h, L.D, L.H, v, rng, L.side_holes(), "side")), (x, y))
    x, y, w, h = RECTS["roof"]
    canvas.paste(to_img(roof_field(w, h, v, rng)), (x, y))
    small_textures(v, rng, canvas)
    return canvas


def flat_variant():
    """Ablation: same geometry/swatches/small textures, but wall + roof fields are flat colour (no painting)."""
    v = L.VARIANTS["a"]
    canvas = build(None, "a")
    for n, col in (("front", v["wall"]), ("side", v["wall"]), ("roof", v["roof"])):
        x, y, w, h = RECTS[n]
        ImageDraw.Draw(canvas).rectangle([x, y, x + w - 1, y + h - 1], fill=tuple(int(c * 255) for c in hexrgb(col)))
    return canvas


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for k in L.VARIANTS:
        build(None, k).save(os.path.join(out, f"hero_atlas_{k}.png"), optimize=True)
    flat_variant().save(os.path.join(out, "hero_atlas_f.png"), optimize=True)
    with open(os.path.join(out, "hero_atlas_layout.json"), "w") as f:
        json.dump(dict(size=S, rects=RECTS), f, indent=1, sort_keys=True)
    print("atlas ok", out)


if __name__ == "__main__":
    main()
