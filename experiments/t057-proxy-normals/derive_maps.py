"""Derive affine projection UV fields from actual exported POSITION/TEXCOORD_0."""
import json,struct,itertools,math,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=Path(__file__).resolve().parent
path=ROOT/'assets/hero/vegetation/normal_experiment/plane_proxy.glb';raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n]);binary=raw[28+n:]
def accessor(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];count={'VEC2':2,'VEC3':3}[a['type']];offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',count*4)
 assert a['componentType']==5126
 return [struct.unpack_from('<'+'f'*count,binary,offset+j*stride) for j in range(a['count'])]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def evaluate(row,p):return dot(row[:3],p)+row[3]
vertices=[]
for mesh in g['meshes']:
 for prim in mesh['primitives']:vertices.extend(zip(accessor(prim['attributes']['POSITION']),accessor(prim['attributes']['TEXCOORD_0'])))
manifest=json.loads((ROOT/'assets/hero/vegetation/proxy_bakes.json').read_text());views=manifest['assets']['plane']['views'];maps=[]
for view in ['front','side','top']:
 x,y,w,h=views[view]['region'];pairs=[(p,uv) for p,uv in vertices if x/1024<=uv[0]<=(x+w)/1024 and y/1024<=uv[1]<=(y+h)/1024];assert len(pairs)==4
 p0,p1,p2=[p for p,uv in pairs[:3]];e1=sub(p1,p0);e2=sub(p2,p0);g11=dot(e1,e1);g12=dot(e1,e2);g22=dot(e2,e2);det=g11*g22-g12*g12;assert det>1e-8
 rows=[]
 for component in [0,1]:
  d1=pairs[1][1][component]-pairs[0][1][component];d2=pairs[2][1][component]-pairs[0][1][component];a=(d1*g22-d2*g12)/det;b=(d2*g11-d1*g12)/det;grad=[a*x+b*y for x,y in zip(e1,e2)];rows.append(grad+[pairs[0][1][component]-dot(grad,p0)])
 axis=cross(e1,e2);length=math.sqrt(dot(axis,axis));axis=[x/length for x in axis]
 error=max(abs(evaluate(rows[c],p)-uv[c]) for p,uv in pairs for c in [0,1]);assert error<1e-6
 # Fourth corner and pair midpoints verify the affine extension, including mirrored UV signs.
 for (p,uv),(q,vq) in itertools.combinations(pairs,2):
  mid=[(a+b)/2 for a,b in zip(p,q)];target=[(a+b)/2 for a,b in zip(uv,vq)];assert max(abs(evaluate(rows[c],mid)-target[c]) for c in [0,1])<1e-6
 maps.append({'view':view,'u':rows[0],'v':rows[1],'axis':axis,'uv_bounds':[min(uv[0] for p,uv in pairs),min(uv[1] for p,uv in pairs),max(uv[0] for p,uv in pairs),max(uv[1] for p,uv in pairs)],'vertices':[{'position':p,'uv':uv} for p,uv in pairs],'max_roundtrip_error':error})
result={'source_proxy':str(path.relative_to(ROOT)),'sha256':hashlib.sha256(raw).hexdigest(),'maps':maps,'normal_data_offset_px':[0,min(record['region'][1] for record in views.values())],'normal_data_size_px':[1024,384]}
(OUT/'projection_maps.json').write_text(json.dumps(result,indent=2)+'\n');print('AFFINE_UV_OK 12vertices +18midpoints; maxerror',max(m['max_roundtrip_error'] for m in maps))
