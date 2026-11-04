"""One fixed source-alpha shell experiment, no representation tuning."""
import bpy,bmesh,numpy as np,json,struct,hashlib,math,sys
from pathlib import Path
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/hero/vegetation/shell_experiment';EVID=Path(__file__).resolve().parent
source=ROOT/'assets/hero/vegetation/veg_hero_plane_a_lod0.glb';atlas=ROOT/'assets/hero/vegetation/vegetation_atlas.png'
raw=source.read_bytes();n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n]);binary=raw[28+n:]
def acc(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];types={5126:('f',4),5123:('H',2),5125:('I',4),5121:('B',1)};t,size=types[a['componentType']];count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',count*size)
 return np.array([struct.unpack_from('<'+t*count,binary,offset+j*stride) for j in range(a['count'])])
for node in g['nodes']:
 assert not any(k in node for k in ['matrix','translation','rotation','scale']), 'source transform must be explicit'
rgba=np.frombuffer((ROOT/'artifacts/verify/t057/shell/source_rgba.bin').read_bytes(),dtype=np.uint8).reshape(1024,1024,4)
linear=rgba[:,:,:3].astype(np.float64)/255;linear=np.where(linear<=.04045,linear/12.92,((linear+.055)/1.055)**2.4)
layout=json.loads((ROOT/'assets/hero/vegetation/atlas_layout.json').read_text());regions=layout['regions']
triangles=[]
for mesh in g['meshes']:
 for prim in mesh['primitives']:
  p=acc(prim['attributes']['POSITION']);uv=acc(prim['attributes']['TEXCOORD_0']);ids=acc(prim['indices']).astype(int).reshape(-1,3)
  for indices in ids:triangles.append((p[indices],uv[indices]))
def in_region(uv,key):
 x,y,w,h=regions[key];p=uv*1024;return bool(np.all((p[:,0]>=x)&(p[:,0]<=x+w)&(p[:,1]>=y)&(p[:,1]<=y+h)))
points=[];colors=[];sample_ids=[];wood=[];sample_total=0;foliage_tri=0;uv_cache={}
for ti,(p,uv) in enumerate(triangles):
 if in_region(uv,'bark'):wood.append((ti,p));continue
 assert in_region(uv,'plane'),('unknown source region',ti,uv)
 foliage_tri+=1;key=tuple(uv.flatten())
 if key not in uv_cache:
  tex=uv*1024;lo=np.ceil(tex.min(axis=0)-.5).astype(int);hi=np.floor(tex.max(axis=0)-.5).astype(int)
  xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1));xy=np.stack([xx.ravel(),yy.ravel()],axis=1);v=(xy+.5)/1024
  matrix=np.column_stack((uv[1]-uv[0],uv[2]-uv[0]));ab=(v-uv[0])@np.linalg.inv(matrix).T;weights=np.column_stack((1-ab.sum(axis=1),ab));valid=np.all(weights>=-1e-10,axis=1)&(rgba[xy[:,1],xy[:,0],3]>=.45*255);xy=xy[valid];weights=weights[valid]
  # Shared-edge source triangles may sample the same texel; ordering remains source triangle,row,column.
  uv_cache[key]=(weights,linear[xy[:,1],xy[:,0]],xy[:,1]*1024+xy[:,0])
 weights,rgb,texids=uv_cache[key];positions=weights@p;points.append(positions);colors.append(rgb);sample_ids.append(np.column_stack((np.full(len(texids),ti),texids)));sample_total+=len(texids)
P=np.concatenate(points);C=np.concatenate(colors);IDS=np.concatenate(sample_ids);del points,colors,sample_ids
D=np.array([(s if axis==i else 0) for i in range(3) for s in [-1,1] for axis in range(3)]).reshape(6,3)
D=np.vstack((D,np.array([(x,y,z) for x in [-1,1] for y in [-1,1] for z in [-1,1]])))
support=[];support_proof=[]
for direction in D:
 products=P@direction;index=int(np.argmax(products)) # first source index wins exact ties
 if index not in support:support.append(index)
 support_proof.append({'direction':direction.tolist(),'sample_index':index,'source_triangle_texel':IDS[index].tolist(),'position':P[index].tolist()})
