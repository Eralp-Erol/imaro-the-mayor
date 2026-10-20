#!/bin/bash
# Kit'i baştan üretir: Blender (headless) -> .glb + manifest, import ayarları, Godot import. Kullanım:
#   art/blender/rebuild_kit.sh [--seed N] [--only res_mid,...]      (varsayılan seed 0, tüm modüller)
# Blender yolu: $BLENDER veya /Applications/Blender.app (4.5 LTS). --factory-startup zorunlu (kullanıcının eklentilerini yükleme).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
blender="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
[ -x "$blender" ] || { echo "Blender bulunamadı: $blender" >&2; exit 2; }
"$blender" --background --factory-startup --python "$root/art/blender/generators/build_kit.py" -- "$@" | grep -E "^(built|manifest)" 
python3 "$root/art/blender/set_import_params.py" || true
"$root/tools/godot.sh" --headless --path "$root" --editor --import --quit >/dev/null 2>&1
python3 "$root/art/blender/set_import_params.py"
"$root/tools/godot.sh" --headless --path "$root" --editor --import --quit >/dev/null 2>&1
"$root/tools/godot.sh" --headless --path "$root" -s res://assets/kit/validate_kit.gd 2>&1 | grep -E "FAIL|validate_kit"
