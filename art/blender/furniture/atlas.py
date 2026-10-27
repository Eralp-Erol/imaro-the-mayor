"""T-058 deterministic opaque matte street-furniture atlas (1024x1024 RGB, sixteen 256 px material tiles).
uv run --with pillow==11.3.0 python art/blender/furniture/atlas.py
Palette = templates-v0 section f FN1..FN6 working values (Q-018 colour decisions stay with the user); no text, logos or
brand colours. Every tile is procedural (fixed seeds), no external or AI imagery.
"""
from pathlib import Path
import json
import random
from PIL import Image, ImageDraw, ImageChops, ImageFilter

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/hero/furniture'
NAMES=['wood','wood_aged','metal_dark','metal_green','glass','stone','concrete','earth','kiosk_green','petrol','shutter','fabric','shrub','plaster','roof','terracotta']
# tile world size (m) = how much surface one tile covers; used by the generator to keep texel density consistent.
WORLD_M={'wood':0.9,'wood_aged':0.9,'metal_dark':0.6,'metal_green':0.6,'glass':1.2,'stone':0.9,'concrete':1.2,'earth':0.8,'kiosk_green':1.0,
         'petrol':0.6,'shutter':0.6,'fabric':0.8,'shrub':0.7,'plaster':1.2,'roof':1.0,'terracotta':0.7}
