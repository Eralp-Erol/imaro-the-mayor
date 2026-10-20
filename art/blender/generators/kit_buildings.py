"""Building family builders for the T-004 kit (first 8 modules of building-kit-v0 section 12).

Every builder returns (Mesh LOD0 in raw coordinates, mass dict). `mass` describes the massing so LOD1 and PROXY can be
derived consistently (same footprint, eave and roof form: spec section 7.2). `finish()` recentres the pivot on the
footprint union and returns the three meshes.
Variants are parameter tables (deterministic); `seed` only picks minor placements (roof boxes, shutter phase, ...).
"""
import math
import random

from kit_common import (
    EPS, FLOOR_H, GF_H, PARAPET_H, PART_ACCENT, PART_BRICK, PART_GLASS, PART_ROOF, PART_STONE, PART_TRIM,
    PART_WALL, RECESS_SHADE, SKIRT, Frame, Mesh, Rec, block_walls, flat_roof, floor_bases, gable_roof, hip_roof,
    mono_roof, roof_box, sawtooth_roof, shop_front, spaced, wall_frames, window_recs)

PARAPET = PARAPET_H


# ------------------------------------------------------------------------------------------------------------
# Shared pieces
# ------------------------------------------------------------------------------------------------------------
def balcony(u0, u1, base, depth=0.9):
    """Balcony recess band (spec 2.1: sill 0.9, opening 1.6, depth 0.6-1.2) with an inset glazing strip."""
    r = Rec(u0, u1, base + 0.9, base + 2.5, depth, back=PART_WALL, back_shade=RECESS_SHADE, reveal=PART_WALL,
            reveal_shade=0.8)
    if u1 - u0 > 1.6:
        r.deco = [(u0 + 0.4, u1 - 0.4, base + 1.2, base + 2.3, -depth + 0.03, PART_GLASS, 1.0)]
    return r


def slit(uc, v0, v1, w=0.8, depth=0.25):
    return Rec(uc - w / 2, uc + w / 2, v0, v1, depth, back=PART_GLASS, reveal=PART_WALL, reveal_shade=0.8)


def ground_floor_residential(w, door_u=0.0):
    recs = [Rec(door_u - 0.9, door_u + 0.9, 0.0, 2.4, 0.5, back=PART_ACCENT, reveal=PART_WALL, reveal_shade=0.8)]
    left = spaced(-w / 2, door_u - 1.5, 3.4, margin=1.0)
    right = spaced(door_u + 1.5, w / 2, 3.4, margin=1.0)
    recs += window_recs(left + right, 0.0, 1.4, 1.3, 1.0, 0.25)
    return recs


def snap(v):
    return round(v * 2.0) / 2.0


def mass_block(rect, h, flat=False, y0=0.0, main=False, wall_part=PART_WALL, fp=True):
    return {"rect": rect, "h": h, "flat": flat, "y0": y0, "main": main, "wall_part": wall_part, "fp": fp}


def parapet_boxes(m, lower, upper, y):
    """Parapet strips on the edges of `lower` where `upper` is set back (setback storey terraces)."""
    x0, x1, z0, z1 = lower
    ux0, ux1, uz0, uz1 = upper
    t, h = 0.3, PARAPET
    if uz1 < z1 - 0.5:
        m.box(x0, x1, y, y + h, z1 - t, z1, side=PART_WALL, top=PART_TRIM, top_shade=1.0, skip=("nz",))
    if ux1 < x1 - 0.5:
        m.box(x1 - t, x1, y, y + h, max(z0, uz0 if uz0 > z0 + 0.5 else z0), z1, side=PART_WALL, top=PART_TRIM,
              skip=("nx",))
    if ux0 > x0 + 0.5:
        m.box(x0, x0 + t, y, y + h, max(z0, uz0 if uz0 > z0 + 0.5 else z0), z1, side=PART_WALL, top=PART_TRIM,
              skip=("px",))
    if uz0 > z0 + 0.5:
        m.box(x0, x1, y, y + h, z0, z0 + t, side=PART_WALL, top=PART_TRIM, skip=("pz",))


# ------------------------------------------------------------------------------------------------------------
# B  res_mid
# ------------------------------------------------------------------------------------------------------------
RES_MID = {
    "a": dict(floors=4, w=14.0, d=11.0, pattern="full", boxes=1, gf=True),
    "b": dict(floors=5, w=18.0, d=12.0, pattern="split", boxes=2, gf=True),
    "c": dict(floors=5, w=12.0, d=10.0, pattern="solid_corner", boxes=1, gf=True),
    "d": dict(floors=6, w=20.0, d=14.0, pattern="alt", boxes=2, gf=False),
}


def _mid_pattern(pattern, w, floor_index, base):
    hw = w / 2.0
    if pattern == "full":
        return [balcony(-hw + 1.5, hw - 1.5, base)]
    if pattern == "split":
        return [balcony(-hw + 1.2, -1.0, base), balcony(1.0, hw - 1.2, base)]
    if pattern == "solid_corner":
        return [balcony(-hw + 1.5, hw - 5.5, base)]
    if pattern == "alt":
        if floor_index % 2 == 1:
            return [balcony(-hw + 1.5, hw - 1.5, base)]
        return [balcony(-hw + 3.0, -1.0, base), balcony(1.0, hw - 3.0, base)]
    raise ValueError(pattern)


