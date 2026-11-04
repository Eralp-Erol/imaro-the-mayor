"""T-054 hero building families: shared layout (metres) for the atlas painter (Pillow) and the Blender builder.
Front facade on y=0 plane facing -Y; x centred; z up. Hole x0/x1 are centred-x for the front, depth-y for sides.
"""


def win(x0, x1, z0, z1, id="w", kind="win", shut="none"):
    return dict(kind=kind, x0=x0, x1=x1, z0=z0, z1=z1, id=id, shut=shut)


def _bazaar():
    W, D, GF, FL, NF = 10.8, 12.0, 4.2, 3.0, 2
    H = GF + NF * FL
    f1, f2 = GF, GF + FL
    holes = [win(-4.9, -1.7, 0.55, 3.4, "shopA", "shop"), win(-0.9, 0.9, 0.10, 3.05, "door", "door"),
             win(1.7, 4.9, 0.55, 3.4, "shopB", "shop"),
             win(-0.5, 0.5, f1 + 0.95, f1 + 2.65, "w10", "win", "open")]
    sh = ["open", "half", "closed", "open", "half"]
    for i, cx in enumerate((-4.32, -2.16, 0.0, 2.16, 4.32)):
        holes.append(win(cx - 0.5, cx + 0.5, f2 + 0.9, f2 + 2.6, "w2%d" % i, "win", sh[i]))
    return dict(name="bazaar", W=W, D=D, H=H, GF=GF, FL=FL, NF=NF, holes=holes,
                side=[win(y - 0.45, y + 0.45, f + 0.95, f + 2.5, "s") for f in (f1, f2) for y in (2.5, 6.0, 9.5)]
                + [win(y - 0.4, y + 0.4, 1.6, 2.7, "sg") for y in (3.0, 8.5)],
                courses=[f1, f2], plinth=0.7, quoins=True, dentils=True, style="plaster",
                signs=[(-5.1, -1.5, 3.55, 4.1), (1.5, 5.1, 3.55, 4.1)], rect_front=(0, 0, 432, 460), rect_side=(432, 0, 480, 460),
                roof=dict(kind="hip", pitch=22.0, over=0.6), cumba_wood=True)


def _mid():
    W, D, GF, FL, NF = 12.0, 14.0, 3.6, 2.9, 5
    H = GF + NF * FL
    holes = [win(-5.5, -2.3, 0.6, 3.0, "shopA", "shop"), win(-0.9, 0.9, 0.1, 2.9, "door", "door"), win(2.3, 5.5, 0.6, 3.0, "shopB", "shop")]
    for f in range(1, NF + 1):
        z = GF + (f - 1) * FL
        for i, c in enumerate((-4.5, -1.5, 1.5, 4.5)):
            holes.append(win(c - 1.35, c - 0.45, z + 0.05, z + 2.35, "bd%d%d" % (f, i), "door_win"))
            holes.append(win(c + 0.1, c + 1.3, z + 1.05, z + 2.35, "w%d%d" % (f, i), "win", "open" if (f + i) % 3 == 0 else "none"))
    return dict(name="res_mid", W=W, D=D, H=H, GF=GF, FL=FL, NF=NF, holes=holes,
                side=[win(y - 0.5, y + 0.5, GF + (f - 1) * FL + 0.9, GF + (f - 1) * FL + 2.3, "s") for f in range(1, NF + 1) for y in (3.5, 7.0, 10.5)],
                courses=[GF + k * FL for k in range(NF)], plinth=0.7, quoins=False, dentils=False, style="plaster",
                signs=[(-5.7, -2.1, 3.1, 3.5), (2.1, 5.7, 3.1, 3.5)], rect_front=(0, 0, 400, 616), rect_side=(400, 0, 460, 616),
                roof=dict(kind="flat", parapet=0.55), balcony=dict(proj=1.1, par=0.9), flat_equipment=True)


