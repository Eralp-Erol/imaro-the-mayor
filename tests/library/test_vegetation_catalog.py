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

    def test_ten_proposals_twentytwo_measured_lods(self):
        self.assertEqual(10,len(self.plants))
        for e in self.plants:
            with self.subTest(e=e['id']):
                self.assertEqual([],vc.validate_chain(e,ROOT))
                self.assertIn(e['approval'],('proposed','approved','rejected'))
                self.assertEqual('proposed',vc.entry(ROOT,e['family'].removeprefix('hero_'))['approval'])
                self.assertEqual('proposed',e['lod_chain']['status'])
                self.assertGreater(e['triangles']['LOD0'],e['triangles']['LOD1'])
                palm=e['family'].startswith('hero_palm')
                self.assertEqual(['LOD0','LOD1','PROXY'] if palm else ['LOD0','LOD1'],list(e['lod_chain']['levels']))
                self.assertEqual(set(e['lod_chain']['levels']),set(e['triangles']))
                if palm:self.assertGreater(e['triangles']['LOD1'],e['triangles']['PROXY'])
                else:
                    for retired in ('proxy_source','proxy_runtime'):self.assertNotIn(retired,e['lod_chain'])
                self.assertEqual({'LOD0_max':120,'LOD1_max':400},{k:e['lod_chain']['distances_m'][k] for k in ('LOD0_max','LOD1_max')})
                self.assertEqual('working-model-not-integrated',e['lod_chain']['distances_m']['status'])
                self.assertEqual({'generate_lods':False,'import_script':None},{k:e['lod_chain']['import_policy'][k] for k in ('generate_lods','import_script')})

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

    def vegetation_copy(self,folder):
        root=Path(folder);shutil.copytree(ROOT/'assets/hero/vegetation',root/'assets/hero/vegetation',ignore=shutil.ignore_patterns('*_experiment'))
        return root

    def plant(self,family):return next(e for e in self.plants if e['family']==family)

    def test_nonpalm_species_have_no_proxy_and_palms_keep_40_tri_proxy(self):
        for e in self.plants:
            species=e['family'].removeprefix('hero_')
            proxy=ROOT/'assets/hero/vegetation'/('veg_hero_%s_a_proxy.glb'%species)
            if e['family'].startswith('hero_palm'):
                self.assertTrue(proxy.exists() and proxy.with_suffix('.glb.import').exists(),species)
                self.assertTrue(0<e['triangles']['PROXY']<=40)
            else:
                self.assertFalse(proxy.exists() or proxy.with_suffix('.glb.import').exists(),species)
                self.assertNotIn('PROXY',e['triangles'])

    def test_retired_proxy_policy_files_are_gone(self):
        for name in vc.LEGACY_SHARED:self.assertFalse((ROOT/'assets/hero/vegetation'/name).exists(),name)

    def test_all_vegetation_imports_disable_generated_lods_without_post_import(self):
        for e in self.plants:
            for level,stats in e['lod_chain']['levels'].items():
                params=vc.import_params((ROOT/stats['glb'].removeprefix('res://')).with_suffix('.glb.import'))
                self.assertEqual('false',params['meshes/generate_lods'],e['id']+' '+level)
                self.assertEqual('""',params['import_script/path'],e['id']+' '+level)

    def test_generate_lods_true_is_rejected(self):
        for family,level in (('hero_plane','lod0'),('hero_palm_date','proxy')):
            with self.subTest(family=family),tempfile.TemporaryDirectory() as d:
                root=self.vegetation_copy(d);config=root/'assets/hero/vegetation'/('veg_%s_a_%s.glb.import'%(family,level))
                config.write_text(config.read_text().replace('meshes/generate_lods=false','meshes/generate_lods=true'))
                self.assertTrue(any('generate_lods' in error for error in vc.validate_chain(self.plant(family),root)))

    def test_post_import_script_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.vegetation_copy(d);config=root/'assets/hero/vegetation/veg_hero_plane_a_lod1.glb.import'
            config.write_text(config.read_text().replace('import_script/path=""','import_script/path="res://assets/hero/vegetation/proxy_import.gd"'))
            self.assertTrue(any('post-import' in error for error in vc.validate_chain(self.plant('hero_plane'),root)))

    def test_source_lod1_hash_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.vegetation_copy(d);glb=root/'assets/hero/vegetation/veg_hero_olive_open_a_lod1.glb'
            glb.write_bytes(glb.read_bytes()+b'\0\0\0\0')
            self.assertTrue(any('lod_chain' in error for error in vc.validate_chain(self.plant('hero_olive_open'),root)))

    def test_old_nonpalm_proxy_residue_is_rejected(self):
        for residue in ('veg_hero_plane_a_proxy.glb','veg_hero_plane_a_proxy.glb.import','proxy_canopy.gdshader','proxy_import.gd','proxy_bakes.json','proxy_canopy.tres'):
            with self.subTest(residue=residue),tempfile.TemporaryDirectory() as d:
                root=self.vegetation_copy(d);(root/'assets/hero/vegetation'/residue).write_text('stale')
                self.assertTrue(any('retired proxy residue' in error for error in vc.validate_chain(self.plant('hero_plane'),root)))

    def test_proxy_level_injected_into_nonpalm_chain_is_rejected(self):
        e=copy.deepcopy(self.plant('hero_cypress'));e['triangles']['PROXY']=6
        self.assertTrue(any('PROXY' in error for error in vc.validate_chain(e,ROOT)))
        e=copy.deepcopy(self.plant('hero_cypress'));e['lod_chain']['proxy_source']={'x':1}
        self.assertTrue(vc.validate_chain(e,ROOT))

    def test_palm_proxy_missing_fails_closed_and_is_kept_in_budget(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.vegetation_copy(d);(root/'assets/hero/vegetation/veg_hero_palm_slender_a_proxy.glb').unlink()
            self.assertTrue(vc.validate_chain(self.plant('hero_palm_slender'),root))
        self.assertEqual({'LOD0':1800,'LOD1':300,'PROXY':40},vc.limits('palm_date'))
        self.assertEqual({'LOD0':1800,'LOD1':300},vc.limits('plane'))
        self.assertEqual({'LOD0':600,'LOD1':120},vc.limits('hedge'))

    def atlas_check(self,root=None):
        command=['uv','run','--with','pillow==11.3.0','python',str(ROOT/'tools/library/check_vegetation_atlas.py')]+(['--root',str(root)] if root else [])
        return subprocess.run(command,capture_output=True,text=True)

    def test_atlas_regions_match_recorded_hashes(self):
        result=self.atlas_check();self.assertEqual(0,result.returncode,result.stdout+result.stderr)

    def test_actual_atlas_pixel_drift_is_rejected(self):
        code="from PIL import Image; import sys; p=sys.argv[1]; i=Image.open(p).convert('RGBA'); i.putpixel((int(sys.argv[2]),int(sys.argv[3])),(255,0,255,255)); i.save(p)"
        for x,y,message in ((64,700,'dead tile region drift'),(64,100,'base foliage/bark pixels drift')):
            with self.subTest(message=message),tempfile.TemporaryDirectory() as folder:
                root=Path(folder);out=root/'assets/hero/vegetation';out.mkdir(parents=True)
                for name in ('vegetation_atlas.png','atlas_regions.json'):shutil.copyfile(ROOT/'assets/hero/vegetation'/name,out/name)
                subprocess.run(['uv','run','--with','pillow==11.3.0','python','-c',code,str(out/'vegetation_atlas.png'),str(x),str(y)],check=True,capture_output=True)
                result=self.atlas_check(root);self.assertNotEqual(0,result.returncode);self.assertIn(message,result.stderr+result.stdout)

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

    def test_unknown_family_is_rejected(self):
        e=copy.deepcopy(self.plants[0]);e['family']='hero_unknown_species'
        self.assertTrue(vc.validate_chain(e,ROOT))


if __name__=='__main__':unittest.main()
