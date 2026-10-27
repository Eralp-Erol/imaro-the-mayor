#!/usr/bin/env bash
# Rebuild the complete shared-atlas vegetation batch (T-057 Karar 5 chain).
# atlas (upper 512 rows regenerated; lower rows carried forward byte-equal)
#  -> base-only (LOD0+LOD1, 10 species) -> palm proxy (2 x 40 tri) -> catalog.
# The eight non-palm species have no single-tree proxy; there is no bake/pack step any more.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
vegetation_blender_bin="${IMARO_BLENDER_BIN:-/Applications/Blender.app/Contents/MacOS/Blender}"
uv run --with pillow==11.3.0 python art/blender/vegetation/atlas.py
"$vegetation_blender_bin" --background --factory-startup --python-exit-code 1 --python art/blender/vegetation/build.py -- --base-only
"$vegetation_blender_bin" --background --factory-startup --python-exit-code 1 --python art/blender/vegetation/build.py -- --proxy-only
python3 tools/library/vegetation_catalog.py --write
python3 tools/library/validate_catalog.py