def _late():
    W, D, GF, FL, NF = 14.0, 16.0, 3.6, 2.9, 7
    H = GF + NF * FL
    holes = [win(-6.6, -1.6, 0.4, 3.1, "shopA", "shop"), win(-0.8, 0.8, 0.1, 2.9, "door", "door"), win(1.6, 6.6, 0.4, 3.1, "shopB", "shop")]
    for f in range(1, NF + 1):
        z = GF + (f - 1) * FL
        for i, c in enumerate((-5.6, -2.8, 0.0, 2.8, 5.6)):
            holes.append(win(c - 1.1, c + 1.1, z + 0.75, z + 2.25, "g%d%d" % (f, i), "wide"))
    return dict(name="res_late", W=W, D=D, H=H, GF=GF, FL=FL, NF=NF, holes=holes,
                side=[win(y - 0.7, y + 0.7, GF + (f - 1) * FL + 0.9, GF + (f - 1) * FL + 2.2, "s") for f in range(1, NF + 1) for y in (4.0, 8.0, 12.0)],
                courses=[], plinth=0.5, quoins=False, dentils=False, style="modern",
                signs=[], rect_front=(0, 0, 370, 640), rect_side=(370, 0, 420, 640),
                roof=dict(kind="flat", parapet=0.9), balcony=dict(proj=0.65, par=0.0), flat_equipment=True, fins=True)


def _house():
    W, D, GF, FL, NF = 8.0, 9.0, 2.9, 2.7, 1
    H = GF + NF * FL
    holes = [win(-0.55, 0.55, 0.1, 2.35, "door", "door"), win(-3.4, -1.9, 0.95, 2.25, "wl", "win", "open"), win(1.9, 3.4, 0.95, 2.25, "wr", "win", "open")]
    for i, c in enumerate((-2.65, 0.0, 2.65)):
        holes.append(win(c - 0.5, c + 0.5, GF + 0.75, GF + 2.05, "u%d" % i, "win", ("open", "half", "open")[i]))
    return dict(name="house", W=W, D=D, H=H, GF=GF, FL=FL, NF=NF, holes=holes,
                side=[win(y - 0.45, y + 0.45, 1.0, 2.2, "s") for y in (2.5, 6.5)] + [win(y - 0.45, y + 0.45, GF + 0.75, GF + 2.0, "s") for y in (2.5, 6.5)],
                courses=[GF], plinth=0.6, quoins=True, dentils=False, style="plaster", signs=[],
                rect_front=(0, 0, 400, 290), rect_side=(400, 0, 450, 290), roof=dict(kind="hip", pitch=28.0, over=0.5), garden=True)


def _ind():
    W, D, H = 16.0, 30.0, 7.2
    holes = [win(-6.8, -2.2, 0.0, 4.4, "gate", "gate"), win(3.0, 5.2, 1.3, 3.7, "dock", "dock"), win(6.4, 7.4, 0.0, 2.3, "pd", "door")]
    for i, c in enumerate((-5.0, 0.0, 5.0)):
        holes.append(win(c - 1.7, c + 1.7, 5.3, 6.5, "cl%d" % i, "wide"))
    return dict(name="industrial", W=W, D=D, H=H, GF=0, FL=0, NF=0, holes=holes,
                side=[win(y - 1.5, y + 1.5, 5.3, 6.5, "sc") for y in (3.0, 7.5, 12.0, 16.5, 21.0, 25.5)] + [win(2.0, 3.2, 0.0, 2.3, "sd", "door")],
                courses=[2.4], plinth=0.0, quoins=False, dentils=False, style="industrial", signs=[],
                rect_front=(0, 0, 512, 230), rect_side=(0, 240, 990, 238), roof=dict(kind="gable", pitch=14.0, over=0.5), dock=True)