def build_res_mid(v, gf, rng):
    s = RES_MID[v]
    w, d, n = s["w"], s["d"], s["floors"]
    rect = (-w / 2, w / 2, -d / 2, d / 2)
    bases, h = floor_bases(n, gf)
    m = Mesh()
    front, back = [], []
    if gf:
        front += shop_front(m, None, -w / 2, w / 2, rect[3], seed=rng.randrange(3))
    else:
        front += ground_floor_residential(w)
    for i in range(1, n):
        front += _mid_pattern(s["pattern"], w, i, bases[i])
    if s["pattern"] == "split":
        front.append(slit(0.0, bases[1] + 0.9, h - 1.0, 0.8))
    if s["pattern"] == "solid_corner":
        front.append(slit(w / 2 - 2.6, bases[1] + 0.9, h - 1.0, 0.7))
    for i in range(n):
        back.append(Rec(-0.5, 0.5, bases[i] + 1.0, bases[i] + 2.3, 0.2, back=PART_GLASS, reveal_shade=0.8))
    block_walls(m, rect, 0.0, h + PARAPET, {"front": front, "back": back})
    flat_roof(m, rect, h)
    bw, bd = 2.5, 3.0
    spots = [(-w / 4, rect[2] + 3.5), (w / 4, rect[2] + 3.5), (0.0, 0.0)]
    rng.shuffle(spots)
    for k in range(s["boxes"]):
        cx, cz = spots[k]
        if k == 1 and v in ("b", "d"):
            roof_box(m, snap(cx), snap(cz), 1.5, 1.5, h, 1.6)        # water tank
        else:
            roof_box(m, snap(cx), snap(cz), bw, bd, h, 2.6)          # stair box
    mass = {"blocks": [mass_block(rect, h, flat=True, main=True)], "roofs": [], "gf": gf, "roof_type": "flat",
            "eave": h}
    return m, mass


# ------------------------------------------------------------------------------------------------------------
# A  res_old
# ------------------------------------------------------------------------------------------------------------
RES_OLD = {
    "a": dict(floors=3, w=7.0, d=12.0, roof="hip", rise=2.2, bay=(0.0, 3.0), gf=True),
    "b": dict(floors=2, w=8.0, d=11.0, roof="gable_x", rise=2.0, bay=(-2.0, 2.5), gf=False, plinth=0.5),
    "c": dict(floors=3, w=7.0, d=13.0, roof="flat", rise=0.0, bay=(1.5, 2.5), gf=True),
    "d": dict(floors=2, w=7.0, d=10.0, roof="hip", rise=1.8, bay=None, gf=False, plinth=0.5),
}


def _bay(m, cx, bw, y0, y1, zf, depth=0.8):
    m.box(cx - bw / 2, cx + bw / 2, y0, y1, zf, zf + depth, side=PART_WALL, top=PART_ROOF, side_shade=1.0,
          bottom=PART_TRIM, skip=("pz",))
    fr = Frame((0, 0, zf + depth), (1, 0, 0), (0, 1, 0), (0, 0, 1))
    recs = []
    base = y0
    while base + 3.0 <= y1 + 0.01:
        recs.append(Rec(cx - 0.8, cx + 0.8, base + 0.8, base + 2.4, 0.15, back=PART_GLASS, reveal_shade=0.8))
        base += 3.0
    fr.tile(m, cx - bw / 2, cx + bw / 2, y0, y1, recs, PART_WALL, 1.0)  # bay front with its window recesses


def build_res_old(v, gf, rng):
    s = RES_OLD[v]
    w, d, n = s["w"], s["d"], s["floors"]
    rect = (-w / 2, w / 2, -d / 2, d / 2)
    bases, h = floor_bases(n, gf)
    pl = s.get("plinth", 0.0)          # raised stone plinth (old houses): keeps 3.0 m storeys, eave 6.5 m for 2 floors
    bases = [b + pl for b in bases]
    h += pl
    m = Mesh()
    front, back, sides = [], [], []
    bay = s["bay"]
    centres = spaced(-w / 2, w / 2, 2.8, margin=1.0)
    for i in range(n):
        if i == 0 and gf:
            front += shop_front(m, None, -w / 2, w / 2, rect[3], unit=3.5, seed=rng.randrange(3))
            continue
        if i == 0:
            front.append(Rec(-w / 2 + 1.2, -w / 2 + 2.4, 0, 2.2 + pl, 0.4, back=PART_ACCENT, reveal_shade=0.8))
            front += window_recs([c for c in centres if c > -w / 2 + 3.0], pl, 1.1, 1.5, 0.9, 0.25)
            continue
        cs = centres
        if bay is not None and i >= 1:
            cs = [c for c in centres if abs(c - bay[0]) > bay[1] / 2 + 0.7]
        front += window_recs(cs, bases[i], 1.1, 1.5, 0.9, 0.25)
        back += window_recs([0.0], bases[i], 1.1, 1.5, 0.9, 0.2)
    if s["roof"] == "flat":
        block_walls(m, rect, 0.0, h + PARAPET, {"front": front, "back": back})
        flat_roof(m, rect, h)
        roof_box(m, snap(w / 4), snap(rect[2] + 3.0), 1.5, 1.5, h, 2.0)
        mass = {"blocks": [mass_block(rect, h, flat=True, main=True)], "roofs": [], "gf": gf,
                "roof_type": "flat", "eave": h}
    else:
        block_walls(m, rect, 0.0, h, {"front": front, "back": back})
        if s["roof"] == "hip":
            hip_roof(m, rect, h, s["rise"], oh=0.45)
            rt, ridge = "hip", "x"
        else:
            gable_roof(m, rect, h, s["rise"], "x", oh=0.45)
            rt, ridge = "gable", "x"
        mass = {"blocks": [mass_block(rect, h, main=True)],
                "roofs": [{"type": rt, "rect": rect, "y": h, "rise": s["rise"], "ridge": ridge, "oh": 0.45}],
                "gf": gf, "roof_type": rt, "eave": h}
    if bay is not None:
        _bay(m, bay[0], bay[1], bases[1], h, rect[3])
    return m, mass


