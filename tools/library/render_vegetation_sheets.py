"""Repeatable T-057 real Godot captures/contact sheets (no illustrative renders).
uv run --with pillow==11.3.0 python tools/library/render_vegetation_sheets.py
Requires catalog +import completed. Runs one Godot command at a time.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design/library/sheets/vegetation-hero'
EVIDENCE=ROOT/'artifacts/verify/t057'
SPECIES=['plane','palm_date','palm_slender','pine_brutia','pine_stone','olive_open','olive_twisted','cypress','maquis','hedge']
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'


def capture(name,args,resolution='1400x1100'):
    result=subprocess.run(['tools/capture.sh','t057-'+name,'--resolution',resolution,'--scene','res://assets/hero/vegetation/vegetation_lab.tscn','--']+args,cwd=ROOT,capture_output=True,text=True,env={**os.environ,'CAPTURE_TIMEOUT':'90'})
    err=(ROOT/'artifacts/verify/capture.err.log').read_text()
    if result.returncode or 'SCRIPT ERROR' in err or 'ERROR:' in err:raise RuntimeError(result.stdout+result.stderr+err)
    return Path(result.stdout.strip().splitlines()[-1])


def main():
    OUT.mkdir(parents=True,exist_ok=True);catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
    entries={e['family'].removeprefix('hero_'):e for e in catalog['entries'] if e.get('source',{}).get('kind')=='hero_vegetation'}
    font=ImageFont.truetype(FONT,22);title=ImageFont.truetype(FONT,28);index=[]
    lod_updates="--lod-updates" in sys.argv[1:]
    requested=[a for a in sys.argv[1:] if not a.startswith("--")]
    old_index={e["id"]:e for e in json.loads((OUT/"index.json").read_text())["entries"]} if lod_updates else {}
    for species in (requested or SPECIES):
        entry=entries[species];paths={}
        if lod_updates:
            for key,path in old_index[entry['id']]['frames'].items():
                view,level=key.rsplit('_',1);paths[view,level]=ROOT/path
            jobs=[('front','proxy')]+([('front','lod1')] if species=='cypress' else [])
        else:jobs=[('front','lod0'),('side','lod0'),('top','lod0'),('front','lod1'),('front','proxy')]
        for view,level in jobs:
            paths[view,level]=capture(species+'-'+view+'-'+level,['--asset='+species,'--view='+view,'--level='+level])
        width,tileh=600,472;sheet=Image.new('RGB',(width*3,96+2*(tileh+40)),(235,232,222));draw=ImageDraw.Draw(sheet)
        draw.text((18,12),entry['id']+' · '+entry['label_tr']+' · PROPOSED',font=title,fill=(42,46,37))
        d=entry['dimensions_m'];tri=entry['triangles']
        draw.text((18,52),'%.2fm height / %.2fm x %.2fm canopy · triangles %d / %d / %d · 1.75m figure · 4xMSAA lab'%(d['height_above_ground'],d['width_x'],d['depth_z'],tri['LOD0'],tri['LOD1'],tri['PROXY']),font=font,fill=(62,65,54))
        views=[('front','lod0','Ön / LOD0'),('side','lod0','Yan / LOD0'),('top','lod0','Üst / LOD0'),('front','lod0','LOD0 / aynı kamera'),('front','lod1','LOD1 / aynı kamera'),('front','proxy','Proxy / aynı kamera')]
        for k,(view,level,label) in enumerate(views):
            x=(k%3)*width;y=96+(k//3)*(tileh+40)
            frame=Image.open(paths[view,level]).convert('RGB').resize((width,tileh),Image.Resampling.LANCZOS)
            sheet.paste(frame,(x,y));draw.text((x+12,y+tileh+8),label,font=font,fill=(42,46,37))
        path=OUT/(entry['id']+'.png');sheet.save(path)
        index.append({'id':entry['id'],'path':str(path.relative_to(ROOT)),'height_m':d['height_above_ground'],'triangles':tri,'frames':{view+'_'+level:str(p.relative_to(ROOT)) for (view,level),p in paths.items()}})
        print(path.relative_to(ROOT),flush=True)
    for context in ([] if requested else ['true','street','slope','lineup']):
        path=capture('context-'+context,['--context='+context], '2200x1100' if context=='lineup' else '1800x1100')
        destination=OUT/('context-'+context+'.png');shutil.copyfile(path,destination)
        print(destination.relative_to(ROOT),flush=True)
    for species in ([] if requested else ['olive_open','palm_date']):
        path=capture(species+'-scissor-no-msaa',['--asset='+species,'--view=front','--aa=off'])
        destination=OUT/(species+'-scissor-no-msaa.png');shutil.copyfile(path,destination)
        print(destination.relative_to(ROOT),flush=True)
    if requested and (OUT/'index.json').exists():
        previous={e['id']:e for e in json.loads((OUT/'index.json').read_text())['entries']}
        previous.update({e['id']:e for e in index})
        index=[previous['veg_hero_'+s+'_a'] for s in SPECIES]
    (OUT/'index.json').write_text(json.dumps({'task':'T-057','source':'actual Godot frames','entries':index},indent=2,ensure_ascii=False)+'\n')
    print('vegetation sheets:10 contacts +4context +2scissor-only diagnostics',flush=True)


if __name__=='__main__':main()
