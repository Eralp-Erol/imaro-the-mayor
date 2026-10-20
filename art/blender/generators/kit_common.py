"""Shared geometry toolkit for the building kit generators (T-004, design/specs/art/building-kit-v0.md).

Pure Python (no bpy at import time) except `export_glb`, so the geometry code can be unit-checked without Blender.
Conventions (spec section 8):
  * "Game frame": x right, y up, z = FRONT (street side, glTF +Z). 1 unit = 1 m. Origin = footprint centre, y = 0 ground.
  * Meshes are lists of faces (pts, part_id, shade). One surface, one material `mat_kit`.
  * UV0.x = (part_id + 0.5) / 16, UV0.y = constant shade multiplier (spec section 6).
  * Faces are flat shaded (the exporter splits vertices per face normal). No bottom faces; foundation skirt to y = -2.5.
"""
import hashlib
import json
import math
import os

# Spec section 6 part ids (6, 7.. were reserved; used here: 6 = fixed brick, 8 = trunk, 9 = skin).
PART_WALL = 0     # wall colour (instance row)
PART_ROOF = 1     # roof colour (instance row)
PART_ACCENT = 2   # shop band / shutter / awning (instance row)
PART_GLASS = 3    # glass / deep recess (fixed G1)
PART_STONE = 4    # fixed stone W11
PART_TRIM = 5     # trim / parapet cap (wall colour x 0.85)
PART_BRICK = 6    # fixed brick W10 (spec reserve slot, used for ind_heritage)
PART_TRUNK = 8    # fixed trunk
PART_SKIN = 9     # fixed skin

FLOOR_H = 3.0
GF_H = 4.2
PARAPET_H = 0.9
PARAPET_T = 0.3
SKIRT = 2.5
RECESS_SHADE = 0.72   # spec section 5: recess colour = wall x 0.72
GRID = 0.5
EPS = 1e-6


def r5(v):
    return round(v + 0.0, 5)


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def newell(pts):
    nx = ny = nz = 0.0
    for i, a in enumerate(pts):
        b = pts[(i + 1) % len(pts)]
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
    return (nx, ny, nz)


class Mesh:
    """Face soup in the game frame."""

    def __init__(self):
        self.faces = []        # (pts, part, shade)
        self.footprint = []    # rects (x0, x1, z0, z1) used to centre the pivot
        self.roof_boxes = []   # (cx, cz, w, d, y, h) roof-top boxes, repeated in LOD1

    # -- primitives ---------------------------------------------------------------------------
    def poly(self, pts, part, shade=1.0, out=None):
        pts = [(r5(p[0]), r5(p[1]), r5(p[2])) for p in pts]
        if out is not None and vdot(newell(pts), out) < 0:
            pts.reverse()
        self.faces.append((pts, part, shade))

    def quad(self, a, b, c, d, part, shade=1.0, out=None):
        self.poly([a, b, c, d], part, shade, out)

    def tri(self, a, b, c, part, shade=1.0, out=None):
        self.poly([a, b, c], part, shade, out)

    def box(self, x0, x1, y0, y1, z0, z1, side=PART_WALL, top=PART_ROOF, bottom=None,
            side_shade=1.0, top_shade=1.0, skip=()):
        """Axis-aligned box. skip: any of 'px','nx','py','ny','pz','nz' to omit a face."""
        def add(key, pts, out, part, shade):
            if key not in skip:
                self.poly(pts, part, shade, out)
        add("pz", [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1), side, side_shade)
        add("nz", [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)], (0, 0, -1), side, side_shade)
        add("px", [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)], (1, 0, 0), side, side_shade)
        add("nx", [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0), side, side_shade)
        if top is not None:
            add("py", [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)], (0, 1, 0), top, top_shade)
        if bottom is not None:
            add("ny", [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0), bottom, side_shade)

    def prism_poly(self, ring, y0, y1, side, top=None, top_shade=1.0, side_shade=1.0):
        """Vertical prism over a convex CCW (seen from above, x right / z toward viewer-down) ring of (x, z)."""
        n = len(ring)
        cx = sum(p[0] for p in ring) / n
        cz = sum(p[1] for p in ring) / n
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            mx, mz = (a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cz
            self.poly([(a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1])],
                      side, side_shade, out=(mx, 0, mz))
        if top is not None:
            self.poly([(p[0], y1, p[1]) for p in ring], top, top_shade, out=(0, 1, 0))

    def translate(self, dx, dy, dz):
        self.faces = [([(r5(p[0] + dx), r5(p[1] + dy), r5(p[2] + dz)) for p in pts], part, shade)
                      for pts, part, shade in self.faces]

    def tri_count(self):
        return sum(len(pts) - 2 for pts, _, _ in self.faces)

    def aabb(self):
        xs = [p[0] for pts, _, _ in self.faces for p in pts]
        ys = [p[1] for pts, _, _ in self.faces for p in pts]
        zs = [p[2] for pts, _, _ in self.faces for p in pts]
        return ((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs)))

    def center_footprint(self):
        """Move the pivot to the centre of the union of the registered footprint rects (0.5 m grid)."""
        if not self.footprint:
            return (0.0, 0.0)
        x0 = min(r[0] for r in self.footprint)
        x1 = max(r[1] for r in self.footprint)
        z0 = min(r[2] for r in self.footprint)
        z1 = max(r[3] for r in self.footprint)
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        self.translate(-cx, 0, -cz)
        self.footprint = [(r[0] - cx, r[1] - cx, r[2] - cz, r[3] - cz) for r in self.footprint]
        return (cx, cz)


