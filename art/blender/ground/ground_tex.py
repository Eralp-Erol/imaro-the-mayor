"""T-055 zemin doku seti: procedural, determinist (sabit tohum), kutu basina TILE EDILEBILIR (seamless) sRGB PNG.
Python + numpy + Pillow (Blender gerekmez; hero atlas hatti ile ayni kalip).

Kullanim:  python3 art/blender/ground/ground_tex.py [--out assets/ground/tex] [--size 512]
Cikti:    <out>/gnd_<id>.png (N x N), <out>/gnd_macro.png (256 x 256 RGBA, dusuk frekans varyasyon maskeleri),
          <out>/ground_layers.json (katman sirasi, dunya boyutu m/tile, ortalama renk, HSV denetimi).

Tilelama: tum gurultu FFT ile uretilir (periyodik); sekil cizimleri (levha, damar, catlak) modulo sarilir.
Palet: design/library/README.md 2.2 (kent zemini s<=0,40, asfalt s<=0,08 v 0,29-0,40; dosme v 0,54-0,74) ve
terrain-palette-v0.md (arazi T1..T6, TS); s>0,70 hicbir yerde yok.
"""
import colorsys
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

N = 512


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


# --------------------------------------------------------------------------- periodic primitives
def fnoise(rng, beta=2.0, lo=0.0, hi=1.0, n=None):
    """Periodic 1/f^beta gurultu, [0,1]. lo/hi: bant siniri (dongu / tile)."""
    n = n or N
    w = rng.standard_normal((n, n))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    filt = r ** (-beta / 2.0)
    if hi < 1.0:
        filt = filt * np.exp(-(r / (hi * n / 2)) ** 4)
    if lo > 0.0:
        filt = filt * (1 - np.exp(-(r / max(lo * n / 2, 1.0)) ** 2))
    filt[0, 0] = 0.0
    a = np.real(np.fft.ifft2(F * filt))
    a = (a - a.mean()) / (a.std() + 1e-9)
    return (np.clip(a * 0.22 + 0.5, 0, 1)).astype(np.float32)


def cells(rng, cnt, jitter=0.9, n=None):
    """Periyodik Voronoi: (F1, F2, id, cell_x, cell_y) -> F1/F2 piksel biriminde; id 0..1."""
    n = n or N
    gx, gy = np.meshgrid(np.arange(cnt), np.arange(cnt))
    px = (gx + 0.5 + (rng.random((cnt, cnt)) - 0.5) * jitter) * n / cnt
    py = (gy + 0.5 + (rng.random((cnt, cnt)) - 0.5) * jitter) * n / cnt
    ids = rng.random((cnt, cnt))
    X, Y = np.meshgrid(np.arange(n), np.arange(n))
    best1 = np.full((n, n), 1e9, np.float32)
    best2 = np.full((n, n), 1e9, np.float32)
    bid = np.zeros((n, n), np.float32)
    for j in range(cnt):
        for i in range(cnt):
            dx = np.abs(X - px[j, i])
            dx = np.minimum(dx, n - dx)
            dy = np.abs(Y - py[j, i])
            dy = np.minimum(dy, n - dy)
            d = np.sqrt(dx * dx + dy * dy).astype(np.float32)
            closer = d < best1
            best2 = np.where(closer, best1, np.minimum(best2, d))
            bid = np.where(closer, ids[j, i], bid)
            best1 = np.where(closer, d, best1)
    return best1, best2, bid


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def ramp(t, stops):
    """t [0,1] -> RGB; stops = [(pos, '#hex'), ...]."""
    pos = np.array([s[0] for s in stops], np.float32)
    cols = np.stack([hexrgb(s[1]) for s in stops])
    out = np.zeros(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, pos, cols[:, c])
    return out


def mixc(img, col, m):
    col = hexrgb(col) if isinstance(col, str) else np.asarray(col, np.float32)
    return img * (1 - m[..., None]) + col * m[..., None]


def shade(img, f):
    return img * f[..., None]


def roll_wrap(a, dx, dy):
    return np.roll(np.roll(a, dy, 0), dx, 1)


