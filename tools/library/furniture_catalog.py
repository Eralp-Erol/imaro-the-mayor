#!/usr/bin/env python3
"""T-058 measure/register/validate isolated hero street-furniture proposals (library only, no game integration).
python3 tools/library/furniture_catalog.py --write | --check
Mirrors tools/library/vegetation_catalog.py: values come from the real GLB files; user-owned fields are never touched.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import glb_info
import hero_lods

ROOT=HERE.parents[1]
NAMES=['bench','bin','lamp_street','bollard','bike_rack','bus_stop','planter','kiosk']
LABELS={'bench':'Bank · ahşap oturak, metal ayak','bin':'Çöp kutusu · sekizgen sac gövde','lamp_street':'Sokak direği · tek kollu armatür gövdesi (ışıksız)',
        'bollard':'Bollard · yaya alanı babası','bike_rack':'Bisiklet park demiri · üç ters-U','bus_stop':'Otobüs durağı · cam/metal/ahşap, yazısız',
        'planter':'Taş saksı · toprak ve çalı','kiosk':'Markasız küçük kiosk · tentesi, kepenkli'}
# templates-v0 section f row, nominal template size [x,y,z] m, palette rows; size_status says whether the size is the template value
# or a working value chosen by technical-artist (no template row / template silent). height_m is the checked intended height.
TEMPLATES={
    'bench':{'template_id':'fur_bench_a','template_size_m':[1.8,0.6,0.8],'size_status':'template-working-value','height_m':0.8,'rows':['FN3','FN2'],'distance_class':'small'},
    'bin':{'template_id':'fur_bin_a','template_size_m':[0.5,0.5,0.9],'size_status':'template-working-value','height_m':0.9,'rows':['FN1'],'distance_class':'small'},
    'lamp_street':{'template_id':'fur_lamp_street_a','template_size_m':[1.5,None,8.0],'size_status':'template-working-value','height_m':8.0,'rows':['FN1','FN2'],'distance_class':'lamp'},
    'bollard':{'template_id':'fur_bollard_a','template_size_m':[0.2,0.2,0.9],'size_status':'template-working-value','height_m':0.9,'rows':['FN2','FN1'],'distance_class':'small'},
    'bike_rack':{'template_id':None,'template_size_m':None,'size_status':'working-value (no template row)','height_m':0.85,'rows':['FN2','FN1'],'distance_class':'small'},
    'bus_stop':{'template_id':'fur_bus_stop_a','template_size_m':[5.0,1.6,2.6],'size_status':'template-working-value','height_m':2.6,'rows':['FN6','FN3','FN5','VH13'],'distance_class':'large'},
    'planter':{'template_id':'fur_planter_a','template_size_m':[1.2,1.2,0.7],'size_status':'template footprint; total 1.34 working','height_m':1.34,'rows':['W11','FN5','P2'],'distance_class':'small'},
    'kiosk':{'template_id':'fur_kiosk_a','template_size_m':[2.4,2.0,2.7],'size_status':'template-working-value','height_m':2.7,'rows':['FN4','FN3','FN6'],'distance_class':'large'},
}
DISTANCES={'small':(40,150),'large':(60,200),'lamp':(80,300)}
LIMITS={'LOD0':1600,'LOD1':240}
LEVELS=['LOD0','LOD1']
ATLAS='res://assets/hero/furniture/furniture_atlas.png'
LAYOUT='res://assets/hero/furniture/atlas_layout.json'
FUR_DIR='assets/hero/furniture'
MATERIAL='mat_furniture_atlas'
HEIGHT_TOLERANCE=0.05


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def import_params(path):
    params={}
    for line in path.read_text().splitlines():
        if '=' in line and not line.startswith('['):
            key,value=line.split('=',1);params[key]=value
    return params


def glb_path(name,level):return 'res://%s/fur_hero_%s_a_%s.glb'%(FUR_DIR,name,level.lower())


def proxy_residue(root,name):
    """Small furniture has no far proxy (cull instead): any *_proxy.glb for the asset is rejected."""
    return [n for n in ('fur_hero_%s_a_proxy.glb'%name,'fur_hero_%s_a_proxy.glb.import'%name) if (root/FUR_DIR/n).exists()]


def measure_chain(root,name):
    levels={level:hero_lods.measure(root,glb_path(name,level)) for level in LEVELS}
    near,far=DISTANCES[TEMPLATES[name]['distance_class']]
    return {'status':'proposed','generator':'art/blender/furniture/build.py','levels':levels,
            'atlas':{'path':ATLAS,'sha256':sha(root/ATLAS.removeprefix('res://')),'size_px':[1024,1024],'layout':LAYOUT,'layout_sha256':sha(root/LAYOUT.removeprefix('res://'))},
            'material_policy':{'material':MATERIAL,'alpha_mode':'OPAQUE','double_sided':False,'roughness':1,'specular':0,'metallic':0,'texture':'one opaque RGB atlas Texture2D shared by every furniture GLB'},
            'import_policy':{'generate_lods':False,'import_script':None,'note':'GLB material imported as-is; no per-asset shader/post-import'},
            'distances_m':{'LOD0_max':near,'LOD1_max':far,'beyond_lod1':'cull (no far proxy for small furniture)','distance_class':TEMPLATES[name]['distance_class'],
                           'status':'working-model-not-integrated','decision':'T-058 technical-artist working value; not an integration or user decision'},
            'budgets':dict(LIMITS)}


def entry(root,name):
    chain=measure_chain(root,name);s=chain['levels']['LOD0'];lo,hi=s['bbox_min'],s['bbox_max'];t=TEMPLATES[name]
    return {'id':'fur_hero_%s_a'%name,'label_tr':LABELS[name],'category':'street_furniture','family':'hero_'+name,'variant':'a','era':'none','region':None,
            'tags':['hero','street-furniture-proposal','matte','opaque-atlas','no-light','no-text','type:'+name],
            'glb':s['glb'],'glb_sha256':s['sha256'],'materials':s['materials'],
            'dimensions_m':{'width_x':round(hi[0]-lo[0],3),'depth_z':round(hi[2]-lo[2],3),'height_above_ground':round(hi[1],3),'foundation_skirt_depth':round(max(0,-lo[1]),3),'bbox_min':lo,'bbox_max':hi,'measured_from':'GLB POSITION accessors, glTF +Y up, metres'},
            'triangles':{k:v['triangles'] for k,v in chain['levels'].items()},
            'palette_rows':{'accent_rows':[],'roof_rows':[],'wall_rows':[],'furniture_rows':t['rows']},
            'template_ref':{'template_id':t['template_id'],'template_size_m':t['template_size_m'],'size_status':t['size_status'],'intended_height_m':t['height_m'],'source':'design/library/templates-v0.md section f'},
            'source':{'kind':'hero_furniture','generator':'art/blender/furniture/build.py','manifest':None,'rebuild':'bash art/blender/furniture/rebuild.sh','spec':'production/tasks/T-058.md'},
            'approval':'proposed','approval_by':None,'approval_date':None,'user_note':'','lod_chain':chain,
            'notes':'Sokak donatısı hero önerisi; yalnız kütüphane/lab. Q-018 (donatı/metal/kiosk/ışık) açık; renk, ölçü ve yerleşim kullanıcı onayı değil.'}


def update(catalog,root):
    result=copy.deepcopy(catalog);positions={e['id']:i for i,e in enumerate(result['entries'])}
    for name in NAMES:
        new=entry(root,name)
        if new['id'] in positions:
            index=positions[new['id']];old=result['entries'][index]
            if old.get('source',{}).get('kind')!='hero_furniture':raise ValueError('id collision: '+new['id'])
            for key,value in old.items():
                if key.startswith(('approval','user_')):new[key]=copy.deepcopy(value)
            result['entries'][index]=new
        else:result['entries'].append(new)
    order={category['id']:i for i,category in enumerate(result['categories'])}
    result['entries'].sort(key=lambda e:(order.get(e['category'],99),e['id']))
    return result


def validate_chain(e,root):
    source=e.get('source')
    if not isinstance(source,dict):return [e.get('id','?')+': source must be an object']
    if source.get('kind')!='hero_furniture':return []
    errors=[];root=Path(root);ident=e.get('id','?')
    try:
        name=e['family'].removeprefix('hero_')
        if name not in NAMES:raise ValueError('unknown furniture type')
        expected=entry(root,name)
        for key in ('glb','glb_sha256','materials','dimensions_m','triangles','lod_chain','palette_rows','template_ref'):
            if e.get(key)!=expected[key]:errors.append(ident+': furniture '+key+' drift or missing metadata')
        if set(expected['lod_chain']['levels'])!=set(LEVELS):errors.append(ident+': wrong LOD chain levels')
        if 'PROXY' in e.get('triangles',{}) or 'PROXY' in e.get('lod_chain',{}).get('levels',{}):errors.append(ident+': furniture must not carry a PROXY level (cull instead)')
        errors.extend(ident+': far proxy residue '+n for n in proxy_residue(root,name))
        for level,stats in expected['lod_chain']['levels'].items():
            if not 0<stats['triangles']<=LIMITS[level]:errors.append(ident+': '+level+' triangle budget exceeded ('+str(stats['triangles'])+'>'+str(LIMITS[level])+')')
            config=root/stats['glb'].removeprefix('res://')
            params=import_params(config.with_suffix('.glb.import'))
            if params.get('meshes/generate_lods')!='false':errors.append(ident+': '+level+' import must set meshes/generate_lods=false')
            if params.get('import_script/path') not in ('""',):errors.append(ident+': '+level+' import must not use a post-import script')
            g=glb_info.read_gltf_json(config)
            mats=g.get('materials',[])
            if len(mats)!=1 or mats[0].get('name')!=MATERIAL:errors.append(ident+': exactly one shared '+MATERIAL+' material required')
            for mat in mats:
                if mat.get('alphaMode') not in (None,'OPAQUE') or mat.get('doubleSided') is True:errors.append(ident+': furniture material must be opaque single-sided')
            images=g.get('images',[])
            if len(images)!=1 or images[0].get('uri')!='furniture_atlas.png' or 'bufferView' in images[0]:errors.append(ident+': texture must be the external shared furniture_atlas.png')
            if stats['bbox_min'][1]<-0.001 or stats['bbox_min'][1]>0.001:errors.append(ident+': '+level+' must be ground-origin (min Y=0)')
        atlas=(root/ATLAS.removeprefix('res://')).read_bytes()
        if atlas[:8]!=b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',atlas[16:24])!=(1024,1024) or atlas[25]!=2:errors.append(ident+': invalid 1024px RGB furniture atlas')
        layout=json.loads((root/LAYOUT.removeprefix('res://')).read_text())
        if len(layout.get('regions',{}))!=16:errors.append(ident+': atlas_layout.json must list 16 regions')
        want=TEMPLATES[name]['height_m'];height=expected['dimensions_m']['height_above_ground']
        if abs(height-want)>want*HEIGHT_TOLERANCE:errors.append('%s: height %.3f m outside %.0f%% of intended %.2f m'%(ident,height,HEIGHT_TOLERANCE*100,want))
        if e.get('approval')=='proposed' and e.get('lod_chain',{}).get('status')!='proposed':errors.append(ident+': generated chain status must remain proposed')
    except (KeyError,OSError,ValueError,TypeError,struct.error,IndexError) as ex:errors.append(ident+': invalid furniture chain: '+str(ex))
    return errors


def main():
    p=argparse.ArgumentParser();p.add_argument('--write',action='store_true');p.add_argument('--check',action='store_true');args=p.parse_args()
    path=ROOT/'data/library/catalog.json';cat=json.loads(path.read_text());result=update(cat,ROOT)
    errors=[error for e in result['entries'] for error in validate_chain(e,ROOT)]
    if errors:print('\n'.join(errors));return 1
    output=json.dumps(result,indent=2,ensure_ascii=False)+'\n'
    if args.write:path.write_text(output)
    elif args.check and path.read_text()!=output:print('furniture catalog stale');return 1
    print('furniture proposals %d; measured LODs %d (LOD0/LOD1, cull beyond LOD1); catalog %s'%(len(NAMES),2*len(NAMES),'written' if args.write else 'checked'));return 0


if __name__=='__main__':raise SystemExit(main())