def _civic():
    W, D, GF, FL, NF = 20.0, 15.0, 4.2, 4.0, 2
    H = GF + NF * FL
    holes = []
    for k, c in enumerate((-9.0, -7.0, -5.0, 5.0, 7.0, 9.0)):
        holes.append(win(c - 0.55, c + 0.55, 0.9, 3.3, "g%d" % k, "win", "none"))
        for f in (1, 2):
            z = GF + (f - 1) * FL
            holes.append(win(c - 0.55, c + 0.55, z + 0.7, z + 3.1, "u%d%d" % (f, k), "win", "open" if k % 2 == 0 else "none"))
    pav = []
    for k, c in enumerate((-1.9, 0.0, 1.9)):
        pav.append(win(c - 0.65, c + 0.65, 0.0, 3.2, "pd%d" % k, "door"))
        for f in (1, 2):
            z = GF + (f - 1) * FL
            pav.append(win(c - 0.6, c + 0.6, z + 0.6, z + 3.1, "pw%d%d" % (f, k), "win", "none"))
    return dict(name="civic", W=W, D=D, H=H, GF=GF, FL=FL, NF=NF, holes=holes + pav, holes_pav=pav, side=
                [win(y - 0.6, y + 0.6, z + 0.7, z + 3.2, "s") for z in (0.8, GF + 0.0, GF + FL) for y in (3.0, 7.5, 12.0)],
                courses=[GF, GF + FL], plinth=0.8, quoins=True, dentils=True, style="plaster", signs=[], rect_front=(0, 0, 500, 330),
                rect_side=(0, 320, 375, 330), roof=dict(kind="hip", pitch=18.0, over=0.7), tower=True)


FAMILIES = dict(bazaar=_bazaar, res_mid=_mid, res_late=_late, house=_house, industrial=_ind, civic=_civic)

