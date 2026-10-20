#!/bin/bash
# Godot ikilisini bulur, sürümünü doğrular ve argümanlarla çalıştırır (exec).
# Sıra: $IMARO_GODOT -> <ana checkout>/.tools/Godot.app -> /Applications/Godot.app
# --path otomatik EKLENMEZ; çağıran verir.  Kullanım: tools/godot.sh --print-path | tools/godot.sh <godot args>
# Çıkış: 2 = ikili bulunamadı, 3 = sürüm uyumsuz (IMARO_GODOT_ALLOW_VERSION_MISMATCH=1 ile geçilir).
set -euo pipefail
REQUIRED_VERSION="4.7.2.stable"

resolve() {
  if [ -n "${IMARO_GODOT:-}" ]; then echo "$IMARO_GODOT"; return; fi
  local here common main
  here="$(cd "$(dirname "$0")/.." && pwd)"
  # Worktree'de .git bir dosyadır; ortak git dizininin üstü ana checkout'tur.
  if common="$(cd "$here" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)"; then
    main="$(dirname "$common")"
    if [ -x "$main/.tools/Godot.app/Contents/MacOS/Godot" ]; then
      echo "$main/.tools/Godot.app/Contents/MacOS/Godot"; return
    fi
  fi
  echo "/Applications/Godot.app/Contents/MacOS/Godot"
}

GODOT="$(resolve)"
if [ ! -x "$GODOT" ]; then
  echo "godot.sh: Godot bulunamadı: $GODOT (IMARO_GODOT ile belirtin)" >&2; exit 2
fi
if [ "${1:-}" = "--print-path" ]; then echo "$GODOT"; exit 0; fi

if [ "${IMARO_GODOT_ALLOW_VERSION_MISMATCH:-0}" != "1" ]; then
  version="$("$GODOT" --version 2>/dev/null | head -n1 || true)"
  case "$version" in
    "$REQUIRED_VERSION"*) ;;
    *) echo "godot.sh: sürüm '$version', beklenen '$REQUIRED_VERSION.*' ($GODOT). Geçmek için IMARO_GODOT_ALLOW_VERSION_MISMATCH=1" >&2; exit 3 ;;
  esac
fi
exec "$GODOT" "$@"
