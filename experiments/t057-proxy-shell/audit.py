"""Audit actual shell GLB topology/normals/linear vertex colors and source trace."""
import json,struct,math,sys
from pathlib import Path
from collections import defaultdict,Counter
ROOT=Path(__file__).resolve().parents[2];EVID=Path(__file__).resolve().parent
path=ROOT/'assets/hero/vegetation/shell_experiment/plane_shell.glb';data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n]);binary=data[28+n:]
def acc(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];t,size={5126:('f',4),5123:('H',2),5125:('I',4),5121:('B',1)}[a['componentType']];c={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',c*size);values=[list(struct.unpack_from('<'+t*c,binary,offset+j*stride)) for j in range(a['count'])]
 if a.get('normalized'):values=[[x/(255 if a['componentType']==5121 else 65535) for x in row] for row in values]
 return values
proof=json.loads((EVID/'provenance.json').read_text());assert not g.get('images') and not g.get('textures'),'proxy must have zero texture samplers'
for node in g['nodes']:assert not any(k in node for k in ['matrix','translation','rotation','scale'])
mat=g['materials'][0];assert len(g['materials'])==1 and mat.get('alphaMode','OPAQUE')=='OPAQUE';pbr=mat['pbrMetallicRoughness'];assert pbr.get('roughnessFactor',1)==1 and pbr.get('metallicFactor',1)==0
faces=[];normals=[];colors=[]
for mesh in g['meshes']:
 for prim in mesh['primitives']:
  p=acc(prim['attributes']['POSITION']);normal=acc(prim['attributes']['NORMAL']);color=acc(prim['attributes']['COLOR_0']);ids=[x[0] for x in acc(prim['indices'])]
  for i in range(0,len(ids),3):
   indices=ids[i:i+3];faces.append([p[j] for j in indices]);normals.append([normal[j] for j in indices]);colors.append([color[j] for j in indices])
if '--negative=open' in sys.argv:faces.pop(0);normals.pop(0);colors.pop(0)
if '--negative=normal' in sys.argv:normals[0][0]=[0,0,0]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
key=lambda p:tuple(round(x,4) for x in p)
edges=defaultdict(list)
for i,f in enumerate(faces):
 normal=cross(sub(f[1],f[0]),sub(f[2],f[0]));length=math.sqrt(dot(normal,normal));assert length>1e-7
 for actual in normals[i]:assert abs(math.sqrt(dot(actual,actual))-1)<1e-4,'zero/nonunit exported real normal';assert dot(normal,actual)/length>.999,'exported normal not flat geometric normal'
 for a,b in zip(f,f[1:]+f[:1]):edges[tuple(sorted((key(a),key(b))))].append(i)
assert all(len(v)==2 for v in edges.values()),'open hull/component edge incidence'
adj=defaultdict(set)
for a,b in edges.values():adj[a].add(b);adj[b].add(a)
remaining=set(range(len(faces)));components=[]
while remaining:
 stack=[min(remaining)];group=set()
 while stack:
  i=stack.pop()
  if i in group:continue
  group.add(i);stack.extend(adj[i]-group)
 remaining-=group;volume=sum(dot(faces[i][0],cross(faces[i][1],faces[i][2]))/6 for i in group);assert volume>1e-5,'inward winding';components.append({'triangles':len(group),'signed_volume':volume})
assert sorted(c['triangles'] for c in components)==[4,8,proof['crown_triangles']];assert len(faces)==proof['total_triangles']<=36
expected={tuple(sorted(key(p) for p in record['points'])):record for record in proof['faces']}
error=0
for f,cs in zip(faces,colors):
 record=expected[tuple(sorted(key(p) for p in f))]
 for c in cs:
  error=max(error,max(abs(c[i]-record['linear_rgb'][i]) for i in range(3)));assert len(c)==3 or c[3]==1
assert error<1e-5,'vertex RGB changed/gamma converted during export'
# Verify each support position comes from its declared source triangle's opaque texel center.
source=ROOT/proof['source_glb'];raw=source.read_bytes();nn=struct.unpack_from('<I',raw,12)[0];sg=json.loads(raw[20:20+nn]);sb=raw[28+nn:];oldg,oldbin=g,binary;g,binary=sg,sb
tri=[]
for mesh in g['meshes']:
 for prim in mesh['primitives']:
  positions=acc(prim['attributes']['POSITION']);uvs=acc_uv=None
  # Source UV vectors have two components; direct accessor reader for this one attribute.
  a=g['accessors'][prim['attributes']['TEXCOORD_0']];v=g['bufferViews'][a['bufferView']];off=v.get('byteOffset',0)+a.get('byteOffset',0);uvs=[struct.unpack_from('<2f',binary,off+j*v.get('byteStride',8)) for j in range(a['count'])]
  ids=[r[0] for r in acc(prim['indices'])]
  for i in range(0,len(ids),3):tri.append(([positions[j] for j in ids[i:i+3]],[uvs[j] for j in ids[i:i+3]]))
rgba=(ROOT/'artifacts/verify/t057/shell/source_rgba.bin').read_bytes()
def sample_source(ti,pixel):
 positions,uv=tri[ti];x,y=pixel%1024,pixel//1024;offset=(y*1024+x)*4;assert rgba[offset+3]>=115
 point=((x+.5)/1024,(y+.5)/1024);a=(uv[1][0]-uv[0][0],uv[1][1]-uv[0][1]);b=(uv[2][0]-uv[0][0],uv[2][1]-uv[0][1]);q=(point[0]-uv[0][0],point[1]-uv[0][1]);det=a[0]*b[1]-a[1]*b[0];u=(q[0]*b[1]-q[1]*b[0])/det;v=(a[0]*q[1]-a[1]*q[0])/det;w=[1-u-v,u,v];assert min(w)>-1e-8
 position=[sum(w[j]*positions[j][i] for j in range(3)) for i in range(3)];rgb=[z/255 for z in rgba[offset:offset+3]];rgb=[z/12.92 if z<=.04045 else ((z+.055)/1.055)**2.4 for z in rgb];return position,rgb
for s in proof['supports']:
 position,rgb=sample_source(*s['source_triangle_texel']);assert max(abs(a-b) for a,b in zip(position,s['position']))<1e-6
for f in proof['faces']:
 if f['kind']=='crown':
  rgb=[sample_source(*pair)[1] for pair in f['source']['nearest16']];mean=[sum(v[i] for v in rgb)/len(rgb) for i in range(3)];assert max(abs(a-b) for a,b in zip(mean,f['linear_rgb']))<1e-8
def inside(point,kind):
 for face in proof['faces']:
  if face['kind']!=kind:continue
  q=face['points'];normal=cross(sub(q[1],q[0]),sub(q[2],q[0]));length=math.sqrt(dot(normal,normal))
  if dot(normal,sub(point,q[0]))/length>1e-5:return False
 return True
stem_tip=proof['main_source_ring_centers'][-1];fork=next(f for f in proof['faces'] if f['kind']=='fork');fork_tip=fork['source']['source_tip'];fork_base=[sum(p[i] for p in fork['points'])/3 for i in range(3)]
connection={'stem_tip_inside_crown':inside(stem_tip,'crown'),'fork_tip_inside_crown':inside(fork_tip,'crown'),'fork_base_inside_stem':inside(fork_base,'stem')}
assert connection['fork_tip_inside_crown'] and connection['fork_base_inside_stem'],'source-derived branch does not connect stem/crown'
result={'connection':connection,'actual_triangles':len(faces),'components':components,'all_edges_two_faces':True,'outward_winding':True,'geometric_flat_normals':True,'linear_vertex_color_max_error':error,'source_supports_verified':len(proof['supports']),'source_face_nearest16_color_verified':proof['crown_triangles'],'textures':0,'materials':1,'bbox':proof['bbox']}
(EVID/'audit.json').write_text(json.dumps(result,indent=2)+'\n');print('SHELL_AUDIT_OK',json.dumps(result))
