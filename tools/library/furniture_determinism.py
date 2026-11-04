#!/usr/bin/env python3
"""T-058 determinism proof: run art/blender/furniture/rebuild.sh twice for real and compare sha256 of every output.
python3 tools/library/furniture_determinism.py   -> artifacts/verify/t058/determinism.json (exit 1 on any difference)
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'artifacts/verify/t058/determinism.json'


def snapshot():
    files=sorted((ROOT/'assets/hero/furniture').glob('fur_hero_*.glb'))+[ROOT/'assets/hero/furniture/furniture_atlas.png',ROOT/'assets/hero/furniture/atlas_layout.json',ROOT/'data/library/catalog.json']
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


def main():
    runs=[]
    for i in range(2):
        result=subprocess.run(['bash','art/blender/furniture/rebuild.sh'],cwd=ROOT,capture_output=True,text=True)
        if result.returncode:print(result.stdout[-3000:],result.stderr[-3000:]);return 1
        runs.append(snapshot())
    differing=[k for k in runs[0] if runs[0][k]!=runs[1].get(k)]
    report={'command':'bash art/blender/furniture/rebuild.sh (x2, real runs)','files_compared':len(runs[0]),'glb_files':sum(k.endswith('.glb') for k in runs[0]),
            'identical':not differing,'differing':differing,'run1':runs[0],'run2':runs[1]}
    OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(report,indent=2)+'\n')
    print('determinism: %d files, identical=%s'%(len(runs[0]),not differing));return 0 if not differing else 1


if __name__=='__main__':sys.exit(main())
