"""Landmark (clock tower) and scale reference props for the T-004 kit (building-kit-v0 sections 2.3, 4).

Game frame as in kit_common: x right, y up, z = front. All builders are deterministic; `seed` only drives the
per-face shade jitter of foliage blobs.
"""
import math
import random

from kit_common import (
    PART_ACCENT, PART_BRICK, PART_GLASS, PART_ROOF, PART_SKIN, PART_STONE, PART_TRIM, PART_TRUNK, PART_WALL, SKIRT,
    Frame, Mesh, Rec, wall_frames)


def ngon_ring(across_flats, n=8, flat_on_axes=True):
    """Regular n-gon ring of (x, z); with n = 8 and flat_on_axes the flats face +-x / +-z."""
    r = across_flats / 2.0 / math.cos(math.pi / n)
    off = math.pi / n if flat_on_axes else 0.0
    return [(r * math.cos(off + 2 * math.pi * k / n), r * math.sin(off + 2 * math.pi * k / n)) for k in range(n)]


# ------------------------------------------------------------------------------------------------------------
# lmk_clocktower  (O) - 23.0 m, human-scale, squat octagonal cap (no spire / campanile silhouette), spec section 4
# ------------------------------------------------------------------------------------------------------------
TOWER = {
    "plinth_h": 1.2, "lower_h": 6.0, "upper_h": 9.0, "clock_h": 3.5, "cap_h": 3.3,
    "lower_w": 4.5, "upper_w": 4.0, "clock_w": 4.0,
}


def _stone_face_with_arch(m, f, hw, v0, v1, uc, w, spring, top, depth):
    """Wall face tiled around a 3-facet arched opening: quads left/right/above the arch bounding rect plus three
    spandrel polygons between the arch polyline and the rect top; the arch itself is a recess."""
    a0, a1 = uc - w / 2, uc + w / 2
    f.rect(m, -hw, a0, v0, v1, 0.0, PART_STONE, 1.0)
    f.rect(m, a1, hw, v0, v1, 0.0, PART_STONE, 1.0)
    f.rect(m, a0, a1, top, v1, 0.0, PART_STONE, 1.0)
    p1 = (uc + (w / 2) * math.cos(math.pi / 3), spring + (top - spring) * math.sin(math.pi / 3))
    p2 = (uc - (w / 2) * math.cos(math.pi / 3), p1[1])
    m.poly([f.p(a1, spring), f.p(a1, top), f.p(p1[0], top), f.p(*p1)], PART_STONE, 1.0, out=f.n)
    m.poly([f.p(*p1), f.p(p1[0], top), f.p(p2[0], top), f.p(*p2)], PART_STONE, 1.0, out=f.n)
    m.poly([f.p(*p2), f.p(p2[0], top), f.p(a0, top), f.p(a0, spring)], PART_STONE, 1.0, out=f.n)
    f.arch_recess(m, uc, w, v0, spring, top, depth, 3, back=PART_GLASS, reveal=PART_STONE, reveal_shade=0.8)