VARIANTS = {
    "bazaar": {
        "a": dict(wall="#DAC9A6", wall_alt="#CDBA96", trim="#EBE0C8", stone="#B5A586", roof="#A06448", shutter="#6E7F70", awn1="#A98A5C", awn2="#DDD3BC", sign="#59695F", door="#6A4B38", wood="#6B4A36", seed=51),
        "b": dict(wall="#D2AE8E", wall_alt="#C6A283", trim="#EAD8C2", stone="#A89582", roof="#7E594A", shutter="#5C7482", awn1="#6F8C8A", awn2="#DAD2BC", sign="#6B4A3E", door="#4F5F66", wood="#4C5A48", seed=52),
        "c": dict(wall="#DCD2BE", wall_alt="#D0C5AF", trim="#F0EADA", stone="#B2A896", roof="#B98C64", shutter="#7A4F3B", awn1="#9C9061", awn2="#E6DCC2", sign="#4E5D5A", door="#5C6B54", wood="#7B5B3A", seed=53)},
    "res_mid": {
        "a": dict(wall="#D3C7B2", wall_alt="#C7BAA4", trim="#E9E1D0", stone="#A99F8E", roof="#9A6D56", shutter="#6E7F70", awn1="#B08A58", awn2="#E1D8C2", sign="#55645F", door="#5B4636", wood="#6B6256", seed=61),
        "b": dict(wall="#D8B79D", wall_alt="#CCAA90", trim="#EADBC8", stone="#A8998A", roof="#85604F", shutter="#5C7482", awn1="#718F8C", awn2="#DDD5C0", sign="#684B40", door="#46585F", wood="#7A6A58", seed=62),
        "c": dict(wall="#CFCBBE", wall_alt="#C3BFB1", trim="#E6E2D6", stone="#A4A092", roof="#A4745A", shutter="#7A6A5A", awn1="#9A8F66", awn2="#E4DCC4", sign="#4F5B5C", door="#5E6A58", wood="#6A6358", seed=63)},
    "res_late": {
        "a": dict(wall="#C9BFAE", wall_alt="#BEB4A3", trim="#DDD6C8", stone="#9E9689", roof="#8B8478", shutter="#6F7377", awn1="#8E8A78", awn2="#DCD6C6", sign="#4E5658", door="#4B545A", wood="#615B52", seed=71),
        "b": dict(wall="#D0C0A8", wall_alt="#C4B49C", trim="#E0D6C4", stone="#A39A8A", roof="#8A8074", shutter="#6B7479", awn1="#95896A", awn2="#DDD5C2", sign="#505857", door="#4F5C5A", wood="#625A4E", seed=72),
        "c": dict(wall="#D4CDC0", wall_alt="#C8C1B3", trim="#E4DFD3", stone="#A8A294", roof="#7E7A70", shutter="#6A7075", awn1="#8C8A7E", awn2="#DAD6CA", sign="#4C5558", door="#52585C", wood="#5E5850", seed=73)},
    "house": {
        "a": dict(wall="#DDCFB2", wall_alt="#D0C1A2", trim="#EDE5D2", stone="#B2A585", roof="#A66548", shutter="#6B7F72", awn1="#B08A58", awn2="#E3DAC2", sign="#59695F", door="#6A4B38", wood="#6B4A36", seed=81),
        "b": dict(wall="#D6B496", wall_alt="#C9A788", trim="#ECDCC8", stone="#A89684", roof="#8A5E49", shutter="#5F7685", awn1="#718F8C", awn2="#DDD5C0", sign="#684B40", door="#46585F", wood="#5C4636", seed=82),
        "c": dict(wall="#E1D9C6", wall_alt="#D5CCB8", trim="#F2EDDF", stone="#B5AB98", roof="#B88A60", shutter="#7A4F3B", awn1="#9C9061", awn2="#E6DCC2", sign="#4E5D5A", door="#5C6B54", wood="#7A5B3C", seed=83)},
    "industrial": {
        "a": dict(wall="#C9C0AE", wall_alt="#BCB3A1", trim="#DAD3C2", stone="#8F8578", roof="#8A9094", shutter="#6B7479", awn1="#8A5E43", awn2="#CFC8B6", sign="#4F5A5C", door="#6E7C74", wood="#7A6246", seed=91, brick="#9C6850", cont1="#6F8579", cont2="#9A6A4C"),
        "b": dict(wall="#D1C6B0", wall_alt="#C4B9A3", trim="#DED7C6", stone="#948A7A", roof="#9C8F82", shutter="#6B7479", awn1="#8A5E43", awn2="#CFC8B6", sign="#4F5A5C", door="#8A6048", wood="#7A6246", seed=92, brick="#A06A52", cont1="#7A8794", cont2="#B0A07A"),
        "c": dict(wall="#CBC5B8", wall_alt="#BEB8AB", trim="#DCD7CB", stone="#8F897D", roof="#7C8286", shutter="#6B7479", awn1="#8A5E43", awn2="#CFC8B6", sign="#4F5A5C", door="#5E7C84", wood="#7A6246", seed=93, brick="#94644E", cont1="#9A5E4C", cont2="#6C7F86")},
    "civic": {
        "a": dict(wall="#D6C7A6", wall_alt="#C9B994", trim="#ECE3CD", stone="#BBA98A", roof="#8C6050", shutter="#6B7C70", awn1="#A98A5C", awn2="#DDD3BC", sign="#59695F", door="#5A4234", wood="#5A4234", seed=101),
        "b": dict(wall="#D9CDB8", wall_alt="#CCC0AA", trim="#EEE8D8", stone="#B0A48E", roof="#76695F", shutter="#5F7482", awn1="#6F8C8A", awn2="#DAD2BC", sign="#4E5D5A", door="#46585F", wood="#46585F", seed=102),
        "c": dict(wall="#DDBFA2", wall_alt="#D0B196", trim="#EFE1CF", stone="#B6A28C", roof="#9A6A52", shutter="#6B7F72", awn1="#B08A58", awn2="#E1D8C2", sign="#6B4A3E", door="#5C4636", wood="#5C4636", seed=103)},
}
