#!/bin/bash
# Library contact sheets (T-052): catalog -> design/library/sheets/<category>-NN.png (Blender headless + Pillow).
# Usage: tools/library/render_sheets.sh [--category building ...] [--force] [--rows 6] [--size 288]
# Needs Blender 4.5 (env BLENDER or /Applications/Blender.app) and python3 with Pillow.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
python3 -I tools/library/build_catalog.py --check || { echo "render_sheets: catalog is stale; run python3 tools/library/build_catalog.py --write" >&2; exit 1; }
exec python3 tools/library/render_sheets.py "$@"