class Rec:
    """A rectangular recess (or opening) on a Frame: u/v rect, depth into the wall."""

    def __init__(self, u0, u1, v0, v1, depth=0.3, back=PART_GLASS, back_shade=1.0,
                 reveal=PART_WALL, reveal_shade=0.8, deco=None):
        self.deco = deco or []   # extra (u0, u1, v0, v1, off, part, shade) quads inside the recess
        self.u0, self.u1, self.v0, self.v1 = u0, u1, v0, v1
        self.depth = depth
        self.back, self.back_shade = back, back_shade
        self.reveal, self.reveal_shade = reveal, reveal_shade


class Frame:
    """A wall plane. Local (u, v) -> world: origin + u*U + v*V + off*N, with U x V = N (CCW seen from outside)."""

    def __init__(self, origin, u, v, n):
        self.o, self.u, self.v, self.n = origin, u, v, n

    def p(self, u, v, off=0.0):
        return (self.o[0] + u * self.u[0] + v * self.v[0] + off * self.n[0],
                self.o[1] + u * self.u[1] + v * self.v[1] + off * self.n[1],
                self.o[2] + u * self.u[2] + v * self.v[2] + off * self.n[2])

    def rect(self, m, u0, u1, v0, v1, off=0.0, part=PART_WALL, shade=1.0):
        m.poly([self.p(u0, v0, off), self.p(u1, v0, off), self.p(u1, v1, off), self.p(u0, v1, off)],
               part, shade, out=self.n)

    def tile(self, m, u0, u1, v0, v1, recs=(), part=PART_WALL, shade=1.0):
        """Fill [u0,u1]x[v0,v1] with wall quads leaving the recess rects open, then build each recess."""
        vs = {v0, v1}
        for r in recs:
            vs.add(min(max(r.v0, v0), v1))
            vs.add(min(max(r.v1, v0), v1))
        vs = sorted(vs)
        rects = []
        for lo, hi in zip(vs[:-1], vs[1:]):
            if hi - lo < EPS:
                continue
            cov = sorted([r for r in recs if r.v0 <= lo + EPS and r.v1 >= hi - EPS], key=lambda r: r.u0)
            cur = u0
            for r in cov:
                if r.u0 > cur + EPS:
                    rects.append([cur, min(r.u0, u1), lo, hi])
                cur = max(cur, r.u1)
            if u1 > cur + EPS:
                rects.append([cur, u1, lo, hi])
        merged = True
        while merged:  # merge vertically adjacent identical-width rects
            merged = False
            for i in range(len(rects)):
                for j in range(len(rects)):
                    a, b = rects[i], rects[j]
                    if i != j and abs(a[0] - b[0]) < EPS and abs(a[1] - b[1]) < EPS and abs(a[3] - b[2]) < EPS:
                        a[3] = b[3]
                        rects.pop(j)
                        merged = True
                        break
                if merged:
                    break
        for r in rects:
            self.rect(m, r[0], r[1], r[2], r[3], 0.0, part, shade)
        for r in recs:
            self.recess(m, r)

    def recess(self, m, r):
        d = r.depth
        self.rect(m, r.u0, r.u1, r.v0, r.v1, -d, r.back, r.back_shade)
        for du0, du1, dv0, dv1, off, dpart, dshade in r.deco:
            self.rect(m, du0, du1, dv0, dv1, off, dpart, dshade)
        rs, rp = r.reveal_shade, r.reveal
        m.poly([self.p(r.u0, r.v0, 0), self.p(r.u1, r.v0, 0), self.p(r.u1, r.v0, -d), self.p(r.u0, r.v0, -d)],
               rp, rs, out=self.v)                                # sill (faces up)
        m.poly([self.p(r.u0, r.v1, 0), self.p(r.u1, r.v1, 0), self.p(r.u1, r.v1, -d), self.p(r.u0, r.v1, -d)],
               rp, rs * 0.9, out=tuple(-c for c in self.v))      # soffit
        m.poly([self.p(r.u0, r.v0, 0), self.p(r.u0, r.v1, 0), self.p(r.u0, r.v1, -d), self.p(r.u0, r.v0, -d)],
               rp, rs, out=self.u)                                # left reveal
        m.poly([self.p(r.u1, r.v0, 0), self.p(r.u1, r.v1, 0), self.p(r.u1, r.v1, -d), self.p(r.u1, r.v0, -d)],
               rp, rs, out=tuple(-c for c in self.u))            # right reveal

    def arch_recess(self, m, uc, w, v0, v_spring, v_top, depth=0.3, segs=3,
                    back=PART_GLASS, reveal=PART_WALL, reveal_shade=0.8):
        """Round-arched recess: rect from v0 to v_spring, half-ellipse up to v_top (segs facets)."""
        hw = w / 2.0
        ring = [(uc - hw, v0), (uc + hw, v0), (uc + hw, v_spring)]
        for i in range(1, segs):
            a = math.pi * i / segs
            ring.append((uc + hw * math.cos(a), v_spring + (v_top - v_spring) * math.sin(a)))
        ring.append((uc - hw, v_spring))
        # ring order: bottom-left, bottom-right, up right side, over the arch (right to left), down left side
        self.poly_recess(m, ring, depth, back, reveal, reveal_shade)

    def poly_recess(self, m, ring, depth, back=PART_GLASS, reveal=PART_WALL, reveal_shade=0.8):
        """ring: CCW (u, v) points; edge 0->1 is the opening floor."""
        m.poly([self.p(u, v, -depth) for u, v in ring], back, 1.0, out=self.n)
        n = len(ring)
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            ex, ey = b[0] - a[0], b[1] - a[1]
            # inward-facing reveal normal: left-normal of the CCW edge
            outn = tuple(-ey * self.u[k] + ex * self.v[k] for k in range(3))
            m.poly([self.p(a[0], a[1], 0), self.p(b[0], b[1], 0), self.p(b[0], b[1], -depth),
                    self.p(a[0], a[1], -depth)], reveal, reveal_shade, out=outn)