assert 4<=len(support)<=14
bm=bmesh.new();bv=[bm.verts.new((float(P[i,0]),float(-P[i,2]),float(P[i,1]))) for i in support];bm.verts.ensure_lookup_table();bmesh.ops.convex_hull(bm,input=bv,use_existing_faces=False);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='FIXED',ngon_method='EAR_CLIP');bm.normal_update()
hull=[]
for f in bm.faces:
 coords=[(v.co.x,v.co.z,-v.co.y) for v in f.verts];indices=[min(support,key=lambda i:np.linalg.norm(P[i]-q)) for q in coords];hull.append(indices)
hull.sort(key=lambda ids:tuple(sorted(ids)));assert len(hull)==2*len(support)-4 and len(hull)<=24
center=P[support].mean(axis=0);face_colors=[];faces=[];verts=[];provenance=[]
def add_face(coords,color,kind,proof=None):
 coords=np.asarray(coords);normal=np.cross(coords[1]-coords[0],coords[2]-coords[0]);assert np.linalg.norm(normal)>1e-8
 start=len(verts);verts.extend(coords.tolist());faces.append((start,start+1,start+2));face_colors.append(color);provenance.append({'kind':kind,'points':coords.tolist(),'linear_rgb':list(color),'source':proof})
for ids in hull:
 q=P[ids];normal=np.cross(q[1]-q[0],q[2]-q[0])
 if np.dot(normal,q.mean(axis=0)-center)<0:ids=[ids[0],ids[2],ids[1]];q=P[ids]
 dist=np.sum((P-q.mean(axis=0))**2,axis=1);near=np.argpartition(dist,15)[:16];limit=dist[near].max();near=np.flatnonzero(dist<=limit);near=near[np.lexsort((near,dist[near]))][:16];rgb=C[near].mean(axis=0)
 add_face(q,rgb,'crown',{'nearest16':IDS[near].tolist(),'sample_indices':near.tolist()})
crown_tri=len(faces)
# Weld actual bark positions, extract each uncapped source tube segment's two boundary rings.
vertex_ids={};wood_vertices=[];wood_faces=[]
for ti,coords in wood:
 ids=[]
 for q in coords:
  key=tuple(np.round(q,5))
  if key not in vertex_ids:vertex_ids[key]=len(wood_vertices);wood_vertices.append(q)
  ids.append(vertex_ids[key])
 wood_faces.append((ti,ids))
edge_faces=defaultdict(list)
for fi,(ti,ids) in enumerate(wood_faces):
 for a,b in zip(ids,ids[1:]+ids[:1]):edge_faces[tuple(sorted((a,b)))].append(fi)
adj=defaultdict(set)
for fs in edge_faces.values():
 for a in fs:
  for b in fs:adj[a].add(b)
remaining=set(range(len(wood_faces)));segments=[]
while remaining:
 stack=[min(remaining)];component=set()
 while stack:
  i=stack.pop()
  if i in component:continue
  component.add(i);stack.extend(adj[i]-component)
 remaining-=component;boundary=[]
 for edge,fs in edge_faces.items():
  if len([i for i in fs if i in component])==1 and any(i in component for i in fs):boundary.append(edge)
 links=defaultdict(set)
 for a,b in boundary:links[a].add(b);links[b].add(a)
 rings=[];todo=set(links)
 while todo:
  ring=set();stack=[min(todo)]
  while stack:
   i=stack.pop()
   if i in ring:continue
   ring.add(i);stack.extend(links[i]-ring)
  todo-=ring;assert all(len(links[i])==2 for i in ring);order=[min(ring)];prev=None
  while len(order)<len(ring):
   options=sorted(links[order[-1]]-({prev} if prev is not None else set()));nxt=next(i for i in options if i not in order);prev=order[-1];order.append(nxt)
  coords=np.array([wood_vertices[i] for i in order]);rings.append({'points':coords,'center':coords.mean(axis=0)})
 assert len(rings)==2
 rings.sort(key=lambda r:r['center'][1]);segments.append({'index':min(wood_faces[i][0] for i in component),'rings':rings})
segments.sort(key=lambda s:s['index']);main=[min(segments,key=lambda s:s['rings'][0]['center'][1])]
while True:
 endpoint=main[-1]['rings'][1]['center'];nexts=[s for s in segments if s not in main and np.linalg.norm(s['rings'][0]['center']-endpoint)<1e-4]
 if not nexts:break
 main.append(min(nexts,key=lambda s:s['index']))
