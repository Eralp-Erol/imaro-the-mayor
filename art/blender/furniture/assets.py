"""T-058 street-furniture proposals: eight parametric builders, each LOD0 (<=1600 tris) and LOD1 (<=240 tris).
Dimensions follow templates-v0 section f; where the template is silent the value is marked "working value" (calisma degeri).
Front = -Y. Metal colour (FN1/FN2) and every other Q-018 decision stays open: colours here are proposals, no logos/text,
no lamp light or emission.
"""
import math
from kit import (Mesh,box,bar,prism,drum,loft,zring,tube,arc,blob,annulus,ngon,rect_profile)

ASSETS=['bench','bin','lamp_street','bollard','bike_rack','bus_stop','planter','kiosk']
BUDGET={0:1600,1:240}
FLAT=-math.pi/2  # phase offset helper


def z8(z,r):return zring(0,0,z,r,8)


def apothem_r(across,n=8):return across/2/math.cos(math.pi/n)


def hex_bolt(m,axis_x,x,y,z,sign,r=0.014,h=0.008,region='metal_green'):
    """Hex bolt head on the outer face of a frame (axis x)."""
    prism(m,'x',x,x+sign*h,ngon(y,z,r,6),region,skip_caps=('bottom',) if sign>0 else ('top',))


def bench(m,lod):
    """Park bench 1.8 x 0.6 x 0.8 (templates-v0 f): cast-metal frames, timber slats."""
    xs=[-0.80,0.0,0.80] if lod==0 else [-0.80,0.80]
    for xc in xs:
        end=abs(xc)>0.1;t=0.025
        if lod==0:
            bar(m,'x',xc-t,xc+t,-0.25,0.02,-0.20,0.66 if end else 0.44,'metal_dark',ch=0.004)
            prism(m,'x',xc-t,xc+t,[(0.16,0.02),(0.21,0.02),(0.22,0.44),(0.285,0.80),(0.235,0.80),(0.17,0.44)],'metal_dark')
            bar(m,'x',xc-t,xc+t,-0.26,0.37,0.20,0.415,'metal_dark',ch=0.004)
            for y0,y1 in ((-0.29,-0.16),(0.12,0.25)):
                box(m,(xc-0.045,y0,0.0),(xc+0.045,y1,0.02),'metal_green')
            if end:
                bar(m,'y',-0.28,0.16,xc-t,0.63,xc+t,0.67,'metal_dark',ch=0.008)
                s=1 if xc>0 else -1
                for y,z in ((-0.20,0.39),(0.17,0.39),(-0.225,0.58)):hex_bolt(m,'x',xc+s*t,y,z,s)
        else:
            box(m,(xc-t,-0.25,0.0),(xc+t,-0.20,0.66),'metal_dark')
            prism(m,'x',xc-t,xc+t,[(0.16,0.0),(0.21,0.0),(0.22,0.44),(0.285,0.80),(0.235,0.80),(0.17,0.44)],'metal_dark')
            box(m,(xc-t,-0.26,0.37),(xc+t,0.20,0.415),'metal_dark')
            bar(m,'y',-0.28,0.16,xc-t,0.63,xc+t,0.67,'metal_dark')
    if lod==0:
        for i in range(4):
            y0=-0.28+0.115*i;bar(m,'x',-0.9,0.9,y0,0.44,y0+0.095,0.475,'wood',ch=0.008)
        bar(m,'x',-0.80,0.80,0.10,0.33,0.14,0.37,'metal_dark')
    else:
        box(m,(-0.9,-0.28,0.44),(0.9,-0.065,0.475),'wood');box(m,(-0.9,-0.05,0.44),(0.9,0.165,0.475),'wood')
    tilt=math.atan2(0.065,0.36);d=(math.sin(tilt),math.cos(tilt));nrm=(-math.cos(tilt),math.sin(tilt))
    heights=[(0.55,0.045),(0.65,0.045),(0.75,0.045)] if lod==0 else [(0.65,0.14)]
    for zc,half in heights:
        yc=0.17+(zc-0.44)*0.065/0.36+nrm[0]*0.0175*-1*-1;cy=yc+nrm[0]*0.0175;cz=zc+nrm[1]*0.0175
        pts=[(cy+sd*d[0]*half+sn*nrm[0]*0.0175,cz+sd*d[1]*half+sn*nrm[1]*0.0175) for sd,sn in ((-1,-1),(1,-1),(1,1),(-1,1))]
        prism(m,'x',-0.88,0.88,pts,'wood')