def build_clocktower():
    t = TOWER
    m = Mesh()
    y_p = t["plinth_h"]
    y_l = y_p + t["lower_h"]
    y_u = y_l + t["upper_h"]
    y_c = y_u + t["clock_h"]
    y_top = y_c + t["cap_h"]
    # kaide/cesme platformu: 9 m across-flats octagon (to y 0.8) + 7 m step (to 1.2)
    m.prism_poly(ngon_ring(9.0), -SKIRT, y_p - 0.4, PART_STONE, top=PART_STONE, side_shade=0.85)
    m.prism_poly(ngon_ring(7.0), y_p - 0.4, y_p, PART_STONE, top=PART_TRIM, side_shade=0.95)
    # lower shaft 4.5 x 4.5: arched openings
    hw = t["lower_w"] / 2
    for name, f in wall_frames(-hw, hw, -hw, hw).items():
        _stone_face_with_arch(m, f, hw, y_p, y_l, 0.0, 1.5, y_p + 2.6, y_p + 3.6, 0.35)
    # ledge ring between the 4.5 and 4.0 shafts (trim)
    uw = t["upper_w"] / 2
    m.quad((-hw, y_l, hw), (hw, y_l, hw), (uw, y_l, uw), (-uw, y_l, uw), PART_TRIM, 1.0, out=(0, 1, 0))
    m.quad((hw, y_l, hw), (hw, y_l, -hw), (uw, y_l, -uw), (uw, y_l, uw), PART_TRIM, 1.0, out=(0, 1, 0))
    m.quad((hw, y_l, -hw), (-hw, y_l, -hw), (-uw, y_l, -uw), (uw, y_l, -uw), PART_TRIM, 1.0, out=(0, 1, 0))
    m.quad((-hw, y_l, -hw), (-hw, y_l, hw), (-uw, y_l, uw), (-uw, y_l, -uw), PART_TRIM, 1.0, out=(0, 1, 0))
    # upper shaft 4.0 x 4.0 with a tall slit window per face
    for name, f in wall_frames(-uw, uw, -uw, uw).items():
        f.tile(m, -uw, uw, y_l, y_u, [Rec(-0.3, 0.3, y_l + 2.5, y_u - 2.0, 0.3, back=PART_GLASS, reveal=PART_STONE,
                                         reveal_shade=0.8)], PART_STONE, 1.0)
    # cornice collar 4.6 square under the clock stage
    cw = 2.3
    m.box(-cw, cw, y_u, y_u + 0.4, -cw, cw, side=PART_TRIM, top=PART_TRIM, side_shade=0.95)
    # clock stage 4.0 x 4.0
    y_cs = y_u + 0.4
    for name, f in wall_frames(-uw, uw, -uw, uw).items():
        f.tile(m, -uw, uw, y_cs, y_c, [], PART_STONE, 1.0)
        yc = (y_cs + y_c) / 2
        disc = [(0.8 * math.cos(math.pi / 8 + k * math.pi / 4), yc + 0.8 * math.sin(math.pi / 8 + k * math.pi / 4))
                for k in range(8)]
        m.poly([f.p(u, v, 0.05) for u, v in disc], PART_WALL, 1.0, out=f.n)
        m.quad(f.p(-0.04, yc - 0.05, 0.09), f.p(0.04, yc - 0.05, 0.09), f.p(0.04, yc + 0.68, 0.09),
               f.p(-0.04, yc + 0.68, 0.09), PART_GLASS, 1.0, out=f.n)
        m.quad(f.p(-0.04, yc - 0.04, 0.09), f.p(0.45, yc - 0.28, 0.09), f.p(0.49, yc - 0.2, 0.09),
               f.p(0.0, yc + 0.04, 0.09), PART_GLASS, 1.0, out=f.n)
    # cap: octagonal drum (4.0 across flats) + arched slits, then a low octagonal lead pyramid
    y_dr = y_c + 1.4
    m.prism_poly(ngon_ring(4.0), y_c, y_dr, PART_STONE, top=None, side_shade=0.95)
    base = ngon_ring(5.2)
    apex = (0.0, y_top, 0.0)
    for k in range(8):
        a, b = base[k], base[(k + 1) % 8]
        m.tri((a[0], y_dr, a[1]), (b[0], y_dr, b[1]), apex, PART_ROOF, 1.0,
              out=((a[0] + b[0]) / 2, 1.0, (a[1] + b[1]) / 2))
    m.footprint = [(-4.5, 4.5, -4.5, 4.5)]
    return m


