#!/usr/bin/env bash
# Rebuild the complete shared-atlas vegetation batch; single-species rebuilds
# cannot safely reset the atlas used by all eight source-derived impostors.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
vegetation_blender_bin="${IMARO_BLENDER_BIN:-/Applications/Blender.app/Contents/MacOS/Blender}"
uv run --with pillow==11.3.0 python art/blender/vegetation/atlas.py
"$vegetation_blender_bin" --background --factory-startup --python art/blender/vegetation/build.py -- --base-only
"$vegetation_blender_bin" --background --factory-startup --python art/blender/vegetation/bake_proxies.py
uv run --with pillow==11.3.0 python art/blender/vegetation/pack_proxies.py
"$vegetation_blender_bin" --background --factory-startup --python art/blender/vegetation/build.py -- --proxy-only
python3 tools/library/vegetation_catalog.py --write
python3 tools/library/validate_catalog.py
