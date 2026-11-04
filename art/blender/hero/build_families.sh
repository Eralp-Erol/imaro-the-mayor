#!/bin/bash
# T-054: atlases + GLBs for all hero families.  usage: art/blender/hero/build_families.sh [family]
cd "$(dirname "$0")/../../.." || exit 1
export PYTHONDONTWRITEBYTECODE=1
B=/Applications/Blender.app/Contents/MacOS/Blender
python3 art/blender/hero/fam_atlas.py assets/hero/fam "$1" || exit 1
for fam in bazaar res_mid res_late house industrial civic; do
  [ -n "$1" ] && [ "$1" != "$fam" ] && continue
  for v in a b c; do
    echo -n "$fam $v: "
    $B --background --factory-startup --python art/blender/hero/fam_build.py -- --family $fam --variant $v \
      --atlas assets/hero/fam/${fam}_$v.png --layout assets/hero/fam/${fam}_layout.json --out assets/hero/fam/hero_${fam}_$v.glb 2>&1 | grep -E "HERO_TRIS|Error|Traceback|File \"/Users.*fam_|Error:" | head -5
  done
done