def tower_mass():
    """LOD1 (<=120) and PROXY (<=14) for the clock tower."""
    t = TOWER
    y_p = t["plinth_h"]
    y_l = y_p + t["lower_h"]
    y_u = y_l + t["upper_h"]
    y_c = y_u + t["clock_h"]
    y_top = y_c + t["cap_h"]
    lod1 = Mesh()
    lod1.prism_poly(ngon_ring(9.0), -SKIRT, y_p, PART_STONE, top=PART_STONE, side_shade=0.85)
    lod1.box(-2.25, 2.25, y_p, y_l, -2.25, 2.25, side=PART_STONE, top=PART_TRIM, side_shade=1.0)
    lod1.box(-2.0, 2.0, y_l, y_u, -2.0, 2.0, side=PART_STONE, top=PART_TRIM, side_shade=1.0)
    lod1.box(-2.3, 2.3, y_u, y_u + 0.4, -2.3, 2.3, side=PART_TRIM, top=PART_TRIM, side_shade=0.95)
    lod1.box(-2.0, 2.0, y_u + 0.4, y_c, -2.0, 2.0, side=PART_STONE, top=None)
    lod1.prism_poly(ngon_ring(4.0), y_c, y_c + 1.4, PART_STONE, top=None)
    base = ngon_ring(5.2)
    for k in range(8):
        a, b = base[k], base[(k + 1) % 8]
        lod1.tri((a[0], y_c + 1.4, a[1]), (b[0], y_c + 1.4, b[1]), (0, y_top, 0), PART_ROOF, 1.0,
                 out=((a[0] + b[0]) / 2, 1.0, (a[1] + b[1]) / 2))
    proxy = Mesh()
    proxy.box(-2.25, 2.25, -SKIRT, y_c, -2.25, 2.25, side=PART_STONE, top=None)     # 8 tris
    pr = ngon_ring(4.6, 4, flat_on_axes=False)                                        # 4 tris pyramid cap
    for k in range(4):
        a, b = pr[k], pr[(k + 1) % 4]
        proxy.tri((a[0], y_c, a[1]), (b[0], y_c, b[1]), (0, y_top, 0), PART_ROOF, 1.0,
                  out=((a[0] + b[0]) / 2, 1.0, (a[1] + b[1]) / 2))
    return lod1, proxy


# ------------------------------------------------------------------------------------------------------------
# props
# ------------------------------------------------------------------------------------------------------------
def build_human():
    m = Mesh()
    m.box(-0.17, 0.17, 0.0, 0.82, -0.10, 0.10, side=PART_ROOF, top=None)              # legs (10)
    m.box(-0.25, 0.25, 0.82, 1.46, -0.13, 0.13, side=PART_WALL, top=PART_WALL)           # torso (10)
    m.box(-0.10, 0.10, 1.46, 1.75, -0.11, 0.11, side=PART_SKIN, top=PART_SKIN)           # head (10)
    return m


def build_car():
    m = Mesh()
    # lower body 4.4 x 1.8, y 0.3..0.9
    m.box(-0.9, 0.9, 0.3, 0.9, -2.2, 2.2, side=PART_WALL, top=PART_WALL, side_shade=0.95)
    # cabin: trapezoid prism y 0.9..1.5, rear z -1.35..-0.75, front z 1.05..0.35 (bottom..top)
    zb0, zb1, zt0, zt1 = -1.45, 1.05, -0.85, 0.35
    xb, xt = 0.82, 0.74
    m.poly([(-xb, 0.9, zb1), (xb, 0.9, zb1), (xt, 1.5, zt1), (-xt, 1.5, zt1)], PART_GLASS, 1.0, out=(0, 1, 1))
    m.poly([(xb, 0.9, zb0), (-xb, 0.9, zb0), (-xt, 1.5, zt0), (xt, 1.5, zt0)], PART_GLASS, 1.0, out=(0, 1, -1))
    m.poly([(xb, 0.9, zb1), (xb, 0.9, zb0), (xt, 1.5, zt0), (xt, 1.5, zt1)], PART_GLASS, 0.9, out=(1, 0.3, 0))
    m.poly([(-xb, 0.9, zb0), (-xb, 0.9, zb1), (-xt, 1.5, zt1), (-xt, 1.5, zt0)], PART_GLASS, 0.9, out=(-1, 0.3, 0))
    m.poly([(-xt, 1.5, zt1), (xt, 1.5, zt1), (xt, 1.5, zt0), (-xt, 1.5, zt0)], PART_WALL, 1.0, out=(0, 1, 0))
    for sx in (-1, 1):                                                                  # wheels (flat discs on sides)
        for cz in (-1.4, 1.4):
            x = sx * 0.92
            m.poly([(x, 0.02, cz - 0.38), (x, 0.02, cz + 0.38), (x, 0.7, cz + 0.38), (x, 0.7, cz - 0.38)],
                   PART_GLASS, 0.9, out=(sx, 0, 0))
    return m


