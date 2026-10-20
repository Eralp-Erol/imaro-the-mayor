#!/bin/bash
# Kanon bütünlüğü: design/foundation/ manifest.json SHA-256 değerleriyle birebir eşleşmeli.
# Foundation değiştirilemez (design/CANON.md). Çıkış: 0 = sağlam, 1 = değişmiş/eksik dosya.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/design/foundation"
[ -f "$dir/manifest.json" ] || { echo "canon-check: manifest.json yok" >&2; exit 1; }
cd "$dir"
expected=$(jq '.files|length' manifest.json)
if out=$(jq -r '.files[]|"\(.sha256)  \(.path)"' manifest.json | shasum -a 256 -c - 2>&1); then
  echo "canon-check: $expected/$expected dosya manifestle eşleşiyor"
else
  echo "canon-check: FOUNDATION DEĞİŞMİŞ veya EKSİK" >&2
  echo "$out" | grep -v ': OK$' >&2
  exit 1
fi
# Manifest dışı eklenmiş dosya da kanonu kirletir.
extra=$(find . -type f ! -name manifest.json ! -name .DS_Store | sed 's|^\./||' | sort | comm -23 - <(jq -r '.files[].path' manifest.json | sort))
if [ -n "$extra" ]; then echo "canon-check: manifest dışı dosya: $extra" >&2; exit 1; fi