def disc_field(rng, count, rmin, rmax, soft=2.0, n=None):
    """Periyodik yuvarlak lekeler (yaprak/calı/çakıl): maske [0,1] + yukseklik (merkeze gore)."""
    n = n or N
    mask = np.zeros((n, n), np.float32)
    hgt = np.zeros((n, n), np.float32)
    Y, X = np.mgrid[0:n, 0:n].astype(np.float32)
    for _ in range(count):
        cx, cy = rng.random() * n, rng.random() * n
        r = rmin + rng.random() * (rmax - rmin)
        dx = np.abs(X - cx)
        dx = np.minimum(dx, n - dx)
        dy = np.abs(Y - cy)
        dy = np.minimum(dy, n - dy)
        # hafif elips
        e = 0.75 + rng.random() * 0.5
        d = np.sqrt(dx * dx * e + dy * dy / e)
        m = 1 - smooth(d, r - soft, r + 0.001)
        hh = np.clip(1 - d / r, 0, 1) * (0.7 + rng.random() * 0.3)
        upd = m > mask
        hgt = np.where(upd, hh, hgt)
        mask = np.maximum(mask, m)
    return mask, hgt


def grain(img, rng, amt=0.12, lo=0.45):
    """Yuksek frekans tane/sap detayi: bulaniklik (blurry) sikayetine karsi keskin piksel-alti doku."""
    g = fnoise(rng, 0.0, lo=lo)
    g2 = _blades(rng, 150, 25, 1.0)
    return img * (1 + ((g - 0.5) * 0.8 + (g2 - 0.5) * 0.8) * amt)[..., None]


def save(img, path):
    a = np.clip(img, 0, 1)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8)).save(path, optimize=True)


# --------------------------------------------------------------------------- recipes
def plaza_stone_a(rng):
    """Acik tas meydan dosemesi (U1 #B9AE9C), 4 m tile: 0,5 m sira, degisken levha boyu, kosebent. Levha basina ton."""
    img = np.zeros((N, N, 3), np.float32)
    rows = 8
    rh = N // rows
    joint = np.zeros((N, N), np.float32)
    tone = np.zeros((N, N), np.float32)
    hue = np.zeros((N, N), np.float32)
    edge_d = np.full((N, N), 99.0, np.float32)
    Y, X = np.mgrid[0:N, 0:N]
    for r in range(rows):
        # satir icinde 3-5 levha, toplam N
        k = int(rng.integers(3, 5))
        w = rng.random(k) + 0.8
        w = np.round(w / w.sum() * N).astype(int)
        w[-1] = N - w[:-1].sum()
        off = int(rng.integers(0, N))
        x0 = 0
        for wi in w:
            xs = (np.arange(x0, x0 + wi) + off) % N
            ys = np.arange(r * rh, (r + 1) * rh)
            tn = (rng.random() - 0.5) * 2
            hu = (rng.random() - 0.5) * 2
            tone[np.ix_(ys, xs)] = tn
            hue[np.ix_(ys, xs)] = hu
            lx = np.arange(wi)
            dxe = np.minimum(lx, wi - 1 - lx)[None, :]
            dye = np.minimum(np.arange(rh), rh - 1 - np.arange(rh))[:, None]
            edge_d[np.ix_(ys, xs)] = np.minimum(dxe, dye)
            x0 += wi
    mott = fnoise(rng, 2.2, hi=0.5)
    fine = fnoise(rng, 0.6, lo=0.2)
    big = fnoise(rng, 3.0, hi=0.08)
    base = ramp(np.clip(0.5 + tone * 0.22 + (mott - 0.5) * 0.6 + (big - 0.5) * 0.5, 0, 1),
                [(0.0, "#9E9078"), (0.5, "#BDAF97"), (1.0, "#CFC2A8")])
    base = base * (1 + (hue[..., None] * np.array([0.03, 0.0, -0.03], np.float32)))
    base = shade(base, 0.95 + (fine - 0.5) * 0.14)
    # derz: koyu, ic kenarda hafif acik bevel
    j = 1 - smooth(edge_d, 1.0, 3.2)
    base = mixc(base, "#6E6558", j * 0.85)
    bev = smooth(edge_d, 3.2, 5.5) * (1 - smooth(edge_d, 5.5, 8.0))
    base = shade(base, 1 + bev * 0.05)
    # kirik/leke: koyu lekeler + birkac catlak
    stain = smooth(fnoise(rng, 2.5, hi=0.15), 0.62, 0.8)
    base = shade(base, 1 - stain * 0.12)
    crack = crack_lines(rng, 2, 40)
    base = shade(base, 1 - crack * 0.25)
    return base


