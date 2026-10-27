"""T-057 deterministic vegetation HERO proposals, isolated library assets.
Blender --background --factory-startup --python art/blender/vegetation/build.py -- [olive_open palm_date ...]
Prerequisite: uv run --with pillow==11.3.0 python art/blender/vegetation/atlas.py
Opaque bark +alpha-mask cutout leaf sprays/fronds share one mat/atlas. No game integration.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import random
import struct
import sys
import bpy
from mathutils import Vector, Euler

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/hero/vegetation'
LAYOUT=json.loads((OUT/'atlas_layout.json').read_text())
SPECIES=['plane','palm_date','palm_slender','pine_brutia','pine_stone','olive_open','olive_twisted','cypress','maquis','hedge']
SEEDS={s:5700+i*71 for i,s in enumerate(SPECIES)}
V=[];F=[];UV=[]


def uv(region,u,v):
    x,y,w,h=LAYOUT['regions'][region];s=LAYOUT['size']
    return ((x+8+u*(w-16))/s,1-(y+8+v*(h-16))/s)


def poly(points,region,coords=None):
    start=len(V);V.extend([tuple(p) for p in points]);F.append(tuple(range(start,start+len(points))))
    coords=coords or [(0,1),(1,1),(1,0),(0,0)]
    UV.extend([uv(region,*p) for p in coords[:len(points)]])


def tube(points,radii,sides=6,region='bark'):
    points=[Vector(p) for p in points]
    for i in range(len(points)-1):
        a,b=points[i:i+2];axis=(b-a).normalized();base=axis.cross(Vector((0,1,0)))
        if base.length<.01:base=axis.cross(Vector((1,0,0)))
        base.normalize();other=axis.cross(base)
        for n in range(sides):
            t0,t1=2*math.pi*n/sides,2*math.pi*(n+1)/sides
            d0=base*math.cos(t0)+other*math.sin(t0);d1=base*math.cos(t1)+other*math.sin(t1)
            poly([a+d0*radii[i],a+d1*radii[i],b+d1*radii[i+1],b+d0*radii[i+1]],region,[(n/sides,1),((n+1)/sides,1),((n+1)/sides,0),(n/sides,0)])


def card(center,width,height,region,yaw,pitch,roll=0):
    transform=Euler((pitch,roll,yaw),'XYZ').to_matrix();c=Vector(center)
    pts=[c+transform@Vector(p) for p in [(-width/2,0,-height/2),(width/2,0,-height/2),(width/2,0,height/2),(-width/2,0,height/2)]]
    poly(pts,region)


def tuft(center,radii,count,region,rng,card_size=1.1):
    for _ in range(count):
        p=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1)))
        if p.length>1:p.normalize()
        loc=Vector(center)+Vector((p.x*radii[0],p.y*radii[1],p.z*radii[2]))
        w=card_size*rng.uniform(.75,1.15)
        card(loc,w,w*rng.uniform(.8,1.3),region,rng.uniform(-math.pi,math.pi),rng.uniform(-1,1),rng.uniform(-.5,.5))


def olive(species,level,rng):
    sides={'LOD0':7,'LOD1':4,'PROXY':3}[level]
    twist=species=='olive_twisted'
    centers=[(-1.1,-.35,3.55),(1.05,.4,3.8),(.05,1.0,3.65)] if not twist else [(-1.3,-.1,3.5),(.7,.4,3.5),(1.4,-.45,3.9),(-.1,1.0,3.8)]
    if level=='PROXY':
        tube([(0,0,0),(.06,0,1.6),(.1,0,2.9)],[.33,.21,.10],3)
        for i,c in enumerate(centers):
            tuft(c,(.8,.7,.25),3,'olive',rng,1.8)
        return
    twist=species=='olive_twisted'
    centers=[(-1.1,-.35,3.55),(1.05,.4,3.8),(.05,1.0,3.65)] if not twist else [(-1.3,-.1,3.5),(.7,.4,3.5),(1.4,-.45,3.9),(-.1,1.0,3.8)]
    tube([(0,0,0),(.12,-.1,.6),(-.05,.04,1.2),(.18,0,1.9),(.05,.08,2.6)],[.39,.31,.26,.22,.15],sides)
    for i,c in enumerate(centers):
        base=(.13,0,1.5+i*.15);end=(c[0]*.8,c[1]*.8,c[2]-.25)
        tube([base,(c[0]*.6,c[1]*.6,2.5),end],[.18,.13,.045],sides)
        if level=='LOD0':
            for k in range(3):
                tip=(c[0]+rng.uniform(-.8,.8),c[1]+rng.uniform(-.7,.7),c[2]+rng.uniform(-.1,.5))
                tube([end,tip],[.06,.015],4)
        tuft(c,(1.0,.9,.40),36 if level=='LOD0' else 7,'olive',rng,1.35 if level=='LOD0' else 1.65)


def frond(angle,base,length,width,rise,droop,segments):
    c=Vector(base);radial=Vector((math.cos(angle),math.sin(angle),0));side=Vector((-math.sin(angle),math.cos(angle),0))
    for k in range(segments):
        ts=[k/segments,(k+1)/segments];pts=[]
        for t,sign in [(ts[0],-1),(ts[0],1),(ts[1],1),(ts[1],-1)]:
            center=c+radial*(length*t)+Vector((0,0,rise*math.sin(math.pi*t)-droop*t*t))
            half=width*(.28+.72*math.sin(math.pi*min(.98,max(.02,t))))/2
            pts.append(center+side*sign*half)
        poly(pts,'frond',[(ts[0],1),(ts[0],0),(ts[1],0),(ts[1],1)])


def palm(species,level,rng):
    slender=species=='palm_slender';height=9.1 if slender else 6.6
    radius=.16 if slender else .40
    trunk=[(0,0,0),(.08,0,height*.3),(.18,.03,height*.65),(.16,0,height)]
    if level=='PROXY':trunk=[trunk[0],trunk[-1]]
    sides={'LOD0':10,'LOD1':6,'PROXY':3}[level]
    tube(trunk,[radius*(1-.18*i/(len(trunk)-1)) for i in range(len(trunk))],sides,'palm_bark')
    count={'LOD0':36 if not slender else 27,'LOD1':12,'PROXY':7}[level]
    segs={'LOD0':6,'LOD1':4,'PROXY':2}[level]
    if level=='PROXY':count=7
    for i in range(count):
        layer=i%3;angle=i*2.399963+(.3 if slender else 0)
        length=(2.35 if slender else 3.45)*(1-.12*layer)
        base=(.16,0,height+layer*.20)
        rise=[.7,1.6,2.4][layer]*(.75 if slender else 1)
        droop=[1.5,.7,-.1][layer]*(.6 if slender else 1)
        frond(angle,base,length,.8 if slender else 1.35,rise,droop,segs)
    for i in range(5 if level=='LOD0' else 3):
        frond(i*2.4,(.16,0,height+.35),1.1 if slender else 1.65,.35 if slender else .5,1.6 if slender else 2.3,-.65,4 if level=='LOD0' else 3 if level=='LOD1' else 1)
    if level=='LOD0':
        for i in range(13):
            a=i*2.4
            frond(a,(.16,0,height-.2),1.0,.22,.2,1.4,3)



def plane_tree(level,rng):
    # Distinct rounded shade canopy, not the stone-pine umbrella/fan skeleton.
    centers=[(-2.6,-1.2,9.6),(0,-2.4,9.5),(2.7,-1.0,10.2),(-2.7,1.2,10.4),(0,2.2,10.0),(2.3,1.1,9.5),(-.2,.2,11.9),(0,-.2,8.9)]
    if level=='PROXY':
        base=Vector((0,.1,8.4));tube([(0,0,0),base],[.43,.15],3)
        for k,i in enumerate([0,2,3,5,6]):
            center=Vector(centers[i]);axis=(center-base).normalized();across=axis.cross(Vector((0,1,0)))
            across.normalize();other=axis.cross(across)
            for side in (across*.14,other*.14):poly([base-side,base+side,center+side*.25,center-side*.25],'bark')
            tuft(center,(.25,.25,.3),1,'plane',random.Random(570135+i),3.5)
        return
    sides=8 if level=='LOD0' else 4
    tube([(0,0,0),(.15,.05,2.0),(-.18,.12,4.6),(.1,.08,6.5),(0,.1,8.0)],[.48,.38,.29,.21,.12],sides)
    for i,c in enumerate(centers):
        crng=random.Random(570135+i*997)
        base=(.1,.08,4.6+(i%3)*.35)
        elbow=(c[0]*.65,c[1]*.65,7.0+(i%2)*.5)
        tube([base,elbow,c],[.18,.12,.045],6 if level=='LOD0' else 4)
        if level=='LOD0':
            for k in range(2):tube([c,(c[0]+crng.uniform(-1,1),c[1]+crng.uniform(-1,1),c[2]+crng.uniform(-.3,.6))],[.06,.018],4)
        tuft(c,(1.45,1.3,.95),40 if level=='LOD0' else 8,'plane',crng,1.7 if level=='LOD0' else 2.6)


def broad_tree(species,level,rng):
    if species=='plane':
        plane_tree(level,rng);return
    plane=False;stone=species=='pine_stone'
    h=14 if plane else 12.8 if stone else 12.0
    stem=h*(.38 if plane else .62 if stone else .42)
    if level=='PROXY':
        # Continuous tree proxy: five source crown centres and crossed opaque
        # branch strips connect them to a trunk. No floating canopy fragments.
        stem_top=h*(.65 if plane else .7 if stone else .45)
        base=Vector((-.1,.15,stem_top))
        tube([(0,0,0),base],[.38 if plane else .3,.14],3)
        source_count=7 if plane else 8 if stone else 9
        for k in range(5):
            source_k=round(k*(source_count-1)/4)
            crng=random.Random(SEEDS[species]+source_k*883)
            angle=source_k*2.39996
            radius=(3.0 if plane else 3.3 if stone else 1.8)*(0.5+.5*((source_k%3)/2))
            z=10.6+crng.uniform(-1.2,1.2) if plane else 10.7+crng.uniform(-.3,.4) if stone else 5.7+source_k*.58
            center=Vector((math.cos(angle)*radius,math.sin(angle)*radius,z))
            axis=(center-base).normalized()
            across=axis.cross(Vector((0,1,0)))
            if across.length<.01:across=axis.cross(Vector((1,0,0)))
            across.normalize();second=axis.cross(across)
            for side in (across*.12,second*.12):
                poly([base-side,base+side,center+side*.25,center-side*.25],'bark')
            tuft(center,(.2,.2,.15),1,'plane' if plane else 'pine',crng,3.2)
        return
    sides={'LOD0':8,'LOD1':4,'PROXY':3}[level]
    tube([(0,0,0),(.16,.10,stem*.45),(-.1,.15,stem)],[.43 if plane else .31,.28,.16],sides)
    crowns=7 if plane else 8 if stone else 9
    if level=='PROXY':crowns=7
    region='plane' if plane else 'pine'
    for k in range(crowns):
        angle=k*2.39996;radius=(3.0 if plane else 3.3 if stone else 1.8)*(0.5+.5*((k%3)/2))
        crng=random.Random(SEEDS[species]+k*883)
        z=10.6+crng.uniform(-1.2,1.2) if plane else 10.7+crng.uniform(-.3,.4) if stone else 5.7+k*.58
        center=(math.cos(angle)*radius,math.sin(angle)*radius,z)
        if level!='PROXY':
            tube([(-.1,.15,stem*.8),(center[0]*.6,center[1]*.6,z-.7),center],[.14,.10,.025],sides)
        tuft(center,(1.7 if plane else 1.5,1.5,1.25 if plane else .35 if stone else .8),24 if level=='LOD0' and plane else 16 if level=='LOD0' else 8 if species!='pine_brutia' else 7,region,crng,1.7 if level=='LOD0' else 2.5)


def small(species,level,rng):
    if species=='cypress':
        tube([(0,0,0),(0,0,4),(0,0,8.8)],[.19,.12,.04],{'LOD0':7,'LOD1':4,'PROXY':3}[level])
        tiers=12 if level in ('LOD0','LOD1') else 5
        for k in range(tiers):
            z=1.7+k*(7.5/(tiers-1));r=.85*(1-(z-1.7)/9.5)
            tuft((.08*math.sin(k),0,z),(r,r,.35),12 if level=='LOD0' else (11 if k in (0,11) else 12) if level=='LOD1' else 1,'pine',rng,1.3 if level!='PROXY' else 2.0)
    else:
        hedge=species=='hedge';count=5 if hedge else 4
        if level=='PROXY':
            for k in range(7):
                x=(k-3)*.6 if hedge else (k%4-1.5)*.65
                card((x,0,.6 if hedge else 1.35),1.2,1.0 if hedge else 1.8,'maquis',0 if hedge and k in (0,6) else k*1.3,.2*(k%2))
            return
        for k in range(count):
            x=(k-(count-1)/2)*(.8 if hedge else .48);z=.6 if hedge else 1.35+(.12 if k%2 else -.1)
            tube([(x,0,0),(x+.1,0,z)],[.07,.025],4 if level=='LOD0' else 3)
            tuft((x,.1*math.sin(k),z),(.55,.2 if hedge else .35,.1 if hedge else .4),32 if level=='LOD0' else 7,'maquis',rng,.6 if hedge else 1.0)


def save(species,level):
    name='veg_hero_'+species+'_a_'+level.lower();mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(V,[],F);mesh.update();layer=mesh.uv_layers.new(name='UVMap')
    for p in mesh.polygons:
        for li in p.loop_indices:layer.data[li].uv=UV[mesh.loops[li].vertex_index]
    ob=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(ob)
    mat=bpy.data.materials.new('mat_vegetation_atlas');mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=1;bsdf.inputs['Specular IOR Level'].default_value=0
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/'vegetation_atlas.png'),check_existing=True)
    mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color']);mat.node_tree.links.new(tex.outputs['Alpha'],bsdf.inputs['Alpha'])
    mesh.materials.append(mat);bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    path=OUT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
    data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n]);imageviews={im.get('bufferView') for im in g.get('images',[]) if 'bufferView' in im}
    for image in g.get('images',[]):image.clear();image['uri']='vegetation_atlas.png'
    for material in g['materials']:material['alphaMode']='MASK';material['alphaCutoff']=.45;material['doubleSided']=True
    remap={i:sum(j not in imageviews for j in range(i)) for i in range(len(g['bufferViews'])) if i not in imageviews}
    g['bufferViews']=[v for i,v in enumerate(g['bufferViews']) if i not in imageviews]
    for accessor in g['accessors']:
        if 'bufferView' in accessor:accessor['bufferView']=remap[accessor['bufferView']]
    used=max(v.get('byteOffset',0)+v['byteLength'] for v in g['bufferViews']);g['buffers'][0]['byteLength']=used
    binary=data[28+n:28+n+used];binary+=b'\0'*((-len(binary))%4)
    tail=struct.pack('<II',len(binary),0x004e4942)+binary
    js=json.dumps(g,separators=(',',':')).encode();js+=b' '*((-len(js))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(js)+len(tail))+struct.pack('<II',len(js),0x4e4f534a)+js+tail)
    tris=sum(len(f)-2 for f in F);small_asset=species in ('maquis','hedge')
    budget=({'LOD0':600,'LOD1':120,'PROXY':24} if small_asset else {'LOD0':1800,'LOD1':300,'PROXY':40})[level]
    print('VEGETATION',species,level,tris,'budget',budget,flush=True)
    if tris>budget:raise ValueError(name+' exceeds budget')



def source_impostor(kind):
    manifest=json.loads((OUT/'proxy_bakes.json').read_text())
    asset=manifest['assets'][kind]
    source=ROOT/asset['source_lod0'].removeprefix('res://')
    if hashlib.sha256(source.read_bytes()).hexdigest()!=asset['source_lod0_sha256']:raise ValueError('stale source impostor bake: '+kind)
    lo,hi=asset['bbox_blender_min'],asset['bbox_blender_max']
    cx,cy=(lo[0]+hi[0])/2,(lo[1]+hi[1])/2
    z=asset['top_plane_height']
    poly([(lo[0],cy,lo[2]),(hi[0],cy,lo[2]),(hi[0],cy,hi[2]),(lo[0],cy,hi[2])],'proxy_'+kind+'_front')
    poly([(cx,lo[1],lo[2]),(cx,hi[1],lo[2]),(cx,hi[1],hi[2]),(cx,lo[1],hi[2])],'proxy_'+kind+'_side')
    poly([(lo[0],lo[1],z),(hi[0],lo[1],z),(hi[0],hi[1],z),(lo[0],hi[1],z)],'proxy_'+kind+'_top')


def main():
    global V,F,UV
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    levels=['LOD0','LOD1'] if '--base-only' in args else ['PROXY'] if '--proxy-only' in args else ['LOD0','LOD1','PROXY']
    species=[a for a in args if not a.startswith('--')]
    for kind in species or SPECIES:
        if kind not in SPECIES:raise ValueError(kind)
        for level in levels:
            for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
            bpy.data.orphans_purge(do_recursive=True);V=[];F=[];UV=[]
            rng=random.Random(SEEDS[kind])
            if level=='PROXY' and not kind.startswith('palm'):source_impostor(kind)
            elif kind.startswith('olive'):olive(kind,level,rng)
            elif kind.startswith('palm'):palm(kind,level,rng)
            elif kind in ('plane','pine_brutia','pine_stone'):broad_tree(kind,level,rng)
            else:small(kind,level,rng)
            save(kind,level)


main()
