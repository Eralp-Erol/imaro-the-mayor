"""T-054 hero building families (Blender headless). One textured surface per GLB, flat shaded, metres, front faces -Y (Godot +Z).

  Blender --background --factory-startup --python art/blender/hero/fam_build.py -- --family bazaar --variant a \
      --atlas assets/hero/fam/bazaar_a.png --layout assets/hero/fam/bazaar_layout.json --out assets/hero/fam/hero_bazaar_a.glb
Deterministic (no randomness). Geometry from fam_layout.py; colour/texture from the atlas.
"""
import json
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fam_layout as FL  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
arg = {argv[i].lstrip("-"): argv[i + 1] for i in range(0, len(argv) - 1, 2)}
LAYOUT = json.load(open(arg["layout"]))
SZ = float(LAYOUT["size"])
RECTS = LAYOUT["rects"]
SPEC = FL.FAMILIES[arg["family"]]()
VAR = arg["variant"]
W, D, H = SPEC["W"], SPEC["D"], SPEC["H"]
TEXTURED = {"shutter", "glass_win", "glass_shop", "kepenk", "awning", "door", "front", "side", "roof", "glass_wide", "sheet", "clock",
            "cont_a", "cont_b", "brick", "roofmetal", "wall_wood"}
V, UV, F = [], [], []


def uv_of(name, fx, fy):
    x, y, w, h = RECTS[name if name in TEXTURED else "f_" + name]
    if name in TEXTURED:
        px, py = x + 1.0 + fx * (w - 2.0), y + 1.0 + fy * (h - 2.0)
    else:
        px, py = x + w * 0.5, y + h * 0.5
    return (px / SZ, 1.0 - py / SZ)


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    l = math.sqrt(dot(a, a)); return (a[0] / l, a[1] / l, a[2] / l)


def poly(pts, uvs, want=None):
    if want is not None:
        n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
        if dot(n, want) < 0:
            pts, uvs = pts[::-1], uvs[::-1]
    i = len(V)
    V.extend(pts); UV.extend(uvs); F.append(tuple(range(i, i + len(pts))))


def flatpoly(pts, name, want=None): poly(pts, [uv_of(name, .5, .5)] * len(pts), want)
def quad_tex(p, name, want, fxs=(0, 1, 1, 0), fys=(1, 1, 0, 0)): poly(p, [uv_of(name, fxs[k], fys[k]) for k in range(4)], want)


def box(c, size, faces, basis=((1, 0, 0), (0, 1, 0), (0, 0, 1))):
    bx, by, bz = basis
    h = (size[0] / 2, size[1] / 2, size[2] / 2)
    ax = {"x": (bx, h[0]), "y": (by, h[1]), "z": (bz, h[2])}
    spec = {"+x": ("x", "y", "z", 1), "-x": ("x", "z", "y", -1), "+y": ("y", "z", "x", 1), "-y": ("y", "x", "z", -1),
            "+z": ("z", "x", "y", 1), "-z": ("z", "y", "x", -1)}
    for key, name in faces.items():
        n_ax, t1, t2, sgn = spec[key]
        n = mul(ax[n_ax][0], sgn)
        ctr = add(c, mul(n, ax[n_ax][1]))
        v1, h1 = ax[t1]; v2, h2 = ax[t2]
        pts = [add(ctr, add(mul(v1, s1 * h1), mul(v2, s2 * h2))) for s1, s2 in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        if name in TEXTURED:
            quad_tex(pts, name, n)
        else:
            flatpoly(pts, name, n)


def aabox(x0, x1, y0, y1, z0, z1, faces):
    box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), faces)


ALL = ("+x", "-x", "+y", "-y", "+z", "-z")
def fcs(name, skip=()): return {k: name for k in ALL if k not in skip}


def cyl(cx, cy, z0, z1, r, n, name, topname=None):
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        p0, p1 = (cx + r * math.cos(a0), cy + r * math.sin(a0)), (cx + r * math.cos(a1), cy + r * math.sin(a1))
        am = (a0 + a1) / 2
        flatpoly([(p0[0], p0[1], z0), (p1[0], p1[1], z0), (p1[0], p1[1], z1), (p0[0], p0[1], z1)], name, (math.cos(am), math.sin(am), 0))
    flatpoly([(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), z1) for i in range(n)], topname or name, (0, 0, 1))


# ------------------------------------------------------------------ planes / walls
NORMALS = {"front": (0, -1, 0), "right": (1, 0, 0), "left": (-1, 0, 0), "back": (0, 1, 0)}


def to3d(plane, u, z, off=0.0):
    if plane == "front": return (u, -off, z)
    if plane == "back": return (u, D + off, z)
    if plane == "right": return (W / 2 + off, u, z)
    return (-W / 2 - off, u, z)


def frontuv(u, z): return uv_of("front", (u + W / 2) / W, 1 - z / H)
def side_r_uv(u, z): return uv_of("side", u / D, 1 - z / H)
def side_l_uv(u, z): return uv_of("side", 1 - u / D, 1 - z / H)


