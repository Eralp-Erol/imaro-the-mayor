#!/usr/bin/env python3
"""T-059 measure/register/validate isolated human-style proposals (library only, no game integration).
python3 tools/library/human_catalog.py --write | --check
Mirrors tools/library/furniture_catalog.py: values come from the real GLB files; user-owned fields are never touched.
A pawn / B block figure / C facet figure x neutral and broad body ratio = 6 proposals; none is selected (Q-018 is the user's).
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
STYLES=['pawn','block','facet']
RATIOS=['neutral','broad']
NAMES=['%s_%s'%(s,r) for s in STYLES for r in RATIOS]
STYLE_LABEL={'pawn':'A piyon · uzuvsuz gövde prizması','block':'B blok figür · prizma uzuvlar, el/ayak blokları','facet':'C faset figür · eklemli uzuvlar, ayakkabı, yaka/manşet'}
RATIO_LABEL={'neutral':'nötr 1,75 m yetişkin','broad':'geniş gövde oranı (1,75 m)'}
# working values (calisma degeri): same height for both ratios so only the body ratio differs
TEMPLATES={'neutral':{'reference_ids':['hum_adult_m_a','hum_adult_f_a'],'template_size_m':[1.75,0.46],'size_status':'working-value between hum_adult_m_a 1.76x0.48 and hum_adult_f_a 1.64x0.42 (height 1.75 per task)'},
           'broad':{'reference_ids':['hum_adult_broad_a'],'template_size_m':[1.74,0.56],'size_status':'template hum_adult_broad_a 1.74x0.56; height set to 1.75 for equal comparison (working value)'}}
HEIGHT_M=1.75
HEIGHT_TOLERANCE=0.01
LIMITS={'LOD0':900,'LOD1':100}
LEVELS=['LOD0','LOD1']
ENVELOPE_TOL=0.02
DISTANCES_M={'LOD0_max':30,'LOD1_max':120}
ATLAS='res://assets/hero/human/human_atlas.png'
LAYOUT='res://assets/hero/human/atlas_layout.json'
HUM_DIR='assets/hero/human'
MATERIAL='mat_human_atlas'
PALETTE=['SK2','HR2','CL7','CL4','CL15','CL6','CL2','CL1']
REQUIRED_TAGS=['hero','human-style-proposal','matte','opaque-atlas','no-face','no-logo','no-text','anonymous','neutral-palette']
ALLOWED_TAGS=set(REQUIRED_TAGS)|{'style:'+s for s in STYLES}|{'ratio:'+r for r in RATIOS}
NOTES='İnsan stil önerisi (A piyon / B blok / C faset); yalnız kütüphane/lab, hiçbiri seçilmiş değil. Q-018 (stilizasyon, kimlik/giyim, mevsim) açık; palet ve oranlar çalışma değeri, kullanıcı onayı değil.'
NOTES_OPEN_QUESTION='Q-018 (stilizasyon, kimlik/giyim, mevsim) açık'  # names the open question; the only sentence allowed to mention a forbidden topic
FORBIDDEN_WORDS=['uniform','üniform','logo','protagonist','named-character','adlı karakter','başörtü','hijab','kippa','religious','dini','season','mevsim','helmet','baret','face-detail']


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def import_params(path):
    params={}
    for line in path.read_text().splitlines():
        if '=' in line and not line.startswith('['):
            key,value=line.split('=',1);params[key]=value
    return params


def glb_path(name,level):return 'res://%s/hum_hero_%s_a_%s.glb'%(HUM_DIR,name,level.lower())


def proxy_residue(root,name):
    return [n for n in ('hum_hero_%s_a_proxy.glb'%name,'hum_hero_%s_a_proxy.glb.import'%name) if (root/HUM_DIR/n).exists()]


def measure_chain(root,name):
    levels={level:hero_lods.measure(root,glb_path(name,level)) for level in LEVELS}
    return {'status':'proposed','generator':'art/blender/human/build.py','levels':levels,
            'atlas':{'path':ATLAS,'sha256':sha(root/ATLAS.removeprefix('res://')),'size_px':[1024,512],'layout':LAYOUT,'layout_sha256':sha(root/LAYOUT.removeprefix('res://'))},
            'material_policy':{'material':MATERIAL,'alpha_mode':'OPAQUE','double_sided':False,'roughness':1,'specular':0,'metallic':0,'texture':'one opaque RGB flat-tile atlas Texture2D shared by every human GLB'},
            'import_policy':{'generate_lods':False,'import_script':None,'note':'GLB material imported as-is; no per-asset shader/post-import'},
            'distances_m':dict(DISTANCES_M,beyond_lod1='cull (no far proxy for a single small figure)',status='working-model-not-integrated',
                               decision='T-059 technical-artist working value (1.75 m figure ~17 px at 120 m, README 5.1); not an integration or user decision'),
            'budgets':dict(LIMITS)}


def entry(root,name):
    style,ratio=name.split('_');chain=measure_chain(root,name);s=chain['levels']['LOD0'];lo,hi=s['bbox_min'],s['bbox_max'];t=TEMPLATES[ratio]
    return {'id':'hum_hero_%s_a'%name,'label_tr':'%s · %s'%(STYLE_LABEL[style],RATIO_LABEL[ratio]),'category':'human','family':'hero_'+name,'variant':'a','era':'none','region':None,
            'tags':['hero','human-style-proposal','matte','opaque-atlas','no-face','no-logo','no-text','anonymous','neutral-palette','style:'+style,'ratio:'+ratio],
            'glb':s['glb'],'glb_sha256':s['sha256'],'materials':s['materials'],
            'dimensions_m':{'width_x':round(hi[0]-lo[0],3),'depth_z':round(hi[2]-lo[2],3),'height_above_ground':round(hi[1],3),'foundation_skirt_depth':round(max(0,-lo[1]),3),'bbox_min':lo,'bbox_max':hi,'measured_from':'GLB POSITION accessors, glTF +Y up, metres'},
            'triangles':{k:v['triangles'] for k,v in chain['levels'].items()},
            'palette_rows':{'accent_rows':[],'roof_rows':[],'wall_rows':[],'human_rows':list(PALETTE)},
            'template_ref':{'template_id':None,'reference_ids':t['reference_ids'],'template_size_m':t['template_size_m'],'size_status':t['size_status'],'intended_height_m':HEIGHT_M,'source':'design/library/templates-v0.md section a'},
            'source':{'kind':'hero_human','generator':'art/blender/human/build.py','manifest':None,'rebuild':'bash art/blender/human/rebuild.sh','spec':'production/tasks/T-059.md'},
            'approval':'proposed','approval_by':None,'approval_date':None,'user_note':'','lod_chain':chain,
            'notes':NOTES}


def update(catalog,root):
    result=copy.deepcopy(catalog);positions={e['id']:i for i,e in enumerate(result['entries'])}
    for name in NAMES:
        new=entry(root,name)
        if new['id'] in positions:
            index=positions[new['id']];old=result['entries'][index]
            if old.get('source',{}).get('kind')!='hero_human':raise ValueError('id collision: '+new['id'])
            for key,value in old.items():
                if key.startswith(('approval','user_')):new[key]=copy.deepcopy(value)
            result['entries'][index]=new
        else:result['entries'].append(new)
    order={category['id']:i for i,category in enumerate(result['categories'])}
    result['entries'].sort(key=lambda e:(order.get(e['category'],99),e['id']))
    return result


def content_errors(e):
    """Forbidden-content gate: only the allow-listed tags, no forbidden words in label/user_note (face, logo, uniform, cultural dress, named character, season)."""
    ident=e.get('id','?');errors=[]
    tags=e.get('tags',[])
    for tag in tags:
        if tag not in ALLOWED_TAGS:errors.append(ident+': tag not allowed for a human proposal: '+str(tag))
    for tag in REQUIRED_TAGS:
        if tag not in tags:errors.append(ident+': missing required tag '+tag)
    text=' '.join([str(e.get(k,'')) for k in ('label_tr','user_note')]+[str(e.get('notes','')).replace(NOTES_OPEN_QUESTION,'')]).lower()  # tags are allow-listed above
    for word in FORBIDDEN_WORDS:
        if word in text:errors.append(ident+': forbidden content word "'+word+'"')
    return errors


def light_errors(g):
    """GLB must stay unlit and non-emissive: no emissive factor/texture, no KHR_lights_punctual (nodes or extensions), no emission extension."""
    errors=[]
    for mat in g.get('materials',[]):
        if any(v>0 for v in mat.get('emissiveFactor',[0,0,0])) or 'emissiveTexture' in mat:errors.append('material must not be emissive')
        for ext in mat.get('extensions',{}):
            if ext=='KHR_materials_emissive_strength':errors.append('emissive extension not allowed')
    used=set(g.get('extensionsUsed',[]))|set(g.get('extensionsRequired',[]))|set(g.get('extensions',{}))
    for node in g.get('nodes',[]):used|=set(node.get('extensions',{}))
    if any('light' in x.lower() for x in used):errors.append('light extension not allowed: '+', '.join(sorted(x for x in used if 'light' in x.lower())))
    if g.get('extensions',{}).get('KHR_lights_punctual') or any('KHR_lights_punctual' in n.get('extensions',{}) for n in g.get('nodes',[])):errors.append('KHR_lights_punctual not allowed')
    return errors


def validate_chain(e,root):
    source=e.get('source')
    if not isinstance(source,dict):return [e.get('id','?')+': source must be an object']
    if source.get('kind')!='hero_human':return []
    errors=content_errors(e);root=Path(root);ident=e.get('id','?')
    try:
        name=e['family'].removeprefix('hero_')
        if name not in NAMES:raise ValueError('unknown human proposal')
        expected=entry(root,name)
        for key in ('glb','glb_sha256','materials','dimensions_m','triangles','lod_chain','palette_rows','template_ref'):
            if e.get(key)!=expected[key]:errors.append(ident+': human '+key+' drift or missing metadata')
        if set(expected['lod_chain']['levels'])!=set(LEVELS):errors.append(ident+': wrong LOD chain levels')
        if 'PROXY' in e.get('triangles',{}) or 'PROXY' in e.get('lod_chain',{}).get('levels',{}):errors.append(ident+': human must not carry a PROXY level (cull instead)')
        errors.extend(ident+': far proxy residue '+n for n in proxy_residue(root,name))
        levels=expected['lod_chain']['levels']
        for level,stats in levels.items():
            if not 0<stats['triangles']<=LIMITS[level]:errors.append(ident+': '+level+' triangle budget exceeded ('+str(stats['triangles'])+'>'+str(LIMITS[level])+')')
            config=root/stats['glb'].removeprefix('res://')
            params=import_params(config.with_suffix('.glb.import'))
            if params.get('meshes/generate_lods')!='false':errors.append(ident+': '+level+' import must set meshes/generate_lods=false')
            if params.get('import_script/path') not in ('""',):errors.append(ident+': '+level+' import must not use a post-import script')
            g=glb_info.read_gltf_json(config);mats=g.get('materials',[])
            if len(mats)!=1 or mats[0].get('name')!=MATERIAL:errors.append(ident+': exactly one shared '+MATERIAL+' material required')
            for mat in mats:
                if mat.get('alphaMode') not in (None,'OPAQUE') or mat.get('doubleSided') is True:errors.append(ident+': human material must be opaque single-sided')
            images=g.get('images',[])
            if len(images)!=1 or images[0].get('uri')!='human_atlas.png' or 'bufferView' in images[0]:errors.append(ident+': texture must be the external shared human_atlas.png')
            errors.extend(ident+': '+level+' '+x for x in light_errors(g))
            names=[n.get('name') for n in g.get('nodes',[])]
            if names!=['%s_%s'%(ident,level)]:errors.append(ident+': '+level+' node names must be exactly '+ident+'_'+level+', got '+str(names))
            if abs(stats['bbox_min'][1])>0.001:errors.append(ident+': '+level+' must be ground-origin (min Y=0)')
            if abs(stats['bbox_max'][1]-HEIGHT_M)>HEIGHT_M*HEIGHT_TOLERANCE:errors.append('%s: %s height %.3f m outside 1%% of %.2f m'%(ident,level,stats['bbox_max'][1],HEIGHT_M))
        lo0,hi0=levels['LOD0']['bbox_min'],levels['LOD0']['bbox_max'];lo1,hi1=levels['LOD1']['bbox_min'],levels['LOD1']['bbox_max']
        for i in range(3):
            if lo1[i]<lo0[i]-ENVELOPE_TOL or hi1[i]>hi0[i]+ENVELOPE_TOL:errors.append(ident+': LOD1 must sit inside the LOD0 envelope (axis %d)'%i)
        atlas=(root/ATLAS.removeprefix('res://')).read_bytes()
        if atlas[:8]!=b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',atlas[16:24])!=(1024,512) or atlas[25]!=2:errors.append(ident+': invalid 1024x512 RGB human atlas')
        layout=json.loads((root/LAYOUT.removeprefix('res://')).read_text())
        if len(layout.get('regions',{}))!=8:errors.append(ident+': atlas_layout.json must list 8 regions')
        if e.get('approval')=='proposed' and e.get('lod_chain',{}).get('status')!='proposed':errors.append(ident+': generated chain status must remain proposed')
    except (KeyError,OSError,ValueError,TypeError,struct.error,IndexError) as ex:errors.append(ident+': invalid human chain: '+str(ex))
    return errors


def main():
    p=argparse.ArgumentParser();p.add_argument('--write',action='store_true');p.add_argument('--check',action='store_true');args=p.parse_args()
    path=ROOT/'data/library/catalog.json';cat=json.loads(path.read_text());result=update(cat,ROOT)
    errors=[error for e in result['entries'] for error in validate_chain(e,ROOT)]
    if errors:print('\n'.join(errors));return 1
    output=json.dumps(result,indent=2,ensure_ascii=False)+'\n'
    if args.write:path.write_text(output)
    elif args.check and path.read_text()!=output:print('human catalog stale');return 1
    print('human proposals %d; measured LODs %d (LOD0/LOD1, cull beyond LOD1); catalog %s'%(len(NAMES),2*len(NAMES),'written' if args.write else 'checked'));return 0


if __name__=='__main__':raise SystemExit(main())