def crack_lines(rng, count, length, width=1.0, n=None):
    n = n or N
    c = np.zeros((n, n), np.float32)
    for _ in range(count):
        x, y = rng.random() * n, rng.random() * n
        a = rng.random() * 6.283
        for _s in range(length):
            a += (rng.random() - 0.5) * 0.7
            x = (x + np.cos(a) * 2.0) % n
            y = (y + np.sin(a) * 2.0) % n
            xi, yi = int(x), int(y)
            c[yi, xi] = 1.0
    im = Image.fromarray((c * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3 if width > 0.5 else 1))
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    return np.asarray(im, np.float32) / 255.0


def sidewalk_cobble(rng):
    """Kaldirim: duzensiz kare-dortgen kilit/kesme tas (U3 #A69C8B), Voronoi + sira egilimi, 3 m tile."""
    f1, f2, ids = cells(rng, 14, jitter=0.55)
    edge = f2 - f1
    mott = fnoise(rng, 2.0, hi=0.6)
    fine = fnoise(rng, 0.5, lo=0.25)
    big = fnoise(rng, 3.0, hi=0.08)
    t = np.clip(0.5 + (ids - 0.5) * 0.5 + (mott - 0.5) * 0.4 + (big - 0.5) * 0.4, 0, 1)
    base = ramp(t, [(0.0, "#8A8070"), (0.5, "#A69C8B"), (1.0, "#BCB3A2")])
    base = shade(base, 0.95 + (fine - 0.5) * 0.14)
    base = shade(base, 1 + (1 - smooth(f1, 0, 14)) * 0.03)  # tas ortasi hafif yuksek
    j = 1 - smooth(edge, 1.2, 4.0)
    base = mixc(base, "#625B50", j * 0.8)
    return base


