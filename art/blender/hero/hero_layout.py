"""T-053 hero building: shared layout (metres) used by BOTH the atlas painter (Pillow) and the Blender generator.

Axes (Blender): +X right, front facade on the y=0 plane facing -Y, building runs +Y to D, +Z up.
glTF export (+Y up) turns this into: front faces +Z in Godot.
"""
W = 9.6          # facade width (m)
D = 11.0         # depth
GF = 3.7         # ground floor (shop band) height
FL = 3.0         # upper floor height (design/library: ~3 m)
NF = 3           # upper floors
H = GF + NF * FL # wall height 12.7
BAYS = [-3.6, -1.2, 1.2, 3.6]
PITCH_DEG = 24.0
OVER = 0.6       # eave overhang
FASCIA = 0.16


def fz(i):  # floor level z of upper floor i (1..3)
    return GF + (i - 1) * FL


def front_holes():
    """Openings on the front plane. kind: win|door_win|shop|door. shut: open|closed|half|none"""
    hs = []
    # ground
    hs.append(dict(kind="shop", x0=-4.35, x1=-1.55, z0=0.75, z1=2.95, id="shopA"))
    hs.append(dict(kind="door", x0=-0.95, x1=0.20, z0=0.18, z1=2.75, id="door"))
    hs.append(dict(kind="shop", x0=1.00, x1=4.35, z0=0.75, z1=2.95, id="shopB"))
    shut = {1: ["none", "none", "none", "none"],
            2: ["open", "open", "closed", "half"],
            3: ["half", "open", "open", "closed"]}
    for f in (1, 2, 3):
        for b, cx in enumerate(BAYS):
            if f == 2 and b < 2:
                continue  # cumba covers these two bays
            if f == 1 and b in (1, 2):
                z0, z1, kind = fz(f) + 0.10, fz(f) + 2.30, "door_win"
            elif f == 3:
                z0, z1, kind = fz(f) + 0.90, fz(f) + 2.60, "win"
            else:
                z0, z1, kind = fz(f) + 0.95, fz(f) + 2.70, "win"
            hs.append(dict(kind=kind, x0=cx - 0.5, x1=cx + 0.5, z0=z0, z1=z1, shut=shut[f][b],
                           id=f"w{f}{b}"))
    return hs


SIDE_Y = [2.3, 5.6, 8.9]


def side_holes():
    hs = []
    for y in (3.0, 8.0):
        hs.append(dict(kind="win", x0=y - 0.4, x1=y + 0.4, z0=1.5, z1=2.7, id="sg"))
    for f in (1, 2, 3):
        for y in SIDE_Y:
            hs.append(dict(kind="win", x0=y - 0.45, x1=y + 0.45, z0=fz(f) + 1.0, z1=fz(f) + 2.5, id=f"s{f}"))
    return hs  # x0/x1 here are along y (depth)


STRING_COURSES = [fz(1), fz(2), fz(3)]

VARIANTS = {
    "a": dict(wall="#D6C7AA", wall_alt="#CBB99B", trim="#EBE0C8", stone="#B5A586", roof="#9E6249",
              shutter="#6E7F70", awn1="#A98A5C", awn2="#DDD3BC", sign="#59695F", door="#6A4B38", seed=11),
    "b": dict(wall="#CFA68E", wall_alt="#C39984", trim="#EAD6C2", stone="#A89582", roof="#7C5848",
              shutter="#5C7482", awn1="#6F8C8A", awn2="#DAD2BC", sign="#6B4A3E", door="#4F5F66", seed=23),
    "c": dict(wall="#DDD3C0", wall_alt="#D0C5AF", trim="#F1ECDD", stone="#B2A896", roof="#B98C64",
              shutter="#7A4F3B", awn1="#9C9061", awn2="#E6DCC2", sign="#4E5D5A", door="#5C6B54", seed=37),
}