def _icosahedron():
    p = (1 + math.sqrt(5)) / 2
    v = [(-1, p, 0), (1, p, 0), (-1, -p, 0), (1, -p, 0), (0, -1, p), (0, 1, p), (0, -1, -p), (0, 1, -p),
         (p, 0, -1), (p, 0, 1), (-p, 0, -1), (-p, 0, 1)]
    v = [tuple(c / math.sqrt(1 + p * p) for c in q) for q in v]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
         (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11),
         (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    return v, f


def _blob(m, c, r, rng, part=PART_ROOF, jitter=0.12):
    v, f = _icosahedron()
    pts = []
    for q in v:
        s = 1.0 + (rng.random() - 0.5) * 2 * jitter
        pts.append((c[0] + q[0] * r[0] * s, c[1] + q[1] * r[1] * s, c[2] + q[2] * r[2] * s))
    for a, b, d in f:
        center = tuple((pts[a][k] + pts[b][k] + pts[d][k]) / 3 - c[k] for k in range(3))
        m.tri(pts[a], pts[b], pts[d], part, 0.88 + rng.random() * 0.16, out=center)


def _frustum(m, y0, y1, r0, r1, n, part, shade=1.0, top=None, top_shade=1.0):
    for k in range(n):
        a0 = 2 * math.pi * k / n
        a1 = 2 * math.pi * (k + 1) / n
        mid = (a0 + a1) / 2
        m.poly([(r0 * math.cos(a0), y0, r0 * math.sin(a0)), (r0 * math.cos(a1), y0, r0 * math.sin(a1)),
                (r1 * math.cos(a1), y1, r1 * math.sin(a1)), (r1 * math.cos(a0), y1, r1 * math.sin(a0))],
               part, shade, out=(math.cos(mid), 0.0, math.sin(mid)))
    if top is not None:
        m.poly([(r1 * math.cos(2 * math.pi * k / n), y1, r1 * math.sin(2 * math.pi * k / n)) for k in range(n)], top,
               top_shade, out=(0, 1, 0))


def build_plane_tree(seed=0, lod=0):
    rng = random.Random(f"{seed}/veg_plane/{lod}")
    m = Mesh()
    _frustum(m, 0.0, 4.5, 0.40, 0.22, 6, PART_TRUNK, 0.95)
    _blob(m, (0.0, 10.1, 0.0), (5.4, 4.7, 5.4), rng)
    if lod == 0:
        _blob(m, (-2.1, 7.4, 1.0), (2.9, 2.6, 2.9), rng)
        _blob(m, (2.2, 7.0, -1.2), (2.8, 2.4, 2.8), rng)
    return m


def build_chimney():
    """prop_chimney: 30 m octagonal brick shaft (base 2.4 m, top 1.8 m) with collar. <= 60 triangles."""
    m = Mesh()
    _frustum(m, -SKIRT, 2.0, 1.25, 1.25, 8, PART_BRICK, 0.9)              # plinth to 2 m
    _frustum(m, 2.0, 29.2, 1.2, 0.9, 8, PART_BRICK, 1.0)                   # shaft
    _frustum(m, 29.2, 30.0, 1.1, 1.1, 8, PART_BRICK, 0.8, top=PART_BRICK, top_shade=0.75)  # collar
    return m
