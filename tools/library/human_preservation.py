#!/usr/bin/env python3
"""T-059 preservation proof: the 99 pre-existing catalog records and the building/vegetation/furniture/ground assets stay byte-equal.
python3 tools/library/human_preservation.py --snapshot   # before the human batch: writes pre.json
python3 tools/library/human_preservation.py --compare    # after: writes preservation.json, exit 1 on any change
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'artifacts/verify/t059'
PROTECTED=['assets/hero/fam','assets/hero/lod','assets/hero/vegetation','assets/hero/furniture','assets/ground','assets/models','assets/hero/hero_a.glb','assets/hero/hero_b.glb','assets/hero/hero_c.glb','assets/hero/hero_f.glb']
SUFFIXES=('.glb','.png','.json')


def files():
    result={}
    for item in PROTECTED:
        base=ROOT/item
        for path in ([base] if base.is_file() else sorted(base.rglob('*'))):
            if path.is_file() and path.suffix in SUFFIXES and '_experiment' not in str(path):
                result[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def snapshot():
    catalog=json.loads((ROOT/'data/library/catalog.json').read_text())
    return {'entries':{e['id']:e for e in catalog['entries']},'files':files()}


def main():
    p=argparse.ArgumentParser();p.add_argument('--snapshot',action='store_true');p.add_argument('--compare',action='store_true');a=p.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    if a.snapshot:
        (OUT/'pre.json').write_text(json.dumps(snapshot(),sort_keys=True));print('snapshot',len(snapshot()['entries']),'entries',len(snapshot()['files']),'files');return 0
    pre=json.loads((OUT/'pre.json').read_text());now=snapshot()
    changed_entries=[i for i,e in pre['entries'].items() if now['entries'].get(i)!=e]
    changed_files=[f for f,h in pre['files'].items() if now['files'].get(f)!=h]
    report={'pre_entries':len(pre['entries']),'entries_byte_equal':len(pre['entries'])-len(changed_entries),'changed_entries':changed_entries,
            'new_entries':sorted(set(now['entries'])-set(pre['entries'])),'protected_files':len(pre['files']),'changed_files':changed_files,
            'files_byte_equal':len(pre['files'])-len(changed_files),'pass':not changed_entries and not changed_files}
    (OUT/'preservation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));return 0 if report['pass'] else 1


if __name__=='__main__':sys.exit(main())
