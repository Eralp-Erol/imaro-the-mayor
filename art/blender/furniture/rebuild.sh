#!/usr/bin/env bash
# Rebuild the complete street-furniture batch (T-058): atlas -> 8 assets x LOD0/LOD1 GLB -> Godot import with the
# generate_lods=false contract pinned -> catalog measurement/registration -> catalog validation.
# Needs Blender (IMARO_BLENDER_BIN), uv + pillow==11.3.0 and the project Godot (tools/godot.sh). One Godot at a time.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
furniture_blender_bin="${IMARO_BLENDER_BIN:-/Applications/Blender.app/Contents/MacOS/Blender}"
uv run --with pillow==11.3.0 python art/blender/furniture/atlas.py
"$furniture_blender_bin" --background --factory-startup --python-exit-code 1 --python art/blender/furniture/build.py
tools/godot.sh --headless --path . --editor --import --quit > artifacts/verify/t058/rebuild-import.log 2>&1
python3 art/blender/furniture/set_import.py
tools/godot.sh --headless --path . --editor --import --quit >> artifacts/verify/t058/rebuild-import.log 2>&1
python3 tools/library/furniture_catalog.py --write
python3 tools/library/validate_catalog.py