# ------------------------------------------------------------------------------------------------------------
# C  res_late
# ------------------------------------------------------------------------------------------------------------
RES_LATE = {
    "a": dict(floors=6, w=18.0, d=16.0, roof="flat", setback=2.0, corners=("r",), core=False, gf=True),
    "b": dict(floors=7, w=24.0, d=14.0, roof="hip", setback=0.0, corners=("l", "r"), core=False, gf=True),
    "c": dict(floors=5, w=16.0, d=12.0, roof="flat", setback=0.0, corners=("l",), core=True, gf=False),
}


def _corner_balcony(m, side, x0, x1, zf, base, bw=3.0, out=1.3, h=1.1):
    if side == "r":
        a, b = x1 - bw, x1
    else:
        a, b = x0, x0 + bw
    m.box(a, b, base, base + h, zf, zf + out, side=PART_TRIM, top=PART_TRIM, side_shade=0.95, top_shade=1.0,
          skip=("nz",))


def build_res_late(v, gf, rng):
    s = RES_LATE[v]
    w, d, n = s["w"], s["d"], s["floors"]
    rect = (-w / 2, w / 2, -d / 2, d / 2)
    x0, x1, z0, z1 = rect
    bases, h = floor_bases(n, gf)
    sb = s["setback"]
    m = Mesh()
    top_idx = n - 1 if sb > 0 else n
    h_low = bases[top_idx] if sb > 0 else h
    front, back = [], []
    for i in range(top_idx):
        if i == 0 and gf:
            front += shop_front(m, None, x0, x1, z1, unit=4.5, seed=rng.randrange(3))
            continue
        if i == 0:
            front += ground_floor_residential(w, 0.0)
            continue
        lo = x0 + (3.4 if "l" in s["corners"] else 1.0)
        hi = x1 - (3.4 if "r" in s["corners"] else 1.0)
        seg = 3 if hi - lo > 12 else 2
        step = (hi - lo) / seg
        for k in range(seg):
            a = lo + k * step + (0.4 if k > 0 else 0.0)
            b = lo + (k + 1) * step - (0.4 if k < seg - 1 else 0.0)
            front.append(Rec(a, b, bases[i] + 0.9, bases[i] + 2.4, 0.3, back=PART_GLASS, reveal_shade=0.8))
        back += window_recs([0.0], bases[i], 1.2, 1.4, 1.0, 0.2)
    block_walls(m, rect, 0.0, h_low if sb > 0 else h + PARAPET, {"front": front, "back": back})
    for i in range(1, top_idx):
        for sd in s["corners"]:
            _corner_balcony(m, sd, x0, x1, z1, bases[i])
    if s["core"]:
        m.box(-2.0, 2.0, 0.0, h, z1, z1 + 0.6, side=PART_WALL, top=PART_TRIM, side_shade=0.95)
        fr = Frame((0, 0, z1 + 0.6), (1, 0, 0), (0, 1, 0), (0, 0, 1))
        fr.rect(m, -0.4, 0.4, 3.0, h - 1.0, 0.03, PART_GLASS, 1.0)
    blocks = [mass_block(rect, h_low, flat=(sb == 0 and s["roof"] == "flat"), main=True)]
    roofs = []
    if sb > 0:
        urect = (x0, x1, z0, z1 - sb)
        ufront = []
        for k in range(3):
            c = x0 + 3.0 + k * (w - 6.0) / 2
            ufront.append(Rec(c - 2.4, c + 2.4, bases[top_idx] + 0.9, bases[top_idx] + 2.4, 0.3, back=PART_GLASS,
                              reveal_shade=0.8))
        block_walls(m, urect, h_low, h + PARAPET, {"front": ufront}, skirt=False, register=False)
        # lower roof terrace in front of the set-back storey
        m.quad((x0, h_low, z1), (x1, h_low, z1), (x1, h_low, z0), (x0, h_low, z0), PART_ROOF, 1.0, out=(0, 1, 0))
        parapet_boxes(m, rect, urect, h_low)
        flat_roof(m, urect, h)
        blocks.append(mass_block(urect, h, flat=True, y0=h_low, fp=False))
        roofs = []
        blocks[0]["flat"] = False
        blocks[0]["terrace"] = True
        roof_box(m, 0.0, snap(z0 + 3.0), 2.5, 3.0, h, 2.6)
    elif s["roof"] == "hip":
        hip_roof(m, rect, h, 2.0, oh=0.5)
        roofs = [{"type": "hip", "rect": rect, "y": h, "rise": 2.0, "ridge": "x", "oh": 0.5}]
        blocks[0]["flat"] = False
    else:
        flat_roof(m, rect, h)
        roof_box(m, snap(-w / 4), snap(z0 + 3.0), 2.5, 3.0, h, 2.6)
        roof_box(m, snap(w / 4), snap(z0 + 3.0), 1.5, 1.5, h, 1.6)
    mass = {"blocks": blocks, "roofs": roofs, "gf": gf, "roof_type": "hip" if s["roof"] == "hip" else "flat",
            "eave": h}
    return m, mass


