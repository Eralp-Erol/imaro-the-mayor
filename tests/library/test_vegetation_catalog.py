"""T-057 actual asset integrity, ownership, negative drift and source-kind routing."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import subprocess
import shutil
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/library'))
import vegetation_catalog as vc
import validate_catalog
import glb_info
import hero_lods
from test_hero_rear_uv import accessors


class VegetationCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
        cls.plants=[e for e in cls.catalog['entries'] if e.get('source',{}).get('kind')=='hero_vegetation']

    def test_ten_proposals_thirty_measured_lods(self):
        self.assertEqual(10,len(self.plants))
        for e in self.plants:
            with self.subTest(e=e['id']):
                self.assertEqual([],vc.validate_chain(e,ROOT))
                self.assertIn(e['approval'],('proposed','approved','rejected'))
                self.assertEqual('proposed',vc.entry(ROOT,e['family'].removeprefix('hero_'))['approval'])
                self.assertEqual('proposed',e['lod_chain']['status'])
                self.assertGreater(e['triangles']['LOD0'],e['triangles']['LOD1'])
                self.assertGreater(e['triangles']['LOD1'],e['triangles']['PROXY'])

    def test_update_keeps_existing_entries_and_user_fields(self):
        original=copy.deepcopy(self.catalog)
        for e in original['entries']:
            if e.get('source',{}).get('kind')=='hero_vegetation':
                e.update(approval='approved',approval_by='user',approval_date='2026-10-27',user_note='Keep',user_custom={'choice':2})
        rebuilt=vc.update(original,ROOT);before={e['id']:e for e in original['entries']}
        for e in rebuilt['entries']:
            old=before[e['id']]
            if e.get('source',{}).get('kind')!='hero_vegetation':self.assertEqual(old,e)
            else:
                protected=lambda a:{k:v for k,v in a.items() if k.startswith(('approval','user_'))}
                self.assertEqual(protected(old),protected(e))
        self.assertEqual(rebuilt,vc.update(rebuilt,ROOT))

    def test_building_chain_validator_ignores_vegetation_kind(self):
        self.assertEqual([],hero_lods.validate_chain(self.plants[0],ROOT))

    def test_geometry_metadata_drift_fails(self):
        e=copy.deepcopy(self.plants[0]);e['lod_chain']['levels']['LOD1']['sha256']='0'*64
        self.assertTrue(vc.validate_chain(e,ROOT))

    def test_texture_drift_fails(self):
        e=copy.deepcopy(self.plants[0]);e['lod_chain']['atlas']['sha256']='0'*64
        self.assertTrue(vc.validate_chain(e,ROOT))

    def test_missing_file_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:self.assertTrue(vc.validate_chain(self.plants[0],Path(d)))

    def test_vegetation_routes_without_building_validator(self):
        errors=[];warnings=[];entry=self.plants[0]
        with mock.patch.object(validate_catalog.hero_lods,'validate_chain',side_effect=AssertionError('vegetation misclassified as building')):
            validate_catalog.check_entry(entry,{'vegetation'},str(ROOT),errors,warnings)
        self.assertEqual([],errors)

    def test_shared_atlas_alpha_mask_and_no_embedded_payload(self):
        for e in self.plants:
            for level,stats in e['lod_chain']['levels'].items():
                path=ROOT/stats['glb'].removeprefix('res://');g=glb_info.read_gltf_json(path)
                self.assertTrue(all(i.get('uri')=='vegetation_atlas.png' and 'bufferView' not in i for i in g['images']))
                self.assertLess(path.stat().st_size,300000,'orphaned embedded texture payload')
                self.assertTrue(all(m.get('alphaMode')=='MASK' and m.get('doubleSided') for m in g['materials']))

    def test_nonpalm_proxy_uses_complete_source_views_and_bounds(self):
        manifest=json.loads((ROOT/'assets/hero/vegetation/proxy_bakes.json').read_text())
        for e in self.plants:
            if e['family'].startswith('hero_palm'):continue
            species=e['family'].removeprefix('hero_');stats=e['lod_chain']['levels']['PROXY']
            self.assertEqual(6,stats['triangles'])
            for key in ('bbox_min','bbox_max'):
                for value,source in zip(stats[key],e['lod_chain']['levels']['LOD0'][key]):self.assertAlmostEqual(value,source,places=4)
            g,read=accessors(ROOT/stats['glb'].removeprefix('res://'));uvs=[]
            for mesh in g['meshes']:
                for prim in mesh['primitives']:uvs.extend(read(prim['attributes']['TEXCOORD_0']))
            self.assertEqual(12,len(uvs))
            used=set()
            for view in ('front','side','top'):
                x,y,w,h=manifest['assets'][species]['views'][view]['region']
                expected={(round((x+u)/1024,6),round((y+v)/1024,6)) for u,v in [(8,8),(120,8),(120,120),(8,120)]}
                actual={(round(u,6),round(v,6)) for u,v in uvs if x/1024<=u<=(x+w)/1024 and y/1024<=v<=(y+h)/1024}
                self.assertEqual(expected,actual,e['id']+' missing/full-view UV coverage: '+view)
                used.update(actual)
            self.assertEqual(12,len(used))

    def test_proxy_tile_content_matches_source_provenance(self):
        import subprocess
        result=subprocess.run(['uv','run','--with','pillow==11.3.0','python',str(ROOT/'tools/library/check_vegetation_proxy_tiles.py')],capture_output=True,text=True)
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    def test_actual_proxy_tile_pixel_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);out=root/'assets/hero/vegetation';out.mkdir(parents=True)
            for name in ['vegetation_atlas.png','proxy_bakes.json']:
                shutil.copyfile(ROOT/'assets/hero/vegetation'/name,out/name)
            manifest=json.loads((out/'proxy_bakes.json').read_text())
            for asset in manifest['assets'].values():
                relative=asset['source_lod0'].removeprefix('res://')
                shutil.copyfile(ROOT/relative,root/relative)
            first=next(iter(manifest['assets'].values()))['views']['front']['region']
            code="from PIL import Image; import sys; p=sys.argv[1]; i=Image.open(p).convert('RGBA'); i.putpixel((int(sys.argv[2])+64,int(sys.argv[3])+64),(255,0,255,255)); i.save(p)"
            subprocess.run(['uv','run','--with','pillow==11.3.0','python','-c',code,str(out/'vegetation_atlas.png'),str(first[0]),str(first[1])],check=True,capture_output=True)
            result=subprocess.run(['uv','run','--with','pillow==11.3.0','python',str(ROOT/'tools/library/check_vegetation_proxy_tiles.py'),'--root',str(root)],capture_output=True,text=True)
            self.assertNotEqual(0,result.returncode)
            self.assertIn('tile content drift',result.stderr+result.stdout)

    def test_malformed_source_is_a_diagnostic_before_dispatch(self):
        for bad in [None,'bad-source',[]]:
            e=copy.deepcopy(self.plants[0]);e['source']=bad;errors=[];warnings=[]
            with mock.patch.object(validate_catalog.hero_lods,'validate_chain',side_effect=AssertionError('invalid source dispatched')):
                with mock.patch.object(validate_catalog.vegetation_catalog,'validate_chain',side_effect=AssertionError('invalid source dispatched')):
                    validate_catalog.check_entry(e,{'vegetation'},str(ROOT),errors,warnings)
            self.assertTrue(any('source must be an object' in error for error in errors))
            self.assertTrue(vc.validate_chain(e,ROOT))
            bad_catalog=copy.deepcopy(self.catalog)
            next(item for item in bad_catalog['entries'] if item['id']==e['id'])['source']=bad
            public_errors,_=validate_catalog.validate(bad_catalog,str(ROOT),None)
            self.assertTrue(any('source must be an object' in error for error in public_errors))

    def test_proxy_runtime_shader_drift_is_rejected(self):
        entry=next(e for e in self.plants if e['family']=='hero_plane')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);shutil.copytree(ROOT/'assets/hero/vegetation',root/'assets/hero/vegetation')
            shader=root/'assets/hero/vegetation/proxy_canopy.gdshader'
            shader.write_text(shader.read_text().replace('shadows_disabled','ambient_light_disabled'))
            self.assertTrue(any('lod_chain' in error for error in vc.validate_chain(entry,root)))

    def test_proxy_import_assignment_missing_is_rejected(self):
        entry=next(e for e in self.plants if e['family']=='hero_plane')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);shutil.copytree(ROOT/'assets/hero/vegetation',root/'assets/hero/vegetation')
            config=root/'assets/hero/vegetation/veg_hero_plane_a_proxy.glb.import'
            config.write_text(config.read_text().replace('import_script/path="res://assets/hero/vegetation/proxy_import.gd"','import_script/path=""'))
            self.assertTrue(any('import policy missing' in error for error in vc.validate_chain(entry,root)))

    def test_unknown_family_is_rejected(self):
        e=copy.deepcopy(self.plants[0]);e['family']='hero_unknown_species'
        self.assertTrue(vc.validate_chain(e,ROOT))


if __name__=='__main__':unittest.main()
