"""T-056 semantic LOD generator. Run with Blender --background --factory-startup --python ... -- [family].
Uses the original authoring functions and atlas. Facades become closed textured quads;
windows are already painted in the source atlas. Retains roof/balcony/landmark geometry.
No decimation and no changes to approved LOD0 files. Units/origin follow source exactly.
"""
import ast
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import subprocess
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
FAMILIES = ['old_core', 'bazaar', 'res_mid', 'res_late', 'house', 'industrial', 'civic']


def source_module(family, variant):
    old = family == 'old_core'
    path = HERE / ('hero_building.py' if old else 'fam_build.py')
    atlas = ROOT / ('assets/hero/hero_atlas_%s.png' % variant if old else 'assets/hero/fam/%s_%s.png' % (family, variant))
    layout = ROOT / ('assets/hero/hero_atlas_layout.json' if old else 'assets/hero/fam/%s_layout.json' % family)
    argv = sys.argv
    sys.argv = ['source', '--', '--family', family, '--variant', variant, '--atlas', str(atlas), '--layout', str(layout), '--out', 'unused']
    # Load only definitions/configuration: never run source's top-level scene deletion/build.
    tree = ast.parse(path.read_text(), filename=str(path))
    tree.body = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom, ast.Assign, ast.FunctionDef))]
    env = {'__file__': str(path), '__name__': 'hero_lod_source'}
    exec(compile(tree, str(path), 'exec'), env)
    sys.argv = argv
    return env, atlas