def bin_(m,lod):
    """Street litter bin 0.5 x 0.5 x 0.9 (templates-v0 f): octagonal sheet-metal drum, ribs, hooded lid."""
    R=apothem_r(0.44);Rb=apothem_r(0.46)
    drum(m,0,0,0.0,0.06,Rb,8,'metal_dark')
    drum(m,0,0,0.06,0.74 if lod==0 else 0.80,R,8,'metal_green',skip_caps=('top',) if lod==0 else ())
    if lod==0:
        for k in range(1,8):
            a=math.radians(-90+45*k);ca,sa=math.cos(a),math.sin(a);r0=0.22+0.006
            cx,cy=ca*r0,sa*r0;tx,ty=-sa,ca
            pts=[(cx+tx*sx*0.012+ca*sr*0.006,cy+ty*sx*0.012+sa*sr*0.006) for sx,sr in ((-1,-1),(1,-1),(1,1),(-1,1))]
            prism(m,'z',0.10,0.70,pts,'metal_dark',skip_caps=('bottom',))
        drum(m,0,0,0.38,0.41,Rb,8,'metal_dark',skip_caps=('bottom','top'))
        drum(m,0,0,0.74,0.80,apothem_r(0.50),8,'metal_dark',skip_caps=('bottom',))
        loft(m,[z8(0.80,apothem_r(0.46)),z8(0.88,apothem_r(0.34))],'metal_green',cap_first=False,cap_last=True)
        drum(m,0,0,0.88,0.90,0.035,6,'metal_dark',skip_caps=('bottom',))
        box(m,(-0.10,-0.2275,0.54),(0.10,-0.215,0.69),'metal_dark')
        for (x0,z0,x1,z1) in ((-0.12,0.52,0.12,0.54),(-0.12,0.69,0.12,0.71),(-0.12,0.54,-0.10,0.69),(0.10,0.54,0.12,0.69)):
            box(m,(x0,-0.2325,z0),(x1,-0.2175,z1),'metal_green')
    else:
        loft(m,[z8(0.80,apothem_r(0.46)),z8(0.88,apothem_r(0.34))],'metal_green',cap_first=False,cap_last=True)
        box(m,(-0.10,-0.2275,0.54),(0.10,-0.215,0.69),'metal_dark')