def asphalt_new(rng):
    """Yeni asfalt (U2 #5F5D5A, v 0,29-0,40, s<=0,08): kum taneleri + cok hafif buyuk leke."""
    fine = fnoise(rng, 0.2, lo=0.35)
    mid = fnoise(rng, 1.4, hi=0.35)
    big = fnoise(rng, 3.0, hi=0.06)
    t = np.clip(0.5 + (mid - 0.5) * 0.5 + (big - 0.5) * 0.7, 0, 1)
    base = ramp(t, [(0.0, "#524F4D"), (0.5, "#5F5D5A"), (1.0, "#6A6764")])
    base = shade(base, 0.9 + (fine - 0.5) * 0.35)
    # aci taneler (acik tas)
    grit = (fnoise(rng, 0.0, lo=0.5) > 0.93).astype(np.float32)
    base = mixc(base, "#7A7773", grit * 0.45)
    # tekerlek izi yok (yon belirsiz tile); ince derz (bitisik serim) cizgisi
    seam = np.zeros((N, N), np.float32)
    seam[N // 2 - 1:N // 2 + 1, :] = 1.0
    seam = np.asarray(Image.fromarray((seam * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255
    base = shade(base, 1 - seam * 0.14)
    return base


def asphalt_worn(rng):
    """Eskimis asfalt: acilmis ton (v<=0,40), onarim yamalari (dikdortgen koyu), catlaklar, yagli leke, tas cikintisi."""
    fine = fnoise(rng, 0.2, lo=0.35)
    mid = fnoise(rng, 1.6, hi=0.4)
    big = fnoise(rng, 3.0, hi=0.07)
    t = np.clip(0.5 + (mid - 0.5) * 0.7 + (big - 0.5) * 0.9, 0, 1)
    base = ramp(t, [(0.0, "#585553"), (0.5, "#6A6663"), (1.0, "#79746E")])
    base = shade(base, 0.9 + (fine - 0.5) * 0.4)
    # onarim yamalari
    for _ in range(5):
        w, h = int(rng.integers(90, 220)), int(rng.integers(50, 130))
        x0, y0 = int(rng.integers(0, N)), int(rng.integers(0, N))
        m = np.zeros((N, N), np.float32)
        ys = (np.arange(h) + y0) % N
        xs = (np.arange(w) + x0) % N
        m[np.ix_(ys, xs)] = 1.0
        edge = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.4)), np.float32) / 255
        ring = np.clip(np.abs(edge - 0.5) * -2 + 1, 0, 1)
        dark = 0.80 + rng.random() * 0.1
        base = base * (1 - m[..., None]) + base * dark * m[..., None]
        base = shade(base, 1 - ring * 0.25)  # yama kenar cizgisi
    crack = crack_lines(rng, 7, 90)
    base = shade(base, 1 - crack * 0.5)
    oil = smooth(fnoise(rng, 2.5, hi=0.12), 0.64, 0.82)
    base = shade(base, 1 - oil * 0.18)
    grit = (fnoise(rng, 0.0, lo=0.5) > 0.9).astype(np.float32)
    base = mixc(base, "#807B75", grit * 0.5)
    return base


def dirt_courtyard(rng):
    """Toprak/avlu (U4 #8A7D68 / U9 #8F7558): karisik, kuru catlak, tas parcalari, patika izi."""
    fine = fnoise(rng, 0.3, lo=0.3)
    mid = fnoise(rng, 1.8, hi=0.5)
    big = fnoise(rng, 3.0, hi=0.07)
    t = np.clip(0.5 + (mid - 0.5) * 0.7 + (big - 0.5) * 0.8, 0, 1)
    base = ramp(t, [(0.0, "#75684F"), (0.45, "#8A7D68"), (1.0, "#A29579")])
    base = shade(base, 0.9 + (fine - 0.5) * 0.3)
    f1, f2, _ = cells(rng, 20, jitter=0.9)
    dry = (1 - smooth(f2 - f1, 0.6, 2.4)) * smooth(big, 0.5, 0.7)
    base = shade(base, 1 - dry * 0.22)
    m, h = disc_field(rng, 90, 3, 9, soft=1.5)
    base = mixc(base, ramp(0.35 + h * 0.5, [(0.0, "#7A7060"), (1.0, "#B3A890")]), m * 0.8)
    base = shade(base, 1 - np.roll(m, (3, 2), (0, 1)) * (1 - m) * 0.25)  # tas golgesi
    return base


def _blades(rng, scale_x, scale_y, strength):
    """Yatay-dikey anizotropik fiskirma (ot saplari / saman), periyodik."""
    w = rng.standard_normal((N, N))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(N)[:, None] * N
    fx = np.fft.fftfreq(N)[None, :] * N
    filt = np.exp(-((fx / scale_x) ** 2 + (fy / scale_y) ** 2))
    a = np.real(np.fft.ifft2(F * filt))
    a = (a - a.mean()) / (a.std() + 1e-9)
    return np.clip(a * 0.2 * strength + 0.5, 0, 1).astype(np.float32)


def grass_dry(rng):
    """Kuru ot / saman-okra (T2 #958A58): sapli tutamlar + acik/koyu yamalar + yer yer toprak."""
    big = fnoise(rng, 3.0, hi=0.07)
    mid = fnoise(rng, 2.0, hi=0.3)
    blade = _blades(rng, 70, 12, 1.0) * 0.6 + _blades(rng, 20, 60, 1.0) * 0.4
    tuft = fnoise(rng, 1.0, lo=0.2, hi=0.8)
    t = np.clip(0.5 + (big - 0.5) * 0.8 + (mid - 0.5) * 0.4 + (blade - 0.5) * 0.5, 0, 1)
    base = ramp(t, [(0.0, "#7B7149"), (0.35, "#958A58"), (0.7, "#A89C68"), (1.0, "#BCAF7C")])
    base = shade(base, 0.93 + (tuft - 0.5) * 0.25)
    soil = smooth(fnoise(rng, 2.8, hi=0.1), 0.66, 0.8)
    base = mixc(base, "#8A7556", soil * 0.55)
    m, h = disc_field(rng, 70, 2, 6, soft=1.2)  # tek tek tutam golgesi
    base = shade(base, 1 - m * (1 - h) * 0.1)
    return grain(base, rng, 0.2)


def grass_green(rng):
    """Park cimi / yesil ot (U5 #7D8551, s<=0,5): kuru Ege yesili, yosun degil."""
    big = fnoise(rng, 3.0, hi=0.07)
    mid = fnoise(rng, 2.0, hi=0.3)
    blade = _blades(rng, 80, 14, 1.0) * 0.5 + _blades(rng, 18, 70, 1.0) * 0.5
    t = np.clip(0.5 + (big - 0.5) * 0.7 + (mid - 0.5) * 0.4 + (blade - 0.5) * 0.55, 0, 1)
    base = ramp(t, [(0.0, "#626C3F"), (0.4, "#7D8551"), (0.75, "#8E9660"), (1.0, "#A3A56D")])
    clover = smooth(fnoise(rng, 2.6, hi=0.15), 0.66, 0.8)
    base = mixc(base, "#6E7A47", clover * 0.5)
    dryp = smooth(fnoise(rng, 2.6, hi=0.1), 0.7, 0.85)
    base = mixc(base, "#9A9262", dryp * 0.4)
    return grain(base, rng, 0.2)


def scrub_maquis(rng):
    """Calı/maki (T3 #6B7048 govde, koyu calı #4F5B38): yuvarlak calı kubbeleri + arada kuru toprak/ot. Ustten bakis."""
    dry = grass_dry(rng) * 0.9
    soil = mixc(dry, "#7E6C4C", smooth(fnoise(rng, 2.5, hi=0.15), 0.55, 0.8) * 0.5)
    img = soil
    for layer, (cnt, rmin, rmax, col_lo, col_hi) in enumerate([
        (34, 12, 26, "#4A5535", "#66703F"), (110, 5, 13, "#4F5B38", "#727A48")]):
        m, h = disc_field(rng, cnt, rmin, rmax, soft=2.0)
        n2 = fnoise(rng, 0.8, lo=0.15, hi=0.8)
        edgen = fnoise(rng, 0.4, lo=0.12)
        m = smooth(m * 1.0 + (edgen - 0.5) * 0.9, 0.35, 0.55) * (m > 0.02)
        tt = np.clip(h * 0.7 + (n2 - 0.5) * 0.9 + (fnoise(rng, 0.0, lo=0.5) - 0.5) * 0.5, 0, 1)
        bush = ramp(tt, [(0.0, col_lo), (1.0, col_hi)])
        # golge halka (kubbenin altinda koyu kenar)
        sh = np.roll(m, (4, 3), (0, 1)) * (1 - m)
        img = shade(img, 1 - sh * 0.35)
        img = img * (1 - m[..., None]) + bush * m[..., None]
    return img


def olive_ground(rng):
    """Zeytinlik zemini: sicak okra toprak + seyrek kuru ot + yaprak golge lekeleri (T3 gri-yesil ima)."""
    big = fnoise(rng, 3.0, hi=0.07)
    mid = fnoise(rng, 2.0, hi=0.4)
    fine = fnoise(rng, 0.3, lo=0.3)
    t = np.clip(0.5 + (big - 0.5) * 0.7 + (mid - 0.5) * 0.5, 0, 1)
    base = ramp(t, [(0.0, "#7A6B4A"), (0.5, "#948558"), (1.0, "#AA9A68")])
    base = shade(base, 0.92 + (fine - 0.5) * 0.2)
    tufts = _blades(rng, 60, 14, 1.0)
    grass = smooth(fnoise(rng, 2.4, hi=0.2), 0.55, 0.72)
    base = mixc(base, ramp(tufts, [(0.0, "#78784A"), (1.0, "#9A9560")]), grass * 0.55)
    # yaprak golgesi: yumusak koyu daireler (agac yarisi golge)
    m, h = disc_field(rng, 22, 20, 44, soft=14)
    base = shade(base, 1 - m * 0.2)
    m2, h2 = disc_field(rng, 80, 2, 5, soft=1.2)  # dusmus zeytin/tas noktalari
    base = mixc(base, "#5E5838", m2 * 0.35)
    return grain(base, rng, 0.18)


def field_plowed(rng):
    """Surulmus tarla: dogrusal tirmik/karık (periyodik, 32 karik), sicak toprak tonlari #8F7558 / #77603F."""
    n_f = 32
    y = np.arange(N, dtype=np.float32)[:, None] / N
    wob = (fnoise(rng, 2.5, hi=0.08) - 0.5) * 0.02
    phase = (y + wob * np.ones((1, N), np.float32)) * n_f * 2 * np.pi
    ridge = 0.5 + 0.5 * np.sin(phase)
    crest = smooth(ridge, 0.4, 0.9)
    clod = fnoise(rng, 0.6, lo=0.15, hi=0.9)
    big = fnoise(rng, 3.0, hi=0.07)
    base = ramp(np.clip(0.5 + (big - 0.5) * 0.7 + (crest - 0.5) * 0.9, 0, 1),
                [(0.0, "#6F5A3E"), (0.5, "#8F7558"), (1.0, "#A58C69")])
    base = shade(base, 0.9 + (clod - 0.5) * 0.3)
    m, _ = disc_field(rng, 140, 1.5, 4, soft=1.0)  # kesek
    base = mixc(base, "#B2A07E", m * 0.35)
    return base


def field_stubble(rng):
    """Sari bicilmis tarla/anız (okra-saman, s<=0,5): ince dik cizgi anız + serit izleri."""
    n_f = 24
    y = np.arange(N, dtype=np.float32)[:, None] / N
    stripe = 0.5 + 0.5 * np.sin((y + (fnoise(rng, 2.5, hi=0.08) - 0.5) * 0.02) * n_f * 2 * np.pi)
    straw = _blades(rng, 150, 30, 1.0)  # yatay ince cizgiler (karik boyunca)
    big = fnoise(rng, 3.0, hi=0.07)
    mid = fnoise(rng, 2.0, hi=0.3)
    t = np.clip(0.5 + (big - 0.5) * 0.6 + (mid - 0.5) * 0.4 + (stripe - 0.5) * 0.25 + (straw - 0.5) * 0.7, 0, 1)
    base = ramp(t, [(0.0, "#A8924E"), (0.4, "#BFA962"), (0.75, "#CDB975"), (1.0, "#DACA8C")])
    soil = smooth(fnoise(rng, 2.6, hi=0.12), 0.68, 0.84)
    base = base * 0.8
    base = mixc(base, "#8A7448", soil * 0.45)
    return grain(base, rng, 0.22)


def beach_sand(rng):
    """Kiyi kumu (TS #B8A77F): ince tane + hafif dalga/ruzgar kivrimlari + nadir sedef/kabuk noktasi."""
    fine = fnoise(rng, 0.1, lo=0.4)
    mid = fnoise(rng, 2.0, hi=0.4)
    big = fnoise(rng, 3.0, hi=0.07)
    warp = fnoise(rng, 3.0, hi=0.05)
    y = np.arange(N, dtype=np.float32)[:, None] / N
    x = np.arange(N, dtype=np.float32)[None, :] / N
    rip = 0.5 + 0.5 * np.sin((y * 0.8 + x * 0.6 + (warp - 0.5) * 0.15) * 20 * 2 * np.pi)
    t = np.clip(0.5 + (mid - 0.5) * 0.4 + (big - 0.5) * 0.6 + (rip - 0.5) * 0.12, 0, 1)
    base = ramp(t, [(0.0, "#A19170"), (0.5, "#B8A77F"), (1.0, "#C8BA94")])
    base = shade(base, 0.96 + (fine - 0.5) * 0.12)
    m, h = disc_field(rng, 50, 1.5, 3.2, soft=0.8)
    base = mixc(base, "#8E8268", m * 0.4)
    return grain(base, rng, 0.14, 0.6)


def gravel(rng):
    """Cakil (kıyı cakili, #8D8576 ailesi): ic ice yuvarlak taslar, tas basina ton, aralar koyu."""
    base = np.full((N, N, 3), hexrgb("#5E574C"), np.float32)
    for cnt, rmin, rmax in [(70, 12, 22), (160, 6, 12), (260, 3, 6)]:
        m, h = disc_field(rng, cnt, rmin, rmax, soft=1.0)
        tone = fnoise(rng, 0.5, lo=0.1)
        # tas basina rastgele ton: disc_field merkezlerini kullanmadan "h" ile modul
        tt = np.clip(0.35 + h * 0.5 + (tone - 0.5) * 0.9, 0, 1)
        stone = ramp(tt, [(0.0, "#6A6256"), (0.5, "#7F776A"), (1.0, "#9A927F")])
        sh = np.roll(m, (2, 2), (0, 1)) * (1 - m)
        base = shade(base, 1 - sh * 0.4)
        base = base * (1 - m[..., None]) + stone * m[..., None]
    return base


def rock_cliff(rng):
    """Kaya/yamac tasi (T6 #9C907C, sicak gri-bej): yatay tabakalar + catlak/levha Voronoi + leke."""
    warp = fnoise(rng, 3.0, hi=0.06)
    mid = fnoise(rng, 2.0, hi=0.4)
    fine = fnoise(rng, 0.5, lo=0.3)
    y = np.arange(N, dtype=np.float32)[:, None] / N
    strata = 0.5 + 0.5 * np.sin((y + (warp - 0.5) * 0.12) * 6 * 2 * np.pi)
    f1, f2, ids = cells(rng, 5, jitter=0.95)
    t = np.clip(0.5 + (ids - 0.5) * 0.45 + (mid - 0.5) * 0.5 + (strata - 0.5) * 0.35, 0, 1)
    base = ramp(t, [(0.0, "#70665A"), (0.45, "#8C8270"), (0.8, "#9C907C"), (1.0, "#B0A58F")])
    base = shade(base, 0.92 + (fine - 0.5) * 0.2)
    seam = 1 - smooth(f2 - f1, 0.8, 3.5)
    base = shade(base, 1 - seam * 0.38)
    lit = smooth(f2 - f1, 3.5, 7.0) * (1 - smooth(f2 - f1, 7.0, 12.0))
    base = shade(base, 1 + lit * 0.04)
    lichen = smooth(fnoise(rng, 2.6, hi=0.12), 0.68, 0.84)
    base = mixc(base, "#A39A6A", lichen * 0.35)
    return base


def macro_masks(rng):
    """256^2 RGBA: dusuk frekans varyasyon maskeleri (A=ton, B=leke, G=nem/kuru, R=karisim bozucu). 1 doku okumasi."""
    n = 256
    ch = [fnoise(rng, 2.6, hi=0.12, n=n), fnoise(rng, 2.4, hi=0.2, n=n), fnoise(rng, 2.0, hi=0.3, n=n), fnoise(rng, 1.4, lo=0.05, n=n)]
    # kontrast ac: kullanim araligi 0..1 tam olsun
    out = []
    for c in ch:
        lo, hi = np.percentile(c, 2), np.percentile(c, 98)
        out.append(np.clip((c - lo) / (hi - lo), 0, 1))
    return np.stack(out, -1)


# id -> (fn, tile_m, zone ('hex' sinir icin palet alani), hex_ref)
LAYERS = [
    ("plaza_stone_a", plaza_stone_a, 4.0, "U1", "#B9AE9C"),
    ("sidewalk_cobble", sidewalk_cobble, 3.0, "U3", "#A69C8B"),
    ("asphalt_new", asphalt_new, 6.0, "U2", "#5F5D5A"),
    ("asphalt_worn", asphalt_worn, 6.0, "U2", "#5F5D5A"),
    ("dirt_courtyard", dirt_courtyard, 6.0, "U4/U9", "#8A7D68"),
    ("grass_dry", grass_dry, 6.0, "T2", "#958A58"),
    ("grass_green", grass_green, 6.0, "U5", "#7D8551"),
    ("scrub_maquis", scrub_maquis, 8.0, "T3", "#6B7048"),
    ("olive_ground", olive_ground, 8.0, "T3", "#948558"),
    ("field_plowed", field_plowed, 8.0, "T1", "#8F7558"),
    ("field_stubble", field_stubble, 8.0, "T1", "#BFA962"),
    ("beach_sand", beach_sand, 4.0, "TS", "#B8A77F"),
    ("gravel", gravel, 3.0, "TS/T6", "#8D8576"),
    ("rock_cliff", rock_cliff, 8.0, "T6", "#9C907C"),
]


def hsv_stats(img):
    a = np.clip(img, 0, 1).reshape(-1, 3)
    mx, mn = a.max(1), a.min(1)
    v = mx
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    rr, gg, bb = a[:, 0], a[:, 1], a[:, 2]
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == rr, ((gg - bb) / d) % 6, np.where(mx == gg, (bb - rr) / d + 2, (rr - gg) / d + 4)) * 60
    m = mx - mn > 0.02
    return {"v_mean": float(v.mean()), "v_p5": float(np.percentile(v, 5)), "v_p95": float(np.percentile(v, 95)),
            "s_mean": float(s.mean()), "s_p99": float(np.percentile(s, 99)), "s_max": float(s.max()),
            "h_mean_deg": float(np.median(h[m])) if m.any() else 0.0}