def wall_frames(x0, x1, z0, z1):
    """Four wall frames of a rectangular block. Local u: front = x, back = -x, right = -z, left = z."""
    return {
        "front": Frame((0, 0, z1), (1, 0, 0), (0, 1, 0), (0, 0, 1)),
        "back": Frame((0, 0, z0), (-1, 0, 0), (0, 1, 0), (0, 0, -1)),
        "right": Frame((x1, 0, 0), (0, 0, -1), (0, 1, 0), (1, 0, 0)),
        "left": Frame((x0, 0, 0), (0, 0, 1), (0, 1, 0), (-1, 0, 0)),
    }


def side_range(side, x0, x1, z0, z1):
    return {"front": (x0, x1), "back": (-x1, -x0), "right": (-z1, -z0), "left": (z0, z1)}[side]


def block_walls(m, rect, y0, y1, recs=None, part=PART_WALL, shade=1.0, skirt=True, skirt_part=PART_STONE,
                sides=("front", "back", "right", "left"), register=True):
    """Four wall planes of a block (recs: side -> [Rec] in that frame's local u)."""
    x0, x1, z0, z1 = rect
    recs = recs or {}
    fr = wall_frames(x0, x1, z0, z1)
    for s in sides:
        u0, u1 = side_range(s, x0, x1, z0, z1)
        fr[s].tile(m, u0, u1, y0, y1, recs.get(s, ()), part, shade)
        if skirt and y0 <= 0.0:
            fr[s].rect(m, u0, u1, -SKIRT, y0, 0.0, skirt_part, 0.8)
    if register:
        m.footprint.append(rect)
    return fr