def lamp_street(m,lod):
    """Single-arm street pole, 8.0 m, arm reach 1.5 m (templates-v0 f). Luminaire body only: no emission, no night-light decision."""
    n=8 if lod==0 else 6
    if lod==0:
        box(m,(-0.14,-0.14,0.0),(0.14,0.14,0.02),'metal_dark')
        for sx in (-1,1):
            for sy in (-1,1):box(m,(sx*0.10-0.02,sy*0.10-0.02,0.02),(sx*0.10+0.02,sy*0.10+0.02,0.055),'metal_green')
        loft(m,[zring(0,0,0.02,0.14,n),zring(0,0,0.10,0.13,n),zring(0,0,0.15,0.105,n),zring(0,0,0.85,0.092,n)],'metal_green',cap_first=False,cap_last=False)
        loft(m,[zring(0,0,0.85,0.092,n),zring(0,0,4.5,0.072,n),zring(0,0,7.55,0.052,n)],'metal_green',cap_first=False,cap_last=False)
        for z0,z1,r in ((0.85,0.93,0.108),(4.45,4.57,0.085),(7.20,7.42,0.068)):drum(m,0,0,z0,z1,r,n,'metal_dark')
        loft(m,[zring(0,0,7.55,0.062,n),zring(0,0,7.70,0.032,n)],'metal_dark',cap_first=True,cap_last=True)
        box(m,(-0.05,-0.103,0.30),(0.05,-0.087,0.72),'metal_dark')
    else:
        box(m,(-0.14,-0.14,0.0),(0.14,0.14,0.05),'metal_dark')
        loft(m,[zring(0,0,0.05,0.10,n),zring(0,0,0.85,0.092,n),zring(0,0,7.60,0.052,n)],'metal_green',cap_first=False,cap_last=True)
    p0=(0.02,0,7.25);p1=(0.02,0,7.85);p2=(0.55,0,7.97);p3=(1.20,0,7.97);path=[]
    steps=8 if lod==0 else 3
    for i in range(steps+1):
        t=i/steps;a=(1-t)**3;b=3*(1-t)**2*t;c=3*(1-t)*t**2;d=t**3
        path.append(tuple(a*p0[k]+b*p1[k]+c*p2[k]+d*p3[k] for k in range(3)))
    tube(m,path,[0.045-0.013*i/steps for i in range(steps+1)],6 if lod==0 else 4,'metal_green',cap_first=False,cap_last=False)
    prism(m,'y',-0.12,0.12,[(0.95,7.84),(1.48,7.84),(1.53,7.90),(1.42,8.0),(1.00,8.0),(0.93,7.92)],'metal_green')
    box(m,(1.0,-0.09,7.82),(1.44,0.09,7.84),'roof')


def bollard(m,lod):
    """Pedestrian-area bollard, 0.2 diameter x 0.9 (templates-v0 f)."""
    if lod==0:
        drum(m,0,0,0.0,0.03,0.100/math.cos(math.pi/8),8,'metal_green')
        drum(m,0,0,0.03,0.14,0.088/math.cos(math.pi/8),8,'metal_green',skip_caps=('top',))
        drum(m,0,0,0.14,0.78,0.076/math.cos(math.pi/8),8,'metal_dark',skip_caps=('top',))
        drum(m,0,0,0.56,0.60,0.090/math.cos(math.pi/8),8,'metal_green')
        loft(m,[z8(0.78,0.082),z8(0.83,0.074),z8(0.87,0.045)],'metal_dark',cap_first=False,cap_last=True)
    else:
        drum(m,0,0,0.0,0.78,0.082,8,'metal_dark',skip_caps=('top',))
        loft(m,[z8(0.78,0.082),z8(0.87,0.045)],'metal_dark',cap_first=False,cap_last=True)


def bike_rack(m,lod):
    """Three inverted-U bike hoops, 0.70 wide x 0.85 high, 0.9 pitch (working values; templates-v0 f has no bike rack)."""
    for y in (-0.9,0.0,0.9):
        if lod==0:
            path=[(-0.35,y,0.0)]+arc((-0.17,y,0.66),0.18,180,90,4)+arc((0.17,y,0.66),0.18,90,0,4)+[(0.35,y,0.0)]
            tube(m,path,[0.021]*len(path),6,'metal_dark',cap_first=False,cap_last=False)
            for x in (-0.35,0.35):
                box(m,(x-0.055,y-0.055,0.0),(x+0.055,y+0.055,0.012),'metal_green')
                drum(m,x,y,0.012,0.065,0.034,6,'metal_green',skip_caps=('bottom',))
        else:
            path=[(-0.35,y,0.0),(-0.35,y,0.72),(-0.2,y,0.85),(0.2,y,0.85),(0.35,y,0.72),(0.35,y,0.0)]
            tube(m,path,[0.021]*6,4,'metal_dark',cap_first=False,cap_last=False)


