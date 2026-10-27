"""Experimental single-plane object normal capture; no albedo/LOD0 writes."""
import bpy,json,hashlib,struct,sys,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];OUT=Path(__file__).resolve().parent
SOURCE=ROOT/'assets/hero/vegetation/veg_hero_plane_a_lod0.glb'
manifest=json.loads((ROOT/'assets/hero/vegetation/proxy_bakes.json').read_text())['assets']['plane']
scene=bpy.context.scene
for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE));bpy.context.view_layer.update()
meshes=[o for o in bpy.data.objects if o.type=='MESH']
# glTF Y-up -> Blender Z-up (x,-z,y), inverse (x,z,-y).
def to_b(v):return Vector((v[0],-v[2],v[1]))
def to_g(v):return (v[0],v[2],-v[1])
for axis in [(1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)]:assert max(abs(a-b) for a,b in zip(axis,to_g(to_b(axis))))<1e-7
# Verify actual imported corner normals against the raw exported glTF NORMALs.
data=SOURCE.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n]);binary=data[28+n:]
def read_acc(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',12)
 return [struct.unpack_from('<3f',binary,start+j*stride) for j in range(a['count'])]
raw=[]
for mesh in g['meshes']:
 for prim in mesh['primitives']:raw.extend(zip(read_acc(prim['attributes']['POSITION']),read_acc(prim['attributes']['NORMAL'])))
lookup={tuple(round(x,5) for x in to_b(p)):[] for p,n in raw}
for p,n in raw:lookup[tuple(round(x,5) for x in to_b(p))].append(to_b(n))
samples=0;max_error=0;source_normals={}
for ob in meshes:
 source_normals[ob.name]=[]
 assert all(abs(ob.matrix_world[i][j]-(1 if i==j else 0))<1e-5 for i in range(4) for j in range(4))
 for loop in ob.data.loops:
  co=ob.data.vertices[loop.vertex_index].co;normal=ob.data.corner_normals[loop.index].vector
  matched=min(lookup[tuple(round(x,5) for x in co)],key=lambda v:(normal-v).length)
  error=(normal-matched).length;source_normals[ob.name].append(matched.copy())
  max_error=max(max_error,error);assert error<1e-3,(co,normal,error);samples+=1
scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=True
scene.view_settings.view_transform='Raw';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
mat=bpy.data.materials.new('raw_source_object_normal');mat.use_nodes=True;mat.use_backface_culling=False
nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
output=nodes.new('ShaderNodeOutputMaterial');mix=nodes.new('ShaderNodeMixShader');transparent=nodes.new('ShaderNodeBsdfTransparent');emission=nodes.new('ShaderNodeEmission');attribute=nodes.new('ShaderNodeVertexColor');attribute.layer_name='source_normal'
tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ROOT/'assets/hero/vegetation/vegetation_atlas.png'));threshold=nodes.new('ShaderNodeMath');threshold.operation='GREATER_THAN';threshold.inputs[1].default_value=.45
links.new(attribute.outputs['Color'],emission.inputs['Color']);links.new(tex.outputs['Alpha'],threshold.inputs[0]);links.new(threshold.outputs[0],mix.inputs[0]);links.new(transparent.outputs[0],mix.inputs[1]);links.new(emission.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],output.inputs['Surface'])
for ob in meshes:
 ob.data.materials.clear();ob.data.materials.append(mat)
 for p in ob.data.polygons:p.material_index=0
 ob.data.color_attributes.new(name='source_normal',type='FLOAT_COLOR',domain='CORNER')
points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)];center=Vector([(a+b)/2 for a,b in zip(lo,hi)])
camera=bpy.data.objects.new('normal_camera',bpy.data.cameras.new('normal_camera'));scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
records=[]
for view,offset in [('front',(0,-100,0)),('side',(100,0,0)),('top',(0,0,100))]:
 toward_camera=Vector(offset).normalized();flipped=0
 for ob in meshes:
  for loop in ob.data.loops:
   normal=source_normals[ob.name][loop.index].copy()
   # Effective source double-sided shading: reverse back-facing surface normal once.
   if normal.dot(toward_camera)<0:normal=-normal;flipped+=1
   encoded=tuple(x*.5+.5 for x in to_g(normal))+(1,)
   ob.data.color_attributes['source_normal'].data[loop.index].color=encoded
 camera.location=center+Vector(offset);camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=max((hi[0]-lo[0],hi[2]-lo[2]) if view=='front' else (hi[1]-lo[1],hi[2]-lo[2]) if view=='side' else (hi[0]-lo[0],hi[1]-lo[1]))
 path=OUT/('raw_'+view+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
 records.append({'view':view,'path':str(path.relative_to(ROOT)),'backface_corner_sign_flips':flipped,'region':manifest['views'][view]['region'],'physical_size':manifest['views'][view]['physical_size']})
# Sentinel emission render proves PNG output has no gamma transform.
for ob in meshes:ob.hide_render=True
bpy.ops.mesh.primitive_plane_add(size=2,location=(0,0,0));plane=bpy.context.object
sm=bpy.data.materials.new('sentinel');sm.use_nodes=True;nt=sm.node_tree;nt.nodes.clear();so=nt.nodes.new('ShaderNodeOutputMaterial');se=nt.nodes.new('ShaderNodeEmission');se.inputs['Color'].default_value=(.25,.5,.75,1);nt.links.new(se.outputs[0],so.inputs[0]);plane.data.materials.append(sm)
camera.location=(0,0,5);camera.rotation_euler=(0,0,0);camera.data.ortho_scale=2;scene.render.filepath=str(OUT/'raw_sentinel.png');bpy.ops.render.render(write_still=True)
proof={'experimental':True,'source':str(SOURCE.relative_to(ROOT)),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'method':'raw effective object-space glTF normals; front/side/top orthographic; original source alpha>.45','axis_roundtrip_sentinels':6,'real_corner_samples':samples,'max_imported_normal_error':max_error,'views':records,'sentinel_linear_rgb':[.25,.5,.75]}
(OUT/'normal_capture.json').write_text(json.dumps(proof,indent=2)+'\n')
print('NORMAL_AXIS_OK',samples,max_error)
