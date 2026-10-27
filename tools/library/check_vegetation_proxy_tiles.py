"""Verify source-derived proxy provenance/atlas coverage.
uv run --with pillow==11.3.0 python tools/library/check_vegetation_proxy_tiles.py
"""
import hashlib
import argparse
import json
from pathlib import Path
from PIL import Image

parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);args=parser.parse_args()
ROOT=args.root;OUT=ROOT/'assets/hero/vegetation'
manifest=json.loads((OUT/'proxy_bakes.json').read_text());atlas=Image.open(OUT/'vegetation_atlas.png').convert('RGBA')
assert hashlib.sha256(atlas.crop((0,0,1024,512)).tobytes()).hexdigest()==manifest['source_upper_rgba_sha256'],'base foliage/bark pixels drift'
assert len(manifest['assets'])==8
seen=[]
for species,asset in manifest['assets'].items():
    assert hashlib.sha256((ROOT/asset['source_lod0'].removeprefix('res://')).read_bytes()).hexdigest()==asset['source_lod0_sha256'],species+': sourceLOD0 drift'
    assert set(asset['views'])=={'front','side','top'}
    for view,record in asset['views'].items():
        x,y,w,h=record['region'];assert y>=640 and w==h==128
        box=(x,y,x+w,y+h)
        assert all(x+w<=a or a+cw<=x or y+h<=b or b+ch<=y for a,b,cw,ch in seen),'overlapping proxy tiles'
        seen.append((x,y,w,h));tile=atlas.crop(box)
        assert hashlib.sha256(tile.tobytes()).hexdigest()==record['rgba_sha256'],species+': tile content drift'
        opaque=sum(v>=115 for v in tile.getchannel('A').getdata())
        assert opaque>128*128*.03,species+': empty/degenerate source silhouette'
print('VEGETATION_PROXY_TILES_OK sources=8 views=24 upper512_unchanged=true')
