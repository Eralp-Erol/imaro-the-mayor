"""T-059 human style proposals: real asset integrity, ownership, routing and negative drift/budget/import/content cases."""
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
import human_catalog as hc
import furniture_catalog
import validate_catalog
import glb_info
import hero_lods
import vegetation_catalog


class HumanCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
        cls.items=[e for e in cls.catalog['entries'] if e.get('source',{}).get('kind')=='hero_human']

    def item(self,family):return next(e for e in self.items if e['family']==family)

    def copy_root(self,folder):
        root=Path(folder);shutil.copytree(ROOT/'assets/hero/human',root/'assets/hero/human',ignore=shutil.ignore_patterns('*.gd','*.tscn','*.uid'))
        return root

    def test_six_proposals_twelve_measured_lods_and_total_count(self):
        self.assertEqual(6,len(self.items))
        self.assertEqual(sorted('hero_'+n for n in hc.NAMES),sorted(e['family'] for e in self.items))
        self.assertEqual({'pawn','block','facet'},{n.split('_')[0] for n in hc.NAMES});self.assertEqual({'neutral','broad'},{n.split('_')[1] for n in hc.NAMES})
        self.assertEqual(99+6,len(self.catalog['entries']))
        for e in self.items:
            with self.subTest(e=e['id']):
                self.assertEqual([],hc.validate_chain(e,ROOT))
                self.assertRegex(e['id'],r'^hum_hero_(pawn|block|facet)_(neutral|broad)_a$')
                self.assertEqual('human',e['category']);self.assertIn(e['approval'],('proposed','approved','rejected'));self.assertEqual('user' if e['approval']!='proposed' else None,e['approval_by']);self.assertTrue(e['approval']=='proposed' or e['approval_date'])  # D-005: user decisions are legitimate; invariant = decided => user-signed+dated, proposed => unsigned
                self.assertEqual(['LOD0','LOD1'],list(e['lod_chain']['levels']));self.assertEqual({'LOD0','LOD1'},set(e['triangles']))
                self.assertTrue(0<e['triangles']['LOD1']<=100 and e['triangles']['LOD1']<e['triangles']['LOD0']<=900)
                self.assertEqual('working-model-not-integrated',e['lod_chain']['distances_m']['status']);self.assertIn('cull',e['lod_chain']['distances_m']['beyond_lod1'])
                self.assertEqual({'generate_lods':False,'import_script':None},{k:e['lod_chain']['import_policy'][k] for k in ('generate_lods','import_script')})
                self.assertEqual(['mat_human_atlas'],e['materials']);self.assertAlmostEqual(0,e['dimensions_m']['bbox_min'][1],places=3)
                self.assertAlmostEqual(1.75,e['dimensions_m']['height_above_ground'],delta=0.02)

    def test_same_height_two_ratios_and_style_order_of_cost(self):
        tris={e['family']:e['triangles']['LOD0'] for e in self.items}
        self.assertLess(tris['hero_pawn_neutral'],tris['hero_block_neutral']);self.assertLess(tris['hero_block_neutral'],tris['hero_facet_neutral'])
        for style in hc.STYLES:
            n=self.item('hero_%s_neutral'%style);b=self.item('hero_%s_broad'%style)
            self.assertGreater(b['dimensions_m']['width_x'],n['dimensions_m']['width_x']+0.03)
            self.assertAlmostEqual(n['dimensions_m']['height_above_ground'],b['dimensions_m']['height_above_ground'],places=3)

    def test_policy_tags_and_no_forbidden_content(self):
        for e in self.items:
            for tag in ('no-face','no-logo','no-text','anonymous','neutral-palette'):self.assertIn(tag,e['tags'])
            self.assertEqual('OPAQUE',e['lod_chain']['material_policy']['alpha_mode'])
            self.assertEqual([],hc.content_errors(e))

    def test_forbidden_content_is_rejected(self):
        for mutate in (lambda e:e['tags'].append('uniform'),lambda e:e['tags'].append('season:summer'),lambda e:e.update(label_tr='Üniformalı görevli'),
                       lambda e:e.update(user_note='hijab variant'),lambda e:e['tags'].remove('no-face'),lambda e:e.update(label_tr='adlı karakter Imaro')):
            e=copy.deepcopy(self.items[0]);mutate(e);self.assertTrue(hc.validate_chain(e,ROOT),'forbidden content accepted')

    def test_update_keeps_existing_entries_and_user_fields(self):
        original=copy.deepcopy(self.catalog)
        for e in original['entries']:
            if e.get('source',{}).get('kind')=='hero_human':e.update(approval='approved',approval_by='user',approval_date='2026-10-27',user_note='Keep',user_custom={'choice':2})
        rebuilt=hc.update(original,ROOT);before={e['id']:e for e in original['entries']};self.assertEqual(len(before),len(rebuilt['entries']))
        protected=lambda a:{k:v for k,v in a.items() if k.startswith(('approval','user_'))}
        for e in rebuilt['entries']:
            old=before[e['id']]
            if e['source']['kind']!='hero_human':self.assertEqual(old,e)
            else:self.assertEqual(protected(old),protected(e))
        self.assertEqual(rebuilt,hc.update(rebuilt,ROOT))

    def test_id_collision_with_other_kind_is_refused(self):
        bad=copy.deepcopy(self.catalog);bad['entries'].append(dict(copy.deepcopy(self.items[0]),source={'kind':'kit'}))
        bad['entries'].remove(next(e for e in bad['entries'] if e['id']==self.items[0]['id'] and e['source']['kind']=='hero_human'))
        with self.assertRaises(ValueError):hc.update(bad,ROOT)

    def test_other_validators_ignore_human_kind(self):
        self.assertEqual([],hero_lods.validate_chain(self.items[0],ROOT));self.assertEqual([],vegetation_catalog.validate_chain(self.items[0],ROOT))
        self.assertEqual([],furniture_catalog.validate_chain(self.items[0],ROOT))
        self.assertEqual([],hc.validate_chain(next(e for e in self.catalog['entries'] if e['source']['kind']=='hero_furniture'),ROOT))

    def test_routes_to_human_validator_only(self):
        errors=[];warnings=[]
        with mock.patch.object(validate_catalog.hero_lods,'validate_chain',side_effect=AssertionError('human misrouted to building validator')):
            with mock.patch.object(validate_catalog.vegetation_catalog,'validate_chain',side_effect=AssertionError('misrouted to vegetation')):
                with mock.patch.object(validate_catalog.furniture_catalog,'validate_chain',side_effect=AssertionError('misrouted to furniture')):
                    validate_catalog.check_entry(self.items[0],{'human'},str(ROOT),errors,warnings)
        self.assertEqual([],errors)

    def test_whole_catalog_validates_and_build_catalog_keeps_humans(self):
        errors,_=validate_catalog.validate(self.catalog,str(ROOT),build_catalog.load_json(str(ROOT/build_catalog.MANIFEST)));self.assertEqual([],errors)
        merged=build_catalog.merge(build_catalog.load_json(str(ROOT/build_catalog.MANIFEST)),self.catalog,str(ROOT),'2026-10-27')
        self.assertEqual(self.catalog,merged)

    def test_geometry_hash_drift_fails(self):
        e=copy.deepcopy(self.items[0]);e['lod_chain']['levels']['LOD1']['sha256']='0'*64;self.assertTrue(hc.validate_chain(e,ROOT))
        e=copy.deepcopy(self.items[1]);e['glb_sha256']='0'*64;self.assertTrue(hc.validate_chain(e,ROOT))

    def test_dimension_and_triangle_drift_fail(self):
        e=copy.deepcopy(self.items[2]);e['dimensions_m']['height_above_ground']+=0.5;self.assertTrue(any('dimensions_m' in x for x in hc.validate_chain(e,ROOT)))
        e=copy.deepcopy(self.items[2]);e['triangles']['LOD0']+=1;self.assertTrue(any('triangles' in x for x in hc.validate_chain(e,ROOT)))

    def test_texture_drift_fails(self):
        e=copy.deepcopy(self.items[0]);e['lod_chain']['atlas']['sha256']='0'*64;self.assertTrue(hc.validate_chain(e,ROOT))

    def test_actual_atlas_byte_change_is_detected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);atlas=root/'assets/hero/human/human_atlas.png';atlas.write_bytes(atlas.read_bytes()+b'x')
            self.assertTrue(any('lod_chain' in x for x in hc.validate_chain(self.items[0],root)))

    def test_missing_and_corrupt_files_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:self.assertTrue(hc.validate_chain(self.items[0],Path(d)))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);(root/'assets/hero/human/hum_hero_block_neutral_a_lod1.glb').unlink()
            self.assertTrue(hc.validate_chain(self.item('hero_block_neutral'),root))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);(root/'assets/hero/human/hum_hero_block_neutral_a_lod0.glb').write_bytes(b'not a glb at all')
            self.assertTrue(any('invalid human chain' in x for x in hc.validate_chain(self.item('hero_block_neutral'),root)))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);glb=root/'assets/hero/human/hum_hero_block_neutral_a_lod0.glb';glb.write_bytes(glb.read_bytes()[:60])
            self.assertTrue(hc.validate_chain(self.item('hero_block_neutral'),root))

    def test_over_cap_lod_is_rejected_with_real_geometry(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);base=root/'assets/hero/human'
            shutil.copyfile(base/'hum_hero_facet_neutral_a_lod0.glb',base/'hum_hero_block_neutral_a_lod1.glb')  # 654 tris as a "LOD1"
            errors=hc.validate_chain(self.item('hero_block_neutral'),root)
            self.assertTrue(any('LOD1 triangle budget exceeded' in x for x in errors),errors)

    def test_lod1_outside_lod0_envelope_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);base=root/'assets/hero/human'
            shutil.copyfile(base/'hum_hero_block_broad_a_lod1.glb',base/'hum_hero_pawn_neutral_a_lod1.glb')  # 98 tris, but broader than the pawn LOD0
            errors=hc.validate_chain(self.item('hero_pawn_neutral'),root)
            self.assertTrue(any('envelope' in x for x in errors),errors)

    def test_generate_lods_true_is_rejected(self):
        for family,level in (('hero_block_neutral','lod0'),('hero_facet_broad','lod1')):
            with self.subTest(family=family),tempfile.TemporaryDirectory() as d:
                root=self.copy_root(d);config=root/'assets/hero/human'/('hum_%s_a_%s.glb.import'%(family,level))
                config.write_text(config.read_text().replace('meshes/generate_lods=false','meshes/generate_lods=true'))
                self.assertTrue(any('generate_lods' in x for x in hc.validate_chain(self.item(family),root)))

    def test_all_imports_pin_generate_lods_false_without_post_import(self):
        for e in self.items:
            for level,stats in e['lod_chain']['levels'].items():
                params=hc.import_params((ROOT/stats['glb'].removeprefix('res://')).with_suffix('.glb.import'))
                self.assertEqual('false',params['meshes/generate_lods'],e['id']+level);self.assertEqual('""',params['import_script/path'])

    def test_post_import_script_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);config=root/'assets/hero/human/hum_hero_pawn_broad_a_lod1.glb.import'
            config.write_text(config.read_text().replace('import_script/path=""','import_script/path="res://x.gd"'))
            self.assertTrue(any('post-import' in x for x in hc.validate_chain(self.item('hero_pawn_broad'),root)))

    def test_proxy_level_or_file_is_rejected(self):
        e=copy.deepcopy(self.items[0]);e['triangles']['PROXY']=6;self.assertTrue(any('PROXY' in x for x in hc.validate_chain(e,ROOT)))
        with tempfile.TemporaryDirectory() as d:
            root=self.copy_root(d);(root/'assets/hero/human/hum_hero_pawn_neutral_a_proxy.glb').write_text('x')
            self.assertTrue(any('proxy residue' in x for x in hc.validate_chain(self.item('hero_pawn_neutral'),root)))

    def test_single_opaque_material_external_shared_atlas_in_every_glb(self):
        for e in self.items:
            for stats in e['lod_chain']['levels'].values():
                path=ROOT/stats['glb'].removeprefix('res://');g=glb_info.read_gltf_json(path)
                self.assertEqual(['human_atlas.png'],[i.get('uri') for i in g['images']]);self.assertTrue(all('bufferView' not in i for i in g['images']))
                self.assertEqual(1,len(g['materials']));self.assertNotIn(g['materials'][0].get('alphaMode'),('MASK','BLEND'));self.assertLess(path.stat().st_size,60000)

    def patch_glb_json(self,path,mutate):
        import struct
        data=path.read_bytes();clen=struct.unpack('<I',data[12:16])[0];g=json.loads(data[20:20+clen]);mutate(g)
        raw=json.dumps(g).encode();raw+=b' '*((-len(raw))%4);rest=data[20+clen:]
        path.write_bytes(data[:8]+struct.pack('<I',20+len(raw)+len(rest))+struct.pack('<II',len(raw),0x4E4F534A)+raw+rest)

    def test_emissive_or_light_glb_is_rejected_even_when_catalog_is_regenerated(self):
        def emissive(g):g['materials'][0]['emissiveFactor']=[1,1,1]
        def light(g):g['extensionsUsed']=g.get('extensionsUsed',[])+['KHR_lights_punctual'];g['extensions']={'KHR_lights_punctual':{'lights':[{'type':'point'}]}}
        def node_light(g):g['nodes'][0].setdefault('extensions',{})['KHR_lights_punctual']={'light':0}
        for mutate in (emissive,light,node_light):
            with tempfile.TemporaryDirectory() as d:
                root=self.copy_root(d);self.patch_glb_json(root/'assets/hero/human/hum_hero_block_neutral_a_lod0.glb',mutate)
                e=copy.deepcopy(self.item('hero_block_neutral'))
                # the catalog is re-measured from the tampered file, so only the content rule can catch it
                e.update(hc.entry(root,'block_neutral'))
                errors=hc.validate_chain(e,root)
                self.assertTrue(any('emissive' in x or 'light' in x for x in errors),errors)
        self.assertEqual([],hc.light_errors(glb_info.read_gltf_json(ROOT/'assets/hero/human/hum_hero_block_neutral_a_lod0.glb')))

    def test_forbidden_word_in_notes_is_rejected(self):
        e=copy.deepcopy(self.items[0]);e['notes']='üniformalı logo';self.assertTrue(any('forbidden content word' in x for x in hc.content_errors(e)))
        e=copy.deepcopy(self.items[0]);e['notes']='hijab';self.assertTrue(hc.validate_chain(e,ROOT))

    def test_unknown_family_and_malformed_source_rejected(self):
        e=copy.deepcopy(self.items[0]);e['family']='hero_unknown';self.assertTrue(hc.validate_chain(e,ROOT))
        for bad in (None,'x',[]):
            e=copy.deepcopy(self.items[0]);e['source']=bad;self.assertTrue(any('source must be an object' in x for x in hc.validate_chain(e,ROOT)))

    # The 99 records that existed before T-059 (embedded on purpose: the test must not depend on gitignored artifacts).
    PRE_T059_IDS=frozenset([
        'bld_civ_hall_a',
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
        'fur_hero_bench_a',
        'fur_hero_bike_rack_a',
        'fur_hero_bin_a',
        'fur_hero_bollard_a',
        'fur_hero_bus_stop_a',
        'fur_hero_kiosk_a',
        'fur_hero_lamp_street_a',
        'fur_hero_planter_a',
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
        old=self.PRE_T059_IDS;new={e['id'] for e in self.items}
        self.assertEqual(len(old),99)
        self.assertFalse(old&new);self.assertTrue(old<=set(ids),'every pre-T-059 id must still be in the catalog')
        self.assertEqual(set(ids)-old,new,'the only additions over the 99 old records are the human proposals')


if __name__=='__main__':unittest.main()