def bus_stop(m,lod):
    """Bus shelter 5.0 x 1.6 x 2.6 (templates-v0 f): petrol frame FN6, dark glass, timber rafters/seat, concrete slab. No text/ads."""
    px=[-2.3,-0.77,0.77,2.3];ch=0.008 if lod==0 else 0.0
    box(m,(-2.5,-0.8,0.0),(2.5,0.8,0.10),'concrete')
    for x in px:
        if lod==0:bar(m,'z',0.10,2.46,x-0.035,0.565,x+0.035,0.635,'petrol',ch=ch)
        else:box(m,(x-0.035,0.565,0.10),(x+0.035,0.635,2.46),'petrol',skip=('pz',))
    for x in (-2.3,2.3):
        if lod==0:bar(m,'z',0.10,2.46,x-0.035,-0.655,x+0.035,-0.585,'petrol',ch=ch)
        else:box(m,(x-0.035,-0.655,0.10),(x+0.035,-0.585,2.46),'petrol',skip=('pz',))
    if lod==0:
        for a,b in zip(px[:-1],px[1:]):
            box(m,(a+0.035,0.59,0.32),(b-0.035,0.61,2.28),'glass')
            box(m,(a+0.035,0.56,0.10),(b-0.035,0.64,0.32),'petrol')
            box(m,(a+0.035,0.56,2.28),(b-0.035,0.64,2.46),'petrol')
        box(m,(-2.31,-0.585,0.32),(-2.29,0.565,2.28),'glass')
        box(m,(-2.34,-0.585,0.10),(-2.26,0.565,0.32),'petrol')
        box(m,(-2.34,-0.585,2.28),(-2.26,0.565,2.46),'petrol')
        for x in (-2.4+0.8*i for i in range(7)):
            box(m,(x-0.03,-0.74,2.38),(x+0.03,0.74,2.46),'wood',skip=('pz',))
        drum(m,2.36,0.66,0.10,2.46,0.025,6,'metal_dark')
        for x in px:
            prism(m,'x',x-0.015,x+0.015,[(0.565,2.46),(0.565,2.2),(0.32,2.46)],'petrol')
        for i in range(3):
            y0=0.17+0.14*i;bar(m,'x',-2.1,-0.95,y0,0.44,y0+0.12,0.475,'wood',ch=0.006)
        for x in (-2.0,-1.05):
            box(m,(x-0.02,0.50,0.10),(x+0.02,0.54,0.44),'metal_dark');box(m,(x-0.02,0.17,0.10),(x+0.02,0.21,0.44),'metal_dark')
            box(m,(x-0.02,0.17,0.40),(x+0.02,0.54,0.44),'metal_dark')
    else:
        box(m,(-2.265,0.59,0.30),(2.265,0.61,2.30),'glass')
        box(m,(-2.31,-0.585,0.30),(-2.29,0.565,2.30),'glass')
        box(m,(-2.1,0.17,0.44),(-0.95,0.54,0.475),'wood')
        for x in (-2.0,-1.05):box(m,(x-0.02,0.17,0.10),(x+0.02,0.54,0.44),'metal_dark',skip=('pz',))
    roof_regions={'pz':'roof','px':'petrol','nx':'petrol','py':'petrol','ny':'petrol','nz':'wood'}
    box(m,(-2.5,-0.8,2.46),(2.5,0.8,2.54),'petrol',regions=roof_regions)
    box(m,(-2.5,-0.8,2.54),(2.5,-0.74,2.60),'petrol',skip=('nz',));box(m,(-2.5,0.74,2.54),(2.5,0.8,2.60),'petrol',skip=('nz',))
    if lod==0:
        box(m,(-2.5,-0.74,2.54),(-2.44,0.74,2.60),'petrol',skip=('nz',));box(m,(2.44,-0.74,2.54),(2.5,0.74,2.60),'petrol',skip=('nz',))


