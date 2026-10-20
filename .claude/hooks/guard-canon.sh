#!/bin/bash
# PreToolUse: design/foundation/ değiştirilemez kanondur. Yazma/düzenleme ve onu değiştirebilecek shell komutlarını reddeder.
# Mantık canon_guard.py içinde (yol normalleştirme, cd/değişken/glob izleme). Arkasında post-canon-verify.sh
# (PostToolUse) yolu metinde görünmeyen dolaylı değişiklikleri yakalar ve HEAD'den geri yükler.
here="$(cd "$(dirname "$0")" && pwd)"
py="$(command -v python3.14 || command -v python3)"
[ -n "$py" ] || exit 0
exec "$py" -I "$here/canon_guard.py"