# ---------------------------------------------------------------------------------------------
# Roofs
# ---------------------------------------------------------------------------------------------
def flat_roof(m, rect, y, parapet=True, deck_part=PART_ROOF, cap_part=PART_TRIM, inner_part=PART_WALL):
    """Deck at y; parapet (outer faces are the block wall tiled up to y + PARAPET_H by the caller)."""
    x0, x1, z0, z1 = rect
    if not parapet:
        m.quad((x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0), deck_part, 1.0, out=(0, 1, 0))
        return
    yt = y + PARAPET_H
    t = PARAPET_T
    ix0, ix1, iz0, iz1 = x0 + t, x1 - t, z0 + t, z1 - t
    m.quad((x0, yt, z1), (x1, yt, z1), (ix1, yt, iz1), (ix0, yt, iz1), cap_part, 1.0, out=(0, 1, 0))
    m.quad((x1, yt, z1), (x1, yt, z0), (ix1, yt, iz0), (ix1, yt, iz1), cap_part, 1.0, out=(0, 1, 0))
    m.quad((x1, yt, z0), (x0, yt, z0), (ix0, yt, iz0), (ix1, yt, iz0), cap_part, 1.0, out=(0, 1, 0))
    m.quad((x0, yt, z0), (x0, yt, z1), (ix0, yt, iz1), (ix0, yt, iz0), cap_part, 1.0, out=(0, 1, 0))
    m.quad((ix0, y, iz1), (ix1, y, iz1), (ix1, yt, iz1), (ix0, yt, iz1), inner_part, 0.9, out=(0, 0, -1))
    m.quad((ix1, y, iz1), (ix1, y, iz0), (ix1, yt, iz0), (ix1, yt, iz1), inner_part, 0.9, out=(-1, 0, 0))
    m.quad((ix1, y, iz0), (ix0, y, iz0), (ix0, yt, iz0), (ix1, yt, iz0), inner_part, 0.9, out=(0, 0, 1))
    m.quad((ix0, y, iz0), (ix0, y, iz1), (ix0, yt, iz1), (ix0, yt, iz0), inner_part, 0.9, out=(1, 0, 0))
    m.quad((ix0, y, iz1), (ix1, y, iz1), (ix1, y, iz0), (ix0, y, iz0), deck_part, 1.0, out=(0, 1, 0))


