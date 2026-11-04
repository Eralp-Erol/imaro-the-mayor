#!/usr/bin/env python3
"""Repeatable T-059 real Godot captures/contact sheets (no illustrative renders), same camera and daylight for every asset.
uv run --with pillow==11.3.0 python tools/library/render_human_sheets.py [pawn_neutral ...]
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
OUT=ROOT/'design/library/sheets/human-hero'
NAMES=['pawn_neutral','pawn_broad','block_neutral','block_broad','facet_neutral','facet_broad']
STYLE={'pawn':'A piyon','block':'B blok figür','facet':'C faset figür'}
RATIO={'neutral':'nötr oran','broad':'geniş oran'}
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
SCENE='res://assets/hero/human/human_lab.tscn'
# (key, view, level, extra args, label, crop_to_centre)
TILES=[('front_lod0','front','lod0',[],'Ön / LOD0',False),('side_lod0','side','lod0',[],'Yan / LOD0',False),('back_lod0','back','lod0',[],'Arka / LOD0',False),
       ('top_lod0','top','lod0',[],'Üst / LOD0',False),('3q_lod0','3q','lod0',[],'3/4 / LOD0',False),('front_lod1','front','lod1',[],'Ön / LOD1 (aynı kamera)',False),
       ('near_lod0','3q','lod0',['--distance=12'],'LOD0 · 12 m · gerçek piksel (merkez kırpım)',True),('far_lod1','3q','lod1',['--distance=60'],'LOD1 · 60 m · gerçek piksel (merkez kırpım)',True)]


def tr(value,digits=2):return ('%.*f'%(digits,value)).replace('.',',')


def capture(name,args,resolution='1400x1100'):
    result=subprocess.run(['tools/capture.sh','t059-'+name,'--resolution',resolution,'--scene',SCENE,'--']+args,cwd=ROOT,capture_output=True,text=True,env={**os.environ,'CAPTURE_TIMEOUT':'90'})
    err=(ROOT/'artifacts/verify/capture.err.log').read_text()
    if result.returncode or 'SCRIPT ERROR' in err or 'ERROR:' in err:raise RuntimeError(result.stdout+result.stderr+err)
    return Path(result.stdout.strip().splitlines()[-1])


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
    entries={e['family'].removeprefix('hero_'):e for e in catalog['entries'] if e.get('source',{}).get('kind')=='hero_human'}
    font=ImageFont.truetype(FONT,22);small=ImageFont.truetype(FONT,19);title=ImageFont.truetype(FONT,28)
    requested=[a for a in sys.argv[1:] if not a.startswith('--')];index={}
    old=OUT/'index.json'
    if requested and old.exists():index={e['id']:e for e in json.loads(old.read_text())['entries']}
    for name in (requested or NAMES):
        entry=entries[name];frames={};style,ratio=name.split('_')
        for key,view,level,extra,label,crop in TILES:
            frames[key]=capture(name+'-'+key,['--asset='+name,'--view='+view,'--level='+level]+extra)
        width,tileh=600,472;sheet=Image.new('RGB',(width*3,96+3*(tileh+40)),(235,232,222));draw=ImageDraw.Draw(sheet)
        d=entry['dimensions_m'];tri=entry['triangles'];dist=entry['lod_chain']['distances_m'];tref=entry['template_ref']
        draw.text((18,12),'%s · %s · ÖNERİ (seçilmedi)'%(entry['id'],STYLE[style]+' · '+RATIO[ratio]),font=title,fill=(42,46,37))
        draw.text((18,52),'%s x %s x %s m (g x d x y) · üçgen LOD0 %d / LOD1 %d · 1,75 m ölçek çubuğu · 4x MSAA lab'%(tr(d['width_x']),tr(d['depth_z']),tr(d['height_above_ground']),tri['LOD0'],tri['LOD1']),font=font,fill=(62,65,54))
        for k,(key,view,level,extra,label,crop) in enumerate(TILES):
            x=(k%3)*width;y=96+(k//3)*(tileh+40);image=Image.open(frames[key]).convert('RGB')
            if crop:
                w,h=image.size;image=image.crop((w//2-300,h//2-236,w//2+300,h//2+236))  # native pixels, no scaling
            else:image=image.resize((width,tileh),Image.Resampling.LANCZOS)
            sheet.paste(image,(x,y));draw.text((x+12,y+tileh+8),label,font=small,fill=(42,46,37))
        x=2*width;y=96+2*(tileh+40)
        lines=['Ölçü: çalışma değeri · ref '+', '.join(tref['reference_ids']),'Mesafe (çalışma): LOD0 < %d m · LOD1 < %d m · sonrası cull'%(dist['LOD0_max'],dist['LOD1_max']),
               'Uzak proxy yok · generate_lods=false','Palet: '+', '.join(entry['palette_rows']['human_rows']),'sha256 LOD0: '+entry['lod_chain']['levels']['LOD0']['sha256'][:8],
               'Yüz/logo/yazı/üniforma yok · onay: proposed','Q-018 açık (kullanıcı)']
        for i,line in enumerate(lines):draw.text((x+12,y+8+i*30),line,font=small,fill=(42,46,37))
        path=OUT/(entry['id']+'.png');sheet.save(path)
        index[entry['id']]={'id':entry['id'],'path':str(path.relative_to(ROOT)),'dimensions_m':[d['width_x'],d['depth_z'],d['height_above_ground']],'triangles':tri,'frames':{k:str(p.relative_to(ROOT)) for k,p in frames.items()}}
        print(path.relative_to(ROOT),flush=True)
    contexts={}
    if not requested:
        for context,res,extra in (('compare-lod0','2200x1100',['--context=compare','--level=lod0','--view=front']),('compare-lod1','2200x1100',['--context=compare','--level=lod1','--view=front']),
                                  ('compare-3q','2200x1100',['--context=compare','--level=lod0','--view=3q']),('compare-side','2200x1100',['--context=compare','--level=lod0','--view=side']),
                                  ('street','1800x1100',['--context=street']),('scale','1800x1100',['--context=scale'])):
            contexts[context]=capture('context-'+context,extra,res);shutil.copyfile(contexts[context],OUT/('context-'+context+'.png'));print('context',context,flush=True)
        sheet=Image.new('RGB',(2200,96+2*590),(235,232,222));draw=ImageDraw.Draw(sheet)
        draw.text((18,12),'İnsan stil önerileri · A piyon / B blok figür / C faset figür · her biri nötr ve geniş oran',font=title,fill=(42,46,37))
        draw.text((18,52),'Aynı 1,75 m, aynı duruş, aynı palet, aynı kamera/ışık. Hiçbiri seçilmedi (Q-018 kullanıcıda). Üçgen LOD0/LOD1: '+' · '.join('%s %d/%d'%(STYLE[n.split('_')[0]][0],entries[n]['triangles']['LOD0'],entries[n]['triangles']['LOD1']) for n in ('pawn_neutral','block_neutral','facet_neutral')),font=font,fill=(62,65,54))
        for k,(key,label) in enumerate((('compare-lod0','Ön · LOD0'),('compare-lod1','Ön · LOD1 (aynı kamera)'),('compare-3q','3/4 · LOD0'))):
            image=Image.open(contexts[key]).convert('RGB').resize((1100,550),Image.Resampling.LANCZOS)
            sheet.paste(image,((k%2)*1100,96+(k//2)*(550+40)));draw.text(((k%2)*1100+12,96+(k//2)*(590)+552),label,font=small,fill=(42,46,37))
        sheet.save(OUT/'style-compare.png');print('style-compare',flush=True)
    (OUT/'index.json').write_text(json.dumps({'task':'T-059','source':'actual Godot frames (human_lab.tscn)','entries':[index['hum_hero_%s_a'%n] for n in NAMES if 'hum_hero_%s_a'%n in index],
        'contexts':['context-compare-lod0.png','context-compare-lod1.png','context-compare-3q.png','context-compare-side.png','context-street.png','context-scale.png'],'style_compare':'style-compare.png'},indent=2,ensure_ascii=False)+'\n')
    print('human sheets done',flush=True)


if __name__=='__main__':main()
