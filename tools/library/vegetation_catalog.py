#!/usr/bin/env python3
"""T-057 measure/register/validate isolated hero vegetation proposals.
python3 tools/library/vegetation_catalog.py --write | --check
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import glb_info
import hero_lods

ROOT=HERE.parents[1]
SPECIES=['plane','palm_date','palm_slender','pine_brutia','pine_stone','olive_open','olive_twisted','cypress','maquis','hedge']
LABELS={'plane':'Çınar','palm_date':'Kalın gövdeli geniş taçlı palmiye','palm_slender':'İnce uzun palmiye','pine_brutia':'Kızılçam','pine_stone':'Fıstık çamı','olive_open':'Zeytin · açık üç taç','olive_twisted':'Zeytin · burgulu yayvan taç','cypress':'Servi','maquis':'Maki / çalı kümesi','hedge':'Budanmış çit'}
ATLAS='res://assets/hero/vegetation/vegetation_atlas.png'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def is_palm(species):return species.startswith('palm')


def levels_for(species):
    """T-057 Karar 5: palms keep the 40-tri PROXY; the eight others are LOD0 -> LOD1 (far = cell blob/HLOD, separate task)."""
    return ['LOD0','LOD1','PROXY'] if is_palm(species) else ['LOD0','LOD1']


def limits(species):
    if species in ('maquis','hedge'):return {'LOD0':600,'LOD1':120}
    return {'LOD0':1800,'LOD1':300,'PROXY':40} if is_palm(species) else {'LOD0':1800,'LOD1':300}


VEG_DIR='assets/hero/vegetation'
LEGACY_SHARED=['proxy_bakes.json','proxy_canopy.gdshader','proxy_canopy.gdshader.uid','proxy_canopy.tres','proxy_import.gd','proxy_import.gd.uid']


def import_params(path):
    params={}
    for line in path.read_text().splitlines():
        if '=' in line and not line.startswith('['):
            key,value=line.split('=',1);params[key]=value
    return params


def legacy_residue(root,species):
    """Retired cross-card proxy leftovers for a non-palm species (assets or shared policy files)."""
    found=[]
    if not is_palm(species):
        for suffix in ('','.import','.uid'):
            if (root/VEG_DIR/('veg_hero_%s_a_proxy.glb%s'%(species,suffix))).exists():found.append('veg_hero_%s_a_proxy.glb%s'%(species,suffix))
        found+= [name for name in LEGACY_SHARED if (root/VEG_DIR/name).exists()]
    return found


def measure_chain(root,species):
    levels={level:hero_lods.measure(root,'res://assets/hero/vegetation/veg_hero_%s_a_%s.glb'%(species,level.lower())) for level in levels_for(species)}
    chain={}
    if is_palm(species):chain.update({'proxy_runtime':None,'proxy_source':None})
    chain.update({'status':'proposed','generator':'art/blender/vegetation/build.py','levels':levels,
            'atlas':{'path':ATLAS,'sha256':sha(root/ATLAS.removeprefix('res://')),'size_px':[1024,1024],'layout':'res://assets/hero/vegetation/atlas_layout.json','layout_sha256':sha(root/'assets/hero/vegetation/atlas_layout.json')},
            'material_policy':{'alpha_mode':'MASK','alpha_cutoff':.45,'double_sided':True,'roughness':1},
            'import_policy':{'generate_lods':False,'import_script':None,'note':'GLB material imported as-is; no per-asset shader/post-import'},
            'distances_m':{'LOD0_max':120,'LOD1_max':400,'beyond_lod1':'PROXY (palms, working)' if is_palm(species) else 'per-cell tree blob/HLOD (separate task, outside T-057)','status':'working-model-not-integrated','decision':'production/qa/T-057-technical-review.md Teknik karar 5'},
            'budgets':limits(species)})
    return chain


def entry(root,species):
    chain=measure_chain(root,species);s=chain['levels']['LOD0'];lo,hi=s['bbox_min'],s['bbox_max']
    return {'id':'veg_hero_'+species+'_a','label_tr':LABELS[species],'category':'vegetation','family':'hero_'+species,'variant':'a','era':'none','region':None,
            'tags':['hero','vegetation-proposal','summer-neutral','alpha-mask','species:'+species],
            'glb':s['glb'],'glb_sha256':s['sha256'],'materials':s['materials'],
            'dimensions_m':{'width_x':round(hi[0]-lo[0],3),'depth_z':round(hi[2]-lo[2],3),'height_above_ground':round(hi[1],3),'foundation_skirt_depth':round(max(0,-lo[1]),3),'bbox_min':lo,'bbox_max':hi,'measured_from':'GLB POSITION accessors, glTF +Y up, metres'},
            'triangles':{k:v['triangles'] for k,v in chain['levels'].items()},'palette_rows':{'accent_rows':[],'roof_rows':[],'wall_rows':[]},
            'source':{'kind':'hero_vegetation','generator':'art/blender/vegetation/build.py','manifest':None,'rebuild':'bash art/blender/vegetation/rebuild.sh','spec':'production/tasks/T-057.md'},
            'approval':'proposed','approval_by':None,'approval_date':None,'user_note':'','lod_chain':chain,
            'notes':'Bitki hero önerisi; yalnız kütüphane/lab. Q-018 açık; oyun yerleşimi/tür oranı/son kullanıcı onayı değil.'}


def update(catalog,root):
    result=copy.deepcopy(catalog);positions={e['id']:i for i,e in enumerate(result['entries'])}
    for species in SPECIES:
        new=entry(root,species)
        if new['id'] in positions:
            index=positions[new['id']];old=result['entries'][index]
            if old.get('source',{}).get('kind')!='hero_vegetation':raise ValueError('id collision: '+new['id'])
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
    if source.get('kind')!='hero_vegetation':return []
    errors=[];root=Path(root);ident=e.get('id','?')
    try:
        species=e['family'].removeprefix('hero_')
        if species not in SPECIES:raise ValueError('unknown vegetation species')
        expected=entry(root,species)
        for key in ('glb','glb_sha256','materials','dimensions_m','triangles','lod_chain'):
            if e.get(key)!=expected[key]:errors.append(ident+': vegetation '+key+' drift or missing metadata')
        if set(expected['lod_chain']['levels'])!=set(levels_for(species)):errors.append(ident+': wrong LOD chain levels for '+species)
        if not is_palm(species):
            if 'PROXY' in e.get('triangles',{}) or 'PROXY' in e.get('lod_chain',{}).get('levels',{}):errors.append(ident+': non-palm species must not carry a PROXY level (Karar 5)')
            for field in ('proxy_source','proxy_runtime'):
                if field in e.get('lod_chain',{}):errors.append(ident+': retired '+field+' present')
            errors.extend(ident+': retired proxy residue '+name for name in legacy_residue(root,species))
        for level,stats in expected['lod_chain']['levels'].items():
            if not 0<stats['triangles']<=limits(species)[level]:errors.append(ident+': '+level+' triangle budget exceeded')
            config=root/stats['glb'].removeprefix('res://')
            params=import_params(config.with_suffix('.glb.import'))
            if params.get('meshes/generate_lods')!='false':errors.append(ident+': '+level+' import must set meshes/generate_lods=false')
            if params.get('import_script/path') not in ('""',):errors.append(ident+': '+level+' import must not use a post-import script')
            g=glb_info.read_gltf_json(config)
            if len(g.get('materials',[]))!=1:errors.append(ident+': one shared atlas material required')
            for mat in g.get('materials',[]):
                if mat.get('alphaMode')!='MASK' or mat.get('alphaCutoff')!=.45 or mat.get('doubleSided') is not True:errors.append(ident+': foliage must use double-sided alpha MASK .45')
            for image in g.get('images',[]):
                if image.get('uri')!='vegetation_atlas.png' or 'bufferView' in image:errors.append(ident+': texture must be external shared vegetation atlas')
        atlas=(root/ATLAS.removeprefix('res://')).read_bytes()
        if atlas[:8]!=b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',atlas[16:24])!=(1024,1024):errors.append(ident+': invalid1024px vegetation atlas')
        height=e['dimensions_m']['height_above_ground']
        if species.startswith('palm') and height>11.5:errors.append(ident+': palm exceeds11.5m working scale')
    except (KeyError,OSError,ValueError,TypeError,struct.error) as ex:errors.append(ident+': invalid vegetation chain: '+str(ex))
    return errors


def main():
    p=argparse.ArgumentParser();p.add_argument('--write',action='store_true');p.add_argument('--check',action='store_true');args=p.parse_args()
    check=subprocess.run(['uv','run','--with','pillow==11.3.0','python',str(HERE/'check_vegetation_atlas.py')])
    if check.returncode:return 1
    path=ROOT/'data/library/catalog.json';cat=json.loads(path.read_text());result=update(cat,ROOT)
    errors=[error for e in result['entries'] for error in validate_chain(e,ROOT)]
    if errors:print('\n'.join(errors));return 1
    output=json.dumps(result,indent=2,ensure_ascii=False)+'\n'
    if args.write:path.write_text(output)
    elif args.check and path.read_text()!=output:print('vegetation catalog stale');return 1
    print('vegetation proposals10; measured LODs22 (8 non-palm LOD0/LOD1 + 2 palm LOD0/LOD1/PROXY); catalog '+('written' if args.write else 'checked'));return 0


if __name__=='__main__':raise SystemExit(main())
