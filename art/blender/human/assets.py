"""T-059 human style proposals: pawn (A), block figure (B), facet figure (C) x two body ratios (neutral, broad).
Same 1.75 m adult, same standing A-pose (arms hang ~6 degrees away from the body, palms inward), same working outfit
(plain shirt/jacket, trousers, shoes), same atlas. LOD0 <= 900, LOD1 <= 100 triangles. Front = -Y.
Working values (calisma degeri, Q-018 is open): both ratios are 1.75 m tall so only the body ratio differs. neutral shoulder width
~0.46 m (between templates-v0 hum_adult_f_a 0.42 and hum_adult_m_a 0.48), broad ~0.56 m (hum_adult_broad_a, template 1.74 -> 1.75).
No face detail, no logo/text/symbol, no cultural or religious dress, no uniform, no named character, no seasonal decision.
"""
from kit import Mesh,ring,loft,prism_x,box

STYLES=['pawn','block','facet']
RATIOS=['neutral','broad']
ASSETS=['%s_%s'%(s,r) for s in STYLES for r in RATIOS]
BUDGET={0:900,1:100}
HEIGHT=1.75
# body half extents (m): shoulder torso hw/hd, waist, hip, upper arm / forearm / wrist hw, leg hw + centre x, ankle hw
RATIO={'neutral':dict(sh=.15,sd=.105,wa=.135,wd=.09,hp=.16,hd=.10,ua=.036,fa=.030,wr=.024,lg=.075,lgx=.085,ank=.040),
       'broad':dict(sh=.18,sd=.13,wa=.19,wd=.12,hp=.20,hd=.125,ua=.046,fa=.039,wr=.030,lg=.093,lgx=.105,ank=.048)}
Z_SH=1.40  # shoulder joint
SLOPE=0.05  # arm A-pose: x drift per metre below the shoulder


def arm_x(p,z,side):return side*(p['sh']+0.01+p['ua']+(Z_SH-z)*SLOPE)


def outer_half(p):return p['sh']+0.01+2*p['ua']


def hair(m,n,cx,cy,hx,hy,z_front,z_back,z_mid,z_top):
    """Hair mass over a head: sloped lower edge (hairline high at the front, low at the back), no face, no fringe detail."""
    lower=[]
    for x,y,_ in ring(cx,cy,0,hx,hy,n):
        t=max(0.0,min(1.0,(y-(cy-hy*1.08))/(2*hy*1.08)));lower.append((x,y,z_front+(z_back-z_front)*t))
    loft(m,[lower,ring(cx,cy,z_mid,hx,hy,n),ring(cx,cy,z_top,hx*.78,hy*.78,n)],'hair',cap_first=False,cap_last=True)


def head(m,style,p):
    cy=-0.005
    if style=='facet':
        loft(m,[ring(0,cy,1.50,.052,.070,8),ring(0,cy,1.56,.072,.090,8),ring(0,cy,1.64,.084,.100,8),ring(0,cy,1.72,.080,.097,8)],'skin',cap_first=False,cap_last=False)
        hair(m,8,0,cy,.089,.106,1.70,1.55,1.725,1.75)
    else:
        loft(m,[ring(0,cy,1.50,.068,.085,4),ring(0,cy,1.62,.085,.100,4),ring(0,cy,1.72,.082,.098,4)],'skin',cap_first=False,cap_last=False)
        hair(m,4,0,cy,.092,.106,1.69,1.55,1.725,1.75)


def head_lod1(m):
    loft(m,[ring(0,-.005,1.46,.055,.085,4),ring(0,-.005,1.72,.083,.099,4)],'skin',cap_first=False,cap_last=False)
    hair(m,4,0,-.005,.092,.106,1.69,1.55,1.725,1.75)


def pawn(m,p,lod):
    """A: one limbless prism (shoe band, trousers, shirt, shoulder shelf), neck, box head (templates-v0 a.1 piyon)."""
    W=outer_half(p);n=8 if lod==0 else 4
    loft(m,[ring(0,0,0,p['hp']*.92,p['hd']+.015,n),ring(0,0,.08,p['hp']*.92,p['hd']+.015,n)],'shoe',cap_first=False,cap_last=False)
    loft(m,[ring(0,0,.08,p['hp']*.92,p['hd']+.015,n),ring(0,0,.90,p['hp'],p['hd'],n)],'bottom',cap_first=False,cap_last=False)
    rings=[ring(0,0,.90,p['hp'],p['hd'],n),ring(0,0,1.30,p['sh']+.01,p['sd'],n),ring(0,0,1.38,W,p['sd']*.95,n),ring(0,0,1.43,.075,.06,n)]
    if lod==1:rings=[rings[0],rings[2],rings[3]]
    loft(m,rings,'top',cap_first=False,cap_last=False)
    loft(m,[ring(0,0,1.42,.045,.05,4),ring(0,0,1.51,.045,.05,4)],'skin',cap_first=False,cap_last=False)
    head(m,'pawn',p) if lod==0 else head_lod1(m)