# ------------------------------------------------------------------------------------------------------------
# E  res_house
# ------------------------------------------------------------------------------------------------------------
RES_HOUSE = {
    "a": dict(floors=1, w=7.0, d=9.0, roof="hip", rise=2.0, annex=False),
    "b": dict(floors=2, w=7.5, d=8.5, roof="gable_z", rise=1.9, annex=False),
    "c": dict(floors=2, w=8.0, d=9.0, roof="hip", rise=2.2, annex=True),
    "d": dict(floors=2, w=10.0, d=8.5, roof="gable_x", rise=2.0, annex=False, twin=True),
    "e": dict(floors=1, w=7.5, d=10.0, roof="gable_x", rise=1.9, annex=False, veranda=True),
}


def build_res_house(v, gf, rng):
    s = RES_HOUSE[v]
    w, d, n = s["w"], s["d"], s["floors"]
    rect = (-w / 2, w / 2, -d / 2, d / 2)
    x0, x1, z0, z1 = rect
    h = n * FLOOR_H
    m = Mesh()
    front, left, right, back = [], [], [], []
    if s.get("twin"):   # twin house: two doors side by side, windows outside them
        for dx in (-1.0, 1.0):
            front.append(Rec(dx - 0.5, dx + 0.5, 0, 2.2, 0.35, back=PART_ACCENT, reveal_shade=0.8))
        for i in range(n):
            base = i * FLOOR_H
            cs = [-3.4, 3.4] + ([-1.0, 1.0] if i > 0 else [])
            front += window_recs(cs, base + (0.0 if i == 0 else 0.0), 1.2, 1.3, 0.9, 0.2)
    else:
        front.append(Rec(-w / 2 + 1.0, -w / 2 + 2.1, 0, 2.2, 0.35, back=PART_ACCENT, reveal_shade=0.8))
        for i in range(n):
            base = i * FLOOR_H
            centres = spaced(-w / 2 + 2.8, w / 2, 2.6, margin=0.9) if i == 0 else spaced(-w / 2, w / 2, 2.6, margin=1.0)
            front += window_recs(centres, base, 1.2, 1.3, 0.9, 0.2)
    for i in range(n):
        base = i * FLOOR_H
        left += window_recs([0.0], base, 1.0, 1.3, 0.9, 0.2)
        right += window_recs([0.0], base, 1.0, 1.3, 0.9, 0.2)
        back += window_recs([0.0], base, 1.0, 1.3, 0.9, 0.2)
    if s["annex"]:
        left = []
    block_walls(m, rect, 0.0, h, {"front": front, "left": left, "right": right, "back": back})
    blocks = [mass_block(rect, h, main=True)]
    roofs = []
    if s["roof"] == "hip":
        hip_roof(m, rect, h, s["rise"], oh=0.5)
        rt = "hip"
        roofs.append({"type": "hip", "rect": rect, "y": h, "rise": s["rise"], "ridge": "x", "oh": 0.5})
    else:
        ridge = "z" if s["roof"] == "gable_z" else "x"
        gable_roof(m, rect, h, s["rise"], ridge, oh=0.5)
        rt = "gable"
        roofs.append({"type": "gable", "rect": rect, "y": h, "rise": s["rise"], "ridge": ridge, "oh": 0.5})
        if ridge == "z":   # porch canopy above the door
            m.box(-w / 2 + 0.4, -w / 2 + 2.7, 2.6, 2.75, z1, z1 + 1.1, side=PART_TRIM, top=PART_ROOF, skip=("nz",))
    if s.get("veranda"):
        m.box(x0 + 0.3, x1 - 0.3, 2.7, 2.85, z1, z1 + 1.4, side=PART_ACCENT, top=PART_ACCENT, side_shade=0.9,
              skip=("nz",))
        for px in (x0 + 0.5, 0.0, x1 - 0.5):
            m.box(px - 0.1, px + 0.1, 0.0, 2.7, z1 + 1.2, z1 + 1.4, side=PART_TRIM, top=None, side_shade=0.9)
    roof_box(m, snap(w / 4), snap(-d / 6), 0.8, 0.8, h + s["rise"] * 0.55, 1.2, PART_TRIM, PART_TRIM)
    if s["annex"]:
        arect = (x0 - 2.5, x0, -3.0, 3.0)
        block_walls(m, arect, 0.0, FLOOR_H, {"front": window_recs([-1.5], 0.0, 1.0, 1.2, 1.0, 0.2)},
                    sides=("front", "back", "left"))
        mono_roof(m, arect, FLOOR_H, 0.9, high_side="right", oh=0.3)
        blocks.append(mass_block(arect, FLOOR_H))
        roofs.append({"type": "mono", "rect": arect, "y": FLOOR_H, "rise": 0.9, "high": "right", "oh": 0.3})
    mass = {"blocks": blocks, "roofs": roofs, "gf": False, "roof_type": rt, "eave": h}
    return m, mass


