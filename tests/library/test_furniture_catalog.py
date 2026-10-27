"""T-058 street-furniture proposals: real asset integrity, ownership, routing and negative drift/budget/import cases."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/library'))
import build_catalog
import furniture_catalog as fc
import validate_catalog
import glb_info
import hero_lods
import vegetation_catalog


class FurnitureCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
        cls.items=[e for e in cls.catalog['entries'] if e.get('source',{}).get('kind')=='hero_furniture']

    def item(self,family):return next(e for e in self.items if e['family']==family)

    def copy_root(self,folder):
        root=Path(folder);shutil.copytree(ROOT/'assets/hero/furniture',root/'assets/hero/furniture',ignore=shutil.ignore_patterns('*.lab','*.gd','*.tscn','*.uid'))
        return root

    def test_eight_proposals_sixteen_measured_lods_and_total_count(self):
        self.assertEqual(8,len(self.items))
        self.assertEqual(sorted('hero_'+n for n in fc.NAMES),sorted(e['family'] for e in self.items))
        kinds={}
        for e in self.catalog['entries']:kinds[e['source']['kind']]=kinds.get(e['source']['kind'],0)+1
        self.assertEqual(8,kinds['hero_furniture']);self.assertEqual(10,kinds['hero_vegetation']);self.assertEqual(81,len(self.catalog['entries'])-18)
        for e in self.items:
            with self.subTest(e=e['id']):
                self.assertEqual([],fc.validate_chain(e,ROOT))
                self.assertTrue(e['id'].startswith('fur_hero_') and e['id'].endswith('_a'))
                self.assertEqual('street_furniture',e['category']);self.assertEqual('proposed',e['approval']);self.assertIsNone(e['approval_by'])
                self.assertEqual(['LOD0','LOD1'],list(e['lod_chain']['levels']));self.assertEqual({'LOD0','LOD1'},set(e['triangles']))
                self.assertTrue(0<e['triangles']['LOD1']<=240 and e['triangles']['LOD1']<e['triangles']['LOD0']<=1600)
                self.assertEqual('working-model-not-integrated',e['lod_chain']['distances_m']['status'])
                self.assertIn('cull',e['lod_chain']['distances_m']['beyond_lod1'])
                self.assertEqual({'generate_lods':False,'import_script':None},{k:e['lod_chain']['import_policy'][k] for k in ('generate_lods','import_script')})
                self.assertEqual(['mat_furniture_atlas'],e['materials'])
                self.assertAlmostEqual(0,e['dimensions_m']['bbox_min'][1],places=3)

    def test_no_logo_light_or_text_policy_in_records(self):
        for e in self.items:
            self.assertIn('no-light',e['tags']);self.assertIn('no-text',e['tags']);self.assertEqual('OPAQUE',e['lod_chain']['material_policy']['alpha_mode'])

    def test_update_keeps_existing_entries_and_user_fields(self):
        original=copy.deepcopy(self.catalog)
        for e in original['entries']:
            if e.get('source',{}).get('kind')=='hero_furniture':e.update(approval='approved',approval_by='user',approval_date='2026-10-27',user_note='Keep',user_custom={'choice':2})
        rebuilt=fc.update(original,ROOT);before={e['id']:e for e in original['entries']};self.assertEqual(len(before),len(rebuilt['entries']))
        protected=lambda a:{k:v for k,v in a.items() if k.startswith(('approval','user_'))}
        for e in rebuilt['entries']:
            old=before[e['id']]
            if e['source']['kind']!='hero_furniture':self.assertEqual(old,e)
            else:self.assertEqual(protected(old),protected(e))
        self.assertEqual(rebuilt,fc.update(rebuilt,ROOT))

    def test_id_collision_with_other_kind_is_refused(self):
        bad=copy.deepcopy(self.catalog);bad['entries'].append(dict(copy.deepcopy(self.items[0]),source={'kind':'kit'}))
        bad['entries'].remove(next(e for e in bad['entries'] if e['id']==self.items[0]['id'] and e['source']['kind']=='hero_furniture'))
        with self.assertRaises(ValueError):fc.update(bad,ROOT)

    def test_other_validators_ignore_furniture_kind(self):
        self.assertEqual([],hero_lods.validate_chain(self.items[0],ROOT));self.assertEqual([],vegetation_catalog.validate_chain(self.items[0],ROOT))
        self.assertEqual([],fc.validate_chain(next(e for e in self.catalog['entries'] if e['source']['kind']=='hero_vegetation'),ROOT))

    def test_routes_to_furniture_validator_only(self):
        errors=[];warnings=[]
        with mock.patch.object(validate_catalog.hero_lods,'validate_chain',side_effect=AssertionError('furniture misrouted to building validator')):
            with mock.patch.object(validate_catalog.vegetation_catalog,'validate_chain',side_effect=AssertionError('furniture misrouted to vegetation validator')):
                validate_catalog.check_entry(self.items[0],{'street_furniture'},str(ROOT),errors,warnings)
        self.assertEqual([],errors)

    def test_whole_catalog_validates_and_build_catalog_keeps_furniture(self):
        errors,_=validate_catalog.validate(self.catalog,str(ROOT),build_catalog.load_json(str(ROOT/build_catalog.MANIFEST)));self.assertEqual([],errors)
        merged=build_catalog.merge(build_catalog.load_json(str(ROOT/build_catalog.MANIFEST)),self.catalog,str(ROOT),'2026-10-27')
        self.assertEqual(self.catalog,merged)

    def test_geometry_hash_drift_fails(self):
        e=copy.deepcopy(self.items[0]);e['lod_chain']['levels']['LOD1']['sha256']='0'*64;self.assertTrue(fc.validate_chain(e,ROOT))
        e=copy.deepcopy(self.items[1]);e['glb_sha256']='0'*64;self.assertTrue(fc.validate_chain(e,ROOT))

    def test_dimension_and_triangle_drift_fail(self):
        e=copy.deepcopy(self.items[2]);e['dimensions_m']['height_above_ground']+=0.5;self.assertTrue(any('dimensions_m' in x for x in fc.validate_chain(e,ROOT)))
        e=copy.deepcopy(self.items[2]);e['triangles']['LOD0']+=1;self.assertTrue(any('triangles' in x for x in fc.validate_chain(e,ROOT)))

    def test_texture_drift_fails(self):
        e=copy.deepcopy(self.items[0]);e['lod_chain']['atlas']['sha256']='0'*64;self.assertTrue(fc.validate_chain(e,ROOT))

    def test_actual_atlas_byte_change_is_detected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);atlas=root/'assets/hero/furniture/furniture_atlas.png';atlas.write_bytes(atlas.read_bytes()+b'x')
            self.assertTrue(any('lod_chain' in x for x in fc.validate_chain(self.items[0],root)))

    def test_missing_and_corrupt_files_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:self.assertTrue(fc.validate_chain(self.items[0],Path(d)))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);(root/'assets/hero/furniture/fur_hero_bin_a_lod1.glb').unlink()
            self.assertTrue(fc.validate_chain(self.item('hero_bin'),root))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);(root/'assets/hero/furniture/fur_hero_bin_a_lod0.glb').write_bytes(b'not a glb at all')
            self.assertTrue(any('invalid furniture chain' in x for x in fc.validate_chain(self.item('hero_bin'),root)))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);glb=root/'assets/hero/furniture/fur_hero_bin_a_lod0.glb';glb.write_bytes(glb.read_bytes()[:60])
            self.assertTrue(fc.validate_chain(self.item('hero_bin'),root))

    def test_over_cap_lod_is_rejected_with_real_geometry(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);base=root/'assets/hero/furniture'
            shutil.copyfile(base/'fur_hero_bus_stop_a_lod0.glb',base/'fur_hero_bin_a_lod1.glb')  # 652 tris as a "LOD1"
            errors=fc.validate_chain(self.item('hero_bin'),root)
            self.assertTrue(any('LOD1 triangle budget exceeded' in x for x in errors),errors)

    def test_generate_lods_true_is_rejected(self):
        for family,level in (('hero_bench','lod0'),('hero_kiosk','lod1')):
            with self.subTest(family=family),tempfile.TemporaryDirectory() as d:
                root=self.copy_root(d);config=root/'assets/hero/furniture'/('fur_%s_a_%s.glb.import'%(family,level))
                config.write_text(config.read_text().replace('meshes/generate_lods=false','meshes/generate_lods=true'))
                self.assertTrue(any('generate_lods' in x for x in fc.validate_chain(self.item(family),root)))

    def test_all_imports_pin_generate_lods_false_without_post_import(self):
        for e in self.items:
            for level,stats in e['lod_chain']['levels'].items():
                params=fc.import_params((ROOT/stats['glb'].removeprefix('res://')).with_suffix('.glb.import'))
                self.assertEqual('false',params['meshes/generate_lods'],e['id']+level);self.assertEqual('""',params['import_script/path'])

    def test_post_import_script_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);config=root/'assets/hero/furniture/fur_hero_bench_a_lod1.glb.import'
            config.write_text(config.read_text().replace('import_script/path=""','import_script/path="res://x.gd"'))
            self.assertTrue(any('post-import' in x for x in fc.validate_chain(self.item('hero_bench'),root)))

    def test_proxy_level_or_file_is_rejected(self):
        e=copy.deepcopy(self.items[0]);e['triangles']['PROXY']=6;self.assertTrue(any('PROXY' in x for x in fc.validate_chain(e,ROOT)))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);(root/'assets/hero/furniture/fur_hero_bench_a_proxy.glb').write_text('x')
            self.assertTrue(any('proxy residue' in x for x in fc.validate_chain(self.item('hero_bench'),root)))

    def test_single_opaque_material_external_shared_atlas_in_every_glb(self):
        for e in self.items:
            for stats in e['lod_chain']['levels'].values():
                path=ROOT/stats['glb'].removeprefix('res://');g=glb_info.read_gltf_json(path)
                self.assertEqual(['furniture_atlas.png'],[i.get('uri') for i in g['images']]);self.assertTrue(all('bufferView' not in i for i in g['images']))
                self.assertEqual(1,len(g['materials']));self.assertNotIn(g['materials'][0].get('alphaMode'),('MASK','BLEND'));self.assertLess(path.stat().st_size,120000)

    def test_unknown_family_and_malformed_source_rejected(self):
        e=copy.deepcopy(self.items[0]);e['family']='hero_unknown';self.assertTrue(fc.validate_chain(e,ROOT))
        for bad in (None,'x',[]):
            e=copy.deepcopy(self.items[0]);e['source']=bad;self.assertTrue(any('source must be an object' in x for x in fc.validate_chain(e,ROOT)))

    PRE_T058_IDS=frozenset(['bld_civ_hall_a',
        'bld_civ_hall_b',
        'bld_civ_hall_c',
        'bld_hero_civ_hero_a',
        'bld_hero_civ_hero_b',
        'bld_hero_civ_hero_c',
        'bld_hero_com_bazaar_a',
        'bld_hero_com_bazaar_b',
        'bld_hero_com_bazaar_c',
        'bld_hero_ind_hero_a',
        'bld_hero_ind_hero_b',
        'bld_hero_ind_hero_c',
        'bld_hero_old_core_a',
        'bld_hero_old_core_b',
        'bld_hero_old_core_c',
        'bld_hero_res_house_a',
        'bld_hero_res_house_b',
        'bld_hero_res_house_c',
        'bld_hero_res_late_a',
        'bld_hero_res_late_b',
        'bld_hero_res_late_c',
        'bld_hero_res_mid_a',
        'bld_hero_res_mid_b',
        'bld_hero_res_mid_c',
        'bld_ind_heritage_a',
        'bld_ind_heritage_b',
        'bld_ind_shed_a',
        'bld_ind_shed_b',
        'bld_ind_shed_c',
        'bld_lmk_clocktower',
        'bld_res_house_a',
        'bld_res_house_b',
        'bld_res_house_c',
        'bld_res_house_d',
        'bld_res_house_e',
        'bld_res_late_a',
        'bld_res_late_a_gf',
        'bld_res_late_b',
        'bld_res_late_b_gf',
        'bld_res_late_c',
        'bld_res_mid_a',
        'bld_res_mid_a_gf',
        'bld_res_mid_b',
        'bld_res_mid_b_gf',
        'bld_res_mid_c',
        'bld_res_mid_c_gf',
        'bld_res_mid_d',
        'bld_res_mid_e',
        'bld_res_mid_e_gf',
        'bld_res_mid_f',
        'bld_res_mid_f_gf',
        'bld_res_mid_g',
        'bld_res_old_a',
        'bld_res_old_a_gf',
        'bld_res_old_b',
        'bld_res_old_c',
        'bld_res_old_c_gf',
        'bld_res_old_d',
        'bld_res_old_town_a',
        'bld_res_old_town_a_gf',
        'bld_res_old_town_b',
        'bld_res_old_town_c',
        'bld_res_old_town_c_gf',
        'gnd_tex_asphalt_new',
        'gnd_tex_asphalt_worn',
        'gnd_tex_beach_sand',
        'gnd_tex_dirt_courtyard',
        'gnd_tex_field_plowed',
        'gnd_tex_field_stubble',
        'gnd_tex_grass_dry',
        'gnd_tex_grass_green',
        'gnd_tex_gravel',
        'gnd_tex_olive_ground',
        'gnd_tex_plaza_stone_a',
        'gnd_tex_rock_cliff',
        'gnd_tex_scrub_maquis',
        'gnd_tex_sidewalk_cobble',
        'prop_chimney',
        'prop_human',
        'veg_hero_cypress_a',
        'veg_hero_hedge_a',
        'veg_hero_maquis_a',
        'veg_hero_olive_open_a',
        'veg_hero_olive_twisted_a',
        'veg_hero_palm_date_a',
        'veg_hero_palm_slender_a',
        'veg_hero_pine_brutia_a',
        'veg_hero_pine_stone_a',
        'veg_hero_plane_a',
        'veg_plane',
        'veh_car'])

    def test_ids_unique_new_and_follow_readme_naming(self):
        ids=[e['id'] for e in self.catalog['entries']];self.assertEqual(len(ids),len(set(ids)))
        old=self.PRE_T058_IDS;new={e['id'] for e in self.items}
        self.assertEqual(len(old),91)
        self.assertFalse(old&new,'new furniture ids must not collide with the 91 pre-T-058 ids')
        self.assertTrue(old<=set(ids),'every pre-T-058 id must still be in the catalog')
        self.assertEqual(set(ids)-old,new,'the only additions over the 91 old records are the furniture proposals')
        for i in new:self.assertRegex(i,r'^fur_hero_[a-z_]+_a$')


if __name__=='__main__':unittest.main()
