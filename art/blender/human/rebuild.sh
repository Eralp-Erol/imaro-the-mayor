#!/usr/bin/env bash
# Rebuild the complete human style batch (T-059): atlas -> 6 proposals x LOD0/LOD1 GLB -> Godot import with the
# generate_lods=false contract pinned -> catalog measurement/registration -> catalog validation.
# Needs Blender (IMARO_BLENDER_BIN), uv + pillow==11.3.0 and the project Godot (tools/godot.sh). One Godot at a time.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
human_blender_bin="${IMARO_BLENDER_BIN:-/Applications/Blender.app/Contents/MacOS/Blender}"
mkdir -p artifacts/verify/t059
uv run --with pillow==11.3.0 python art/blender/human/atlas.py
"$human_blender_bin" --background --factory-startup --python-exit-code 1 --python art/blender/human/build.py
tools/godot.sh --headless --path . --editor --import --quit > artifacts/verify/t059/rebuild-import.log 2>&1
python3 art/blender/human/set_import.py
tools/godot.sh --headless --path . --editor --import --quit >> artifacts/verify/t059/rebuild-import.log 2>&1
python3 tools/library/human_catalog.py --write
python3 tools/library/validate_catalog.py