# ------------------------------------------------------------------------------------------------------------
# I  ind_shed
# ------------------------------------------------------------------------------------------------------------
IND_SHED = {
    "a": dict(w=40.0, d=24.0, eave=7.5, roof="gable", pitch=10.0, doors=3, annex=False),
    "b": dict(w=36.0, d=28.0, eave=7.0, roof="saw", tooth=1.6, pitch=4.5, doors=2, annex=False),
    "c": dict(w=46.0, d=30.0, eave=8.5, roof="gable", pitch=8.0, doors=4, annex=True),
}


def build_ind_shed(v, gf, rng):
    s = IND_SHED[v]
    w, d, h = s["w"], s["d"], s["eave"]
    rect = (-w / 2, w / 2, -d / 2, d / 2)
    x0, x1, z0, z1 = rect
    m = Mesh()
    front, back, left, right = [], [], [], []
    nd = s["doors"]
    door_c = spaced(x0, x1, w / nd, margin=0.0)
    for c in door_c:
        front.append(Rec(c - 2.5, c + 2.5, 0.0, 5.0, 0.3, back=PART_ACCENT, reveal_shade=0.8))
    for sx in (-1, 1):
        front.append(Rec(sx * (w / 2 - 2.0) - 0.6, sx * (w / 2 - 2.0) + 0.6, 1.0, 2.2, 0.2, back=PART_GLASS,
                         reveal_shade=0.8))
    # high ribbon glazing between doors (clerestory)
    for c0, c1 in zip(door_c[:-1], door_c[1:]):
        front.append(Rec(c0 + 4.0, c1 - 4.0, h - 2.6, h - 1.2, 0.2, back=PART_GLASS, reveal_shade=0.8))
    back += [Rec(c - 2.0, c + 2.0, 0.0, 4.2, 0.3, back=PART_ACCENT, reveal_shade=0.8) for c in (-w / 4, w / 4)]
    left.append(Rec(-1.5, 1.5, 0.0, 4.0, 0.3, back=PART_ACCENT, reveal_shade=0.8))
    block_walls(m, rect, 0.0, h, {"front": front, "back": back, "left": left})
    blocks = [mass_block(rect, h, main=True)]
    roofs = []
    if s["roof"] == "gable":
        rise = (d / 2) * math.tan(math.radians(s["pitch"]))
        gable_roof(m, rect, h, rise, "x", oh=0.3)
        roofs.append({"type": "gable", "rect": rect, "y": h, "rise": rise, "ridge": "x", "oh": 0.3})
        rt = "gable"
    else:
        sawtooth_roof(m, rect, h, s["tooth"], s["pitch"])
        roofs.append({"type": "saw", "rect": rect, "y": h, "rise": s["tooth"], "pitch": s["pitch"]})
        rt = "sawtooth"
    if s["annex"]:
        arect = (x1, x1 + 10.0, z0, z1)
        block_walls(m, arect, 0.0, 4.5, {"front": [Rec(1.5, 6.5, 0.0, 3.6, 0.3, back=PART_ACCENT)],
                                         "back": [Rec(-6.5, -1.5, 0.0, 3.6, 0.3, back=PART_ACCENT)]},
                    sides=("front", "back", "right"))
        mono_roof(m, arect, 4.5, 0.8, high_side="left", oh=0.25)
        blocks.append(mass_block(arect, 4.5))
        roofs.append({"type": "mono", "rect": arect, "y": 4.5, "rise": 0.8, "high": "left", "oh": 0.25})
        # loading canopy on the front (cantilever + posts)
        m.box(x0 + 8, x0 + 28, 5.0, 5.2, z1, z1 + 3.0, side=PART_ACCENT, top=PART_ROOF, side_shade=0.9)
        for px in (x0 + 8.5, x0 + 27.5):
            m.box(px - 0.15, px + 0.15, 0.0, 5.0, z1 + 2.7, z1 + 3.0, side=PART_TRIM, top=None, side_shade=0.9)
    mass = {"blocks": blocks, "roofs": roofs, "gf": False, "roof_type": rt, "eave": h}
    return m, mass


# ------------------------------------------------------------------------------------------------------------
# K  ind_heritage
# ------------------------------------------------------------------------------------------------------------
IND_HERITAGE = {
    "a": dict(w=30.0, d=18.0, floors=2, material=PART_BRICK, roof="gable", pitch=22.0, tower=False),
    "b": dict(w=32.0, d=18.0, floors=2, material=PART_STONE, roof="saw", tooth=1.8, pitch=5.0, tower=True),
}
STOREY_K = 5.0


