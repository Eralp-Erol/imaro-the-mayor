"""Pin the Godot import contract of the human GLBs: meshes/generate_lods=false, no post-import script (T-057 contract);
the shared atlas imports with mipmaps.
python3 art/blender/human/set_import.py   (run after the first `tools/godot.sh --headless --path . --editor --import --quit`,
then import again). Idempotent; only touches the one key.
"""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[3]
changed=0
for path in sorted((ROOT/'assets/hero/human').glob('hum_hero_*.glb.import')):
    text=path.read_text();new=re.sub(r'^meshes/generate_lods=.*$','meshes/generate_lods=false',text,flags=re.M)
    if new!=text:path.write_text(new);changed+=1
atlas=ROOT/'assets/hero/human/human_atlas.png.import'
if atlas.exists():
    text=atlas.read_text();new=re.sub(r'^mipmaps/generate=.*$','mipmaps/generate=true',text,flags=re.M)
    if new!=text:atlas.write_text(new);changed+=1
print('human import params pinned; changed',changed)
