#!/usr/bin/env python3
"""Repeatable T-058 real Godot captures/contact sheets (no illustrative renders), same camera and daylight for every asset.
uv run --with pillow==11.3.0 python tools/library/render_furniture_sheets.py [bench bin ...]
Requires the catalog + Godot import to be done. Runs one Godot command at a time (tools/capture.sh).
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'design/library/sheets/furniture-hero'
NAMES=['bench','bin','lamp_street','bollard','bike_rack','bus_stop','planter','kiosk']
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
SCENE='res://assets/hero/furniture/furniture_lab.tscn'
# (key, view, level, extra args, label, crop_to_centre)
TILES=[('front_lod0','front','lod0',[],'Ön / LOD0',False),('side_lod0','side','lod0',[],'Yan / LOD0',False),('back_lod0','back','lod0',[],'Arka / LOD0',False),
       ('top_lod0','top','lod0',[],'Üst / LOD0',False),('3q_lod0','3q','lod0',[],'3/4 / LOD0',False),('front_lod1','front','lod1',[],'Ön / LOD1 (aynı kamera)',False),
       ('near_lod0','3q','lod0',['--distance=25'],'LOD0 · 25 m · gerçek piksel (merkez kırpım)',True),('far_lod1','3q','lod1',['--distance=100'],'LOD1 · 100 m · gerçek piksel (merkez kırpım)',True)]


def capture(name,args,resolution='1400x1100'):
    result=subprocess.run(['tools/capture.sh','t058-'+name,'--resolution',resolution,'--scene',SCENE,'--']+args,cwd=ROOT,capture_output=True,text=True,env={**os.environ,'CAPTURE_TIMEOUT':'90'})
    err=(ROOT/'artifacts/verify/capture.err.log').read_text()
    if result.returncode or 'SCRIPT ERROR' in err or 'ERROR:' in err:raise RuntimeError(result.stdout+result.stderr+err)
    return Path(result.stdout.strip().splitlines()[-1])


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
    entries={e['family'].removeprefix('hero_'):e for e in catalog['entries'] if e.get('source',{}).get('kind')=='hero_furniture'}
    font=ImageFont.truetype(FONT,22);small=ImageFont.truetype(FONT,19);title=ImageFont.truetype(FONT,28)
    requested=[a for a in sys.argv[1:] if not a.startswith('--')];index={}
    old=OUT/'index.json'
    if requested and old.exists():index={e['id']:e for e in json.loads(old.read_text())['entries']}
    for name in (requested or NAMES):
        entry=entries[name];frames={}
        for key,view,level,extra,label,crop in TILES:
            frames[key]=capture(name+'-'+key,['--asset='+name,'--view='+view,'--level='+level]+extra)
        width,tileh=600,472;sheet=Image.new('RGB',(width*3,96+3*(tileh+40)),(235,232,222));draw=ImageDraw.Draw(sheet)
        d=entry['dimensions_m'];tri=entry['triangles'];dist=entry['lod_chain']['distances_m'];tref=entry['template_ref']
        draw.text((18,12),entry['id']+' · '+entry['label_tr']+' · PROPOSED',font=title,fill=(42,46,37))
        draw.text((18,52),'%.2f x %.2f x %.2f m (g x d x y) · üçgen LOD0 %d / LOD1 %d · 1,75 m figür · 4x MSAA lab'%(d['width_x'],d['depth_z'],d['height_above_ground'],tri['LOD0'],tri['LOD1']),font=font,fill=(62,65,54))
        for k,(key,view,level,extra,label,crop) in enumerate(TILES):
            x=(k%3)*width;y=96+(k//3)*(tileh+40);image=Image.open(frames[key]).convert('RGB')
            if crop:
                w,h=image.size;image=image.crop((w//2-300,h//2-236,w//2+300,h//2+236))  # native pixels, no scaling
            else:image=image.resize((width,tileh),Image.Resampling.LANCZOS)
            sheet.paste(image,(x,y));draw.text((x+12,y+tileh+8),label,font=small,fill=(42,46,37))
        x=2*width;y=96+2*(tileh+40)
        lines=['Ölçü: '+tref['size_status'][:40],('Şablon: %s %s'%(tref['template_id'],' x '.join('-' if v is None else ('%g'%v) for v in tref['template_size_m'])) if tref['template_id'] else 'Şablon satırı yok · çalışma değeri'),'Mesafe (çalışma): LOD0 < %d m · LOD1 < %d m · sonrası cull'%(dist['LOD0_max'],dist['LOD1_max']),
               'Uzak proxy yok · generate_lods=false','Palet satırları: '+', '.join(entry['palette_rows']['furniture_rows']),'sha256 LOD0: '+entry['lod_chain']['levels']['LOD0']['sha256'][:8],
               'Işık/yazı/logo yok · onay: proposed','Q-018 açık (kullanıcı)']
        for i,line in enumerate(lines):draw.text((x+12,y+8+i*30),line,font=small,fill=(42,46,37))
        path=OUT/(entry['id']+'.png');sheet.save(path)
        index[entry['id']]={'id':entry['id'],'path':str(path.relative_to(ROOT)),'dimensions_m':[d['width_x'],d['depth_z'],d['height_above_ground']],'triangles':tri,'frames':{k:str(p.relative_to(ROOT)) for k,p in frames.items()}}
        print(path.relative_to(ROOT),flush=True)
    if not requested:
        for context,res in (('scale','1800x1100'),('street','1800x1100'),('lineup','2200x1100')):
            shutil.copyfile(capture('context-'+context,['--context='+context],res),OUT/('context-'+context+'.png'));print('context',context,flush=True)
    (OUT/'index.json').write_text(json.dumps({'task':'T-058','source':'actual Godot frames (furniture_lab.tscn)','entries':[index['fur_hero_%s_a'%n] for n in NAMES if 'fur_hero_%s_a'%n in index],
        'contexts':['context-scale.png','context-street.png','context-lineup.png']},indent=2,ensure_ascii=False)+'\n')
    print('furniture sheets done',flush=True)


if __name__=='__main__':main()