def build_ind_heritage(v, gf, rng):
    s = IND_HERITAGE[v]
    w, d, n = s["w"], s["d"], s["floors"]
    h = n * STOREY_K
    mat = s["material"]
    rect = (-w / 2, w / 2, -d / 2, d / 2)
    x0, x1, z0, z1 = rect
    m = Mesh()
    front = []
    cs = [c for c in spaced(x0, x1, 4.0, margin=2.0) if abs(c) > 2.6]
    for i in range(n):
        base = i * STOREY_K
        for c in cs:
            front.append(Rec(c - 0.8, c + 0.8, base + 1.0, base + 4.0, 0.3, back=PART_GLASS, reveal=mat,
                             reveal_shade=0.8))
    front.append(Rec(-1.6, 1.6, 0.0, 4.0, 0.4, back=PART_ACCENT, reveal=mat, reveal_shade=0.8))
    side = []
    for i in range(n):
        base = i * STOREY_K
        side += [Rec(c - 0.8, c + 0.8, base + 1.0, base + 4.0, 0.3, back=PART_GLASS, reveal=mat, reveal_shade=0.8)
                 for c in spaced(z0, z1, 4.5, margin=3.0)]
    block_walls(m, rect, 0.0, h, {"front": front, "left": side, "right": side}, part=mat, skirt_part=mat)
    # cornice band (trim) along the eave
    m.box(x0 - 0.15, x1 + 0.15, h - 0.5, h, z0 - 0.15, z1 + 0.15, side=mat, top=None, side_shade=0.85,
          skip=("ny",))
    blocks = [mass_block(rect, h, main=True, wall_part=mat)]
    roofs = []
    if s["roof"] == "gable":
        rise = (d / 2) * math.tan(math.radians(s["pitch"]))
        gable_roof(m, rect, h, rise, "x", oh=0.3, gable_part=mat)
        roofs.append({"type": "gable", "rect": rect, "y": h, "rise": rise, "ridge": "x", "oh": 0.3})
        rt = "gable"
    else:
        sawtooth_roof(m, rect, h, s["tooth"], s["pitch"], wall_part=mat)
        roofs.append({"type": "saw", "rect": rect, "y": h, "rise": s["tooth"], "pitch": s["pitch"]})
        rt = "sawtooth"
    if s["tower"]:
        trect = (x0, x0 + 6.0, z1 - 1.0, z1 + 5.0)
        th = 14.0
        # front frame u = absolute x, left frame u = absolute z
        trecs = {"front": [Rec(x0 + 1.5, x0 + 4.5, 3.0, 5.5, 0.3, back=PART_GLASS, reveal=mat),
                           Rec(x0 + 1.5, x0 + 4.5, 8.5, 11.0, 0.3, back=PART_GLASS, reveal=mat)],
                 "left": [Rec(z1 + 0.5, z1 + 3.5, 3.0, 5.5, 0.3, back=PART_GLASS, reveal=mat),
                          Rec(z1 + 0.5, z1 + 3.5, 8.5, 11.0, 0.3, back=PART_GLASS, reveal=mat)]}
        block_walls(m, trect, 0.0, th, trecs, part=mat, skirt_part=mat, sides=("front", "left", "right"))
        hip_roof(m, trect, th, 3.0, oh=0.4)
        blocks.append(mass_block(trect, th, wall_part=mat))
        roofs.append({"type": "hip", "rect": trect, "y": th, "rise": 3.0, "ridge": "x", "oh": 0.4})
    mass = {"blocks": blocks, "roofs": roofs, "gf": False, "roof_type": rt, "eave": h}
    return m, mass


# ------------------------------------------------------------------------------------------------------------
# L  civ_hall
# ------------------------------------------------------------------------------------------------------------
CIV_HALL = {
    "a": dict(kind="entry", floors=3, w=40.0, d=24.0),
    "b": dict(kind="u", floors=3, w=44.0, d=28.0),
    "c": dict(kind="stepped", floors=4, w=36.0, d=22.0),
}
STOREY_L = 4.0


def _hall_windows(centres, floors, skip_fn=None):
    recs = []
    for i in range(floors):
        base = i * STOREY_L
        for c in centres:
            if skip_fn and skip_fn(i, c):
                continue
            recs.append(Rec(c - 0.8, c + 0.8, base + 1.0, base + 3.2, 0.35, back=PART_GLASS, reveal_shade=0.8))
    return recs


