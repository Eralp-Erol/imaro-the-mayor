"""T-059 human geometry kit (pure Python, no bpy): flat-shaded polygon soup with atlas UVs.
Blender Z up, metres, origin on the ground between the feet, figure front = -Y (glTF +Z). Every polygon owns its vertices
(flat shading). Each polygon is projected on its own plane and mapped into the centre of the flat atlas tile of its
material region (central 30% of the tile, so mip filtering never reaches a neighbouring tile). No randomness.
"""
import json
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
LAYOUT=json.loads((ROOT/'assets/hero/human/atlas_layout.json').read_text())
WINDOW=0.3


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
    def __init__(self):self.V=[];self.F=[];self.UV=[]

    @property
    def tris(self):return sum(len(f)-2 for f in self.F)

    def bbox(self):
        return [min(v[i] for v in self.V) for i in range(3)],[max(v[i] for v in self.V) for i in range(3)]

    def poly(self,pts,region,out=None):
        """Add one polygon. `out` = reference point the face must point away from (fixes winding of convex parts)."""
        pts=[tuple(map(float,p)) for p in pts]
        n=newell(pts)
        if out is not None and dot(n,sub(centroid(pts),out))<0:pts.reverse();n=mul(n,-1)
        n=unit(n)
        z=(0.0,0.0,1.0);v=sub(z,mul(n,dot(z,n)))
        v=unit(v) if length(v)>.2 else (0.0,1.0,0.0)
        u=cross(v,n)
        pu=[dot(p,u) for p in pts];pv=[dot(p,v) for p in pts];cu=sum(pu)/len(pu);cv=sum(pv)/len(pv)
        x0,y0,tw,th=LAYOUT['regions'][region];w,h=LAYOUT['size']
        start=len(self.V);self.V.extend(pts);self.F.append(tuple(range(start,start+len(pts))))
        for a,b in zip(pu,pv):
            tu=0.5+max(-0.5,min(0.5,(a-cu)/0.6))*WINDOW*2*0.5;tv=0.5+max(-0.5,min(0.5,(b-cv)/0.6))*WINDOW*2*0.5
            px=x0+tu*tw;py=y0+(1-tv)*th
            self.UV.append((px/w,1-py/h))


def ring(cx,cy,z,hx,hy,n):
    """n-gon ring (n = 4 or 8) whose x/y half extents (flat to flat) are hx/hy; n=4 gives the rectangle corners."""
    phase=math.pi/n;k=1.0/math.cos(math.pi/n)
    return [(cx+hx*k*math.cos(phase+2*math.pi*i/n),cy+hy*k*math.sin(phase+2*math.pi*i/n),z) for i in range(n)]


def loft(m,rings,region,cap_first=True,cap_last=True,regions=None):
    """Connect consecutive rings (equal point counts) with quads; outward = away from the ring axis."""
    cs=[centroid(r) for r in rings];k=len(rings[0])
    for i in range(len(rings)-1):
        ref=mul(add(cs[i],cs[i+1]),.5)
        for j in range(k):
            m.poly([rings[i][j],rings[i][(j+1)%k],rings[i+1][(j+1)%k],rings[i+1][j]],(regions or {}).get(i,region),out=ref)
    if cap_first:m.poly(rings[0],region,out=cs[1])
    if cap_last:m.poly(rings[-1],region,out=cs[-2])


def prism_x(m,x0,x1,profile,region,caps=True):
    """Extrude a (y,z) profile (convex or simple polygon) along x from x0 to x1."""
    ref=(( x0+x1)/2,sum(p[0] for p in profile)/len(profile),sum(p[1] for p in profile)/len(profile))
    a=[(x0,y,z) for y,z in profile];b=[(x1,y,z) for y,z in profile];k=len(profile)
    for i in range(k):m.poly([a[i],a[(i+1)%k],b[(i+1)%k],b[i]],region,out=ref)
    if caps:m.poly(a,region,out=ref);m.poly(b,region,out=ref)


def box(m,lo,hi,region,skip=()):
    x0,y0,z0=lo;x1,y1,z1=hi;c=((x0+x1)/2,(y0+y1)/2,(z0+z1)/2)
    quads={'px':[(x1,y0,z0),(x1,y1,z0),(x1,y1,z1),(x1,y0,z1)],'nx':[(x0,y0,z0),(x0,y1,z0),(x0,y1,z1),(x0,y0,z1)],
           'py':[(x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)],'ny':[(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1)],
           'pz':[(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)],'nz':[(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0)]}
    skip=set(skip)
    if z0<=0.001:skip.add('nz')
    for name,q in quads.items():
        if name not in skip:m.poly(q,region,out=c)
