"""Verify the shared vegetation atlas regions (T-057 Karar 5).
uv run --with pillow==11.3.0 python tools/library/check_vegetation_atlas.py [--root DIR]
Upper 512 rows (source foliage/bark/frond) and the dead y640-1023 tile region must match the
recorded RGBA hashes in assets/hero/vegetation/atlas_regions.json.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);args=parser.parse_args()
OUT=args.root/'assets/hero/vegetation'
record=json.loads((OUT/'atlas_regions.json').read_text())
atlas=Image.open(OUT/'vegetation_atlas.png').convert('RGBA')
assert atlas.size==(1024,1024),'atlas must be 1024x1024'
assert hashlib.sha256(atlas.crop((0,0,1024,512)).tobytes()).hexdigest()==record['upper512_rgba_sha256'],'base foliage/bark pixels drift'
region=record['dead_tile_region']
assert hashlib.sha256(atlas.crop(tuple(region['rect_xyxy'])).tobytes()).hexdigest()==region['rgba_sha256'],'dead tile region drift (must stay byte-equal)'
print('VEGETATION_ATLAS_OK upper512_unchanged=true dead_tile_region_byte_equal=true')
