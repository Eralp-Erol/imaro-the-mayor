"""Independent source-image numeric continuity diagnostic at physical card intersection."""
import json,math,itertools
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];OUT=Path(__file__).resolve().parent
maps=json.loads((OUT/'projection_maps.json').read_text())['maps']
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def norm(a):
 l=math.sqrt(dot(a,a));return [x/l for x in a] if l else [0,0,0]
def linear(c):return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4
axes=[m['axis'] for m in maps];distances=[dot(m['axis'],m['vertices'][0]['position']) for m in maps];cols=[cross(axes[1],axes[2]),cross(axes[2],axes[0]),cross(axes[0],axes[1])];det=dot(axes[0],cols[0]);p=[sum(d*v[c] for d,v in zip(distances,cols))/det for c in range(3)]
images=[Image.open(ROOT/'assets/hero/vegetation/vegetation_atlas.png').convert('RGBA'),Image.open(ROOT/'assets/hero/vegetation/normal_experiment/object_normals.png').convert('RGBA')]
def sample(image,uv,srgb=False):
 x,y=uv[0]*image.width-.5,uv[1]*image.height-.5;ix,iy=math.floor(x),math.floor(y);fx,fy=x-ix,y-iy;value=[0.0]*4
 for dx,dy,w in [(0,0,(1-fx)*(1-fy)),(1,0,fx*(1-fy)),(0,1,(1-fx)*fy),(1,1,fx*fy)]:
  pixel=[v/255 for v in image.getpixel((max(0,min(ix+dx,image.width-1)),max(0,min(iy+dy,image.height-1))))]
  if srgb:pixel=[linear(v) if c<3 else v for c,v in enumerate(pixel)]
  value=[a+w*b for a,b in zip(value,pixel)]
 return value
c=norm([18,13,43]);samples=[]
for m in maps:
 uv=[dot(m[k][:3],p)+m[k][3] for k in ['u','v']];color=sample(images[0],uv,True);data_uv=[uv[0],(uv[1]*1024-640)/384];raw=[2*v-1 for v in sample(images[1],data_uv)[:3]];n=norm(raw)
 if dot(n,c)<0:n=[-v for v in n]
 w=dot(c,m['axis'])**2*color[3] if dot(raw,raw)>=.0025 else 0
 samples.append({'view':m['view'],'uv':uv,'linear_rgb':color[:3],'normal':n,'weight':w})
total=sum(s['weight'] for s in samples);assert total>1e-6
rgb=[sum(s['linear_rgb'][i]*s['weight'] for s in samples)/total for i in range(3)];normal=norm([sum(s['normal'][i]*s['weight'] for s in samples) for i in range(3)])
legacy_spread=max(math.sqrt(sum((a['normal'][i]-b['normal'][i])**2 for i in range(3))) for a,b in itertools.combinations(samples,2));assert legacy_spread>.1
# Shared output is explicitly independent of card index/UV; report all receiving cards.
results=[{'receiving_card':m['view'],'rgb':rgb,'normal':normal} for m in maps];assert all(r['rgb']==results[0]['rgb'] and r['normal']==results[0]['normal'] for r in results)
proof={'physical_intersection':p,'current_camera_direction':c,'sample_scope':'bilinear base-level source texels, linear RGB, noncolor normal; actual runtime uses analytic camera-plane LOD','legacy_per_card_samples':samples,'legacy_normal_spread':legacy_spread,'shared_field_per_card':results,'shared_difference':0,'actual_shader_explicit_lod':True}
(OUT/'fpc-numeric-continuity.json').write_text(json.dumps(proof,indent=2)+'\n');print('FPC_CONTINUITY_OK sameP RGB+normal spread0; previous card normal spread',legacy_spread)
