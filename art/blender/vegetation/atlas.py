"""Deterministic RGBA vegetation atlas, muted Ege summer proposals, no AI/external assets.
uv run --with pillow==11.3.0 python art/blender/vegetation/atlas.py
"""
from pathlib import Path
import json
import math
import random
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/hero/vegetation'
REGIONS={'bark':(0,0,256,256),'olive':(256,0,256,256),'plane':(512,0,256,256),'pine':(768,0,256,256),'palm_bark':(0,256,256,256),'maquis':(256,256,256,256),'frond':(512,256,512,256)}
IMPOSTOR_SPECIES=['plane','pine_brutia','pine_stone','olive_open','olive_twisted','cypress','maquis','hedge']
for _i,_species in enumerate(IMPOSTOR_SPECIES):
    for _j,_view in enumerate(['front','side','top']):
        _slot=_i*3+_j
        REGIONS['proxy_'+_species+'_'+_view]=((_slot%8)*128,640+(_slot//8)*128,128,128)



def leaf(draw,x,y,length,width,angle,color):
    a=math.radians(angle);u=(math.cos(a),math.sin(a));v=(-u[1],u[0])
    pts=[]
    for s,t in [(-.5,0),(-.2,-.48),(.24,-.4),(.5,0),(.24,.4),(-.2,.48)]:
        pts.append((x+s*length*u[0]+t*width*v[0],y+s*length*u[1]+t*width*v[1]))
    draw.polygon(pts,fill=color+(255,))
    draw.line([(x-.37*length*u[0],y-.37*length*u[1]),(x+.35*length*u[0],y+.35*length*u[1])],fill=tuple(min(255,c+12) for c in color)+(255,),width=1)


def spray(kind):
    rng=random.Random({'olive':112,'plane':135,'pine':432,'maquis':998}[kind])
    image=Image.new('RGBA',(256,256));d=ImageDraw.Draw(image)
    bases={'olive':(126,138,106),'plane':(91,115,65),'pine':(62,89,54),'maquis':(78,103,59)}
    for branch in range(11 if kind=="olive" else 7):
        root=(128+rng.randrange(-20,20),238)
        end=(rng.randrange(24,230),rng.randrange(12,140))
        d.line([root,end],fill=(105,91,66,255),width=2 if kind!='plane' else 3)
        for k in range(16 if kind=='olive' else 12 if kind!='plane' else 8):
            t=(k+.6)/(17 if kind=="olive" else 13)
            x=root[0]+(end[0]-root[0])*t;y=root[1]+(end[1]-root[1])*t
            sign=-1 if k%2 else 1
            tip=(x+sign*rng.uniform(10,32),y-rng.uniform(0,13))
            d.line([(x,y),tip],fill=(103,92,67,255),width=1)
            shade=rng.randrange(-16,19);color=tuple(max(0,min(255,c+shade)) for c in bases[kind])
            if kind=='pine':
                for n in range(9):
                    theta=math.radians(-165+n*18+rng.uniform(-6,6));length=rng.uniform(10,23)
                    d.line([tip,(tip[0]+math.cos(theta)*length,tip[1]+math.sin(theta)*length)],fill=color+(255,),width=2)
            elif kind=='plane':
                angle=rng.uniform(-180,180);a=math.radians(angle);points=[]
                for n in range(10):
                    th=a+n*math.pi/5;r=14 if n%2==0 else 6
                    points.append((tip[0]+math.cos(th)*r,tip[1]+math.sin(th)*r))
                d.polygon(points,fill=color+(255,))
                d.line([tip,(tip[0]+math.cos(a)*12,tip[1]+math.sin(a)*12)],fill=(139,143,91,255),width=1)
            else:leaf(d,tip[0],tip[1],rng.uniform(20,30) if kind=='olive' else rng.uniform(15,21),rng.uniform(8,13) if kind=='olive' else rng.uniform(8,12),-50*sign+rng.uniform(-18,18),color)
    return image



def plane_cluster():
    rng=random.Random(570135);image=Image.new('RGBA',(256,256));d=ImageDraw.Draw(image)
    for k in range(10):
        x=128+rng.uniform(-55,55);y=128+rng.uniform(-55,55)
        d.line([(128,172),(x,y)],fill=(103,100,71,255),width=2)
    for k in range(115):
        angle=rng.uniform(0,math.tau);radius=math.sqrt(rng.random())*94
        x=128+math.cos(angle)*radius;y=128+math.sin(angle)*radius*.9
        outer=rng.uniform(13,20);inner=outer*.48;a=rng.uniform(0,math.tau)
        points=[(x+math.cos(a+n*math.pi/5)*(outer if n%2==0 else inner),y+math.sin(a+n*math.pi/5)*(outer if n%2==0 else inner)) for n in range(10)]
        shade=rng.randrange(-15,15);color=(94+shade,119+shade,69+shade,255)
        d.polygon(points,fill=color)
        d.line([(x,y),(x+math.cos(a)*outer*.75,y+math.sin(a)*outer*.75)],fill=(120+shade,132+shade,86+shade,255),width=1)
    return image


def main():
    rng=random.Random(57001);atlas=Image.new('RGBA',(1024,1024))
    for kind in ['bark','palm_bark']:
        im=Image.new('RGBA',(256,256));d=ImageDraw.Draw(im)
        for y in range(256):
            for x in range(256):
                value=rng.randrange(-17,18)
                if kind=='bark':
                    ridge=math.sin(x*.32+math.sin(y*.03))*12
                    base=(123,112,90)
                else:
                    ridge=(((x+(y//20%2)*14)//28)%2)*12
                    base=(129,110,83)
                im.putpixel((x,y),tuple(max(0,min(255,int(v+value+ridge))) for v in base)+(255,))
        if kind=='palm_bark':
            for y in range(-20,276,24):
                for x in range(-28,284,30):
                    offset=15 if (y//24)%2 else 0
                    d.line([(x+offset,y),(x+offset+15,y+11),(x+offset+30,y)],fill=(87,75,59,255),width=3)
        else:
            for k in range(40):
                x=rng.randrange(256);y=rng.randrange(256)
                d.line([(x,y),(x+rng.randrange(-5,6),min(255,y+rng.randrange(15,55)))],fill=(83,78,64,255),width=2)
        atlas.paste(im,REGIONS[kind][:2])
    for kind in ['olive','plane','pine','maquis']:atlas.paste(plane_cluster() if kind=='plane' else spray(kind),REGIONS[kind][:2])
    frond=Image.new('RGBA',(512,256));d=ImageDraw.Draw(frond)
    d.line([(10,128),(505,128)],fill=(124,133,72,255),width=4)
    for k in range(1,24):
        u=k/24;x=8+496*u;width=math.sin(math.pi*u)**.6*114
        for sign in [-1,1]:
            x1=x+18+20*(1-u);y1=128+sign*width
            col=(82+rng.randrange(-6,9),103+rng.randrange(-7,10),65+rng.randrange(-5,9),255)
            d.polygon([(x-7,128),(x+11,128+sign*15),(x1,y1),(x1-14,y1-sign*25)],fill=col)
            d.line([(x,128),(x1-2,y1-sign*5)],fill=(100,116,79,255),width=1)
    atlas.paste(frond,REGIONS['frond'][:2])
    OUT.mkdir(parents=True,exist_ok=True)
    atlas.save(OUT/'vegetation_atlas.png',optimize=False)
    (OUT/'atlas_layout.json').write_text(json.dumps({'size':1024,'regions':REGIONS,'seed':57001},indent=2)+'\n')
    print('vegetation atlas:1024 RGBA, deterministic cutout sprays/bark/fronds')


if __name__=='__main__':main()
