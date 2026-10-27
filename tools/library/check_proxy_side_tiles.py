"""uv run --with pillow==11.3.0 python tools/library/check_proxy_side_tiles.py
The proxy side/rear tile must remain original albedo; no right-side geometry bake
may paint source-absent doors/windows onto the rear. Exclude a 4px Lanczos border.
"""
import json
from pathlib import Path
from PIL import Image, ImageChops

ROOT=Path(__file__).resolve().parents[2]
FAMILY={'hero_old_core':'old_core','hero_com_bazaar':'bazaar','hero_res_mid':'res_mid','hero_res_late':'res_late','hero_res_house':'house','hero_ind_hero':'industrial','hero_civ_hero':'civic'}
catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
checked=0
for e in catalog['entries']:
    if 'lod_chain' not in e or e.get('source',{}).get('kind')!='hero':continue
    family=FAMILY[e['family']]
    layout=ROOT/('assets/hero/hero_atlas_layout.json' if family=='old_core' else 'assets/hero/fam/%s_layout.json'%family)
    x,y,w,h=json.loads(layout.read_text())['rects']['side']
    source=Image.open(ROOT/e['lod_chain']['atlas']['path'].removeprefix('res://')).convert('RGB').resize((256,256),Image.Resampling.LANCZOS)
    proxy=Image.open(ROOT/e['lod_chain']['proxy_atlas']['path'].removeprefix('res://')).convert('RGB')
    region=(int(x/4)+4,int(y/4)+4,int((x+w)/4)-4,int((y+h)/4)-4)
    if ImageChops.difference(source.crop(region),proxy.crop(region)).getbbox():
        raise SystemExit(e['id']+': proxy side/rear tile differs from original side albedo')
    checked+=1
assert checked==21
print('HERO_PROXY_SIDE_TILES_OK 21 original side/rear albedo tiles retained')