def build_civ_hall(v, gf, rng):
    s = CIV_HALL[v]
    n, w, d = s["floors"], s["w"], s["d"]
    h = n * STOREY_L
    m = Mesh()
    kind = s["kind"]
    blocks, roofs = [], []
    if kind == "entry":
        rect = (-w / 2, w / 2, -d / 2, d / 2)
        x0, x1, z0, z1 = rect
        cs = spaced(x0, x1, 4.4, margin=2.0)
        front = _hall_windows(cs, n, skip_fn=lambda i, c: i <= 1 and abs(c) < 7.0)
        front.append(Rec(-5.0, 5.0, 0.0, 6.6, 0.6, back=PART_GLASS, reveal_shade=0.8))
        slits = [slit(0.0, 4.0, h - 1.5, 1.2, 0.3)]
        block_walls(m, rect, 0.0, h + PARAPET, {"front": front, "left": slits, "right": slits,
                                               "back": _hall_windows(spaced(x0, x1, 8.8, margin=3.0), n)})
        flat_roof(m, rect, h)
        # entry portico: 4 piers + slab + steps
        m.box(-7.0, 7.0, 7.4, 8.0, z1, z1 + 4.0, side=PART_TRIM, top=PART_ROOF, side_shade=0.95, skip=("nz",))
        for px in (-5.5, -1.8, 1.8, 5.5):
            m.box(px - 0.5, px + 0.5, 0.0, 7.4, z1 + 3.0, z1 + 4.0, side=PART_STONE, top=None)
        for k in range(3):
            za = z1 + 4.0 + k * 0.8
            m.box(-7.0, 7.0, 0.0, 0.45 - 0.15 * k, za, za + 0.8, side=PART_STONE, top=PART_STONE, skip=("nz", "nx",
                                                                                                      "px"))
        blocks = [mass_block(rect, h, flat=True, main=True),
                  mass_block((-7.0, 7.0, z1, z1 + 4.0), 8.0, flat=False, fp=False)]
        blocks[1]["terrace"] = True
    elif kind == "u":
        wing_w = 12.0
        cbody = (-w / 2 + wing_w, w / 2 - wing_w, -d / 2, -d / 2 + 10.0)
        lw = (-w / 2, -w / 2 + wing_w, -d / 2, d / 2)
        rw = (w / 2 - wing_w, w / 2, -d / 2, d / 2)
        x0, x1, z0, z1 = -w / 2, w / 2, -d / 2, d / 2
        cs_in = spaced(cbody[0], cbody[1], 4.4, margin=2.0)
        centre_front = _hall_windows(cs_in, n, skip_fn=lambda i, c: i == 0 and abs(c) < 3.0)
        centre_front.append(Rec(-2.5, 2.5, 0.0, 5.0, 0.5, back=PART_GLASS, reveal_shade=0.8))
        block_walls(m, cbody, 0.0, h + PARAPET, {"front": centre_front, "back": _hall_windows([0.0], n)},
                    sides=("front", "back"))
        flat_roof(m, cbody, h)
        wing_fronts = _hall_windows(spaced(0.0, wing_w, 4.4, margin=2.0), n)
        zc = spaced(z0 + 11.0, z1, 4.4, margin=1.8)           # courtyard-facing windows, clear of the centre body
        for rect, inner in ((lw, "right"), (rw, "left")):
            fx = [Rec(r.u0 + rect[0], r.u1 + rect[0], r.v0, r.v1, r.depth, r.back, r.back_shade, r.reveal,
                      r.reveal_shade) for r in wing_fronts]
            sign = -1.0 if inner == "right" else 1.0         # right frame u = -z, left frame u = z
            inner_recs = []
            for i in range(n):
                base = i * STOREY_L
                for c in zc:
                    u = sign * c
                    inner_recs.append(Rec(u - 0.8, u + 0.8, base + 1.0, base + 3.2, 0.35, back=PART_GLASS))
            block_walls(m, rect, 0.0, h + PARAPET, {"front": fx, inner: inner_recs})
            flat_roof(m, rect, h)
        blocks = [mass_block(cbody, h, flat=True, main=True), mass_block(lw, h, flat=True),
                  mass_block(rw, h, flat=True)]
    else:  # stepped
        low = (-w / 2, w / 2, -d / 2, d / 2)
        x0, x1, z0, z1 = low
        h_low = 2 * STOREY_L
        up = (-w / 2 + 6.0, w / 2 - 6.0, -d / 2 + 2.0, d / 2 - 4.0)
        cs = spaced(x0, x1, 3.6, margin=2.0)
        front = _hall_windows(cs, 2)
        front.append(Rec(-2.0, 2.0, 0.0, 5.0, 0.5, back=PART_GLASS, reveal_shade=0.8))
        front = [r for r in front if not (r.v0 < 4.0 and r.v0 > 0.5 and abs((r.u0 + r.u1) / 2) < 3.0)]
        block_walls(m, low, 0.0, h_low, {"front": front, "back": _hall_windows(spaced(x0, x1, 7.2, margin=3.0), 2)})
        m.quad((x0, h_low, z1), (x1, h_low, z1), (x1, h_low, z0), (x0, h_low, z0), PART_ROOF, 1.0, out=(0, 1, 0))
        parapet_boxes(m, low, up, h_low)
        ucs = spaced(up[0], up[1], 3.6, margin=2.0)
        ufront = []
        for i in range(2):
            base = h_low + i * STOREY_L
            ufront += [Rec(c - 0.8, c + 0.8, base + 1.0, base + 3.2, 0.35, back=PART_GLASS) for c in ucs]
        block_walls(m, up, h_low, h, {"front": ufront}, skirt=False, register=False)
        hip_roof(m, up, h, 1.5, oh=0.5)
        blocks = [mass_block(low, h_low, main=True), mass_block(up, h, y0=h_low, fp=False)]
        roofs = [{"type": "hip", "rect": up, "y": h, "rise": 1.5, "ridge": "x", "oh": 0.5}]
        blocks[0]["terrace"] = True
    mass = {"blocks": blocks, "roofs": roofs, "gf": False, "roof_type": "hip" if kind == "stepped" else "flat",
            "eave": h}
    return m, mass


# ------------------------------------------------------------------------------------------------------------
# LOD1 / PROXY from massing
# ------------------------------------------------------------------------------------------------------------
def _block_top(b):
    return b["h"] + (PARAPET if b.get("flat") else 0.0)


def lod1_from_mass(mass):
    m = Mesh()
    for b in mass["blocks"]:
        x0, x1, z0, z1 = b["rect"]
        y0, yt = b["y0"], _block_top(b)
        wp = b.get("wall_part", PART_WALL)
        fr = wall_frames(x0, x1, z0, z1)
        for side in ("front", "back", "right", "left"):
            u0, u1 = _range(side, b["rect"])
            if side == "front" and mass.get("gf") and b.get("main"):
                fr[side].rect(m, u0, u1, y0, GF_H, 0.0, PART_ACCENT, 0.9)
                fr[side].rect(m, u0, u1, GF_H, yt, 0.0, wp, 1.0)
            else:
                fr[side].rect(m, u0, u1, y0, yt, 0.0, wp, 1.0)
            if y0 <= 0.0:
                fr[side].rect(m, u0, u1, -SKIRT, 0.0, 0.0, PART_STONE, 0.8)
        if b.get("flat") or b.get("terrace"):
            m.quad((x0, yt if b.get("flat") else b["h"], z1), (x1, yt if b.get("flat") else b["h"], z1),
                   (x1, yt if b.get("flat") else b["h"], z0), (x0, yt if b.get("flat") else b["h"], z0), PART_ROOF,
                   1.0, out=(0, 1, 0))
    for r in mass["roofs"]:
        _roof(m, r, lod=1)
    return m