def roof_box(m, cx, cz, w, d, y, h, part_side=PART_WALL, part_top=PART_ROOF):
    if h >= 1.5:
        m.roof_boxes.append((cx, cz, w, d, y, h, part_side, part_top))
    m.box(cx - w / 2, cx + w / 2, y, y + h, cz - d / 2, cz + d / 2, side=part_side, top=part_top, side_shade=0.92,
          top_shade=0.95)


def hip_roof(m, rect, y, rise, oh=0.4, part=PART_ROOF):
    """Hip roof over rect, ridge along the longer axis; rise measured at the wall line."""
    x0, x1, z0, z1 = rect
    wx, wz = x1 - x0, z1 - z0
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    hs = min(wx, wz) / 2.0
    slope = rise / hs
    ey = y - oh * slope
    ex0, ex1, ez0, ez1 = x0 - oh, x1 + oh, z0 - oh, z1 + oh
    ry = y + rise
    if wx >= wz:
        rx0, rx1, rz0, rz1 = x0 + hs, x1 - hs, cz, cz
    else:
        rx0, rx1, rz0, rz1 = cx, cx, z0 + hs, z1 - hs
    eps = 1e-4
    if wx >= wz:
        _roof_face(m, [(ex0, ey, ez1), (ex1, ey, ez1), (rx1, ry, rz1), (rx0, ry, rz0)], part, (0, 1, 1))
        _roof_face(m, [(ex1, ey, ez0), (ex0, ey, ez0), (rx0, ry, rz0), (rx1, ry, rz1)], part, (0, 1, -1))
        m.tri((ex1, ey, ez1), (ex1, ey, ez0), (rx1, ry, rz1), part, 1.0, out=(1, 1, 0))
        m.tri((ex0, ey, ez0), (ex0, ey, ez1), (rx0, ry, rz0), part, 1.0, out=(-1, 1, 0))
    else:
        _roof_face(m, [(ex1, ey, ez1), (ex1, ey, ez0), (rx1, ry, rz0), (rx0, ry, rz1)], part, (1, 1, 0))
        _roof_face(m, [(ex0, ey, ez0), (ex0, ey, ez1), (rx0, ry, rz1), (rx1, ry, rz0)], part, (-1, 1, 0))
        m.tri((ex0, ey, ez1), (ex1, ey, ez1), (rx1, ry, rz1), part, 1.0, out=(0, 1, 1))
        m.tri((ex1, ey, ez0), (ex0, ey, ez0), (rx0, ry, rz0), part, 1.0, out=(0, 1, -1))
    del eps


def _roof_face(m, pts, part, out):
    # drop duplicate points (pyramid roofs collapse a trapezoid to a triangle)
    uniq = []
    for p in pts:
        if not uniq or max(abs(p[i] - uniq[-1][i]) for i in range(3)) > 1e-4:
            uniq.append(p)
    if len(uniq) > 1 and max(abs(uniq[0][i] - uniq[-1][i]) for i in range(3)) <= 1e-4:
        uniq.pop()
    m.poly(uniq, part, 1.0, out=out)


def gable_roof(m, rect, y, rise, ridge_axis="x", oh=0.4, part=PART_ROOF, gable_part=PART_WALL, gable_shade=1.0):
    """Gable roof. ridge_axis 'x' = ridge parallel to the street (slopes face front/back, gables left/right);
    'z' = ridge perpendicular to the street (gables face the street)."""
    x0, x1, z0, z1 = rect
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    ry = y + rise
    if ridge_axis == "x":
        slope = rise / ((z1 - z0) / 2)
        ey = y - oh * slope
        ez0, ez1 = z0 - oh, z1 + oh
        _roof_face(m, [(x0, ey, ez1), (x1, ey, ez1), (x1, ry, cz), (x0, ry, cz)], part, (0, 1, 1))
        _roof_face(m, [(x1, ey, ez0), (x0, ey, ez0), (x0, ry, cz), (x1, ry, cz)], part, (0, 1, -1))
        m.tri((x1, y, z1), (x1, y, z0), (x1, ry, cz), gable_part, gable_shade, out=(1, 0, 0))
        m.tri((x0, y, z0), (x0, y, z1), (x0, ry, cz), gable_part, gable_shade, out=(-1, 0, 0))
    else:
        slope = rise / ((x1 - x0) / 2)
        ey = y - oh * slope
        ex0, ex1 = x0 - oh, x1 + oh
        _roof_face(m, [(ex1, ey, z1), (ex1, ey, z0), (cx, ry, z0), (cx, ry, z1)], part, (1, 1, 0))
        _roof_face(m, [(ex0, ey, z0), (ex0, ey, z1), (cx, ry, z1), (cx, ry, z0)], part, (-1, 1, 0))
        m.tri((x0, y, z1), (x1, y, z1), (cx, ry, z1), gable_part, gable_shade, out=(0, 0, 1))
        m.tri((x1, y, z0), (x0, y, z0), (cx, ry, z0), gable_part, gable_shade, out=(0, 0, -1))


