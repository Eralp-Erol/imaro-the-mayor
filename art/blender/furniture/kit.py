"""T-058 street-furniture geometry kit (pure Python, no bpy): flat-shaded polygon soup with atlas UVs.
Blender Z up, metres, origin on the ground centre, asset front = -Y (glTF +Z). Every polygon owns its vertices
(flat shading). UVs are planar per face with a window cropped from one 256 px atlas tile so texel density follows
the tile's world size (atlas.py WORLD_M); no randomness except fixed hash offsets.
"""
import json
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
LAYOUT=json.loads((ROOT/'assets/hero/furniture/atlas_layout.json').read_text())
UPRIGHT={'stone','shutter','fabric','kiosk_green','glass','plaster','roof','earth','shrub','concrete','terracotta'}
MARGIN=5/256


def sub(a,b):return (a[0]-b[0],a[1]-b[1],a[2]-b[2])
def add(a,b):return (a[0]+b[0],a[1]+b[1],a[2]+b[2])
def mul(a,s):return (a[0]*s,a[1]*s,a[2]*s)
def dot(a,b):return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def length(a):return math.sqrt(dot(a,a))
def unit(a):
    l=length(a);return (a[0]/l,a[1]/l,a[2]/l) if l>1e-9 else (0.0,0.0,1.0)
def centroid(pts):return mul(tuple(map(sum,zip(*pts))),1.0/len(pts))
def newell(pts):
    n=(0.0,0.0,0.0)
    for i,p in enumerate(pts):
        q=pts[(i+1)%len(pts)]
        n=add(n,((p[1]-q[1])*(p[2]+q[2]),(p[2]-q[2])*(p[0]+q[0]),(p[0]-q[0])*(p[1]+q[1])))
    return n


class Mesh:
    def __init__(self):self.V=[];self.F=[];self.UV=[];self.count=0

    @property
    def tris(self):return sum(len(f)-2 for f in self.F)

    def scale(self,sx,sy,sz):self.V=[(x*sx,y*sy,z*sz) for x,y,z in self.V]

    def bbox(self):
        return [min(v[i] for v in self.V) for i in range(3)],[max(v[i] for v in self.V) for i in range(3)]

    def poly(self,pts,region,mode=None,out=None):
        """Add one polygon. `out` = reference point the face must point away from (fixes winding for convex parts)."""
        pts=[tuple(map(float,p)) for p in pts]
        n=newell(pts)
        if out is not None and dot(n,sub(centroid(pts),out))<0:pts.reverse();n=mul(n,-1)
        n=unit(n);k=len(pts)
        mode=mode or ('upright' if region in UPRIGHT else 'long')
        if mode=='upright':
            z=(0.0,0.0,1.0);v=sub(z,mul(n,dot(z,n)))
            v=unit(v) if length(v)>.2 else (0.0,1.0,0.0)
            u=cross(v,n)
        else:
            best=max(range(k),key=lambda i:length(sub(pts[(i+1)%k],pts[i])))
            e=sub(pts[(best+1)%k],pts[best]);u=unit(sub(e,mul(n,dot(e,n))));v=cross(n,u)
        pu=[dot(p,u) for p in pts];pv=[dot(p,v) for p in pts]
        mu,mv=min(pu),min(pv);eu=max(max(pu)-mu,1e-4);ev=max(max(pv)-mv,1e-4)
        w=LAYOUT['world_m'][region];wu=min(1.0,eu/w);wv=min(1.0,ev/w)
        self.count+=1
        ou=((self.count*0.6180339887)%1.0)*(1-wu);ov=((self.count*0.7548776662)%1.0)*(1-wv)
        x0,y0,tw,th=LAYOUT['regions'][region];size=LAYOUT['size']
        start=len(self.V);self.V.extend(pts);self.F.append(tuple(range(start,start+k)))
        for a,b in zip(pu,pv):
            tu=ou+(a-mu)/eu*wu;tv=ov+(b-mv)/ev*wv
            px=x0+(MARGIN+tu*(1-2*MARGIN))*tw;py=y0+(1-(MARGIN+tv*(1-2*MARGIN)))*th
            self.UV.append((px/size,1-py/size))


FACES=('px','nx','py','ny','pz','nz')


def box(m,lo,hi,region,skip=(),regions=None):
    """Axis-aligned box lo..hi. Bottom face skipped when it rests on the ground. regions={'pz':'wood',...} overrides per face."""
    x0,y0,z0=lo;x1,y1,z1=hi;c=((x0+x1)/2,(y0+y1)/2,(z0+z1)/2)
    quads={'px':[(x1,y0,z0),(x1,y1,z0),(x1,y1,z1),(x1,y0,z1)],'nx':[(x0,y0,z0),(x0,y1,z0),(x0,y1,z1),(x0,y0,z1)],
           'py':[(x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)],'ny':[(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1)],
           'pz':[(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)],'nz':[(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0)]}
    skip=set(skip)
    if z0<=0.001:skip.add('nz')
    for name in FACES:
        if name not in skip:m.poly(quads[name],(regions or {}).get(name,region),out=c)


def to3(axis,s,p,q):
    return {'x':(s,p,q),'y':(p,s,q),'z':(p,q,s)}[axis]