def planter(m,lod):
    """Stone flower pot / planter, 1.2 across x 0.7 (templates-v0 f 'beton saksi + cali' made stone+earth: user asked tas/toprak)."""
    n=8
    def R(across):return apothem_r(across,n)
    drum(m,0,0,0.0,0.07,R(1.00),n,'stone')
    loft(m,[zring(0,0,0.07,R(1.06),n),zring(0,0,0.62,R(1.17),n)],'stone',cap_first=False,cap_last=False)
    if lod==0:drum(m,0,0,0.34,0.37,R(1.16),n,'stone',skip_caps=('bottom','top'))
    drum(m,0,0,0.62,0.70,R(1.20),n,'stone',skip_caps=('top',))
    annulus(m,0.70,R(1.20),R(1.00),n,'stone')
    m.poly(zring(0,0,0.70,R(1.00),n),'earth',out=(0.0,0.0,-100.0))
    if lod==0:
        for c,r in (((0,0,1.0),(.42,.40,.34)),((-.28,.12,.88),(.30,.30,.26)),((.30,-.10,.90),(.30,.30,.28)),((.05,.30,.86),(.26,.26,.24)),((-.05,-.30,.84),(.26,.26,.22))):
            blob(m,c,r,8,4,'shrub',tilt=0.3*c[0],lower=False)
    else:
        # low dome seated on the soil (z 0.70), centred on the pot axis like the LOD0 cluster, following its measured envelope (r 0.53 at soil, 0.61 widest, apex 1.34)
        rings=[zring(0,0,z,r,10) for z,r in ((0.70,0.49),(0.90,0.58),(1.10,0.50),(1.25,0.27))]
        loft(m,rings,'shrub',cap_first=False,cap_last=False)
        for j in range(10):m.poly([(0,0,1.34),rings[-1][(j+1)%10],rings[-1][j]],'shrub',out=(0,0,0.95))