def simplify(env, family, level):
    old = family == 'old_core'
    raw_box = env['box']
    def original_box(x0,x1,y0,y1,z0,z1,faces):
        raw_box(((x0+x1)/2,(y0+y1)/2,(z0+z1)/2),(x1-x0,y1-y0,z1-z0),faces)
    # Delete details whose cross section is subpixel at LOD1 distance. Long floor
    # slabs, rail panels, chimneys, tower and roof masses survive this predicate.
    def detail_box(x0, x1, y0, y1, z0, z1, faces):
        dims = sorted([abs(x1-x0), abs(y1-y0), abs(z1-z0)])
        if dims[1] < 0.30 or (dims[0] < 0.10 and dims[1] < 0.65):
            return
        original_box(x0, x1, y0, y1, z0, z1, faces)
    env['aabox'] = detail_box
    def wall(plane, holes, uvfn, u0, u1, *args, **kw):
        if old:
            z0, z1, off = 0, args[0], 0
        else:
            z0, z1 = args[:2]
            off = kw.get('off', args[2] if len(args) > 2 else 0)
        corners = [(u0,z0), (u1,z0), (u1,z1), (u0,z1)]
        env['poly']([env['to3d'](plane,u,z,off) for u,z in corners], [uvfn(u,z) for u,z in corners], env['NORMALS'][plane])
    env['wall_grid'] = wall
    noop = lambda *a, **kw: None
    for name in ('do_opening', 'opening', 'shutters', 'sill_box', 'courses', 'string_courses'):
        if name in env:
            env[name] = noop
    if level == 'LOD1':
        def shutter_flats(h, mode):
            if mode == 'none': return
            x0,x1,z0,z1=h['x0'],h['x1'],h['z0'],h['z1']
            half=(x1-x0)/2
            leaves=[(x0-half,x0-.01),(x1+.01,x1+half)] if mode=='open' else ([(x0-.03,(x0+x1)/2-.01),((x0+x1)/2+.01,x1+.03)] if mode=='closed' else [(x0-half,x0-.01),((x0+x1)/2+.01,x1+.03)])
            for a,b in leaves:
                env['quad_tex']([(a,-.055,z0),(b,-.055,z0),(b,-.055,z1),(a,-.055,z1)],'shutter',(0,-1,0))
        def opening_flat(plane,h,depth,glass,*args,**kwargs):
            off=kwargs.get('base_off',0.0)
            x0,x1,z0,z1=h['x0'],h['x1'],h['z0'],h['z1']
            pts=[env['to3d'](plane,x,z,off+.006) for x,z in [(x0,z0),(x1,z0),(x1,z1),(x0,z1)]]
            env['quad_tex'](pts,glass,env['NORMALS'][plane])
        env['opening']=opening_flat
        env['shutters']=shutter_flats
        if not old:
            def opening_shutters(plane,h,off=0):
                glass={'shop':'glass_shop','door':'door','gate':'kepenk','dock':'kepenk','wide':'glass_wide'}.get(h['kind'],'glass_win')
                opening_flat(plane,h,0,glass,base_off=off)
                if plane=='front' and h['kind']=='win' and off==0:
                    shutter_flats(h,h.get('shut','none'))
            env['do_opening']=opening_shutters
    if not old:
        original_cyl = env['cyl']
        def cylinder(cx,cy,z0,z1,r,n,name,topname=None):
            original_cyl(cx,cy,z0,z1,r,min(n,6),name,topname)
        env['cyl'] = cylinder
    if level == 'LOD1':
        if old:
            # Source facade's holes already baked in atlas; keep projecting cumba,
            # balcony, roof, dormer and major chimney/solar silhouettes.
            env['facade'](); env['sides'](); env['cornice'](); env['awnings']()
            env['balcony'](); env['cumba'](); env['roof'](); env['chimneys'](); env['solar'](); env['dormer']()
        else:
            env['FAM'][family]()
        return
    # Proxy uses explicit large masses, retaining family-specific roofs and landmark.
    # Floor/window rhythm comes from the same atlas; ornament/props disappear.
    if old:
        env['facade'] = noop
        l = env['L']
        for p,u0,u1,uv in [('front',-l.W/2,l.W/2,env['frontuv']),('back',-l.W/2,l.W/2,lambda u,z:env['uv_of']('side',(u+l.W/2)/l.W*0.9+0.05,1-z/l.H)),('right',0,l.D,env['side_r_uv']),('left',0,l.D,env['side_l_uv'])]:
            wall(p, [], uv, u0,u1,l.H)
        env['box'] = noop  # suppress hip ridge caps
        env['roof']()
    else:
        s = env['SPEC']; w,d,h = s['W'],s['D'],s['H']
        for p,u0,u1,uv in [('front',-w/2,w/2,env['frontuv']),('back',-w/2,w/2,lambda u,z:env['uv_of']('side',(u+w/2)/w*0.9+0.05,1-z/h)),('right',0,d,env['side_r_uv']),('left',0,d,env['side_l_uv'])]:
            wall(p,[],uv,u0,u1,0,h)
        # no ridge-cap geometry; hip roof keeps original eaves and ridge position
        env['box'] = noop
        if family in ('bazaar','house','civic') or (family == 'res_mid' and env['VAR'] == 'c'):
            pitch = {'bazaar':22,'house':28,'civic':18,'res_mid':20}[family]
            env['hip_roof'](s['roof'].get('over',0.6),pitch)
        elif family in ('res_mid','res_late'):
            z=h+s['roof']['parapet']
            original_box(-w/2,w/2,0,d,h,z,env['fcs']('parapet'))
            original_box(-w/2+1.2,-w/2+4.2,d-5.2,d-2.2,h+.03,h+2.73,env['fcs']('wall'))
        elif family == 'industrial':
            # Preserve original gable vs barrel variant, apron and chimney.
            import math
            hw=w/2
            if env['VAR']=='b':
                profile=[(-hw-.2+(w+.4)*(1-math.cos(math.pi*i/6))/2,h+2.6*math.sin(math.pi*i/6)+.12) for i in range(7)]
            else:
                profile=[(-hw-.5,h+.14),(0,h+.14+(hw+.5)*math.tan(math.radians(14))),(hw+.5,h+.14)]
            for (x0,z0),(x1,z1) in zip(profile,profile[1:]):
                env['flatpoly']([(x0,-.3,z0),(x1,-.3,z1),(x1,d+.3,z1),(x0,d+.3,z0)],'roofm',(0,0,1))
            for y,normal in [(0,(0,-1,0)),(d,(0,1,0))]:
                env['flatpoly']([(x,y,z) for x,z in profile],'sheet',normal)
            original_box(5.6,6.8,20,21.2,0,15.35,env['fcs']('brick'))
            env['flatpoly']([(-hw-3,-9,.02),(hw+3,-9,.02),(hw+3,0,.02),(-hw-3,0,.02)],'concrete',(0,0,1))
        if family=='house':
            env['flatpoly']([(-5,-3.8,.02),(5,-3.8,.02),(5,0,.02),(-5,0,.02)],'gravel',(0,0,1))
            for a,b in [(-5,-.8),(.8,5)]:
                original_box(a,b,-3.955,-3.645,0,1.4,env['fcs']('wall'))
            for x in (-5,5):
                original_box(x-.125,x+.125,-3.8,0,0,1.3,env['fcs']('wall'))
        if family=='industrial':
            for opening in s['holes']:
                if opening['kind'] not in ('gate','dock','door'): continue
                glass='door' if opening['kind']=='door' else 'kepenk'
                a,b,z0,z1=[opening[k] for k in ('x0','x1','z0','z1')]
                env['quad_tex']([(a,-.006,z0),(b,-.006,z0),(b,-.006,z1),(a,-.006,z1)],glass,(0,-1,0))
            for y in (-8.2,-5.5):
                original_box(w/2-6.4,w/2-.4,y,y+2.3,.02,2.62,env['fcs']('cont_a'))
            if env['VAR']=='c':
                original_box(w/2-6.4,w/2-.4,-8.2,-5.9,2.62,5.22,env['fcs']('cont_b'))
        if family=='civic':
            # Source tower's four stage profile and pyramid cap, not a generic box.
            cy=5.0
            z=h-.2
            for sx,sy,hh in [(4.5,4.5,4.4),(4.0,4.0,3.0),(4.2,4.2,2.9)]:
                original_box(-sx/2,sx/2,cy-sy/2,cy+sy/2,z,z+hh,env['fcs']('wall'))
                z+=hh
            for a,b,n in [((-2.3,cy-2.3),(2.3,cy-2.3),(0,-1,1)),((2.3,cy-2.3),(2.3,cy+2.3),(1,0,1)),((2.3,cy+2.3),(-2.3,cy+2.3),(0,1,1)),((-2.3,cy+2.3),(-2.3,cy-2.3),(-1,0,1))]:
                env['flatpoly']([(a[0],a[1],z),(b[0],b[1],z),(0,cy,z+1.6)],'tile',n)
            clock_z=z-1.45
            for plane in ('front','back','right','left'):
                if plane=='front': pts=[(-.9,cy-2.13,clock_z-.9),(.9,cy-2.13,clock_z-.9),(.9,cy-2.13,clock_z+.9),(-.9,cy-2.13,clock_z+.9)]
                elif plane=='back': pts=[(.9,cy+2.13,clock_z-.9),(-.9,cy+2.13,clock_z-.9),(-.9,cy+2.13,clock_z+.9),(.9,cy+2.13,clock_z+.9)]
                elif plane=='right': pts=[(2.13,cy-.9,clock_z-.9),(2.13,cy+.9,clock_z-.9),(2.13,cy+.9,clock_z+.9),(2.13,cy-.9,clock_z+.9)]
                else: pts=[(-2.13,cy+.9,clock_z-.9),(-2.13,cy-.9,clock_z-.9),(-2.13,cy-.9,clock_z+.9),(-2.13,cy+.9,clock_z+.9)]
                env['quad_tex'](pts,'clock',env['NORMALS'][plane])


