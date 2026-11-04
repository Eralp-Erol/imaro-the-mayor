"""T-056 real asset integrity and negative-path tests; never mutates production assets."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/library'))
import hero_lods


class HeroLODTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
        cls.heroes=[e for e in cls.catalog['entries'] if e.get('family') in hero_lods.FAMILY_MAP and e.get('source',{}).get('kind')=='hero']

    def test_all_twenty_one_chains_measured_and_budgeted(self):
        self.assertEqual(21,len(self.heroes))
        for entry in self.heroes:
            with self.subTest(entry=entry['id']):
                self.assertIn('lod_chain',entry)
                self.assertEqual([],hero_lods.validate_chain(entry,ROOT))
                levels=entry['lod_chain']['levels']
                self.assertLess(levels['LOD1']['triangles'],levels['LOD0']['triangles'])
                self.assertLess(levels['PROXY']['triangles'],levels['LOD1']['triangles'])

    def test_regeneration_preserves_all_user_fields_and_unrelated_entries(self):
        original=copy.deepcopy(self.catalog)
        for e in original['entries']:
            if e.get('family') in hero_lods.FAMILY_MAP:
                e.update(approval='approved',approval_by='user',approval_date='2026-10-26',user_note='Keep this',user_custom={'decision':'yes'})
        rebuilt=hero_lods.update(original,ROOT)
        for before,after in zip(original['entries'],rebuilt['entries']):
            protected=lambda e:{k:v for k,v in e.items() if k.startswith(('approval','user_'))}
            self.assertEqual(protected(before),protected(after))
            if before.get('family') not in hero_lods.FAMILY_MAP: self.assertEqual(before,after)
        self.assertEqual(rebuilt,hero_lods.update(rebuilt,ROOT))

    def test_geometry_hash_drift_is_rejected(self):
        entry=copy.deepcopy(self.heroes[0])
        entry['lod_chain']['levels']['LOD1']['sha256']='0'*64
        self.assertTrue(hero_lods.validate_chain(entry,ROOT))

    def test_wrong_count_rejected(self):
        entry=copy.deepcopy(self.heroes[0]);entry['triangles']['LOD1']=10000
        self.assertTrue(hero_lods.validate_chain(entry,ROOT))

    def test_approval_does_not_extend_to_new_lods(self):
        entry=copy.deepcopy(self.heroes[0]);entry['lod_chain']['status']='approved'
        self.assertTrue(hero_lods.validate_chain(entry,ROOT))

    def test_missing_asset_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertTrue(hero_lods.validate_chain(self.heroes[0],Path(d)))

    def test_changed_atlas_hash_rejected(self):
        entry=copy.deepcopy(self.heroes[0]);entry['lod_chain']['atlas']['sha256']='0'*64
        self.assertTrue(hero_lods.validate_chain(entry,ROOT))


if __name__=='__main__': unittest.main()