def wall_grid(plane, holes, uvfn, u0, u1, z0, z1, off=0.0):
    us = sorted({u0, u1} | {h["x0"] for h in holes} | {h["x1"] for h in holes})
    zs = sorted({z0, z1} | {h["z0"] for h in holes} | {h["z1"] for h in holes})
    for i in range(len(us) - 1):
        for j in range(len(zs) - 1):
            uc, zc = (us[i] + us[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
            if any(h["x0"] < uc < h["x1"] and h["z0"] < zc < h["z1"] for h in holes):
                continue
            cs = ((us[i], zs[j]), (us[i + 1], zs[j]), (us[i + 1], zs[j + 1]), (us[i], zs[j + 1]))
            poly([to3d(plane, a, b, off) for a, b in cs], [uvfn(a, b) for a, b in cs], NORMALS[plane])


def inward_dir(plane, du, dz):
    return {"front": (du, 0, dz), "back": (-du, 0, dz), "right": (0, du, dz), "left": (0, du, dz)}[plane]


def opening(plane, h, depth, glass, frame="frame", fw=0.06, off=0.0, sticks=True):
    n = NORMALS[plane]
    inw = mul(n, -1)
    u0, u1, z0, z1 = h["x0"], h["x1"], h["z0"], h["z1"]
    def P(u, z, d): return add(to3d(plane, u, z, off), mul(inw, d))
    for (u, dirn) in ((u0, 1), (u1, -1)):
        flatpoly([P(u, z0, 0), P(u, z1, 0), P(u, z1, depth), P(u, z0, depth)], "jamb", inward_dir(plane, dirn, 0))
    flatpoly([P(u0, z1, 0), P(u1, z1, 0), P(u1, z1, depth), P(u0, z1, depth)], "jamb", (0, 0, -1))
    flatpoly([P(u0, z0, 0), P(u1, z0, 0), P(u1, z0, depth), P(u0, z0, depth)], "sill", (0, 0, 1))
    quad_tex([P(u0, z0, depth), P(u1, z0, depth), P(u1, z1, depth), P(u0, z1, depth)], glass, n)
    if sticks:
        def stick(a0, a1, b0, b1):
            pa, pb = P(a0, b0, depth - 0.10), P(a1, b1, depth)
            aabox(min(pa[0], pb[0]), max(pa[0], pb[0]), min(pa[1], pb[1]), max(pa[1], pb[1]), min(pa[2], pb[2]), max(pa[2], pb[2]), fcs(frame))
        stick(u0, u0 + fw, z0, z1); stick(u1 - fw, u1, z0, z1); stick(u0, u1, z1 - fw, z1); stick(u0, u1, z0, z0 + fw)


def sill_box(h, plane="front", proj=0.12):
    if plane == "front":
        aabox(h["x0"] - 0.08, h["x1"] + 0.08, -proj, 0.05, h["z0"] - 0.07, h["z0"], fcs("sill"))
    else:
        sx = 1 if plane == "right" else -1
        x = sx * W / 2
        aabox(min(x, x + sx * proj), max(x, x + sx * proj), h["x0"] - 0.07, h["x1"] + 0.07, h["z0"] - 0.07, h["z0"], fcs("sill"))


def shutters(h, mode):
    if mode == "none":
        return
    w, z0, z1 = h["x1"] - h["x0"], h["z0"], h["z1"]
    lw = w / 2
    def leaf(xa, xb):
        aabox(xa, xb, -0.05, -0.012, z0 - 0.02, z1 + 0.02, {"-y": "shutter", "+x": "wall_dark", "-x": "wall_dark", "+z": "wall_dark"})
    cx = (h["x0"] + h["x1"]) / 2
    if mode == "open":
        leaf(h["x0"] - lw, h["x0"] - 0.01); leaf(h["x1"] + 0.01, h["x1"] + lw)
    elif mode == "closed":
        leaf(h["x0"] - 0.03, cx - 0.01); leaf(cx + 0.01, h["x1"] + 0.03)
    else:
        leaf(h["x0"] - lw, h["x0"] - 0.01); leaf(cx + 0.01, h["x1"] + 0.03)


def do_opening(plane, h, off=0.0):
    k = h["kind"]
    if k == "shop":
        opening(plane, h, 0.30, "glass_shop", "wood_dark", 0.09, off, sticks=True)
        cx = (h["x0"] + h["x1"]) / 2
        aabox(cx - 0.04, cx + 0.04, -off + 0.17, -off + 0.26, h["z0"], h["z1"], fcs("wood_dark"))
    elif k == "door":
        opening(plane, h, 0.28, "door", "wood_dark", 0.07, off)
        if plane == "front":
            aabox(h["x0"] - 0.15, h["x1"] + 0.15, -off - 0.22, -off + 0.04, 0.0, 0.18, fcs("step"))
    elif k in ("gate", "dock"):
        opening(plane, h, 0.15, "kepenk", "steel", 0.1, off)
    elif k == "wide":
        opening(plane, h, 0.2, "glass_wide", "frame", 0.05, off)
    else:
        opening(plane, h, 0.2, "glass_win", "frame", 0.06, off)
        if plane == "front" and k == "win" and off == 0.0:
            sill_box(h)
            shutters(h, h.get("shut", "none"))
        elif plane != "front":
            sill_box(h, plane)


def shell(front_holes=None):
    fh = front_holes if front_holes is not None else SPEC["holes"]
    wall_grid("front", fh, frontuv, -W / 2, W / 2, 0.0, H)
    for h in fh:
        do_opening("front", h)
    for plane, uvf in (("right", side_r_uv), ("left", side_l_uv)):
        wall_grid(plane, SPEC["side"], uvf, 0.0, D, 0.0, H)
        for h in SPEC["side"]:
            do_opening(plane, h)
    wall_grid("back", [], lambda u, z: uv_of("side", (u + W / 2) / W * 0.9 + 0.05, 1 - z / H), -W / 2, W / 2, 0.0, H)


def courses(proj=0.09):
    for zc in SPEC["courses"]:
        aabox(-W / 2 - 0.04, W / 2 + 0.04, -proj, 0.0, zc - 0.10, zc + 0.10, {"-y": "trim", "+z": "trim", "-z": "wall_dark", "+x": "trim", "-x": "trim"})


def cornice(z=None, big=True):
    z = H if z is None else z
    f = {"cornice": "cornice", "soffit": "soffit"}
    aabox(-W / 2 - 0.2, W / 2 + 0.2, -0.20, 0.0, z - 0.24, z - 0.10, {"-y": "cornice", "+z": "cornice", "-z": "soffit", "+x": "cornice", "-x": "cornice"})
    aabox(-W / 2 - 0.34, W / 2 + 0.34, -0.34, 0.0, z - 0.10, z, {"-y": "cornice", "+z": "cornice", "-z": "soffit", "+x": "cornice", "-x": "cornice"})
    for sx in (1, -1):
        x = sx * W / 2
        aabox(min(x, x + sx * 0.2), max(x, x + sx * 0.2), 0, D, z - 0.24, z - 0.10, fcs("cornice", skip=("-y", "+y")))
        aabox(min(x, x + sx * 0.34), max(x, x + sx * 0.34), 0, D, z - 0.10, z, fcs("cornice", skip=("-y", "+y")))


def awnings(holes, z_top=2.95, z_low=2.42, proj=1.25, kinds=("shop",)):
    for h in holes:
        if h["kind"] not in kinds:
            continue
        x0, x1 = h["x0"] - 0.25, h["x1"] + 0.25
        w = x1 - x0
        quad_tex([(x0, -0.04, z_top), (x1, -0.04, z_top), (x1, -proj, z_low), (x0, -proj, z_low)], "awning", (0, -0.5, 1), fxs=(0, 1, 1, 0), fys=(0, 0, 1, 1))
        vb = z_low - 0.22
        quad_tex([(x0, -proj, vb), (x1, -proj, vb), (x1, -proj, z_low), (x0, -proj, z_low)], "awning", (0, -1, 0))
        n = max(5, int(w / 0.45))
        for i in range(n):
            a, b = x0 + w * i / n, x0 + w * (i + 1) / n
            poly([(a, -proj, vb), (b, -proj, vb), ((a + b) / 2, -proj, vb - 0.14)], [uv_of("awning", i / n, .5), uv_of("awning", (i + 1) / n, .5), uv_of("awning", (i + .5) / n, .5)], (0, -1, 0))
        for sx, nx in ((x0, -1), (x1, 1)):
            flatpoly([(sx, -0.04, z_top), (sx, -proj, z_low), (sx, -proj, vb), (sx, -0.04, z_low)], "awn_side", (nx, 0, 0))
        flatpoly([(x0, -0.04, z_top - 0.03), (x0, -proj, z_low - 0.03), (x1, -proj, z_low - 0.03), (x1, -0.04, z_top - 0.03)], "soffit", (0, 0.4, -1))


# ------------------------------------------------------------------ roofs
def hip_roof(over, pitch, name_cap="ridge", eave_h=None, cx=0.0, y0=0.0, y1=None, hw=None):
    y1 = D if y1 is None else y1
    hw = W / 2 if hw is None else hw
    tp, cp = math.tan(math.radians(pitch)), math.cos(math.radians(pitch))
    zs = H if eave_h is None else eave_h
    ze = zs + 0.16
    xa, xb, ya, yb = cx - hw - over, cx + hw + over, y0 - over, y1 + over
    a, b = (xb - xa) / 2, (yb - ya) / 2
    s = min(a, b)
    zr = ze + s * tp
    mx, my = (xa + xb) / 2, (ya + yb) / 2
    if a >= b:
        R0, R1 = (mx - (a - s), my, zr), (mx + (a - s), my, zr)
    else:
        R0, R1 = (mx, my - (b - a), zr), (mx, my + (b - a), zr)
    e00, e10, e11, e01 = (xa, ya, ze), (xb, ya, ze), (xb, yb, ze), (xa, yb, ze)
    ppm = min(40.0, 500.0 / max(xb - xa, yb - ya), 232.0 / (min(a, b) / cp))
    def face(pts, e0, e1):
        d = norm((e1[0] - e0[0], e1[1] - e0[1], 0))
        nrm = (-d[1], d[0])
        uvs = []
        for p in pts:
            u = (p[0] - e0[0]) * d[0] + (p[1] - e0[1]) * d[1]
            v = abs((p[0] - e0[0]) * nrm[0] + (p[1] - e0[1]) * nrm[1]) / cp
            uvs.append(uv_of("roof", min(u * ppm / 510.0, 1.0) if False else (u * ppm) / RECTS["roof"][2], (v * ppm) / RECTS["roof"][3]))
        c = (sum(p[0] for p in pts) / len(pts) - mx, sum(p[1] for p in pts) / len(pts) - my, 1.0)
        poly(pts, uvs, (c[0], c[1], 1.2))
    if a >= b:
        face([e00, e10, R1, R0], e00, e10); face([e11, e01, R0, R1], e11, e01)
        face([e10, e11, R1], e10, e11); face([e01, e00, R0], e01, e00)
    else:
        face([e00, e10, R1, R0] if False else [e00, e10, R0], e00, e10); face([e11, e01, R1], e11, e01)
        face([e10, e11, R1, R0], e10, e11); face([e01, e00, R0, R1], e01, e00)
    for (p, q, n) in ((e00, e10, (0, -1, 0)), (e11, e01, (0, 1, 0)), (e10, e11, (1, 0, 0)), (e01, e00, (-1, 0, 0))):
        flatpoly([(p[0], p[1], zs), (q[0], q[1], zs), (q[0], q[1], ze), (p[0], p[1], ze)], "fascia", n)
    flatpoly([(xa, ya, zs), (xb, ya, zs), (cx + hw, y0, zs), (cx - hw, y0, zs)], "soffit", (0, 0, -1))
    flatpoly([(xb, ya, zs), (xb, yb, zs), (cx + hw, y1, zs), (cx + hw, y0, zs)], "soffit", (0, 0, -1))
    flatpoly([(xb, yb, zs), (xa, yb, zs), (cx - hw, y1, zs), (cx + hw, y1, zs)], "soffit", (0, 0, -1))
    flatpoly([(xa, yb, zs), (xa, ya, zs), (cx - hw, y0, zs), (cx - hw, y1, zs)], "soffit", (0, 0, -1))

    def cap(p, q_):
        d = norm(sub(q_, p))
        bz = norm(sub((0, 0, 1), mul(d, dot((0, 0, 1), d))))
        by = cross(bz, d)
        ln = math.sqrt(dot(sub(q_, p), sub(q_, p)))
        box(add(mul(add(p, q_), 0.5), mul(bz, 0.04)), (ln + 0.1, 0.30, 0.20), {k: name_cap for k in ("+x", "-x", "+y", "-y", "+z")}, basis=(d, by, bz))
    if math.dist(R0, R1) > 0.01:
        cap(R0, R1)
    for e, R in ((e00, R0), (e10, R0 if a < b else R1), (e11, R1), (e01, R1 if a < b else R0)):
        cap(e, R)
    def rz(x, y):
        return ze + min(x - xa, xb - x, y - ya, yb - y) * tp
    return rz, zr


def chimney(cx, cy, rz, hh=1.5, w=0.76, name="chimney"):
    zt = rz(cx, cy) + hh
    aabox(cx - w / 2, cx + w / 2, cy - w / 2, cy + w / 2, rz(cx, cy) - 0.5, zt, fcs(name, skip=("-z",)))
    aabox(cx - w / 2 - 0.12, cx + w / 2 + 0.12, cy - w / 2 - 0.12, cy + w / 2 + 0.12, zt, zt + 0.12, fcs("trim", skip=("-z",)))
    for fx in (-0.17, 0.17):
        aabox(cx + fx - 0.09, cx + fx + 0.09, cy - 0.09, cy + 0.09, zt + 0.12, zt + 0.42, fcs("tile", skip=("-z",)))


def flat_roof(parapet):
    z0, z1 = H, H + parapet
    for (a, b, n) in (((-W / 2, 0), (W / 2, 0), (0, -1, 0)), ((W / 2, D), (-W / 2, D), (0, 1, 0))):
        flatpoly([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], "parapet", n)
    for sx in (1, -1):
        x = sx * W / 2
        flatpoly([(x, 0, z0), (x, D, z0), (x, D, z1), (x, 0, z1)], "parapet", (sx, 0, 0))
    # inner faces + cap
    t = 0.22
    flatpoly([(-W / 2 + t, t, z1), (W / 2 - t, t, z1), (W / 2 - t, t, z0), (-W / 2 + t, t, z0)], "parapet", (0, 1, 0))
    flatpoly([(W / 2 - t, D - t, z1), (-W / 2 + t, D - t, z1), (-W / 2 + t, D - t, z0), (W / 2 - t, D - t, z0)], "parapet", (0, -1, 0))
    for sx in (1, -1):
        x = sx * (W / 2 - t)
        flatpoly([(x, t, z1), (x, D - t, z1), (x, D - t, z0), (x, t, z0)], "parapet", (-sx, 0, 0))
    aabox(-W / 2 - 0.04, W / 2 + 0.04, -0.06, t, z1 - 0.0, z1 + 0.07, fcs("slab", skip=("-z",)))
    aabox(-W / 2 - 0.04, W / 2 + 0.04, D - t, D + 0.06, z1, z1 + 0.07, fcs("slab", skip=("-z",)))
    for sx in (1, -1):
        x = sx * (W / 2 - t / 2)
        aabox(x - (t + 0.08) / 2, x + (t + 0.08) / 2, t, D - t, z1, z1 + 0.07, fcs("slab", skip=("-z",)))
    flatpoly([(-W / 2 + t, t, z0 + 0.02), (W / 2 - t, t, z0 + 0.02), (W / 2 - t, D - t, z0 + 0.02), (-W / 2 + t, D - t, z0 + 0.02)], "concrete", (0, 0, 1))


def roof_equipment(n_tanks=2, stair=True):
    z = H + 0.03
    if stair:
        aabox(-W / 2 + 1.2, -W / 2 + 4.2, D - 5.2, D - 2.2, z, z + 2.7, {"-y": "wall", "+x": "wall", "-x": "wall", "+y": "wall", "+z": "slab"})
        aabox(-W / 2 + 2.0, -W / 2 + 3.0, D - 5.25, D - 5.2, z, z + 2.0, {"-y": "dark"})
    for i in range(n_tanks):
        cyl(W / 2 - 2.0 - i * 1.7, D - 3.5, z + 0.6, z + 2.0, 0.65, 10, "tank")
        for sx in (-0.45, 0.45):
            for sy in (-0.45, 0.45):
                aabox(W / 2 - 2.0 - i * 1.7 + sx - 0.04, W / 2 - 2.0 - i * 1.7 + sx + 0.04, D - 3.5 + sy - 0.04, D - 3.5 + sy + 0.04, z, z + 0.6, fcs("steel"))
    # solar heaters (tilted slabs) + antenna
    for i in range(2):
        cx = -1.0 + i * 1.7
        bz = norm((0, -0.5, 0.87)); bx = (1, 0, 0); by = cross(bz, bx)
        box((cx, D * 0.45, z + 0.55), (1.3, 1.8, 0.07), {"+z": "panel", "-z": "dark", "+x": "steel", "-x": "steel", "+y": "steel", "-y": "steel"}, basis=(bx, by, bz))
        aabox(cx - 0.05, cx + 0.05, D * 0.45 - 0.7, D * 0.45 - 0.5, z, z + 0.2, fcs("steel"))
    ax, ay = W / 2 - 3.0, 2.5
    aabox(ax - 0.03, ax + 0.03, ay - 0.03, ay + 0.03, z, z + 4.0, fcs("steel", skip=("-z",)))
    for k, zz in enumerate((2.6, 3.2, 3.7)):
        aabox(ax - 0.5 + k * 0.08, ax + 0.5 - k * 0.08, ay - 0.02, ay + 0.02, z + zz, z + zz + 0.04, fcs("steel"))
    for i in range(3):
        aabox(-W / 2 + 6.0 + i * 0.9, -W / 2 + 6.6 + i * 0.9, D - 3.2, D - 2.6, z, z + 0.55, {"-y": "ac", "+x": "ac", "-x": "ac", "+z": "ac", "+y": "ac"})


def slab_balcony(proj, par_h, full=True, rail="parapet", rail_top="slab", floors=None, x0=None, x1=None):
    x0 = -W / 2 if x0 is None else x0
    x1 = W / 2 if x1 is None else x1
    for f in (floors or range(1, SPEC["NF"] + 1)):
        z = SPEC["GF"] + (f - 1) * SPEC["FL"]
        aabox(x0 - 0.02, x1 + 0.02, -proj, 0.0, z - 0.18, z + 0.03, {"-y": "slab", "+z": "balcony_top", "-z": "soffit", "+x": "slab", "-x": "slab"})
        if par_h > 0:
            aabox(x0 - 0.02, x1 + 0.02, -proj, -proj + 0.14, z + 0.03, z + par_h, {"-y": rail, "+y": rail, "+z": rail_top, "+x": rail, "-x": rail})
            aabox(x0 - 0.04, x1 + 0.04, -proj - 0.03, -proj + 0.16, z + par_h - 0.1, z + par_h + 0.04, {"-y": rail_top, "+z": rail_top, "+x": rail_top, "-x": rail_top})
            for sx in (x0, x1):
                aabox(sx - 0.07, sx + 0.07, -proj, 0.0, z + 0.03, z + par_h, fcs(rail, skip=("-z",)))
        else:   # glass rail
            aabox(x0, x1, -proj, -proj + 0.05, z + 0.03, z + 0.95, {"-y": "glass_rail", "+y": "glass_rail"})
            aabox(x0, x1, -proj - 0.02, -proj + 0.06, z + 1.02, z + 1.08, fcs("steel"))
            for sx in (x0, x1):
                aabox(sx - 0.03, sx + 0.03, -proj, 0.0, z + 0.03, z + 1.05, {"+x": "glass_rail", "-x": "glass_rail"})


# ------------------------------------------------------------------ families
def fam_bazaar():
    shell()
    courses(); cornice()
    awnings(SPEC["holes"], z_top=3.38, z_low=2.85, proj=1.35, kinds=("shop",))
    awnings(SPEC["holes"], z_top=3.15, z_low=2.75, proj=0.9, kinds=("door",))
    f1 = SPEC["GF"]
    # two timber cumba (ahsap cikma) on floor 1
    for (xa, xb) in ((-5.0, -1.25), (1.25, 5.0)):
        z0, z1, dep = f1 - 0.02, f1 + 2.75, 0.8
        aabox(xa, xb, -dep, 0.0, z0, z1, {"+x": "wall_wood", "-x": "wall_wood", "-z": "soffit"})
        yf = -dep
        wy0, wy1 = f1 + 0.8, f1 + 2.4
        def q(a, b, za, zb, nm): flatpoly([(a, yf - 0.005, za), (b, yf - 0.005, za), (b, yf - 0.005, zb), (a, yf - 0.005, zb)], nm, (0, -1, 0))
        q(xa, xb, z0, wy0, "wood"); q(xa, xb, wy1, z1, "wood")
        n = 3; pw = (xb - xa - 0.4) / n; x_ = xa + 0.2
        q(xa, x_, wy0, wy1, "wood"); q(xb - 0.2, xb, wy0, wy1, "wood")
        for i in range(n):
            a, b = x_ + i * pw + 0.07, x_ + (i + 1) * pw - 0.07
            if i > 0:
                q(x_ + i * pw - 0.07, x_ + i * pw + 0.07, wy0, wy1, "wood")
            quad_tex([(a, yf + 0.08, wy0), (b, yf + 0.08, wy0), (b, yf + 0.08, wy1), (a, yf + 0.08, wy1)], "glass_win", (0, -1, 0))
            for xx, nm in ((a, 1), (b, -1)):
                flatpoly([(xx, yf, wy0), (xx, yf, wy1), (xx, yf + 0.08, wy1), (xx, yf + 0.08, wy0)], "jamb", (nm, 0, 0))
            for zz, nm in ((wy1, -1), (wy0, 1)):
                flatpoly([(a, yf, zz), (b, yf, zz), (b, yf + 0.08, zz), (a, yf + 0.08, zz)], "jamb", (0, 0, nm))
            for sx in (a, b - 0.05):
                aabox(sx, sx + 0.05, yf - 0.025, yf + 0.08, wy0, wy1, fcs("frame"))
            aabox(a, b, yf - 0.025, yf + 0.08, wy1 - 0.05, wy1, fcs("frame"))
        for cx in (xa + 0.45, (xa + xb) / 2, xb - 0.45):
            aabox(cx - 0.1, cx + 0.1, -0.5, 0.0, z0 - 0.50, z0 - 0.02, fcs("wood"))   # corbels
        aabox(xa - 0.04, xb + 0.04, -dep - 0.05, 0.0, z0 - 0.14, z0, fcs("wood"))
        xr0, xr1, yr = xa - 0.1, xb + 0.1, -dep - 0.2
        flatpoly([(xr0, yr, z1), (xr1, yr, z1), (xr1, 0.0, z1 + 0.45), (xr0, 0.0, z1 + 0.45)], "tile", (0, -0.5, 1))
        flatpoly([(xr0, yr, z1), (xr0, 0, z1 + 0.45), (xr0, 0, z1)], "fascia", (-1, 0, 0))
        flatpoly([(xr1, yr, z1), (xr1, 0, z1), (xr1, 0, z1 + 0.45)], "fascia", (1, 0, 0))
        flatpoly([(xr0, yr, z1 - 0.12), (xr1, yr, z1 - 0.12), (xr1, yr, z1), (xr0, yr, z1)], "fascia", (0, -1, 0))
    rz, _ = hip_roof(0.6, 22.0)
    chimney(-2.0, 7.5, rz); chimney(2.6, 8.8, rz, 1.2)
    aabox(W / 2 - 0.16, W / 2 - 0.07, -0.13, -0.04, 0.0, H - 0.3, fcs("steel"))


def fam_mid():
    shell()
    courses(); cornice(SPEC["H"] - 0.0) if False else None
    awnings(SPEC["holes"], z_top=3.0, z_low=2.55, proj=1.2, kinds=("shop",))
    slab_balcony(SPEC["balcony"]["proj"], SPEC["balcony"]["par"])
    # roof: a,b flat with equipment; c low hip
    if VAR == "c":
        cornice()
        rz, _ = hip_roof(0.6, 20.0)
        chimney(-2.0, 9.0, rz); chimney(3.0, 6.5, rz, 1.2)
    else:
        flat_roof(SPEC["roof"]["parapet"])
        roof_equipment(2, True)
    aabox(W / 2 - 0.16, W / 2 - 0.07, -SPEC["balcony"]["proj"] - 0.1, -SPEC["balcony"]["proj"] - 0.01, 0.0, H - 0.4, fcs("steel"))


def fam_late():
    shell()
    awnings(SPEC["holes"], z_top=3.25, z_low=2.8, proj=1.0, kinds=("shop",))
    slab_balcony(SPEC["balcony"]["proj"], 0.0)
    flat_roof(SPEC["roof"]["parapet"])
    roof_equipment(3, True)
    # vertical fins between bays on the upper part (shadow lines)
    for x in (-7.0, -4.2, -1.4, 1.4, 4.2, 7.0):
        if abs(x) >= W / 2:
            continue
        aabox(x - 0.1, x + 0.1, -0.30, 0.0, SPEC["GF"], H, fcs("stonecap", skip=("-z", "+z")))


def fam_house():
    shell()
    courses(0.07)
    zs = H
    # porch canopy over door
    aabox(-1.1, 1.1, -1.1, 0.0, 2.55, 2.67, {"-y": "wall", "+z": "tile", "-z": "soffit", "+x": "wall", "-x": "wall"})
    for sx in (-0.95, 0.95):
        aabox(sx - 0.07, sx + 0.07, -1.0, -0.86, 0.0, 2.55, fcs("wood"))
    rz, _ = hip_roof(0.5, 28.0)
    chimney(-1.6, 5.0, rz, 1.3, 0.7)
    for h in SPEC["holes"]:
        pass
    # garden: gravel yard, wall, gate posts, hedges, tree planter, path
    yd = 3.8
    flatpoly([(-5.0, -yd, 0.02), (5.0, -yd, 0.02), (5.0, 0.0, 0.02), (-5.0, 0.0, 0.02)], "gravel", (0, 0, 1))
    flatpoly([(-0.6, -yd, 0.035), (0.6, -yd, 0.035), (0.6, -0.05, 0.035), (-0.6, -0.05, 0.035)], "concrete", (0, 0, 1))
    wh, t = 1.3, 0.25
    for (a, b) in ((-5.0, -0.8), (0.8, 5.0)):
        aabox(a, b, -yd - t / 2, -yd + t / 2, 0.0, wh, {"-y": "wall", "+y": "wall", "+z": "stonecap", "+x": "wall", "-x": "wall"})
        aabox(a - 0.04, b + 0.04, -yd - t / 2 - 0.03, -yd + t / 2 + 0.03, wh, wh + 0.1, fcs("stonecap", skip=("-z",)))
    for sx in (-5.0, 5.0):
        aabox(sx - t / 2, sx + t / 2, -yd, 0.0, 0.0, wh, {"+x": "wall", "-x": "wall", "+z": "stonecap"})
    for sx in (-0.8, 0.8):
        aabox(sx - 0.18, sx + 0.18, -yd - 0.18, -yd + 0.18, 0.0, 1.7, fcs("stonecap", skip=("-z",)))
    aabox(-5.0 + t, -0.9, -yd + t, -yd + t + 0.5, 0.0, 0.8, fcs("hedge", skip=("-z",)))
    aabox(0.9, 5.0 - t, -yd + t, -yd + t + 0.5, 0.0, 0.8, fcs("hedge", skip=("-z",)))
    cyl(-3.0, -1.9, 0.0, 0.3, 0.95, 10, "stonecap", "earth")


def fam_ind():
    shell(front_holes=SPEC["holes"])
    hw = W / 2
    over = 0.5
    # dock platform + steps + canopy
    aabox(2.2, 7.9, -3.0, 0.0, 0.0, 1.25, {"-y": "concrete", "+x": "concrete", "-x": "concrete", "+z": "concrete"})
    aabox(1.0, 2.2, -3.0, -1.2, 0.0, 0.5, fcs("concrete", skip=("-z",)))
    aabox(2.4, 5.8, -2.2, 0.0, 3.85, 3.95, {"-y": "steel", "+z": "steel", "-z": "soffit"})
    pitch = 14.0
    tp = math.tan(math.radians(pitch))
    ze = H + 0.14
    xo = hw + over
    ya, yb = -over, D + over
    barrel = (VAR == "b")
    rise = hw * tp + 0.14
    if not barrel:
        zr = ze + xo * tp
        # gable end walls (front/back) as 'sheet' triangles
        for (y, n) in ((0.0, (0, -1, 0)), (D, (0, 1, 0))):
            poly([(-hw, y, H), (hw, y, H), (0, y, H + hw * tp)], [uv_of("sheet", 0, 1), uv_of("sheet", 1, 1), uv_of("sheet", .5, 0)], n)
        for sx in (1, -1):
            pts = [(sx * xo, ya, ze), (sx * xo, yb, ze), (0, yb, zr), (0, ya, zr)]
            flatpoly(pts, "roofm", (sx * 0.5, 0, 1))
            for k in range(int(D / 1.2) + 1):
                y = ya + k * (yb - ya) / (int(D / 1.2))
                aabox(sx * xo * 0.5 - 0.04 * 0 - 0.03, sx * xo * 0.5 + 0.03, y - 0.03, y + 0.03, 0, 0, {}) if False else None
            for k in range(0, 18):
                x = sx * xo * (k / 18.0)
                z = ze + (xo - abs(x)) * tp * 1.0
                zz = ze + (xo - abs(x)) * tp
                aabox(x - 0.03, x + 0.03, ya, yb, zz, zz + 0.07, fcs("steel", skip=("-z", "+x", "-x"))) if False else aabox(x - 0.03, x + 0.03, ya, yb, zz, zz + 0.06, {"+z": "roofm", "+y": "roofm", "-y": "roofm"})
        # eave fascia
        for sx in (1, -1):
            aabox(sx * xo - 0.04, sx * xo + 0.04, ya, yb, H, ze, fcs("fascia", skip=("-z", "+z")))
        aabox(-0.1, 0.1, ya, yb, zr, zr + 0.12, fcs("steel", skip=("-z",)))
        rooftop = zr
    else:
        n = 10
        pts = []
        for i in range(n + 1):
            a = math.pi * i / n
            pts.append((-hw - 0.2 + (W + 0.4) * (1 - math.cos(a)) / 2, 2.6 * math.sin(a)))
        for (y, nn) in ((0.0, (0, -1, 0)), (D, (0, 1, 0))):
            poly([(p[0], y, H - 0.0 + p[1] * 0.0 + p[1]) for p in pts] if False else [(p[0], y, H + p[1]) for p in pts], [uv_of("sheet", (p[0] + hw + 0.2) / (W + 0.4), 1 - p[1] / 2.6) for p in pts], nn)
        for i in range(n):
            (x0_, z0_), (x1_, z1_) = pts[i], pts[i + 1]
            amid = (x0_ + x1_) / 2 - 0.0
            flatpoly([(x0_, -0.3, H + z0_ + 0.12), (x1_, -0.3, H + z1_ + 0.12), (x1_, D + 0.3, H + z1_ + 0.12), (x0_, D + 0.3, H + z0_ + 0.12)], "roofm", (0, 0, 1) if i not in (0,) else (-1, 0, 1))
        rooftop = H + 2.8
    # clerestory etc handled by holes. Chimney stack (brick) at back corner
    aabox(5.6, 6.8, 20.0, 21.2, 0.0, 15.0, {"-y": "brick", "+y": "brick", "+x": "brick", "-x": "brick"})
    aabox(5.45, 6.95, 19.85, 21.35, 15.0, 15.35, fcs("stonecap", skip=("-z",)))
    # yard: concrete apron, fence, pallets, containers
    flatpoly([(-hw - 3.0, -9.0, 0.02), (hw + 3.0, -9.0, 0.02), (hw + 3.0, 0.0, 0.02), (-hw - 3.0, 0.0, 0.02)], "concrete", (0, 0, 1))
    for k in range(0, 22):
        x = -hw - 3.0 + k * (W + 6.0) / 21.0
        aabox(x - 0.04, x + 0.04, -9.04, -8.96, 0.0, 1.8, fcs("steel", skip=("-z",)))
    aabox(-hw - 3.0, hw + 3.0, -9.04, -8.96, 1.75, 1.8, fcs("steel"))
    aabox(-hw - 3.0, hw + 3.0, -9.04, -8.96, 0.9, 0.94, fcs("steel"))
    for (x, y, rows) in ((-6.0, -3.8, 3), (-4.6, -3.8, 2), (-6.0, -6.2, 2), (-3.6, -6.4, 3)):
        for r in range(rows):
            aabox(x - 0.6, x + 0.6, y - 0.5, y + 0.5, 0.02 + r * 0.16, 0.14 + r * 0.16, {"-y": "pallet", "+y": "pallet", "+x": "pallet", "-x": "pallet", "+z": "wood"})
            aabox(x - 0.55, x + 0.55, y - 0.45, y + 0.45, 0.14 + r * 0.16, 0.14 + r * 0.16 + 0.0, {})
        aabox(x - 0.5, x + 0.5, y - 0.4, y + 0.4, 0.02 + rows * 0.16, 0.02 + rows * 0.16 + 0.9, {"-y": "sheet", "+y": "sheet", "+x": "sheet", "-x": "sheet", "+z": "slab"})
    aabox(hw - 6.4, hw - 0.4, -8.2, -5.7, 0.02, 2.62, {"-y": "cont_a", "+y": "cont_a", "+x": "cont_a", "-x": "cont_a", "+z": "cont1f"})
    aabox(hw - 6.4, hw - 0.4, -5.5, -3.2 - 0.0, 0.02, 2.62, {"-y": "cont_b", "+y": "cont_b", "+x": "cont_b", "-x": "cont_b", "+z": "cont2f"})
    aabox(hw - 6.4, hw - 0.4, -8.2, -5.7, 2.62, 5.22, {"-y": "cont_b", "+y": "cont_b", "+x": "cont_b", "-x": "cont_b", "+z": "cont2f"}) if VAR == "c" else None


def fam_civic():
    pav = SPEC["holes_pav"]
    main = [h for h in SPEC["holes"] if h not in pav]
    px0, px1, py = -3.5, 3.5, 1.1
    # main front wall: remove pavilion span (wall hidden behind it)
    wall_grid("front", main, frontuv, -W / 2, W / 2, 0.0, H)
    for h in main:
        do_opening("front", h)
        if h["kind"] == "win" and h.get("shut") == "open":
            pass
    for plane, uvf in (("right", side_r_uv), ("left", side_l_uv)):
        wall_grid(plane, SPEC["side"], uvf, 0.0, D, 0.0, H)
        for h in SPEC["side"]:
            do_opening(plane, h)
    wall_grid("back", [], lambda u, z: uv_of("side", (u + W / 2) / W * 0.9 + 0.05, 1 - z / H), -W / 2, W / 2, 0.0, H)
    # pavilion: projecting block (front plane at y=-py)
    wall_grid("front", pav, lambda u, z: frontuv(u, z), px0, px1, 0.0, H, off=py)
    for h in pav:
        do_opening("front", h, off=py)
    for sx, nx in ((px0, -1), (px1, 1)):
        flatpoly([(sx, -py, 0), (sx, 0, 0), (sx, 0, H), (sx, -py, H)], "wall", (nx, 0, 0))
    # string courses on wings, cornice
    courses()
    cornice()
    aabox(px0 - 0.3, px1 + 0.3, -py - 0.3, 0.0, H - 0.24, H, {"-y": "cornice", "+z": "cornice", "-z": "soffit", "+x": "cornice", "-x": "cornice"})
    # pediment
    ph = 1.7
    flatpoly([(px0 - 0.3, -py - 0.3, H), (px1 + 0.3, -py - 0.3, H), (0, -py - 0.3, H + ph)], "trim", (0, -1, 0))
    flatpoly([(px0 + 0.3, -py - 0.32, H + 0.12), (px1 - 0.3, -py - 0.32, H + 0.12), (0, -py - 0.32, H + ph - 0.45)], "wall_dark", (0, -1, 0))
    for sx in (-1, 1):
        flatpoly([(sx * (px1 + 0.3), -py - 0.3, H), (0, -py - 0.3, H + ph), (0, 0.5, H + ph), (sx * (px1 + 0.3), 0.5, H)], "tile", (-sx * 0.4, -0.3, 1))
    # portico: steps + columns + entablature
    for k in range(3):
        aabox(px0 + 0.4 - k * 0.2, px1 - 0.4 + k * 0.2, -py - 1.0 - 0.0 + 0.3 * k * 0 - (2 - k) * 0.3, -py + 0.0, 0.0, 0.17 * (3 - k) + 0.0, fcs("step", skip=("-z",)))
    for cx in (-3.0, -1.0, 1.0, 3.0):
        cyl(cx, -py - 0.9, 0.5, 4.4, 0.24, 8, "trim")
        aabox(cx - 0.32, cx + 0.32, -py - 0.9 - 0.32, -py - 0.9 + 0.32, 4.4, 4.55, fcs("stonecap", skip=("-z",)))
        aabox(cx - 0.32, cx + 0.32, -py - 0.9 - 0.32, -py - 0.9 + 0.32, 0.4, 0.55, fcs("stonecap", skip=("-z",)))
    aabox(px0 - 0.1, px1 + 0.1, -py - 1.3, -py + 0.0, 4.55, 5.1, {"-y": "trim", "+z": "trim", "-z": "soffit", "+x": "trim", "-x": "trim"})
    aabox(px0 - 0.1, px1 + 0.1, -py - 1.3, -py - 1.1, 5.1, 5.7, {"-y": "trim", "+z": "trim", "+x": "trim", "-x": "trim"})
    # hip roof over wings + tower
    rz, zr = hip_roof(0.7, 18.0)
    # clock tower (v0 spec 4 section: ~23 m total, 4 stages + cap) centred behind pavilion
    cy = 5.0
    z = H - 0.2
    stages = [(4.5, 4.5, 4.4, "stone", "wall"), (4.0, 4.0, 3.0, "wall", "wall"), (4.2, 4.2, 2.9, "stonecap", "trim")]
    for (sx, sy, hh, nm, nm2) in stages:
        aabox(-sx / 2, sx / 2, cy - sy / 2, cy + sy / 2, z, z + hh, {k: nm2 for k in ("+x", "-x", "+y", "-y")} | {"+z": "trim"})
        aabox(-sx / 2 - 0.1, sx / 2 + 0.1, cy - sy / 2 - 0.1, cy + sy / 2 + 0.1, z + hh - 0.15, z + hh, fcs("stonecap", skip=("-z",)))
        z += hh
    zc0 = z - 2.9
    d = 2.1 + 0.02
    for (ax, ay, nrm, rot) in ((0, -d, (0, -1, 0), 0), (0, d + 2 * cy - 2 * 0.0 - 0.0, (0, 1, 0), 0)):
        pass
    cl = 1.8
    zc = zc0 + 1.45
    quad_tex([(-cl / 2, cy - 2.1 - 0.03, zc - cl / 2), (cl / 2, cy - 2.1 - 0.03, zc - cl / 2), (cl / 2, cy - 2.1 - 0.03, zc + cl / 2), (-cl / 2, cy - 2.1 - 0.03, zc + cl / 2)], "clock", (0, -1, 0))
    quad_tex([(cl / 2, cy + 2.1 + 0.03, zc - cl / 2), (-cl / 2, cy + 2.1 + 0.03, zc - cl / 2), (-cl / 2, cy + 2.1 + 0.03, zc + cl / 2), (cl / 2, cy + 2.1 + 0.03, zc + cl / 2)], "clock", (0, 1, 0))
    quad_tex([(2.1 + 0.03, cy - cl / 2, zc - cl / 2), (2.1 + 0.03, cy + cl / 2, zc - cl / 2), (2.1 + 0.03, cy + cl / 2, zc + cl / 2), (2.1 + 0.03, cy - cl / 2, zc + cl / 2)], "clock", (1, 0, 0))
    quad_tex([(-2.1 - 0.03, cy + cl / 2, zc - cl / 2), (-2.1 - 0.03, cy - cl / 2, zc - cl / 2), (-2.1 - 0.03, cy - cl / 2, zc + cl / 2), (-2.1 - 0.03, cy + cl / 2, zc + cl / 2)], "clock", (-1, 0, 0))
    # tower slit windows on mid stage
    zm = H - 0.2 + 4.4
    for sx in (-0.5, 0.5):
        aabox(sx - 0.18, sx + 0.18, cy - 2.0 - 0.04, cy - 2.0, zm + 0.6, zm + 2.2, fcs("dark", skip=("-z",)))
    # cap pyramid + finial
    s = 2.3
    base = z
    for (a, b, nrm) in (((-s, cy - s), (s, cy - s), (0, -1, 0.5)), ((s, cy - s), (s, cy + s), (1, 0, 0.5)), ((s, cy + s), (-s, cy + s), (0, 1, 0.5)), ((-s, cy + s), (-s, cy - s), (-1, 0, 0.5))):
        flatpoly([(a[0], a[1], base), (b[0], b[1], base), (0, cy, base + 1.6)], "tile", nrm)
    aabox(-0.06, 0.06, cy - 0.06, cy + 0.06, base + 1.6, base + 2.3, fcs("steel", skip=("-z",)))


FAM = dict(bazaar=fam_bazaar, res_mid=fam_mid, res_late=fam_late, house=fam_house, industrial=fam_ind, civic=fam_civic)


def build():
    FAM[arg["family"]]()
    name = "bld_hero_" + arg["family"] + "_" + VAR
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(V, [], F)
    mesh.update()
    uvl = mesh.uv_layers.new(name="UVMap")
    for p in mesh.polygons:
        p.use_smooth = False
        for li in p.loop_indices:
            uvl.data[li].uv = UV[mesh.loops[li].vertex_index]
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("mat_hero_atlas")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    img = bpy.data.images.load(os.path.abspath(arg["atlas"]))
    img.colorspace_settings.name = "sRGB"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    for nm in ("Specular IOR Level", "Specular"):
        if nm in bsdf.inputs:
            bsdf.inputs[nm].default_value = 0.0
    mesh.materials.append(mat)
    xs = [p[0] for p in V]; ys = [p[1] for p in V]; zs = [p[2] for p in V]
    print("HERO_TRIS", sum(len(f) - 2 for f in F), "BBOX", round(min(xs), 2), round(max(xs), 2), round(min(ys), 2), round(max(ys), 2), round(max(zs), 2))
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(arg["out"]), export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_image_format="AUTO")


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
build()
