"""Pack24 source-derived128px tiles into existing atlas without altering upper512rows.
uv run --with pillow==11.3.0 python art/blender/vegetation/pack_proxies.py
"""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[3];OUT=ROOT/'assets/hero/vegetation'
RAW=ROOT/'artifacts/verify/t057/impostor-bakes'
manifest=json.loads((RAW/'source-manifest.json').read_text())
canvas=Image.open(OUT/'vegetation_atlas.png').convert('RGBA')
upper=canvas.crop((0,0,1024,512)).tobytes();manifest['source_upper_rgba_sha256']=hashlib.sha256(upper).hexdigest()
# Reset only the reserved lower512 rows; source foliage/bark/frond pixels never change.
canvas.paste(Image.new('RGBA',(1024,512)),(0,512))
for species,asset in manifest['assets'].items():
    for view,record in asset['views'].items():
        source=Image.open(ROOT/record['raw']).convert('RGBA');width,height=record['physical_size'];span=max(width,height);size=source.width
        box=tuple(round(v) for v in ((1-width/span)*size/2,(1-height/span)*size/2,(1+width/span)*size/2,(1+height/span)*size/2))
        content=source.crop(box).resize((112,112),Image.Resampling.LANCZOS)
        tile=Image.new('RGBA',(128,128));tile.paste(content,(8,8))
        x,y,w,h=record['region'];assert (w,h)==(128,128)
        canvas.paste(tile,(x,y));record['rgba_sha256']=hashlib.sha256(tile.tobytes()).hexdigest()
        # Raw render is reproducible evidence, not a required runtime asset.
        record.pop('raw',None)
assert canvas.crop((0,0,1024,512)).tobytes()==upper
canvas.save(OUT/'vegetation_atlas.png',optimize=False)
(OUT/'proxy_bakes.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print('source impostor atlas:24 tiles, upper512 unchanged, one1024RGBA texture')