def shoe(m,x,facet):
    if facet:
        w=.043;prof=[(-.165,.035),(-.14,.08),(-.05,.10),(0.0,.13),(.085,.13),(.105,.09),(.105,.035)]
        prism_x(m,x-w,x+w,prof,'shoe');box(m,(x-w-.002,-.175,0),(x+w+.002,.11,.035),'sole')
    else:
        w=.045;prism_x(m,x-w,x+w,[(-.17,0),(.10,0),(.10,.09),(-.05,.10),(-.17,.04)],'shoe')


def block(m,p,lod):
    """B: tapering torso, 2 legs, 2 arms, mitten hands, wedge feet, box head. LOD1 keeps the same envelope with minimum faces."""
    for s in (-1,1):
        lx=s*p['lgx']
        ax=lambda z,s=s:arm_x(p,z,s)
        if lod==0:
            loft(m,[ring(lx,0,.09,p['ank'],.05,4),ring(lx,0,.49,p['lg']*.76,.065,4),ring(lx,0,.88,p['lg'],.085,4)],'bottom',cap_first=False,cap_last=False)
            shoe(m,lx,False)
            loft(m,[ring(ax(1.40),0,1.40,p['ua'],.045,4),ring(ax(1.10),0,1.10,p['fa']+.004,.040,4),ring(ax(.80),0,.80,p['wr'],.030,4),
                    ring(ax(.73),0,.73,p['wr']+.006,.040,4),ring(ax(.64),0,.64,p['wr']+.003,.036,4)],'top',cap_first=False,cap_last=True,regions={2:'skin',3:'skin'})
        else:
            loft(m,[ring(lx,-.02,.10,p['ank']+.005,.07,4),ring(lx,0,.88,p['lg']*.9,.085,4)],'bottom',cap_first=False,cap_last=False)
            box(m,(lx-.045,-.17,0),(lx+.045,.10,.10),'shoe')
            loft(m,[ring(ax(1.40),0,1.40,p['ua'],.045,4),ring(ax(.64),0,.64,p['wr']+.003,.036,4)],'top',cap_first=False,cap_last=True)
    rings=[ring(0,0,.88,p['hp'],p['hd'],4),ring(0,0,1.08,p['wa'],p['wd'],4),ring(0,0,Z_SH,p['sh'],p['sd'],4),ring(0,0,1.45,p['sh']*.45,p['sd']*.6,4)]
    if lod==1:rings=[rings[0],rings[2],rings[3]]
    loft(m,rings,'top',cap_first=False,cap_last=False)
    if lod==0:
        loft(m,[ring(0,0,1.42,.045,.05,4),ring(0,0,1.51,.045,.05,4)],'skin',cap_first=False,cap_last=False)
        head(m,'block',p)
    else:head_lod1(m)


def facet(m,p,lod):
    """C: tapering limbs with joints, shoe wedge + sole, sleeve cuffs, collar band, thumbs, faceted head and hair mass."""
    if lod==1:return block(m,p,1)
    n=8
    for s in (-1,1):
        lx=s*p['lgx'];lg=p['lg'];ax=lambda z,s=s:arm_x(p,z,s)
        loft(m,[ring(lx,0,.13,p['ank'],.052,n),ring(lx,0,.26,lg*.68,.062,n),ring(lx,0,.49,lg*.76,.066,n),ring(lx,0,.65,lg*.92,.078,n),ring(lx,0,.86,lg,.088,n)],'bottom',cap_first=False,cap_last=False)
        shoe(m,lx,True)
        loft(m,[ring(ax(1.40),0,1.40,p['ua'],.048,n),ring(ax(1.25),0,1.25,p['ua']*.96,.046,n),ring(ax(1.10),0,1.10,p['fa']+.004,.041,n),
                ring(ax(.95),0,.95,p['fa'],.036,n),ring(ax(.84),0,.84,p['wr']+.004,.031,n),ring(ax(.80),0,.80,p['wr']+.006,.032,n)],'top',cap_first=False,cap_last=False,regions={4:'trim'})
        loft(m,[ring(ax(.80),0,.80,p['wr'],.028,n),ring(ax(.74),0,.74,p['wr']+.008,.040,n),ring(ax(.66),0,.66,p['wr']+.003,.034,n)],'skin',cap_first=False,cap_last=True)
        tx=ax(.73)-s*(p['wr']+.008+.002);box(m,(tx-.007,-.062,.70),(tx+.007,-.022,.765),'skin')
    rings=[ring(0,0,.80,p['hp']+.02,p['hd']+.02,n),ring(0,0,.90,p['hp']+.02,p['hd']+.02,n),ring(0,0,1.07,p['wa'],p['wd'],n),ring(0,0,1.26,p['sh']+.008,p['sd'],n),
           ring(0,0,Z_SH,p['sh'],p['sd']*.97,n),ring(0,0,1.44,p['sh']*.45,p['sd']*.58,n)]
    loft(m,rings,'top',cap_first=False,cap_last=False)
    loft(m,[ring(0,0,1.43,.052,.058,n),ring(0,0,1.465,.052,.058,n)],'under',cap_first=False,cap_last=False)
    loft(m,[ring(0,0,1.46,.044,.050,n),ring(0,0,1.51,.044,.050,n)],'skin',cap_first=False,cap_last=False)
    head(m,'facet',p)


BUILDERS={'pawn':pawn,'block':block,'facet':facet}


def build(name,lod):
    style,ratio=name.split('_');m=Mesh();BUILDERS[style](m,RATIO[ratio],lod);return m