REGIONS={n:((i%4)*256,(i//4)*256,256,256) for i,n in enumerate(NAMES)}


def clip(v):return max(0,min(255,int(v)))


def noise(rng,size=256):return Image.frombytes('L',(size,size),rng.randbytes(size*size))


def blotch(rng,cells=10,size=256):
    small=Image.frombytes('L',(cells,cells),rng.randbytes(cells*cells))
    return small.resize((size,size),Image.Resampling.BICUBIC)


def base(color,rng,grain=10,mottle=14):
    """Flat matte colour with fine grain noise plus soft weathering blotches (all deterministic)."""
    n=noise(rng);b=blotch(rng)
    channels=[]
    for c in color:
        fine=n.point(lambda v,c=c:clip(c+(v-128)*grain/128))
        soft=b.point(lambda v:clip(128+(v-128)*mottle/128))
        channels.append(ImageChops.add(fine,soft,scale=1,offset=-128))
    return Image.merge('RGB',channels)


def shade(color,f):return tuple(clip(c*f) for c in color)


def tile_wood(rng,color,aged):
    im=base(color,rng,8,12);d=ImageDraw.Draw(im)
    for y in range(0,256,2):  # grain streaks running along u (the plank length)
        if rng.random()<.55:
            f=rng.uniform(.80,.95) if rng.random()<.6 else rng.uniform(1.04,1.1)
            x0=rng.randrange(0,120);d.line([(x0,y),(x0+rng.randrange(60,256),y)],fill=shade(color,f),width=1)
    for k in range(5 if not aged else 8):
        x=rng.randrange(20,230);y=rng.randrange(10,246)  # knots
        d.ellipse([x-5,y-3,x+5,y+3],outline=shade(color,.62),fill=shade(color,.74))
    for y in (0,128):d.line([(0,y),(255,y)],fill=shade(color,.7),width=2)  # plank seams (two planks per tile)
    return im


def tile_metal(rng,color):
    im=base(color,rng,7,8);d=ImageDraw.Draw(im)
    for y in range(0,256,3):d.line([(0,y),(255,y)],fill=shade(color,rng.uniform(.93,1.08)),width=1)  # brushed streaks
    for k in range(60):
        x=rng.randrange(256);y=rng.randrange(256);d.point((x,y),fill=shade(color,1.3))  # powder-coat chips
    d.rectangle([0,0,255,255],outline=shade(color,.8))
    return im


def tile_glass(rng):
    im=base((48,66,70),rng,3,5);d=ImageDraw.Draw(im)
    for k in range(-256,512,70):  # soft diagonal sheen bands, matte (no reflection)
        d.polygon([(k,256),(k+26,256),(k+126,0),(k+100,0)],fill=(58,80,84))
    return im.filter(ImageFilter.GaussianBlur(1.2))


def tile_stone(rng):
    color=(190,180,160);im=base(color,rng,12,16);d=ImageDraw.Draw(im)
    for row in range(4):  # ashlar courses, offset joints every second course
        y=row*64;d.line([(0,y),(255,y)],fill=shade(color,.66),width=2)
        for x in range((row%2)*48,256,96):d.line([(x,y),(x,y+64)],fill=shade(color,.66),width=2)
    for k in range(70):
        x=rng.randrange(256);y=rng.randrange(256);d.ellipse([x,y,x+rng.randrange(2,6),y+rng.randrange(2,4)],fill=shade(color,rng.choice((.82,1.1))))
    return im


def tile_concrete(rng):
    color=(201,195,181);im=base(color,rng,10,14);d=ImageDraw.Draw(im)
    for k in range(14):
        x=rng.randrange(256);y=rng.randrange(256);d.ellipse([x,y,x+3,y+2],fill=shade(color,.72))  # air pockets
    d.line([(0,128),(255,128)],fill=shade(color,.82),width=1)
    return im


def tile_earth(rng):
    color=(88,72,56);im=base(color,rng,18,16);d=ImageDraw.Draw(im)
    for k in range(120):
        x=rng.randrange(256);y=rng.randrange(256);r=rng.randrange(1,4);d.ellipse([x,y,x+r,y+r],fill=shade(color,rng.choice((.7,1.25))))
    return im


def tile_kiosk(rng):
    color=(94,110,82);im=base(color,rng,8,10);d=ImageDraw.Draw(im)
    for x in range(0,256,32):d.line([(x,0),(x,255)],fill=shade(color,.88),width=1)  # painted board joints
    for k in range(30):
        x=rng.randrange(256);y=rng.randrange(256);d.line([(x,y),(x+rng.randrange(-2,3),y+rng.randrange(8,28))],fill=shade(color,1.12),width=1)  # fading
    return im


def tile_shutter(rng):
    color=(150,146,134);im=base(color,rng,6,10);d=ImageDraw.Draw(im)
    for y in range(0,256,16):  # corrugation / roll-up slats, light top edge + dark underside
        d.line([(0,y),(255,y)],fill=shade(color,1.12),width=3);d.line([(0,y+5),(255,y+5)],fill=shade(color,.72),width=3)
    return im


def tile_fabric(rng):
    cream=(214,203,176);teal=(98,128,124);im=base(cream,rng,8,8);d=ImageDraw.Draw(im)
    for x in range(0,256,64):d.rectangle([x,0,x+31,255],fill=teal)  # four broad vertical awning stripes
    out=ImageChops.add(im,noise(rng).convert('RGB').point(lambda v:clip((v-128)*.08)),scale=1,offset=0)
    return out


def tile_shrub(rng):
    color=(82,100,66);im=base(color,rng,14,14);d=ImageDraw.Draw(im)
    for k in range(260):  # leaf flecks (opaque, no alpha)
        x=rng.randrange(256);y=rng.randrange(256);s=rng.randrange(4,9);f=rng.uniform(.75,1.25)
        d.polygon([(x,y),(x+s,y-s//2),(x+2*s,y),(x+s,y+s//2)],fill=shade((88,108,70),f))
    return im


def tile_plaster(rng):
    color=(214,206,188);im=base(color,rng,8,10);return im


def tile_roof(rng):
    color=(112,114,110);im=base(color,rng,7,9);d=ImageDraw.Draw(im)
    for x in range(0,256,48):d.line([(x,0),(x,255)],fill=shade(color,.8),width=2)  # standing seams
    return im


def tile_terracotta(rng):
    color=(158,112,84);im=base(color,rng,12,14);d=ImageDraw.Draw(im)  # muted, brown-ochre (not red-tile)
    for y in range(0,256,64):d.line([(0,y),(255,y)],fill=shade(color,.82),width=2)
    return im


def main():
    atlas=Image.new('RGB',(1024,1024),(128,128,128))
    makers={'wood':lambda r:tile_wood(r,(139,106,74),False),'wood_aged':lambda r:tile_wood(r,(122,104,84),True),
            'metal_dark':lambda r:tile_metal(r,(46,50,54)),'metal_green':lambda r:tile_metal(r,(61,74,74)),'glass':tile_glass,'stone':tile_stone,
            'concrete':tile_concrete,'earth':tile_earth,'kiosk_green':tile_kiosk,'petrol':lambda r:tile_metal(r,(76,108,120)),'shutter':tile_shutter,
            'fabric':tile_fabric,'shrub':tile_shrub,'plaster':tile_plaster,'roof':tile_roof,'terracotta':tile_terracotta}
    for i,name in enumerate(NAMES):
        atlas.paste(makers[name](random.Random(58000+i*31)),REGIONS[name][:2])
    OUT.mkdir(parents=True,exist_ok=True)
    atlas.save(OUT/'furniture_atlas.png',optimize=False)
    (OUT/'atlas_layout.json').write_text(json.dumps({'size':1024,'tile_px':256,'regions':REGIONS,'world_m':WORLD_M,'seed_base':58000,
        'format':'RGB opaque (no alpha); matte; one shared Texture2D'},indent=2)+'\n')
    print('furniture atlas: 1024 RGB, 16 material tiles')


if __name__=='__main__':main()