def _range(side, rect):
    x0, x1, z0, z1 = rect
    return {"front": (x0, x1), "back": (-x1, -x0), "right": (-z1, -z0), "left": (z0, z1)}[side]


def _roof(m, r, lod):
    t = r["type"]
    if t == "hip":
        hip_roof(m, r["rect"], r["y"], r["rise"], oh=r.get("oh", 0.4))
    elif t == "gable":
        gable_roof(m, r["rect"], r["y"], r["rise"], r.get("ridge", "x"), oh=r.get("oh", 0.4))
    elif t == "mono":
        mono_roof(m, r["rect"], r["y"], r["rise"], r.get("high", "back"), oh=r.get("oh", 0.3))
    elif t == "saw":
        x0, x1, z0, z1 = r["rect"]
        y = r["y"] + r["rise"] * 0.5
        m.quad((x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0), PART_ROOF, 1.0, out=(0, 1, 0))
        for side in ("front", "back"):
            pass
        # close the 0.5*rise gap on the four walls
        fr = wall_frames(x0, x1, z0, z1)
        for side in ("front", "back", "right", "left"):
            u0, u1 = _range(side, r["rect"])
            fr[side].rect(m, u0, u1, r["y"], y, 0.0, PART_WALL, 1.0)


def proxy_from_mass(mass):
    """<= 14 triangles: open-bottom box (10) or roof prism (<= 14) over the union of the blocks."""
    m = Mesh()
    blocks = mass["blocks"]
    roofs = mass["roofs"]
    single = len(blocks) == 1 and len(roofs) <= 1
    if single:
        b = blocks[0]
        rect = b["rect"]
        pitched = bool(roofs) and roofs[0]["type"] in ("hip", "gable", "mono")
        if pitched:
            top = b["h"]
        elif roofs:   # sawtooth: flat cap at mid-tooth
            top = b["h"] + roofs[0]["rise"] * 0.5
        else:
            top = _block_top(b)
        _box_open(m, rect, -SKIRT, top, b.get("wall_part", PART_WALL))
        if pitched:
            _roof(m, roofs[0], lod=2)
        else:
            x0, x1, z0, z1 = rect
            m.quad((x0, top, z1), (x1, top, z1), (x1, top, z0), (x0, top, z0), PART_ROOF, 1.0, out=(0, 1, 0))
        return m
    rect = (min(b["rect"][0] for b in blocks), max(b["rect"][1] for b in blocks),
            min(b["rect"][2] for b in blocks), max(b["rect"][3] for b in blocks))
    top = max(_block_top(b) for b in blocks)
    _box_open(m, rect, -SKIRT, top, blocks[0].get("wall_part", PART_WALL))
    x0, x1, z0, z1 = rect
    m.quad((x0, top, z1), (x1, top, z1), (x1, top, z0), (x0, top, z0), PART_ROOF, 1.0, out=(0, 1, 0))
    return m


def _box_open(m, rect, y0, y1, part):
    x0, x1, z0, z1 = rect
    fr = wall_frames(x0, x1, z0, z1)
    for side in ("front", "back", "right", "left"):
        u0, u1 = _range(side, rect)
        fr[side].rect(m, u0, u1, y0, y1, 0.0, part, 1.0)


def finish(m0, mass):
    """Recentre the pivot on the footprint union (0.5 m grid); build LOD1 + PROXY with the same shift."""
    m1 = lod1_from_mass(mass)
    for cx, cz, w, d, y, h, ps, pt in m0.roof_boxes:   # roof-top volumes stay in LOD1 (silhouette / shadow match)
        m1.box(cx - w / 2, cx + w / 2, y, y + h, cz - d / 2, cz + d / 2, side=ps, top=pt, side_shade=0.92,
               top_shade=0.95)
    mp = proxy_from_mass(mass)
    fps = [b["rect"] for b in mass["blocks"] if b.get("fp", True)]
    x0 = min(r[0] for r in fps)
    x1 = max(r[1] for r in fps)
    z0 = min(r[2] for r in fps)
    z1 = max(r[3] for r in fps)
    cx, cz = (x0 + x1) / 2.0, (z0 + z1) / 2.0
    for mm in (m0, m1, mp):
        mm.translate(-cx, 0.0, -cz)
    mass["footprint"] = (x1 - x0, z1 - z0)
    return m0, m1, mp


BUILDERS = {
    "res_mid": (build_res_mid, RES_MID),
    "res_old": (build_res_old, RES_OLD),
    "res_late": (build_res_late, RES_LATE),
    "res_house": (build_res_house, RES_HOUSE),
    "ind_shed": (build_ind_shed, IND_SHED),
    "ind_heritage": (build_ind_heritage, IND_HERITAGE),
    "civ_hall": (build_civ_hall, CIV_HALL),
}