def seam_error(img):
    """Tile dikis olcumu: sinir komsu pikseller farki / ic komsu pikseller farki (≈1 = gorunmez dikis)."""
    a = img.astype(np.float32)
    inner = (np.abs(a[:, 1:] - a[:, :-1]).mean() + np.abs(a[1:] - a[:-1]).mean()) / 2
    wrap = (np.abs(a[:, 0] - a[:, -1]).mean() + np.abs(a[0] - a[-1]).mean()) / 2
    return float(wrap / max(inner, 1e-9))


def main():
    global N
    out = "assets/ground/tex"
    args = sys.argv[1:]
    if "--out" in args:
        out = args[args.index("--out") + 1]
    if "--size" in args:
        N = int(args[args.index("--size") + 1])
    os.makedirs(out, exist_ok=True)
    meta = []
    for i, (lid, fn, tile_m, zone, ref) in enumerate(LAYERS):
        rng = np.random.default_rng(5500 + i * 17)
        img = np.clip(fn(rng), 0, 1)
        save(img, os.path.join(out, f"gnd_{lid}.png"))
        st = hsv_stats(img)
        st["seam_ratio"] = seam_error(img)
        meta.append({"index": i, "id": lid, "file": f"gnd_{lid}.png", "tile_m": tile_m, "palette_zone": zone, "palette_ref": ref,
                     "mean_srgb": [round(float(x), 4) for x in img.reshape(-1, 3).mean(0)], "hsv": {k: round(v, 4) for k, v in st.items()}})
        print(f"{lid:16s} v={st['v_mean']:.2f} s_mean={st['s_mean']:.2f} s_p99={st['s_p99']:.2f} h={st['h_mean_deg']:.0f} seam={st['seam_ratio']:.2f}")
    mac = macro_masks(np.random.default_rng(5599))
    Image.fromarray((mac * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out, "gnd_macro.png"), optimize=True)
    with open(os.path.join(out, "ground_layers.json"), "w") as f:
        json.dump({"version": 1, "size_px": N, "macro": {"file": "gnd_macro.png", "size_px": 256, "world_period_m": 96.0}, "layers": meta}, f, indent=1)
    print("done", len(LAYERS), "layers + macro")


if __name__ == "__main__":
    main()
