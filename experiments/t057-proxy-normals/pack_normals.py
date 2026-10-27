from pathlib import Path
import json,hashlib,struct
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];OUT=Path(__file__).resolve().parent
RUNTIME=ROOT/'assets/hero/vegetation/normal_experiment';RUNTIME.mkdir(exist_ok=True)
proof=json.loads((OUT/'normal_capture.json').read_text());atlas=Image.new('RGBA',(1024,384),(128,128,128,255))
sentinel=Image.open(OUT/'raw_sentinel.png').convert('RGBA').getpixel((256,256));assert all(abs(a-b)<=1 for a,b in zip(sentinel[:3],(64,128,191))),sentinel
proof['raw_gamma_sentinel_rgba']=sentinel
for rec in proof['views']:
 view=rec['view'];raw=Image.open(ROOT/rec['path']).convert('RGBA');original=Image.open(ROOT/f'artifacts/verify/t057/impostor-bakes/plane_{view}.png').convert('RGBA')
 a=list(raw.getchannel('A').getdata());b=list(original.getchannel('A').getdata())
 assert all((x>=115)==(y>=115) for x,y in zip(a,b)),view+': source .45 mask differs'
 rec['raw_alpha_byte_differences']=sum(x!=y for x,y in zip(a,b))
 raw.putalpha(original.getchannel('A'))
 width,height=rec['physical_size'];span=max(width,height);size=raw.width
 box=tuple(round(v) for v in ((1-width/span)*size/2,(1-height/span)*size/2,(1+width/span)*size/2,(1+height/span)*size/2))
 # Premultiply encoded vector about neutral before filtering; transparent pixels contribute zero vector.
 pixels=[]
 for r,g,b,a in raw.getdata():pixels.append(tuple(round(128+(c-128)*a/255) for c in (r,g,b))+(255,))
 premult=Image.new('RGBA',raw.size);premult.putdata(pixels);content=premult.crop(box).resize((112,112),Image.Resampling.LANCZOS)
 tile=Image.new('RGBA',(128,128),(128,128,128,255));tile.paste(content,(8,8));x,y,w,h=rec['region'];atlas.paste(tile,(x,y-640))
 rec['source_binary_alpha45_exact']=True;rec['data_region']=[x,y-640,w,h];rec['rgb_unique']=len(set(content.getdata()));rec['rgba_sha256']=hashlib.sha256(tile.tobytes()).hexdigest()
 assert rec['rgb_unique']>100
# Independent known signed axes in an unused tile; Godot imported readback must preserve RGB, including blue sign.
axes=[(255,128,128,255),(0,128,128,255),(128,255,128,255),(128,0,128,255),(128,128,255,255),(128,128,0,255)]
for i,color in enumerate(axes):atlas.putpixel((1000+i,380),color)
proof['axis_pixels']=[{'xy':[1000+i,380],'rgba':list(c)} for i,c in enumerate(axes)]
atlas.save(RUNTIME/'object_normals.png');proof['data_png_sha256']=hashlib.sha256((RUNTIME/'object_normals.png').read_bytes()).hexdigest();proof['data_png_bytes']=(RUNTIME/'object_normals.png').stat().st_size
# Isolated real GLB import: geometry untouched; URI resolves the existing canonical albedo resource.
source=ROOT/'assets/hero/vegetation/veg_hero_plane_a_proxy.glb';data=source.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n]);g['images'][0]['uri']='../vegetation_atlas.png';js=json.dumps(g,separators=(',',':')).encode();js+=b' '*((-len(js))%4);tail=data[20+n:];(RUNTIME/'plane_proxy.glb').write_bytes(struct.pack('<III',0x46546c67,2,20+len(js)+len(tail))+struct.pack('<II',len(js),0x4e4f534a)+js+tail)
proof['source_proxy_sha256']=hashlib.sha256(data).hexdigest();proof['experimental_glb_sha256']=hashlib.sha256((RUNTIME/'plane_proxy.glb').read_bytes()).hexdigest()
(OUT/'normal_capture.json').write_text(json.dumps(proof,indent=2)+'\n');print('NORMAL_PACK_OK raw_gamma',sentinel,'mask3/3exact',proof['data_png_bytes'])