def prism(m,axis,a,b,profile,region,skip_caps=(),regions=None):
    """Extrude a 2D profile (axis x: (y,z); y: (x,z); z: (x,y)) from a to b along `axis`; any simple polygon."""
    direction={'x':(1.0,0,0),'y':(0,1.0,0),'z':(0,0,1.0)}[axis]
    top=[to3(axis,b,p,q) for p,q in profile]
    if dot(newell(top),direction)<0:profile=list(reversed(profile));top=[to3(axis,b,p,q) for p,q in profile]
    bot=[to3(axis,a,p,q) for p,q in profile];k=len(profile)
    if 'top' not in skip_caps:m.poly(top,(regions or {}).get('cap',region))
    if 'bottom' not in skip_caps:m.poly(list(reversed(bot)),(regions or {}).get('cap',region))
    for i in range(k):
        m.poly([bot[i],bot[(i+1)%k],top[(i+1)%k],top[i]],region)


def rect_profile(p0,q0,p1,q1,ch=0.0):
    if ch<=0:return [(p0,q0),(p1,q0),(p1,q1),(p0,q1)]
    return [(p0+ch,q0),(p1-ch,q0),(p1,q0+ch),(p1,q1-ch),(p1-ch,q1),(p0+ch,q1),(p0,q1-ch),(p0,q0+ch)]


def bar(m,axis,a,b,p0,q0,p1,q1,region,ch=0.0,skip_caps=(),regions=None):
    prism(m,axis,a,b,rect_profile(p0,q0,p1,q1,ch),region,skip_caps,regions)


def ngon(cx,cy,r,n,phase=0.0):
    return [(cx+r*math.cos(phase+2*math.pi*i/n),cy+r*math.sin(phase+2*math.pi*i/n)) for i in range(n)]


def flat_n(n):return math.pi/n  # phase that puts a flat side towards -Y for even n (offset by -90 deg handled by caller)


def drum(m,cx,cy,z0,z1,r,n,region,phase=None,skip_caps=(),regions=None):
    """Regular n-gon prism (circumradius r), flat towards -Y by default."""
    phase=-math.pi/2+math.pi/n if phase is None else phase
    prism(m,'z',z0,z1,ngon(cx,cy,r,n,phase),region,skip_caps,regions)


def loft(m,rings,region,cap_first=True,cap_last=True,regions=None):
    """Connect consecutive rings (equal point counts) with quads; outward = away from the ring axis."""
    cs=[centroid(r) for r in rings];k=len(rings[0])
    for i in range(len(rings)-1):
        ref=mul(add(cs[i],cs[i+1]),.5)
        for j in range(k):
            m.poly([rings[i][j],rings[i][(j+1)%k],rings[i+1][(j+1)%k],rings[i+1][j]],region,out=ref)
    if cap_first:m.poly(rings[0],(regions or {}).get('cap',region),out=cs[1])
    if cap_last:m.poly(rings[-1],(regions or {}).get('cap',region),out=cs[-2])


def zring(cx,cy,z,r,n,phase=None):
    phase=-math.pi/2+math.pi/n if phase is None else phase
    return [(x,y,z) for x,y in ngon(cx,cy,r,n,phase)]


def tube(m,path,radii,sides,region,ref=(0.0,1.0,0.0),cap_first=True,cap_last=True,regions=None):
    """Tube along a polyline; rings are perpendicular to the averaged tangent (ref must not be parallel to it)."""
    rings=[]
    for i,p in enumerate(path):
        a=path[max(i-1,0)];b=path[min(i+1,len(path)-1)];t=unit(sub(b,a))
        side=unit(cross(t,ref));up=cross(side,t)
        rings.append([add(p,add(mul(side,radii[i]*math.cos(2*math.pi*j/sides)),mul(up,radii[i]*math.sin(2*math.pi*j/sides)))) for j in range(sides)])
    loft(m,rings,region,cap_first,cap_last,regions)


def arc(center,radius,a0,a1,steps,plane='xz'):
    pts=[]
    for i in range(steps+1):
        t=math.radians(a0+(a1-a0)*i/steps);c,s=math.cos(t)*radius,math.sin(t)*radius
        pts.append((center[0]+c,center[1],center[2]+s) if plane=='xz' else (center[0],center[1]+c,center[2]+s))
    return pts


def blob(m,center,radii,seg,rings,region,tilt=0.0,lower=True):
    """Faceted ellipsoid (UV-sphere, flat shaded); lower pole omitted when it sits inside the soil (z<center)."""
    ring_pts=[]
    for i in range(1,rings):
        phi=math.pi*i/rings;z=math.cos(phi)*radii[2];r=math.sin(phi)
        ring_pts.append([(center[0]+math.cos(tilt+2*math.pi*j/seg)*radii[0]*r,center[1]+math.sin(tilt+2*math.pi*j/seg)*radii[1]*r,center[2]+z) for j in range(seg)])
    top=(center[0],center[1],center[2]+radii[2]);bottom=(center[0],center[1],center[2]-radii[2])
    for j in range(seg):
        m.poly([top,ring_pts[0][(j+1)%seg],ring_pts[0][j]],region,out=center)
    for i in range(len(ring_pts)-1):
        for j in range(seg):
            m.poly([ring_pts[i][j],ring_pts[i][(j+1)%seg],ring_pts[i+1][(j+1)%seg],ring_pts[i+1][j]],region,out=center)
    for j in range(seg if lower else 0):
        m.poly([bottom,ring_pts[-1][j],ring_pts[-1][(j+1)%seg]],region,out=center)


def annulus(m,z,r_out,r_in,n,region,phase=None):
    """Flat upward-facing ring between two n-gons (e.g. a coping top)."""
    a=zring(0,0,z,r_out,n,phase);b=zring(0,0,z,r_in,n,phase)
    for j in range(n):
        m.poly([a[j],a[(j+1)%n],b[(j+1)%n],b[j]],region,out=(0.0,0.0,z-100.0))
