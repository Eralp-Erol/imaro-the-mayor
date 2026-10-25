"""T-055 LAB kontrol haritasi (yalniz lab; oyun maskesi degil): 200 m x 200 m, 1024^2 RGBA.
R = asfalt, G = tas (meydan/kaldirim), A = tarla; B = tur (asfalt 0 yeni/1 eskimis; tas 0 kaldirim/1 meydan; tarla 0 surulmus/1 bicilmis).
Dunya x,z in [-100,100]; piksel = ((x+100)/200, (z+100)/200). Kenarlar hafif dalgali (cizgi gibi duz degil).
Kullanim: python3 art/blender/ground/ground_lab_ctrl.py [--out assets/ground/tex/gnd_lab_ctrl.png]
"""
import sys

import numpy as np
from PIL import Image

S = 1024
M = 200.0 / S


def main():
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else "assets/ground/tex/gnd_lab_ctrl.png"
    rng = np.random.default_rng(5501)
    ix = (np.arange(S) + 0.5) * M - 100.0
    X, Z = np.meshgrid(ix, ix)
    # kenar dalgasi (periyodik olmayan, dusuk genlik)
    def wob(a, f1, f2, amp):
        return amp * (np.sin(X * f1 + a) * 0.6 + np.sin(Z * f2 + a * 2.1) * 0.4)
    ph = rng.random(6) * 6.28
    dx = wob(ph[0], 0.35, 0.21, 0.14)
    dz = wob(ph[1], 0.27, 0.4, 0.14)
    Xw, Zw = X + dx, Z + dz
    R = np.zeros((S, S), np.float32)
    G = np.zeros((S, S), np.float32)
    B = np.zeros((S, S), np.float32)
    A = np.zeros((S, S), np.float32)

    def rect(x0, x1, z0, z1):
        return ((Xw >= x0) & (Xw <= x1) & (Zw >= z0) & (Zw <= z1)).astype(np.float32)

    # sokak: ana yol (yeni asfalt) z 22..29, kaldirimlar z 19..22 ve 29..32 (x tum seridde)
    road1 = rect(-100, 100, 22, 29)
    walk = np.maximum(rect(-100, 100, 19, 22), rect(-100, 100, 29, 32))
    # yamaca cikan eski yol (eskimis asfalt): x 43..48.5, z 29 -> -46, hafif bukulen
    cx = 45.5 + 4.0 * np.sin((Z + 100) * 0.055)
    road2 = ((np.abs(Xw - cx) <= 2.8) & (Zw <= 29) & (Zw >= -46)).astype(np.float32)
    # meydan z -4..19, x -32..12 (kaldirim ile birlesir)
    plaza = rect(-32, 12, -4, 19)
    # tarlalar: 6 parsel (donuk dikdortgen), 4 m ara patika (dogal zemin)
    ang = np.deg2rad(11.0)
    U = (Xw * np.cos(ang) + Zw * np.sin(ang))
    V = (-Xw * np.sin(ang) + Zw * np.cos(ang))
    fields = np.zeros((S, S), np.float32)
    ftype = np.zeros((S, S), np.float32)
    plots = [(-92, -66, -66, -40, 0), (-62, -34, -66, -40, 1), (-30, -4, -66, -40, 0),
             (-92, -66, -36, -26, 1), (-62, -34, -36, -26, 0), (-30, -4, -36, -26, 1)]
    for (u0, u1, v0, v1, t) in plots:
        m = ((U >= u0) & (U <= u1) & (V >= v0) & (V <= v1)).astype(np.float32)
        fields = np.maximum(fields, m)
        ftype = np.where(m > 0, t, ftype)
    R = np.maximum(road1, road2)
    G = np.maximum(walk, plaza)
    G = G * (1 - R)
    A = fields * (1 - R) * (1 - G)
    B = np.where(R > 0.5, (road2 > 0.5).astype(np.float32) * (1 - road1), np.where(G > 0.5, plaza, np.where(A > 0.5, ftype, 0.0)))
    img = np.stack([R, G, B, A], -1)
    # hafif blur: bilineer + keskinlestirme (shader) temiz AA kenar verir
    from PIL import ImageFilter
    chans = [Image.fromarray((img[..., i] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)) for i in range(4)]
    res = Image.merge("RGBA", chans)
    res.save(out)
    print(out, res.size)


if __name__ == "__main__":
    main()