def mono_roof(m, rect, y, rise, high_side="back", oh=0.3, part=PART_ROOF, wall_part=PART_WALL):
    """Single slope. high_side: 'back'|'front'|'left'|'right' (the tall edge). Side infill triangles/quads in wall colour."""
    x0, x1, z0, z1 = rect
    lo, hi = y, y + rise
    if high_side in ("back", "front"):
        zh, zl = (z0, z1) if high_side == "back" else (z1, z0)
        slope = rise / abs(z1 - z0)
        ey = lo - oh * slope
        zl_e = zl + (oh if zl > zh else -oh)
        _roof_face(m, [(x0, ey, zl_e), (x1, ey, zl_e), (x1, hi, zh), (x0, hi, zh)], part,
                   (0, 1, 1 if zl > zh else -1))
        m.poly([(x1, y, zl), (x1, y, zh), (x1, hi, zh)], wall_part, 1.0, out=(1, 0, 0))
        m.poly([(x0, y, zh), (x0, y, zl), (x0, hi, zh)], wall_part, 1.0, out=(-1, 0, 0))
        m.quad((x0, y, zh), (x1, y, zh), (x1, hi, zh), (x0, hi, zh), wall_part, 1.0,
               out=(0, 0, -1 if zh < zl else 1))
    else:
        xh, xl = (x0, x1) if high_side == "left" else (x1, x0)
        slope = rise / abs(x1 - x0)
        ey = lo - oh * slope
        xl_e = xl + (oh if xl > xh else -oh)
        _roof_face(m, [(xl_e, ey, z1), (xl_e, ey, z0), (xh, hi, z0), (xh, hi, z1)], part,
                   (1 if xl > xh else -1, 1, 0))
        m.poly([(x0, y, z1), (x1, y, z1), (xh, hi, z1)], wall_part, 1.0, out=(0, 0, 1))
        m.poly([(x1, y, z0), (x0, y, z0), (xh, hi, z0)], wall_part, 1.0, out=(0, 0, -1))
        m.quad((xh, y, z0), (xh, y, z1), (xh, hi, z1), (xh, hi, z0), wall_part, 1.0,
               out=(-1 if xh < xl else 1, 0, 0))


def sawtooth_roof(m, rect, y, rise, pitch, glass_part=PART_GLASS, part=PART_ROOF, wall_part=PART_WALL):
    """Teeth with ridges along Z, repeating along X every `pitch`; vertical glazing faces look to +X."""
    x0, x1, z0, z1 = rect
    n = max(1, int(round((x1 - x0) / pitch)))
    step = (x1 - x0) / n
    for i in range(n):
        a = x0 + i * step
        b = a + step
        m.quad((a, y, z1), (b, y + rise, z1), (b, y + rise, z0), (a, y, z0), part, 1.0, out=(-rise, step, 0))
        m.quad((b, y + rise, z1), (b, y, z1), (b, y, z0), (b, y + rise, z0), glass_part, 1.0, out=(1, 0, 0))
        m.tri((a, y, z1), (b, y, z1), (b, y + rise, z1), wall_part, 1.0, out=(0, 0, 1))
        m.tri((b, y, z0), (a, y, z0), (b, y + rise, z0), wall_part, 1.0, out=(0, 0, -1))


