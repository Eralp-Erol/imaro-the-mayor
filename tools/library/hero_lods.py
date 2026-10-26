#!/usr/bin/env python3
"""Measure/register/validate T-056 library-only hero LOD chains; preserve user fields.
python3 tools/library/hero_lods.py --write | --check
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys
import struct

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import glb_info

ROOT=HERE.parents[1]
FAMILY_MAP={'hero_old_core':'old_core','hero_com_bazaar':'bazaar','hero_res_mid':'res_mid','hero_res_late':'res_late','hero_res_house':'house','hero_ind_hero':'industrial','hero_civ_hero':'civic'}


def measure(root,path):
    file=root/path.removeprefix('res://')
    info=glb_info.inspect(file)
    nodes=list(info['nodes'].values())
    return {'glb':path,'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),
            'triangles':sum(n['tris'] for n in nodes),
            'bbox_min':[round(min(n['min'][i] for n in nodes),6) for i in range(3)],
            'bbox_max':[round(max(n['max'][i] for n in nodes),6) for i in range(3)],
            'materials':info['materials']}


def chain(root,entry):
    family=FAMILY_MAP[entry['family']]
    lods={'LOD0':measure(root,entry['glb'])}
    for level in ('LOD1','PROXY'):
        path='res://assets/hero/lod/hero_%s_%s_%s.glb'%(family,entry['variant'],level.lower())
        lods[level]=measure(root,path)
    atlas=('assets/hero/hero_atlas_%s.png'%entry['variant'] if family=='old_core' else 'assets/hero/fam/%s_%s.png'%(family,entry['variant']))
    atlas=('assets/hero/hero_%s_hero_atlas_%s.png'%(entry['variant'],entry['variant']) if family=='old_core' else 'assets/hero/fam/hero_%s_%s_%s_%s.png'%(family,entry['variant'],family,entry['variant']))
    proxy_atlas='assets/hero/lod/proxy_%s_%s.png'%(family,entry['variant'])
    return {'proxy_atlas':{'path':'res://'+proxy_atlas,'sha256':hashlib.sha256((root/proxy_atlas).read_bytes()).hexdigest(),'size_px':[256,256], 'method':'unlit orthographic LOD0 front; original side/rear tile retained, original UV layout, downsampled Lanczos', 'derived_from_glb_sha256':lods['LOD0']['sha256']},'status':'proposed','generator':'art/blender/hero/build_lods.py',
            'rebuild':'/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python art/blender/hero/build_lods.py -- '+family,
            'distances_m':{'LOD0_max':100,'LOD1_max':300,'status':'working-model-not-integrated'},
            'atlas':{'path':'res://'+atlas,'sha256':hashlib.sha256((root/atlas).read_bytes()).hexdigest()},'levels':lods}


def update(catalog,root):
    result=copy.deepcopy(catalog)
    for entry in result['entries']:
        if entry.get('source',{}).get('kind')=='hero' and entry.get('family') in FAMILY_MAP:
            entry['lod_chain']=chain(root,entry)
            entry['triangles']={k:v['triangles'] for k,v in entry['lod_chain']['levels'].items()}
    return result


def validate_chain(entry,root):
    errors=[]
    if 'lod_chain' not in entry: return errors
    ident=entry.get('id','?')
    try:
        expected=chain(Path(root),entry)
        actual=entry['lod_chain']
        if actual!=expected: errors.append(ident+': LOD chain drift or invalid metadata')
        for level in ('LOD1','PROXY'):
            stats=expected['levels'][level]
            if not 0<stats['triangles']<=(800 if level=='LOD1' else 80):
                errors.append(ident+': '+level+' exceeds triangle budget')
            if entry['triangles'].get(level)!=stats['triangles']:
                errors.append(ident+': '+level+' catalog triangle drift')
            gltf=glb_info.read_gltf_json(Path(root)/stats['glb'].removeprefix('res://'))
            for image in gltf.get('images',[]):
                uri=image.get('uri','')
                if not uri or uri.startswith(('http:','https:','data:')):
                    errors.append(ident+': '+level+' must reuse a local shared atlas')
                else:
                    texture=(Path(root)/stats['glb'].removeprefix('res://')).parent/uri
                    if texture.resolve()!=(Path(root)/expected['proxy_atlas' if level=='PROXY' else 'atlas']['path'].removeprefix('res://')).resolve():
                        errors.append(ident+': '+level+' shared atlas path mismatch')
        png=(Path(root)/expected['proxy_atlas']['path'].removeprefix('res://')).read_bytes()
        if png[:8]!=b'\x89PNG\r\n\x1a\n' or list(struct.unpack('>II',png[16:24]))!=[256,256]:
            errors.append(ident+': proxy atlas must be a 256px PNG')
        if actual.get('status')!='proposed': errors.append(ident+': generated LOD approval must remain proposed')
    except (KeyError,ValueError,OSError,TypeError) as exc:
        errors.append(ident+': invalid LOD chain: '+str(exc))
    return errors


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write',action='store_true'); parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    path=ROOT/'data/library/catalog.json'; cat=json.loads(path.read_text())
    result=update(cat,ROOT)
    errors=[error for e in result['entries'] for error in validate_chain(e,ROOT)]
    if errors: print('\n'.join(errors)); return 1
    text=json.dumps(result,indent=2,ensure_ascii=False)+'\n'
    if args.write: path.write_text(text)
    elif args.check and path.read_text()!=text: print('hero LOD catalog stale'); return 1
    print('hero LOD chains: 21; measured levels: 63; catalog '+('written' if args.write else 'checked'))
    return 0


if __name__=='__main__': raise SystemExit(main())