def export(env, atlas, family, variant, level):
    name='hero_%s_%s_%s' % (family,variant,level.lower())
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(env['V'], [], env['F']); mesh.update()
    uv=mesh.uv_layers.new(name='UVMap')
    for p in mesh.polygons:
        p.use_smooth=False
        for li in p.loop_indices: uv.data[li].uv=env['UV'][mesh.loops[li].vertex_index]
    ob=bpy.data.objects.new(name,mesh); bpy.context.scene.collection.objects.link(ob)
    mat=bpy.data.materials.new('mat_hero_atlas'); mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    image=bpy.data.images.load(str(atlas),check_existing=True)
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=image
    mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value=1
    bsdf.inputs['Specular IOR Level'].default_value=0
    mesh.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob
    out=ROOT/'assets/hero/lod'/('%s.glb'%name)
    bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
    if level=='LOD1':
        # Godot's existing LOD0 import uses this tracked, byte-identical extract.
        # Share the same resource, not a second copy of the authoring PNG.
        shared=ROOT/('assets/hero/hero_%s_hero_atlas_%s.png'%(variant,variant) if family=='old_core' else 'assets/hero/fam/hero_%s_%s_%s_%s.png'%(family,variant,family,variant))
        if shared.read_bytes()!=atlas.read_bytes(): raise ValueError('LOD0 imported atlas differs from authoring atlas')
        atlas=shared
    # Share external atlases; remove orphaned embedded PNG data from the GLB.
    data=out.read_bytes(); n=struct.unpack_from('<I',data,12)[0]
    obj=json.loads(data[20:20+n]);
    image_views={im.get('bufferView') for im in obj.get('images',[]) if 'bufferView' in im}
    for image_spec in obj.get('images',[]):
        image_spec.pop('bufferView',None); image_spec.pop('mimeType',None)
        image_spec['uri']=os.path.relpath(atlas,out.parent)
    remap={i:sum(j not in image_views for j in range(i)) for i in range(len(obj['bufferViews'])) if i not in image_views}
    obj['bufferViews']=[v for i,v in enumerate(obj['bufferViews']) if i not in image_views]
    for accessor in obj['accessors']:
        if 'bufferView' in accessor: accessor['bufferView']=remap[accessor['bufferView']]
    used=max(v.get('byteOffset',0)+v['byteLength'] for v in obj['bufferViews'])
    binary=data[28+n:28+n+used]
    obj['buffers'][0]['byteLength']=used
    binary+=b'\0'*((-len(binary))%4)
    tail=struct.pack('<II',len(binary),0x004e4942)+binary
    js=json.dumps(obj,separators=(',',':')).encode(); js+=b' '*((-len(js))%4)
    out.write_bytes(struct.pack('<III',0x46546c67,2,20+len(js)+len(tail))+struct.pack('<II',len(js),0x4e4f534a)+js+tail)
    tris=sum(len(f)-2 for f in env['F'])
    print('LOD_RESULT',family,variant,level,tris,flush=True)
    if tris > (800 if level=='LOD1' else 80): raise ValueError('%s exceeds triangle budget: %s'%(name,tris))