def kiosk(m,lod):
    """Unbranded street kiosk 2.4 x 2.0 x 2.7 (templates-v0 f): green board body, service window, awning, closed shutter, stone plinth."""
    full=lod==0
    box(m,(-1.24,-0.54,0.0),(1.24,1.04,0.18),'stone')
    box(m,(-1.2,-0.42,0.18),(1.2,1.0,2.35),'kiosk_green',skip=('ny',) if full else ())
    # front wall around the service window (x -1.0..0.5, z 1.08..2.0) + closed shutter bay on the right
    parts=[((-1.2,-0.5,0.18),(0.62,-0.42,1.08)),((-1.2,-0.5,2.0),(0.62,-0.42,2.35)),((-1.2,-0.5,1.08),(-1.0,-0.42,2.0)),((0.5,-0.5,1.08),(0.62,-0.42,2.0))]
    if full:
        for lo,hi in parts:box(m,lo,hi,'kiosk_green')
    else:
        box(m,(-1.2,-0.5,0.18),(0.62,-0.42,1.08),'kiosk_green');box(m,(-1.2,-0.5,2.0),(0.62,-0.42,2.35),'kiosk_green')
    box(m,(-1.0,-0.435,1.08),(0.5,-0.42,2.0),'metal_dark')
    box(m,(0.62,-0.5,0.18),(1.2,-0.42,2.35),'shutter',regions={'px':'kiosk_green','nx':'kiosk_green','pz':'kiosk_green'})
    if full:
        for lo,hi in (((0.62,-0.515,0.18),(0.68,-0.5,2.35)),((1.14,-0.515,0.18),(1.2,-0.5,2.35)),((0.68,-0.515,2.29),(1.14,-0.5,2.35)),((0.68,-0.515,0.18),(1.14,-0.5,0.24))):
            box(m,lo,hi,'kiosk_green',skip=('py',))
        box(m,(0.72,-0.53,1.0),(0.78,-0.5,1.25),'metal_dark')
        for lo,hi in (((-1.03,-0.52,1.05),(-0.97,-0.48,2.03)),((0.47,-0.52,1.05),(0.53,-0.48,2.03)),((-0.97,-0.52,1.97),(0.47,-0.48,2.03))):
            box(m,lo,hi,'wood_aged')
    box(m,(-1.1,-0.82,1.06),(0.6,-0.5,1.11),'wood')
    if full:
        box(m,(-1.1,-0.82,0.92),(0.6,-0.80,1.06),'wood_aged')
        for x in (-0.8,0.3):prism(m,'x',x-0.015,x+0.015,[(-0.8,1.06),(-0.5,1.06),(-0.5,0.80)],'metal_dark')
    # awning (stripes run down the slope), valance, two end triangles, two ribs
    top_z,low_z=2.38,2.0
    m.poly([(-1.15,-0.5,top_z),(0.62,-0.5,top_z),(0.62,-1.0,low_z),(-1.15,-1.0,low_z)],'fabric',out=(0.0,-0.75,low_z-5.0))
    m.poly([(-1.15,-0.5,top_z-0.02),(-1.15,-1.0,low_z-0.02),(0.62,-1.0,low_z-0.02),(0.62,-0.5,top_z-0.02)],'fabric',out=(0.0,-0.75,top_z+5.0))
    m.poly([(-1.15,-1.0,low_z),(0.62,-1.0,low_z),(0.62,-1.0,low_z-0.16),(-1.15,-1.0,low_z-0.16)],'fabric',out=(0.0,5.0,low_z-0.08))
    if full:
        for x in (-1.15,0.62):
            m.poly([(x,-0.5,top_z),(x,-1.0,low_z),(x,-1.0,low_z-0.16),(x,-0.5,top_z-0.02)],'fabric',out=(x*-5.0,-0.75,low_z))
        for x in (-1.1,0.57):tube(m,[(x,-0.5,top_z-0.03),(x,-0.98,low_z-0.05)],[0.015,0.015],4,'metal_dark',ref=(1.0,0.0,0.0))
    # roof slab, parapet, roof hardware
    box(m,(-1.3,-0.6,2.35),(1.3,1.1,2.43),'concrete',regions={'pz':'roof'})
    for lo,hi in (((-1.3,-0.6,2.43),(1.3,-0.54,2.68)),((-1.3,1.04,2.43),(1.3,1.1,2.68)),((-1.3,-0.54,2.43),(-1.24,1.04,2.68)),((1.24,-0.54,2.43),(1.3,1.04,2.68))):
        box(m,lo,hi,'kiosk_green',skip=('nz',))
        if not full and lo[0]==-1.3 and lo[1]==-0.54:break
    if full:
        box(m,(0.3,0.4,2.43),(0.9,1.0,2.6),'roof');drum(m,-0.6,0.7,2.43,2.64,0.09,6,'metal_dark',skip_caps=('bottom',))
        # left side louver, right side door, rear corner downpipe
        box(m,(-1.215,0.2,1.7),(-1.2,0.7,2.1),'metal_dark')
        for i in range(5):box(m,(-1.235,0.2,1.72+0.075*i),(-1.2,0.7,1.76+0.075*i),'metal_green')
        box(m,(1.2,0.15,0.18),(1.215,0.85,2.1),'wood_aged')
        for lo,hi in (((1.2,0.12,0.18),(1.225,0.17,2.14)),((1.2,0.83,0.18),(1.225,0.88,2.14)),((1.2,0.17,2.10),(1.225,0.83,2.14))):box(m,lo,hi,'wood')
        box(m,(1.215,0.72,1.0),(1.24,0.78,1.12),'metal_dark')
        drum(m,1.15,1.06,0.18,2.40,0.035,6,'metal_dark')
    else:
        box(m,(-1.0,-0.82,1.06),(0.6,-0.5,1.11),'wood')
    m.scale(2.4/2.6,2.0/2.1,1.0)  # roof overhang/awning measured 2.6 x 2.1: fit to the template 2.4 x 2.0 footprint


BUILDERS={'bench':bench,'bin':bin_,'lamp_street':lamp_street,'bollard':bollard,'bike_rack':bike_rack,'bus_stop':bus_stop,'planter':planter,'kiosk':kiosk}


def build(name,lod):
    m=Mesh();BUILDERS[name](m,lod);return m
