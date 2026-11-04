"""T-053 hero building generator (Blender headless, bpy). One textured surface, flat shaded, metres, origin ground centre of footprint.

  Blender --background --factory-startup --python art/blender/hero/hero_building.py -- \
      --atlas assets/hero/hero_atlas_a.png --layout assets/hero/hero_atlas_layout.json --out assets/hero/hero_a.glb
Deterministic: no randomness. Geometry is variant-independent; the variant lives in the atlas PNG.
"""
import json
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_layout as L  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
arg = {argv[i].lstrip("-"): argv[i + 1] for i in range(0, len(argv) - 1, 2)}
LAYOUT = json.load(open(arg["layout"]))
SZ = float(LAYOUT["size"])
RECTS = LAYOUT["rects"]
TEXTURED = {"shutter", "glass_win", "glass_shop", "kepenk", "awning", "door", "front", "side", "roof"}

V, UV, F = [], [], []   # unshared verts -> flat shading


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
    """pts CCW seen from outside; if `want` normal given, auto-fix winding."""
    if want is not None:
        n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
        if dot(n, want) < 0:
            pts, uvs = pts[::-1], uvs[::-1]
    i = len(V)
    V.extend(pts)
    UV.extend(uvs)
    F.append(tuple(range(i, i + len(pts))))


def flatpoly(pts, name, want=None):
    poly(pts, [uv_of(name, .5, .5)] * len(pts), want)


def quad_tex(p, name, want, fxs=(0, 1, 1, 0), fys=(1, 1, 0, 0)):
    poly(p, [uv_of(name, fxs[k], fys[k]) for k in range(4)], want)


def box(c, size, faces, basis=((1, 0, 0), (0, 1, 0), (0, 0, 1))):
    """faces: dict '+x','-x','+y','-y','+z','-z' -> swatch/texture name. Oriented box (basis bx,by,bz unit)."""
    bx, by, bz = basis
    h = (size[0] / 2, size[1] / 2, size[2] / 2)
    ax = {"x": (bx, h[0]), "y": (by, h[1]), "z": (bz, h[2])}
    spec = {"+x": ("x", "y", "z", 1), "-x": ("x", "z", "y", -1), "+y": ("y", "z", "x", 1), "-y": ("y", "x", "z", -1),
            "+z": ("z", "x", "y", 1), "-z": ("z", "y", "x", -1)}
    for key, name in faces.items():
        n_ax, t1, t2, sgn = spec[key]
        n = mul(ax[n_ax][0], sgn)
        ctr = add(c, mul(n, ax[n_ax][1]))
        v1, h1 = ax[t1]
        v2, h2 = ax[t2]
        pts = []
        for s1, s2 in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            pts.append(add(ctr, add(mul(v1, s1 * h1), mul(v2, s2 * h2))))
        if name in TEXTURED:
            # fx along t1, fy from top: flip so +t2 is up
            quad_tex(pts, name, n, fxs=(0, 1, 1, 0), fys=(1, 1, 0, 0))
        else:
            flatpoly(pts, name, n)


def aabox(x0, x1, y0, y1, z0, z1, faces):
    box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), faces)


ALL = ("+x", "-x", "+y", "-y", "+z", "-z")
def fcs(name, skip=()): return {k: name for k in ALL if k not in skip}


