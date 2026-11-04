"""T-059 deterministic opaque matte human atlas (1024x512 RGB, eight 256 px flat material tiles).
uv run --with pillow==11.3.0 python art/blender/human/atlas.py
Palette = templates-v0 section a.3 working values (SK2, HR2, CL7, CL4, CL15, CL6, CL2, CL1). One neutral working outfit
(plain shirt/jacket, trousers, shoes): no pattern, stripe, text, logo or colour code; Q-018 colour/clothing decisions stay with
the user. Tiles are flat with only fine grain (no bands, no gradients), so nothing bakes shading into the model (art-gate T-058 B2).
"""
from pathlib import Path
import json
import random
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/hero/human'
# name -> (palette row, sRGB hex, grain amplitude)
TILES={'skin':('SK2',(0xC9,0x9C,0x7C),4),'hair':('HR2',(0x5A,0x40,0x30),6),'top':('CL7',(0x8A,0x8F,0x86),5),'bottom':('CL4',(0x3E,0x54,0x70),5),
       'shoe':('CL15',(0x3B,0x2F,0x2A),4),'sole':('CL6',(0x5B,0x5F,0x63),4),'trim':('CL2',(0xD2,0xC3,0xA5),4),'under':('CL1',(0xE6,0xE1,0xD6),3)}
NAMES=list(TILES)
REGIONS={n:((i%4)*256,(i//4)*256,256,256) for i,n in enumerate(NAMES)}


def clip(v):return max(0,min(255,int(round(v))))


def tile(rng,color,grain):
    noise=rng.randbytes(256*256);data=bytearray()
    for v in noise:
        d=(v-128)*grain/128.0
        data.extend((clip(color[0]+d),clip(color[1]+d),clip(color[2]+d)))
    return Image.frombytes('RGB',(256,256),bytes(data))


def main():
    atlas=Image.new('RGB',(1024,512),(128,128,128))
    for i,name in enumerate(NAMES):
        atlas.paste(tile(random.Random(59000+i*17),TILES[name][1],TILES[name][2]),REGIONS[name][:2])
    OUT.mkdir(parents=True,exist_ok=True)
    atlas.save(OUT/'human_atlas.png',optimize=False)
    (OUT/'atlas_layout.json').write_text(json.dumps({'size':[1024,512],'tile_px':256,'regions':REGIONS,'palette_rows':{n:TILES[n][0] for n in NAMES},
        'palette_hex':{n:'#%02X%02X%02X'%TILES[n][1] for n in NAMES},'seed_base':59000,'format':'RGB opaque (no alpha); matte; flat tiles with fine grain; one shared Texture2D'},indent=2)+'\n')
    print('human atlas: 1024x512 RGB, %d flat material tiles'%len(NAMES))


if __name__=='__main__':main()