lower=main[0]['rings'][0];upper=main[-1]['rings'][1];assert len(main)>=2
bark_region=regions['bark'];x,y,w,h=bark_region;bark_rgb=linear[y:y+h,x:x+w][rgba[y:y+h,x:x+w,3]>=.45*255].mean(axis=0)
a=lower['points'][np.floor(np.arange(3)*len(lower['points'])/3).astype(int)];b=upper['points'][np.floor(np.arange(3)*len(upper['points'])/3).astype(int)];prism=np.vstack((a,b));stem_faces=[(0,2,1),(3,4,5),(0,1,4),(0,4,3),(1,2,5),(1,5,4),(2,0,3),(2,3,5)]
def closed_component(coords,indices,kind,proof):
 midpoint=np.mean(coords,axis=0)
 for ids in indices:
  q=coords[list(ids)]
  if np.dot(np.cross(q[1]-q[0],q[2]-q[0]),q.mean(axis=0)-midpoint)<0:q=q[[0,2,1]]
  add_face(q,bark_rgb,kind,proof)
closed_component(prism,stem_faces,'stem',{'source_segments':[s['index'] for s in main],'lower_center':lower['center'].tolist(),'upper_center':upper['center'].tolist()})
# First source fork chain; capped tetrahedron joins the source junction to a crown interior endpoint.
main_ids={s['index'] for s in main};branch=min((s for s in segments if s['index'] not in main_ids),key=lambda s:s['index']);chain=[branch]
while True:
 endpoint=chain[-1]['rings'][1]['center'];nexts=[s for s in segments if s['index'] not in main_ids and all(s['index']!=v['index'] for v in chain) and np.linalg.norm(s['rings'][0]['center']-endpoint)<1e-4]
 if not nexts:break
 chain.append(min(nexts,key=lambda s:s['index']))
ring=chain[0]['rings'][0]['points'];base=ring[np.floor(np.arange(3)*len(ring)/3).astype(int)];tip=chain[-1]['rings'][1]['center'];tetra=np.vstack((base,tip))
closed_component(tetra,[(0,2,1),(0,1,3),(1,2,3),(2,0,3)],'fork',{'source_segments':[s['index'] for s in chain],'source_tip':tip.tolist()})
assert len(faces)<=36
# Export flat vertex-color geometry; glTF positions return to source Y-up unchanged.
for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
mesh=bpy.data.meshes.new('source_shell');mesh.from_pydata([(p[0],-p[2],p[1]) for p in verts],[],faces);mesh.update();color=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER');mesh.color_attributes.active_color=color
for face,rgb in zip(mesh.polygons,face_colors):
 face.use_smooth=False
 for li in face.loop_indices:color.data[li].color=(*rgb,1)
mat=bpy.data.materials.new('source_shell_opaque');mat.use_nodes=True;bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=1;bsdf.inputs['Metallic'].default_value=0;bsdf.inputs['Specular IOR Level'].default_value=0
node=mat.node_tree.nodes.new('ShaderNodeVertexColor');node.layer_name='Color';mat.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color']);mesh.materials.append(mat)
ob=bpy.data.objects.new('plane_source_shell',mesh);bpy.context.scene.collection.objects.link(ob);ob.select_set(True);bpy.context.view_layer.objects.active=ob
path=OUT/'plane_shell.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
proof={'experimental':True,'source_glb':str(source.relative_to(ROOT)),'source_sha256':hashlib.sha256(raw).hexdigest(),'atlas_sha256':hashlib.sha256(atlas.read_bytes()).hexdigest(),'axis':'source glTF Y-up -> Blender(x,-z,y) -> export glTF Y-up','foliage_source_triangles':foliage_tri,'valid_source_texel_center_samples':len(P),'sample_bounds':{'min':P.min(axis=0).tolist(),'max':P.max(axis=0).tolist()},'supports':support_proof,'unique_supports':len(support),'crown_triangles':crown_tri,'stem_triangles':8,'fork_triangles':4,'total_triangles':len(faces),'origin':[0,0,0],'bbox':{'min':np.min(verts,axis=0).tolist(),'max':np.max(verts,axis=0).tolist()},'faces':provenance,'main_source_ring_centers':[main[0]['rings'][0]['center'].tolist()]+[s['rings'][1]['center'].tolist() for s in main],'bark_linear_rgb':bark_rgb.tolist(),'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(EVID/'provenance.json').write_text(json.dumps(proof,indent=2)+'\n');print('SHELL_EXPORTED',len(P),'samples',len(support),'supports',crown_tri,'crowntri',len(faces),'total')