# ---------------------------------------------------------------- walls with holes
def wall_grid(plane, holes, uvfn, W0, W1, hm):
    """plane 'front' (y=0 normal -Y), 'right' (x=+W/2 normal +X), 'left', 'back'. Holes in (u0,u1,z0,z1) along the plane's u."""
    us = sorted({W0, W1} | {h["x0"] for h in holes} | {h["x1"] for h in holes})
    zs = sorted({0.0, hm} | {h["z0"] for h in holes} | {h["z1"] for h in holes})
    for i in range(len(us) - 1):
        for j in range(len(zs) - 1):
            ucx, zcz = (us[i] + us[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
            if any(h["x0"] < ucx < h["x1"] and h["z0"] < zcz < h["z1"] for h in holes):
                continue
            ps, uvs = [], []
            for (uu, zz) in ((us[i], zs[j]), (us[i + 1], zs[j]), (us[i + 1], zs[j + 1]), (us[i], zs[j + 1])):
                ps.append(to3d(plane, uu, zz))
                uvs.append(uvfn(uu, zz))
            poly(ps, uvs, NORMALS[plane])


NORMALS = {"front": (0, -1, 0), "right": (1, 0, 0), "left": (-1, 0, 0), "back": (0, 1, 0)}


def to3d(plane, u, z, off=0.0):
    if plane == "front": return (u, off, z)
    if plane == "back": return (u, L.D - off, z)
    if plane == "right": return (L.W / 2 - off, u, z)
    return (-L.W / 2 + off, u, z)


def frontuv(u, z): return uv_of("front", (u + L.W / 2) / L.W, 1 - z / L.H)
def side_r_uv(u, z): return uv_of("side", u / L.D, 1 - z / L.H)
def side_l_uv(u, z): return uv_of("side", 1 - u / L.D, 1 - z / L.H)


def opening(plane, h, depth, glass, frame_w=0.06, sill=True, shut=None, frame="frame", base_off=0.0):
    """reveal + glass + frame sticks (+ sill) for a hole. Coordinates along plane u. depth = reveal depth (into the wall)."""
    n = NORMALS[plane]
    inward = mul(n, -1)
    u0, u1, z0, z1 = h["x0"], h["x1"], h["z0"], h["z1"]
    def P(u, z, d): return add(to3d(plane, u, z, base_off), mul(inward, d))
    # jambs / head / sill reveal (face into opening)
    for (a, b, c_, d_, wn) in (
        ((u0, z0), (u0, z1), (u1, z1), (u1, z0), None),
    ):
        pass
    side_pairs = [
        ((u0, z0), (u0, z1), (1, 0)),   # left jamb
        ((u1, z0), (u1, z1), (-1, 0)),  # right jamb
    ]
    for (pa, pb, dirn) in side_pairs:
        pts = [P(pa[0], pa[1], 0), P(pb[0], pb[1], 0), P(pb[0], pb[1], depth), P(pa[0], pa[1], depth)]
        wn = to_world_dir(plane, dirn[0], 0)
        flatpoly(pts, "jamb", wn)
    for (zz, dz) in ((z1, -1), (z0, 1)):
        pts = [P(u0, zz, 0), P(u1, zz, 0), P(u1, zz, depth), P(u0, zz, depth)]
        flatpoly(pts, "jamb" if dz < 0 else "sill", (0, 0, dz))
    # glass
    gp = [P(u0, z0, depth), P(u1, z0, depth), P(u1, z1, depth), P(u0, z1, depth)]
    quad_tex(gp, glass, n)
    # frame sticks (box in plane space)
    fd = 0.10
    def stick(a0, a1, b0, b1):
        pa, pb = P(a0, b0, depth - fd), P(a1, b1, depth)
        lo = (min(pa[0], pb[0]), min(pa[1], pb[1]), min(pa[2], pb[2]))
        hi = (max(pa[0], pb[0]), max(pa[1], pb[1]), max(pa[2], pb[2]))
        aabox(lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], fcs(frame, skip=("-z",)) if False else fcs(frame))
    fw = frame_w
    if glass != "glass_shop":
        stick(u0, u0 + fw, z0, z1); stick(u1 - fw, u1, z0, z1)
        stick(u0, u1, z1 - fw, z1); stick(u0, u1, z0, z0 + fw)
    return


def to_world_dir(plane, du, dz):
    if plane == "front": return (du, 0, dz)
    if plane == "back": return (-du, 0, dz)
    if plane == "right": return (0, du, dz)
    return (0, du, dz)


def sill_box(h, plane="front", proj=0.12):
    assert plane == "front"
    aabox(h["x0"] - 0.08, h["x1"] + 0.08, -proj, 0.05, h["z0"] - 0.07, h["z0"], fcs("sill"))


def shutters(h, mode):
    if mode == "none":
        return
    w, z0, z1 = h["x1"] - h["x0"], h["z0"], h["z1"]
    lw = w / 2
    y0, y1 = -0.05, -0.012
    def leaf(xa, xb):
        aabox(xa, xb, y0, y1, z0 - 0.02, z1 + 0.02, {"-y": "shutter", "+x": "frame", "-x": "frame", "+z": "shutter", "-z": "shutter"} if False else
              {"-y": "shutter", "+x": "wall_dark", "-x": "wall_dark", "+z": "wall_dark"})
    cx = (h["x0"] + h["x1"]) / 2
    if mode == "open":
        leaf(h["x0"] - lw, h["x0"] - 0.01); leaf(h["x1"] + 0.01, h["x1"] + lw)
    elif mode == "closed":
        leaf(h["x0"] - 0.03, cx - 0.01); leaf(cx + 0.01, h["x1"] + 0.03)
    else:  # half: one leaf open one closed
        leaf(h["x0"] - lw, h["x0"] - 0.01); leaf(cx + 0.01, h["x1"] + 0.03)


# ---------------------------------------------------------------- front facade
def facade():
    holes = L.front_holes()
    wall_grid("front", holes, frontuv, -L.W / 2, L.W / 2, L.H)
    for h in holes:
        k = h["kind"]
        if k == "shop":
            opening("front", h, 0.30, "glass_shop", frame_w=0.09, sill=False, frame="wood_dark")
            aabox(h["x0"] - 0.0, h["x1"], -0.02, 0.30, h["z0"] - 0.05, h["z0"], fcs("wood_dark"))
            # mullion
            cx = (h["x0"] + h["x1"]) / 2
            aabox(cx - 0.04, cx + 0.04, 0.17, 0.26, h["z0"], h["z1"], fcs("wood_dark"))
        elif k == "door":
            n = (0, -1, 0)
            # recessed door slab + transom
            opening("front", h, 0.28, "door", frame_w=0.07, frame="wood_dark")
            aabox(h["x0"] - 0.15, h["x1"] + 0.15, -0.22, 0.04, 0.0, 0.18, fcs("step"))   # step
        else:
            opening("front", h, 0.20, "glass_win")
            if k == "win":
                sill_box(h)
            shutters(h, h.get("shut", "none"))


def string_courses():
    for zc in L.STRING_COURSES:
        aabox(-L.W / 2 - 0.04, L.W / 2 + 0.04, -0.09, 0.0, zc - 0.10, zc + 0.10, {"-y": "trim", "+z": "trim", "-z": "wall_dark", "+x": "trim", "-x": "trim"})


def cornice():
    H = L.H
    aabox(-L.W / 2 - 0.2, L.W / 2 + 0.2, -0.20, 0.0, H - 0.24, H - 0.10, {"-y": "cornice", "+z": "cornice", "-z": "soffit", "+x": "cornice", "-x": "cornice"})
    aabox(-L.W / 2 - 0.34, L.W / 2 + 0.34, -0.34, 0.0, H - 0.10, H, {"-y": "cornice", "+z": "cornice", "-z": "soffit", "+x": "cornice", "-x": "cornice"})
    # side cornice (visible on right/left walls)
    for sx in (1, -1):
        x = sx * L.W / 2
        aabox(min(x, x + sx * 0.2), max(x, x + sx * 0.2), 0, L.D, H - 0.24, H - 0.10, fcs("cornice", skip=("-y", "+y")))
        aabox(min(x, x + sx * 0.34), max(x, x + sx * 0.34), 0, L.D, H - 0.10, H, fcs("cornice", skip=("-y", "+y")))


def awnings():
    z_top, z_low, proj = 2.95, 2.42, 1.25
    for h in L.front_holes():
        if h["kind"] != "shop":
            continue
        x0, x1 = h["x0"] - 0.25, h["x1"] + 0.25
        w = x1 - x0
        top = [(x0, -0.04, z_top), (x1, -0.04, z_top), (x1, -proj, z_low), (x0, -proj, z_low)]
        quad_tex(top, "awning", (0, -0.5, 1), fxs=(0, 1, 1, 0), fys=(0, 0, 1, 1))
        # valance with scallops
        vtop, vbot = z_low, z_low - 0.22
        quad_tex([(x0, -proj, vbot), (x1, -proj, vbot), (x1, -proj, vtop), (x0, -proj, vtop)], "awning", (0, -1, 0))
        n = 7
        for i in range(n):
            a, b = x0 + w * i / n, x0 + w * (i + 1) / n
            poly([(a, -proj, vbot), (b, -proj, vbot), ((a + b) / 2, -proj, vbot - 0.14)],
                 [uv_of("awning", i / n, 0.5), uv_of("awning", (i + 1) / n, 0.5), uv_of("awning", (i + .5) / n, 0.5)], (0, -1, 0))
        for sx in (x0, x1):
            flatpoly([(sx, -0.04, z_top), (sx, -proj, z_low), (sx, -proj, vbot), (sx, -0.04, z_low - 0.0)], "awn_side", (1 if sx == x0 else -1, 0, 0) if False else ((-1, 0, 0) if sx == x0 else (1, 0, 0)))
        flatpoly([(x0, -0.04, z_top - 0.03), (x0, -proj, z_low - 0.03), (x1, -proj, z_low - 0.03), (x1, -0.04, z_top - 0.03)], "soffit", (0, 0.4, -1))
    # kepenk (half closed) on shop B
    for h in L.front_holes():
        if h["id"] == "shopB":
            z1 = h["z1"]; z0 = z1 - 1.55
            quad_tex([(h["x0"] + 0.02, -0.03, z0), (h["x1"] - 0.02, -0.03, z0), (h["x1"] - 0.02, -0.03, z1), (h["x0"] + 0.02, -0.03, z1)], "kepenk", (0, -1, 0))
            aabox(h["x0"], h["x1"], -0.10, 0.0, z1 - 0.02, z1 + 0.16, fcs("metal"))   # kepenk box


def balcony():
    f = L.fz(1)
    x0, x1, dep = -2.5, 2.5, 0.95
    aabox(x0, x1, -dep, 0.0, f - 0.17, f + 0.03, {"-y": "wall", "+x": "wall", "-x": "wall", "+z": "balcony_top", "-z": "soffit"})
    for cx in (x0 + 0.5, 0.0, x1 - 0.5):
        aabox(cx - 0.09, cx + 0.09, -0.62, 0.0, f - 0.40, f - 0.17, fcs("trim"))
        aabox(cx - 0.09, cx + 0.09, -0.34, 0.0, f - 0.62, f - 0.40, fcs("trim"))
    zb0, zb1, bw = f + 0.03, f + 1.0, 0.024
    ins = 0.05
    # top rail + bottom rail
    for zz, th in ((zb1 - 0.04, 0.05), (zb0, 0.035)):
        aabox(x0 + ins, x1 - ins, -dep + ins, -dep + ins + th, zz, zz + th, fcs("rail"))
        for sx in (x0 + ins, x1 - ins - th):
            aabox(sx, sx + th, -dep + ins, -ins, zz, zz + th, fcs("rail"))
    xs = []
    n = int((x1 - x0 - 2 * ins) / 0.14)
    for i in range(n + 1):
        xs.append(x0 + ins + (x1 - x0 - 2 * ins) * i / n)
    for x in xs:
        aabox(x - bw, x + bw, -dep + ins, -dep + ins + 2 * bw, zb0, zb1 - 0.04, {"-y": "rail", "+x": "rail", "-x": "rail"})
    m = int((dep - 2 * ins) / 0.14)
    for sx in (x0 + ins, x1 - ins):
        for i in range(1, m):
            y = -dep + ins + (dep - 2 * ins) * i / m
            aabox(sx - bw, sx + bw, y - bw, y + bw, zb0, zb1 - 0.04, {"-y": "rail", "+y": "rail", "+x": "rail", "-x": "rail"})
    # satellite dish on rail
    pass


def cumba():
    f2 = L.fz(2)
    x0, x1, dep = -4.45, -0.35, 0.78
    z0, z1 = f2 - 0.02, f2 + 2.78
    # body
    aabox(x0, x1, -dep, 0.0, z0, z1, {"+x": "wall_dark", "-x": "wall_dark", "-z": "soffit"})
    # front: wall panel below windows + 3 windows + posts
    yf = -dep
    wy0, wy1 = f2 + 0.78, f2 + 2.5
    def q(xa, xb, za, zb, name): flatpoly([(xa, yf - 0.005, za), (xb, yf - 0.005, za), (xb, yf - 0.005, zb), (xa, yf - 0.005, zb)], name, (0, -1, 0))
    q(x0, x1, z0, wy0, "wall"); q(x0, x1, wy1, z1, "wall")
    n = 3
    pw = (x1 - x0 - 0.2 * 2) / n
    q(x0, x0 + 0.2, wy0, wy1, "wall"); q(x1 - 0.2, x1, wy0, wy1, "wall")
    xa = x0 + 0.2
    for i in range(n):
        h = dict(x0=xa + i * pw + 0.06, x1=xa + (i + 1) * pw - 0.06, z0=wy0, z1=wy1)
        if i > 0:
            q(xa + i * pw - 0.06, xa + i * pw + 0.06, wy0, wy1, "wall")
        # window in plane y=yf (offset): reuse opening with base_off
        pln = dict(h)
        gl = [(h["x0"], yf + 0.07, wy0), (h["x1"], yf + 0.07, wy0), (h["x1"], yf + 0.07, wy1), (h["x0"], yf + 0.07, wy1)]
        quad_tex(gl, "glass_win", (0, -1, 0))
        for (a, b, za, zb, nm) in ((h["x0"], h["x0"], wy0, wy1, 1), (h["x1"], h["x1"], wy0, wy1, -1)):
            flatpoly([(a, yf, za), (a, yf, zb), (a, yf + 0.07, zb), (a, yf + 0.07, za)], "jamb", (nm, 0, 0))
        for zz, nm in ((wy1, -1), (wy0, 1)):
            flatpoly([(h["x0"], yf, zz), (h["x1"], yf, zz), (h["x1"], yf + 0.07, zz), (h["x0"], yf + 0.07, zz)], "jamb", (0, 0, nm))
        aabox(h["x0"] - 0.07, h["x1"] + 0.07, yf - 0.08, yf, wy0 - 0.06, wy0, fcs("sill"))
        for sx in (h["x0"], h["x1"] - 0.05):
            aabox(sx, sx + 0.05, yf - 0.025, yf + 0.07, wy0, wy1, fcs("frame"))
        aabox(h["x0"], h["x1"], yf - 0.025, yf + 0.07, wy1 - 0.05, wy1, fcs("frame"))
    # string trim / corbels
    aabox(x0 - 0.05, x1 + 0.05, -dep - 0.06, 0.0, z0 - 0.14, z0, fcs("trim"))
    aabox(x0 + 0.2, x1 - 0.2, -dep + 0.15, 0.0, z0 - 0.34, z0 - 0.14, fcs("trim"))
    for cx in (x0 + 0.5, (x0 + x1) / 2, x1 - 0.5):
        aabox(cx - 0.1, cx + 0.1, -0.42, 0.0, z0 - 0.62, z0 - 0.34, fcs("trim"))
    # lean-to tiled roof
    zr0, zr1 = z1, z1 + 0.42
    xr0, xr1, yr = x0 - 0.08, x1 + 0.08, -dep - 0.18
    flatpoly([(xr0, yr, zr0), (xr1, yr, zr0), (xr1, 0.0, zr1), (xr0, 0.0, zr1)], "tile", (0, -0.5, 1))
    flatpoly([(xr0, yr, zr0), (xr0, 0, zr1), (xr0, 0, zr0)], "fascia", (-1, 0, 0))
    flatpoly([(xr1, yr, zr0), (xr1, 0, zr0), (xr1, 0, zr1)], "fascia", (1, 0, 0))
    flatpoly([(xr0, yr, zr0 - 0.12), (xr1, yr, zr0 - 0.12), (xr1, yr, zr0), (xr0, yr, zr0)], "fascia", (0, -1, 0))


# ---------------------------------------------------------------- sides
def sides():
    for plane, uvfn in (("right", side_r_uv), ("left", side_l_uv)):
        holes = L.side_holes()
        wall_grid(plane, holes, uvfn, 0.0, L.D, L.H)
        for h in holes:
            opening(plane, h, 0.2, "glass_win")
            # simple sill
            n = NORMALS[plane]
            x = (L.W / 2 if plane == "right" else -L.W / 2)
            sx = 1 if plane == "right" else -1
            aabox(min(x, x + sx * 0.12), max(x, x + sx * 0.12), h["x0"] - 0.07, h["x1"] + 0.07, h["z0"] - 0.07, h["z0"], fcs("sill"))
    # back wall (plain)
    wall_grid("back", [], lambda u, z: uv_of("side", (u + L.W / 2) / L.W * 0.9 + 0.05, 1 - z / L.H), -L.W / 2, L.W / 2, L.H)
    # downspout
    aabox(L.W / 2 - 0.16, L.W / 2 - 0.07, -0.13, -0.04, 0.0, L.H - 0.3, fcs("metal"))
    # AC unit under a window
    aabox(3.25, 3.95, -0.30, 0.0, L.fz(3) + 0.18, L.fz(3) + 0.70, {"-y": "ac", "+x": "ac", "-x": "ac", "+z": "ac", "-z": "wall_dark"})


# ---------------------------------------------------------------- roof
TP = math.tan(math.radians(L.PITCH_DEG))
CP = math.cos(math.radians(L.PITCH_DEG))
ZE = L.H + L.FASCIA
XO, YO0, YO1 = L.W / 2 + L.OVER, -L.OVER, L.D + L.OVER
A = XO


def roof_z(x, y):
    return ZE + min(x + XO, XO - x, y - YO0, YO1 - y) * TP


def roof():
    zr = ZE + A * TP
    R0, R1 = (0, YO0 + A, zr), (0, YO1 - A, zr)
    e00, e10, e11, e01 = (-XO, YO0, ZE), (XO, YO0, ZE), (XO, YO1, ZE), (-XO, YO1, ZE)
    ppm = 40.0
    def ruv(u, v): return uv_of("roof", (u * ppm - 0.0) / RECTS["roof"][2], (v * ppm) / RECTS["roof"][3])
    def U(p, axis): return p
    # front hip (triangle): u along x from left, v = slant from eave
    def vs(d): return d / CP
    poly([e00, e10, R0], [ruv(0.0, 0.0), ruv(2 * XO, 0.0), ruv(XO, vs(A))], (0, -0.4, 1))
    poly([e11, e01, R1], [ruv(0.0, 0.0), ruv(2 * XO, 0.0), ruv(XO, vs(A))], (0, 0.4, 1))
    L_ = YO1 - YO0
    poly([e10, e11, R1, R0], [ruv(0, 0), ruv(L_, 0), ruv(L_ - A, vs(A)), ruv(A, vs(A))], (0.4, 0, 1))
    poly([e01, e00, R0, R1], [ruv(0, 0), ruv(L_, 0), ruv(L_ - A, vs(A)), ruv(A, vs(A))], (-0.4, 0, 1))
    # fascia (vertical) + soffit ring
    for (a, b, n) in ((e00, e10, (0, -1, 0)), (e11, e01, (0, 1, 0)), (e10, e11, (1, 0, 0)), (e01, e00, (-1, 0, 0))):
        flatpoly([(a[0], a[1], L.H), (b[0], b[1], L.H), (b[0], b[1], ZE), (a[0], a[1], ZE)], "fascia", n)
    xi, xo = L.W / 2, XO
    zs = L.H
    flatpoly([(-xo, YO0, zs), (xo, YO0, zs), (xi, 0, zs), (-xi, 0, zs)], "soffit", (0, 0, -1))
    flatpoly([(xo, YO0, zs), (xo, YO1, zs), (xi, L.D, zs), (xi, 0, zs)], "soffit", (0, 0, -1))
    flatpoly([(xo, YO1, zs), (-xo, YO1, zs), (-xi, L.D, zs), (xi, L.D, zs)], "soffit", (0, 0, -1))
    flatpoly([(-xo, YO1, zs), (-xo, YO0, zs), (-xi, 0, zs), (-xi, L.D, zs)], "soffit", (0, 0, -1))
    # ridge + hip caps
    def cap(p, q_):
        d = norm(sub(q_, p))
        up = (0, 0, 1)
        bz = norm(sub(up, mul(d, dot(up, d))))
        by = cross(bz, d)
        ln = math.sqrt(dot(sub(q_, p), sub(q_, p)))
        mid = mul(add(p, q_), 0.5)
        box(add(mid, mul(bz, 0.04)), (ln + 0.1, 0.30, 0.20), {k: "ridge" for k in ("+x", "-x", "+y", "-y", "+z")}, basis=(d, by, bz))
    cap(R0, R1)
    for e, R in ((e00, R0), (e10, R0), (e11, R1), (e01, R1)):
        cap(e, R)
    return zr


def chimneys():
    for (cx, cy, hh) in ((-1.9, 7.6, 1.5), (2.5, 8.6, 1.2)):
        zt = roof_z(cx, cy) + hh
        zb = roof_z(cx, cy) - 0.5
        aabox(cx - 0.38, cx + 0.38, cy - 0.38, cy + 0.38, zb, zt, fcs("chimney", skip=("-z",)))
        aabox(cx - 0.50, cx + 0.50, cy - 0.50, cy + 0.50, zt, zt + 0.12, fcs("trim", skip=("-z",)) )
        for fx in (-0.17, 0.17):
            aabox(cx + fx - 0.09, cx + fx + 0.09, cy - 0.09, cy + 0.09, zt + 0.12, zt + 0.42, fcs("tile", skip=("-z",)))


def solar():
    # right (+x) slope: downslope direction d, normal n
    s, c = math.sin(math.radians(L.PITCH_DEG)), CP
    n = (s, 0.0, c)
    bx = (0, 1, 0)
    bz = n
    by = cross(bz, bx)
    x, y = 3.7, 5.2
    z = roof_z(x, y)
    ctr = add((x, y, z), mul(n, 0.16))
    box(ctr, (1.30, 1.9, 0.08), {"+z": "panel", "-z": "dark", "+x": "metal", "-x": "metal", "+y": "metal", "-y": "metal"}, basis=(bx, by, bz))
    up = by
    ctr2 = add(add(ctr, mul(up, 1.25)), mul(n, 0.24))
    box(ctr2, (1.2, 0.46, 0.40), fcs("tank"), basis=(bx, by, bz))
    for off in (-0.35, 0.35):
        box(add(add(ctr, mul(bx, off)), mul(n, -0.10)), (0.06, 1.7, 0.14), fcs("metal", skip=("-z",)), basis=(bx, by, bz))


def dormer():
    cx, wd = 1.2, 1.5
    y0 = 0.5
    zb = roof_z(cx, y0) - 0.15
    ht = 1.75
    zt = zb + ht
    y1 = y0 + 2.2
    aabox(cx - wd / 2, cx + wd / 2, y0, y1, zb, zt, {"+x": "wall_dark", "-x": "wall_dark"})
    h = dict(x0=cx - 0.38, x1=cx + 0.38, z0=zb + 0.36, z1=zb + 1.48)
    ax0, ax1 = cx - wd / 2, cx + wd / 2
    for (xa_, xb_, za_, zb_) in ((ax0, h["x0"], zb, zt), (h["x1"], ax1, zb, zt), (h["x0"], h["x1"], zb, h["z0"]), (h["x0"], h["x1"], h["z1"], zt)):
        flatpoly([(xa_, y0, za_), (xb_, y0, za_), (xb_, y0, zb_), (xa_, y0, zb_)], "wall", (0, -1, 0))
    yf = y0
    quad_tex([(h["x0"], yf + 0.14, h["z0"]), (h["x1"], yf + 0.14, h["z0"]), (h["x1"], yf + 0.14, h["z1"]), (h["x0"], yf + 0.14, h["z1"])], "glass_win", (0, -1, 0))
    for zz, nm in ((h["z1"], -1), (h["z0"], 1)):
        flatpoly([(h["x0"], yf, zz), (h["x1"], yf, zz), (h["x1"], yf + .14, zz), (h["x0"], yf + .14, zz)], "jamb", (0, 0, nm))
    for xx, nm in ((h["x0"], 1), (h["x1"], -1)):
        flatpoly([(xx, yf, h["z0"]), (xx, yf, h["z1"]), (xx, yf + .14, h["z1"]), (xx, yf + .14, h["z0"])], "jamb", (nm, 0, 0))
    aabox(h["x0"] - 0.06, h["x1"] + 0.06, yf - 0.08, yf + 0.04, h["z0"] - 0.05, h["z0"], fcs("sill"))
    for sx in (h["x0"], h["x1"] - 0.04):
        aabox(sx, sx + 0.04, yf + 0.06, yf + 0.14, h["z0"], h["z1"], fcs("frame"))
    aabox(h["x0"], h["x1"], yf + 0.06, yf + 0.14, h["z1"] - 0.04, h["z1"], fcs("frame"))
    ov = 0.22
    zr = zt + (wd / 2 + ov) * 0.62
    xa, xb = cx - wd / 2 - ov, cx + wd / 2 + ov
    ya, yb = y0 - ov, y1
    flatpoly([(xa, ya, zt), (xa, yb, zt), (cx, yb, zr), (cx, ya, zr)], "tile", (-0.55, 0, 1))
    flatpoly([(xb, yb, zt), (xb, ya, zt), (cx, ya, zr), (cx, yb, zr)], "tile", (0.55, 0, 1))
    flatpoly([(xa, ya, zt), (cx, ya, zr), (xb, ya, zt)], "wall", (0, -1, 0))
    flatpoly([(xa, ya, zt - 0.1), (xb, ya, zt - 0.1), (xb, ya, zt), (xa, ya, zt)], "fascia", (0, -1, 0))
    aabox(cx - 0.06, cx + 0.06, ya, yb, zr, zr + 0.09, fcs("ridge", skip=("-z",)))


# ---------------------------------------------------------------- main
def build():
    facade(); string_courses(); cornice(); awnings(); balcony(); cumba(); sides(); roof(); chimneys(); solar(); dormer()
    mesh = bpy.data.meshes.new("bld_hero_old_core")
    mesh.from_pydata(V, [], F)
    mesh.update()
    uvl = mesh.uv_layers.new(name="UVMap")
    for poly_ in mesh.polygons:
        poly_.use_smooth = False
        for li in poly_.loop_indices:
            uvl.data[li].uv = UV[mesh.loops[li].vertex_index]
    ob = bpy.data.objects.new("bld_hero_old_core", mesh)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("mat_hero_atlas")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    img = bpy.data.images.load(os.path.abspath(arg["atlas"]))
    img.colorspace_settings.name = "sRGB"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    for nm in ("Specular IOR Level", "Specular"):
        if nm in bsdf.inputs:
            bsdf.inputs[nm].default_value = 0.0
    mesh.materials.append(mat)
    tris = sum(len(f) - 2 for f in F)
    print("HERO_TRIS", tris, "VERTS", len(V), "FACES", len(F))
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(arg["out"]), export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_image_format="AUTO")


# clean default scene objects
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
build()
