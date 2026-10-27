#!/usr/bin/env python3
"""T-059 C facet jacket-hem close-ups: 6x nearest-neighbour crops of the real front/side/back LOD0 frames listed in index.json (no new render).
uv run --with pillow==11.3.0 python tools/library/human_hem_crops.py
"""
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design/library/sheets/human-hero'
BOX_X={'front':370,'side':550,'back':745}  # left edge of a 300x120 px window around the hem; y 500..620 (same camera/light for every frame)


def main():
    index=json.loads((OUT/'index.json').read_text());crops={}
    for entry in index['entries']:
        if '_facet_' not in entry['id']:continue
        for view in ('front','side','back'):
            image=Image.open(ROOT/entry['frames'][view+'_lod0']).convert('RGB').crop((BOX_X[view],500,BOX_X[view]+300,620)).resize((1800,720),Image.Resampling.NEAREST)
            path=OUT/('hem_%s_%s.png'%(entry['id'].removeprefix('hum_hero_').removesuffix('_a'),view));image.save(path);crops[path.stem]=str(path.relative_to(ROOT))
    index['hem_crops']=crops;(OUT/'index.json').write_text(json.dumps(index,indent=2,ensure_ascii=False)+'\n');print(len(crops),'crops')


if __name__=='__main__':main()
