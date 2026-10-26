"""Regression: compare exported rear-body UVs against actual approved LOD0 GLB.
This inspects binary POSITION/NORMAL/TEXCOORD accessors, not generator strings.
"""
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'art/blender/hero'))
sys.path.insert(0,str(ROOT/'tools/library'))
import fam_layout
import hero_layout
import hero_lods


def accessors(path):
    data=path.read_bytes();length=struct.unpack_from('<I',data,12)[0]
    doc=json.loads(data[20:20+length]);binary=data[28+length:]
    def read(index):
        a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
        count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        component={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
        fmt='<'+component*count;size=struct.calcsize(fmt)
        offset=view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',size)
        return [struct.unpack_from(fmt,binary,offset+i*stride) for i in range(a['count'])]
    return doc,read


def rear_corners(path,width,depth,height):
    doc,read=accessors(path);result={}
    for mesh in doc['meshes']:
        for prim in mesh['primitives']:
            pos=read(prim['attributes']['POSITION']);uv=read(prim['attributes']['TEXCOORD_0']);normal=read(prim['attributes']['NORMAL'])
            indices=[x[0] for x in read(prim['indices'])] if 'indices' in prim else list(range(len(pos)))
            for i in range(0,len(indices),3):
                ids=indices[i:i+3];points=[pos[j] for j in ids]
                if not all(abs(p[2]+depth)<1e-4 and normal[j][2]<-.999 for p,j in zip(points,ids)):continue
                ax,ay=points[1][0]-points[0][0],points[1][1]-points[0][1]
                bx,by=points[2][0]-points[0][0],points[2][1]-points[0][1]
                if abs(ax*by-ay*bx)/2 < width*height*.20:continue
                for j in ids:
                    key=tuple(round(v,4) for v in pos[j]);result.setdefault(key,[]).append(uv[j])
    return result


class HeroRearUVTests(unittest.TestCase):
    def test_proxy_side_tile_retains_source_albedo(self):
        result=subprocess.run(['uv','run','--with','pillow==11.3.0','python',str(ROOT/'tools/library/check_proxy_side_tiles.py')],capture_output=True,text=True)
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    def test_exported_rear_mapping_matches_approved_source(self):
        catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
        for entry in catalog['entries']:
            if 'lod_chain' not in entry:continue
            family=hero_lods.FAMILY_MAP[entry['family']]
            dimensions={'W':hero_layout.W,'D':hero_layout.D,'H':hero_layout.H} if family=='old_core' else fam_layout.FAMILIES[family]()
            source=rear_corners(ROOT/entry['glb'].removeprefix('res://'),dimensions['W'],dimensions['D'],dimensions['H'])
            self.assertEqual(4,len(source),entry['id']+' source rear corners')
            for level in ('LOD1','PROXY'):
                with self.subTest(asset=entry['id'],level=level):
                    reduced=rear_corners(ROOT/entry['lod_chain']['levels'][level]['glb'].removeprefix('res://'),dimensions['W'],dimensions['D'],dimensions['H'])
                    self.assertEqual(set(source),set(reduced),'rear body must keep source positions')
                    for corner,values in reduced.items():
                        for uv in values:
                            self.assertTrue(any(abs(uv[0]-expected[0])<1e-6 and abs(uv[1]-expected[1])<1e-6 for expected in source[corner]),'%s rear UV differs from source at %s: %s vs %s'%(level,corner,uv,source[corner]))


if __name__=='__main__':unittest.main()
