"""T-059 human style proposals (isolated library assets, no game integration).
Blender --background --factory-startup --python art/blender/human/build.py -- [pawn_neutral ...]
Prerequisite: uv run --with pillow==11.3.0 python art/blender/human/atlas.py
One opaque matte atlas material (mat_human_atlas, roughness 1, specular 0) shared by every GLB; texture stays external.
Objects are named <id>_LOD0 / <id>_LOD1 (design/library/README.md section 8). Metres, ground origin, front = -Y.
"""
import json
from pathlib import Path
import struct
import sys
import bpy

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import assets

ROOT=HERE.parents[2]
OUT=ROOT/'assets/hero/human'


def save(name,level,mesh_data):
    ident='hum_hero_%s_a'%name;obj_name='%s_LOD%d'%(ident,level)
    mesh=bpy.data.meshes.new(obj_name);mesh.from_pydata(mesh_data.V,[],mesh_data.F);mesh.update()
    layer=mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        for li in poly.loop_indices:layer.data[li].uv=mesh_data.UV[mesh.loops[li].vertex_index]
    ob=bpy.data.objects.new(obj_name,mesh);bpy.context.scene.collection.objects.link(ob)
    mat=bpy.data.materials.new('mat_human_atlas');mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=1;bsdf.inputs['Specular IOR Level'].default_value=0
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/'human_atlas.png'),check_existing=True)
    mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    mesh.materials.append(mat);bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    path=OUT/('%s_lod%d.glb'%(ident,level))
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
    data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n])
    imageviews={im.get('bufferView') for im in g.get('images',[]) if 'bufferView' in im}
    for image in g.get('images',[]):image.clear();image['uri']='human_atlas.png'
    for material in g['materials']:material['doubleSided']=False;material.pop('alphaMode',None)
    remap={i:sum(j not in imageviews for j in range(i)) for i in range(len(g['bufferViews'])) if i not in imageviews}
    g['bufferViews']=[v for i,v in enumerate(g['bufferViews']) if i not in imageviews]
    for accessor in g['accessors']:
        if 'bufferView' in accessor:accessor['bufferView']=remap[accessor['bufferView']]
    used=max(v.get('byteOffset',0)+v['byteLength'] for v in g['bufferViews']);g['buffers'][0]['byteLength']=used
    binary=data[28+n:28+n+used];binary+=b'\0'*((-len(binary))%4)
    tail=struct.pack('<II',len(binary),0x004e4942)+binary
    js=json.dumps(g,separators=(',',':')).encode();js+=b' '*((-len(js))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(js)+len(tail))+struct.pack('<II',len(js),0x4e4f534a)+js+tail)
    lo,hi=mesh_data.bbox()
    print('HUMAN',ident,'LOD%d'%level,mesh_data.tris,'budget',assets.BUDGET[level],'bbox',[round(v,3) for v in lo],[round(v,3) for v in hi],flush=True)
    if mesh_data.tris>assets.BUDGET[level]:raise ValueError(obj_name+' exceeds triangle budget')


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    names=[a for a in args if not a.startswith('--')] or assets.ASSETS
    for name in names:
        if name not in assets.ASSETS:raise ValueError(name)
        for level in (0,1):
            for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
            bpy.data.orphans_purge(do_recursive=True)
            save(name,level,assets.build(name,level))


main()