# ---------------------------------------------------------------------------------------------
# Facade helpers
# ---------------------------------------------------------------------------------------------
def floor_bases(floors, gf):
    """Base y of every floor and the eave height. gf = shop ground floor (4.2 m)."""
    bases = []
    y = 0.0
    for i in range(floors):
        bases.append(y)
        y += GF_H if (i == 0 and gf) else FLOOR_H
    return bases, y


def window_recs(centres, base, w, h, sill, depth=0.25, back=PART_GLASS):
    return [Rec(c - w / 2, c + w / 2, base + sill, base + sill + h, depth, back=back, reveal_shade=0.8)
            for c in centres]


def spaced(u0, u1, step, margin=0.0):
    """Evenly spaced centres in [u0+margin, u1-margin] with at most `step` spacing, symmetric."""
    span = (u1 - u0) - 2 * margin
    n = max(1, int(round(span / step)))
    s = span / n
    return [u0 + margin + s * (i + 0.5) for i in range(n)]


def shop_front(m, frame, u0, u1, zf, unit=4.5, pier=0.7, awning=True, shutter_every=3, seed=0):
    """Ground-floor shop band on the FRONT frame (u = x, front plane z = zf): glass recesses (0.3 deep) between
    wall piers, shutter units (accent), an awning plate at 3.0 m (1.2 m out, 0.15 thick). Returns the Rec list."""
    n = max(1, int(round((u1 - u0) / unit)))
    step = (u1 - u0) / n
    recs = []
    for i in range(n):
        a = u0 + i * step + pier / 2
        b = u0 + (i + 1) * step - pier / 2
        shutter = shutter_every > 0 and (i + seed) % shutter_every == 1
        recs.append(Rec(a, b, 0.0 if shutter else 0.4, 3.0, 0.3, back=PART_ACCENT if shutter else PART_GLASS,
                        reveal=PART_WALL, reveal_shade=0.8))
    if awning:
        m.box(u0, u1, 3.0, 3.15, zf, zf + 1.2, side=PART_ACCENT, top=PART_ACCENT, side_shade=0.9, top_shade=1.0,
              skip=("nz",))
    return recs


def dedupe_name(name):
    return name.replace(" ", "_").lower()


# ---------------------------------------------------------------------------------------------
# Blender export (the only bpy user)
# ---------------------------------------------------------------------------------------------
def export_glb(path, objects):
    """objects: ordered dict name -> Mesh (game frame). Writes a .glb with mat_kit, UV0 = (part id, shade)."""
    import bpy  # noqa: imported lazily so the geometry code runs without Blender

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    mat = bpy.data.materials.new("mat_kit")
    mat.use_nodes = True
    mat.use_backface_culling = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    created = []
    for name, m in objects.items():
        verts, polys, uvs = [], [], []
        for pts, part, shade in m.faces:
            idx = []
            for p in pts:
                verts.append((p[0], -p[2], p[1]))  # game (x, y, z) -> Blender Z-up (x, -z, y)
                idx.append(len(verts) - 1)
            polys.append(idx)
            uvs.append(((part + 0.5) / 16.0, 1.0 - shade))  # glTF exporter flips V: glTF TEXCOORD_0.y = shade
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts, [], polys)
        mesh.update()
        uv = mesh.uv_layers.new(name="UVMap")
        for poly, tex in zip(mesh.polygons, uvs):
            poly.use_smooth = False
            for li in poly.loop_indices:
                uv.data[li].uv = tex
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        created.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in created:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = created[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_materials="EXPORT", export_image_format="NONE", export_texcoords=True, export_normals=True,
        export_tangents=False, export_cameras=False, export_lights=False, export_extras=False,
        export_draco_mesh_compression_enable=False)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
