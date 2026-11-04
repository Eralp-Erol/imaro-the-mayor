"""Pack unlit orthographic hero front facade render into the original atlas layout.
Run via uv run --with pillow==11.3.0 python ... (called by build_lods.py).
Only the front region changes; side/rear remain source atlas data; roofs/palette samples/clock retain original layout.
Output is 256px RGB: 256 KiB base + mip chain ~=341 KiB per proxy atlas.
"""
import argparse
import json
from pathlib import Path
from PIL import Image

p=argparse.ArgumentParser();p.add_argument('job');a=p.parse_args()
job=json.loads(Path(a.job).read_text())
canvas=Image.open(job['source_atlas']).convert('RGBA')
for face in job['faces'][:1]:
    render=Image.open(face['render']).convert('RGBA')
    width,height=face['physical_size'];span=max(width,height)
    size=render.width
    crop=((1-width/span)*size/2,(1-height/span)*size/2,(1+width/span)*size/2,(1+height/span)*size/2)
    region=render.crop(tuple(round(v) for v in crop))
    x,y,w,h=face['rect']
    region=region.resize((w,h),Image.Resampling.LANCZOS)
    original=canvas.crop((x,y,x+w,y+h))
    original.alpha_composite(region)
    canvas.paste(original,(x,y))
canvas.convert('RGB').resize((256,256),Image.Resampling.LANCZOS).save(job['out'],optimize=False)