def bake_proxy_atlas(family,variant):
    """Render source albedo, no lights/shadows; retain actual projected colour coverage."""
    env,source_atlas=source_module(family,variant)
    if family=='old_core':
        for key in ('facade','string_courses','cornice','awnings','balcony','cumba','sides','roof','chimneys','solar','dormer'): env[key]()
        width,depth,height=env['L'].W,env['L'].D,env['L'].H
    else:
        env['FAM'][family]()
        width,depth,height=env['W'],env['D'],env['H']
    mesh=bpy.data.meshes.new('source_albedo')
    mesh.from_pydata(env['V'],[],env['F']);mesh.update()
    uv=mesh.uv_layers.new(name='UVMap')
    for face in mesh.polygons:
        for li in face.loop_indices: uv.data[li].uv=env['UV'][mesh.loops[li].vertex_index]
    ob=bpy.data.objects.new('source_albedo',mesh);bpy.context.scene.collection.objects.link(ob)
    material=bpy.data.materials.new('unlit_source_albedo');material.use_nodes=True
    nodes=material.node_tree.nodes;nodes.clear()
    output=nodes.new('ShaderNodeOutputMaterial');emission=nodes.new('ShaderNodeEmission');tex=nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(source_atlas),check_existing=True)
    material.node_tree.links.new(tex.outputs['Color'],emission.inputs['Color'])
    material.node_tree.links.new(emission.outputs['Emission'],output.inputs['Surface'])
    mesh.materials.append(material)
    scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
    scene.render.film_transparent=True
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
    camera=bpy.data.objects.new('albedo_camera',bpy.data.cameras.new('albedo_camera'))
    scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO';camera.data.lens=50
    folder=ROOT/'artifacts/verify/t056/proxy-bake';folder.mkdir(parents=True,exist_ok=True)
    job={'source_atlas':str(source_atlas),'out':str(ROOT/'assets/hero/lod'/('proxy_%s_%s.png'%(family,variant))),'faces':[]}
    for face,span_x,target,position in [('front',width,(0,0,height/2),(0,-100,height/2))]:
        camera.location=position;direction=Vector(target)-camera.location
        camera.rotation_euler=direction.to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=max(span_x,height)
        out=folder/('%s_%s_%s.png'%(family,variant,face));scene.render.filepath=str(out)
        bpy.ops.render.render(write_still=True)
        job['faces'].append({'render':str(out),'rect':env['RECTS'][face],'physical_size':[span_x,height]})
    jobpath=folder/('%s_%s.json'%(family,variant));jobpath.write_text(json.dumps(job))
    subprocess.run(['uv','run','--with','pillow==11.3.0','python',str(HERE/'proxy_atlas_pack.py'),str(jobpath)],check=True)
    return Path(job['out'])


def main():
    families=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    reuse_bakes='--reuse-proxy-atlases' in families
    families=[f for f in families if not f.startswith('--')]
    families=families or FAMILIES
    for family in families:
        if family not in FAMILIES: raise ValueError(family)
        for variant in 'abc':
            for level in ('LOD1','PROXY'):
                for ob in list(bpy.data.objects): bpy.data.objects.remove(ob,do_unlink=True)
                derived=None
                if level=='PROXY':
                    bpy.data.orphans_purge(do_recursive=True)
                    derived=ROOT/'assets/hero/lod'/('proxy_%s_%s.png'%(family,variant)) if reuse_bakes else bake_proxy_atlas(family,variant)
                    if not derived.is_file(): raise ValueError('missing cached proxy atlas')
                    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob,do_unlink=True)
                bpy.data.orphans_purge(do_recursive=True)
                env,atlas=source_module(family,variant)
                if derived: atlas=derived
                simplify(env,family,level)
                export(env,atlas,family,variant,level)

main()
