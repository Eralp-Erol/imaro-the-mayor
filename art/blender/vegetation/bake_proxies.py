"""T-057 source-LOD0 unlit+alpha front/side/top impostors; no changes to LOD0.
Blender --background --factory-startup --python art/blender/vegetation/bake_proxies.py
Then uv run --with pillow==11.3.0 python art/blender/vegetation/pack_proxies.py
"""
import hashlib
import json
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/hero/vegetation'
RAW=ROOT/'artifacts/verify/t057/impostor-bakes'
SPECIES=['plane','pine_brutia','pine_stone','olive_open','olive_twisted','cypress','maquis','hedge']


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    RAW.mkdir(parents=True,exist_ok=True)
    layout=json.loads((OUT/'atlas_layout.json').read_text())
    manifest={'version':1,'method':'actual LOD0 GLB, emission albedo with binary source alpha cutoff .45, no lights/shadows','generator':'art/blender/vegetation/bake_proxies.py','assets':{}}
    scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
    scene.render.film_transparent=True;scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
    for species in SPECIES:
        scene.camera=None
        for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
        bpy.data.orphans_purge(do_recursive=True)
        source=OUT/('veg_hero_'+species+'_a_lod0.glb')
        bpy.ops.import_scene.gltf(filepath=str(source))
        bpy.context.view_layer.update()
        meshes=[o for o in bpy.data.objects if o.type=='MESH']
        points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
        lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
        center=Vector([(a+b)/2 for a,b in zip(lo,hi)])
        mat=bpy.data.materials.new('source_unlit_mask');mat.use_nodes=True;mat.use_backface_culling=False
        nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
        output=nodes.new('ShaderNodeOutputMaterial');mix=nodes.new('ShaderNodeMixShader');transparent=nodes.new('ShaderNodeBsdfTransparent');emission=nodes.new('ShaderNodeEmission');tex=nodes.new('ShaderNodeTexImage');threshold=nodes.new('ShaderNodeMath')
        tex.image=bpy.data.images.load(str(OUT/'vegetation_atlas.png'),check_existing=True)
        threshold.operation='GREATER_THAN';threshold.inputs[1].default_value=.45
        links.new(tex.outputs['Color'],emission.inputs['Color']);links.new(tex.outputs['Alpha'],threshold.inputs[0]);links.new(threshold.outputs[0],mix.inputs[0]);links.new(transparent.outputs[0],mix.inputs[1]);links.new(emission.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],output.inputs['Surface'])
        leaf_heights=[]
        for ob in meshes:
            uv=ob.data.uv_layers.active
            for loop in ob.data.loops:
                coord=uv.data[loop.index].uv
                if not (0<coord.x<.25 and .75<coord.y<1):leaf_heights.append((ob.matrix_world@ob.data.vertices[loop.vertex_index].co).z)
            ob.data.materials.clear();ob.data.materials.append(mat)
            for p in ob.data.polygons:p.material_index=0
        camera=bpy.data.objects.new('source_camera',bpy.data.cameras.new('source_camera'));scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
        asset={'source_lod0':'res://'+str(source.relative_to(ROOT)),'source_lod0_sha256':sha(source),'bbox_blender_min':[round(x,6) for x in lo],'bbox_blender_max':[round(x,6) for x in hi],'top_plane_height':round(sum(leaf_heights)/len(leaf_heights),6),'views':{}}
        for view,offset,size in [('front',(0,-100,0),(hi[0]-lo[0],hi[2]-lo[2])),('side',(100,0,0),(hi[1]-lo[1],hi[2]-lo[2])),('top',(0,0,100),(hi[0]-lo[0],hi[1]-lo[1]))]:
            camera.location=center+Vector(offset);camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=max(size)
            path=RAW/(species+'_'+view+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
            asset['views'][view]={'region':layout['regions']['proxy_'+species+'_'+view],'physical_size':[round(x,6) for x in size],'raw':str(path.relative_to(ROOT))}
        manifest['assets'][species]=asset
        print('SOURCE_PROXY_BAKED',species,flush=True)
    (RAW/'source-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')


main()
