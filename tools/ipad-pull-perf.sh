#!/bin/bash
# T-076: iPad'de `--perf-log` ile yazılan ölçüm dosyalarını bilgisayara çeker (xcrun devicectl device copy from).
# Cihaz kimliği HARDCODE DEĞİL: --device veya IMARO_IPAD_DEVICE (ad, UDID, ECID, seri no, uuid; `xcrun devicectl list devices`).
# Bu betik yalnız dosya çeker/listeler; uygulamayı başlatmaz (başlatma örneği: --help).
#
# Kullanım:
#   tools/ipad-pull-perf.sh --device <kimlik> [--bundle <id>] [--source <yol>] [--dest <dizin>] [--list] [--dry-run]
#
# Ortam: IMARO_IPAD_DEVICE (cihaz), IMARO_IPAD_BUNDLE (varsayılan: export_presets.cfg iOS ön ayarındaki
# application/bundle_identifier), IMARO_IPAD_PERF_SOURCE (varsayılan Documents/perf).
#
# DOĞRULANMAMIŞ (gerçek cihazda denenmedi): Godot iOS `user://` dizininin uygulama kapsayıcısında nereye düştüğü.
# Varsayılan kaynak `Documents/perf` bir tahmindir; tutmazsa `--list` ile kapsayıcıyı gezin ve `--source` verin.
# Sözdizimi `xcrun devicectl device copy from --help` ve `device info files --help` çıktısından alındı (Xcode devicectl).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
device="${IMARO_IPAD_DEVICE:-}"
bundle="${IMARO_IPAD_BUNDLE:-}"
source_path="${IMARO_IPAD_PERF_SOURCE:-Documents/perf}"
dest=""
list_only=0
dry_run=0

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Cihazda ölçümü başlatma (bu betik yapmaz; sahip/Studio Director çalıştırır). Tam adımlar: production/tasks/T-076.md.
  tools/ios-install.sh --launch-only --device <kimlik> -- -- --demo --perf-log=demo-a1.json --perf-log-frames=6000
  (oyun bayrakları Godot'nun `--` ayracından sonra okunur; ayracın cihaza ulaşıp ulaşmadığı DOĞRULANMADI: ilk
   koşu sonrası rapordaki "args" alanı boşsa T-076 adım 4'teki ikinci varyantı deneyin. Argümansız yedek:
   DEVICECTL_CHILD_IMARO_PERF_LOG=1 ile başlatıp oyunu elle oynamak.)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --device) device="${2:?--device değer ister}"; shift 2 ;;
    --bundle) bundle="${2:?--bundle değer ister}"; shift 2 ;;
    --source) source_path="${2:?--source değer ister}"; shift 2 ;;
    --dest) dest="${2:?--dest değer ister}"; shift 2 ;;
    --list) list_only=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ipad-pull-perf: bilinmeyen argüman: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$device" ]; then
  echo "ipad-pull-perf: cihaz kimliği yok. --device <kimlik> ya da IMARO_IPAD_DEVICE verin (xcrun devicectl list devices)." >&2
  exit 2
fi

if [ -z "$bundle" ] && [ -f "$root/export_presets.cfg" ]; then
  # İlk iOS ön ayarının bundle kimliği (imza/takım bilgisi repoda yok; bundle kimliği gizli değil).
  bundle="$(awk '/^platform="iOS"/{ios=1} ios && /^application\/bundle_identifier=/{gsub(/.*="|"$/,""); print; exit}' \
    "$root/export_presets.cfg")"
fi
if [ -z "$bundle" ]; then
  echo "ipad-pull-perf: bundle kimliği bulunamadı. --bundle <id> ya da IMARO_IPAD_BUNDLE verin." >&2
  exit 2
fi

if [ -z "$dest" ]; then
  dest="$root/artifacts/perf/ipad-$(date +%Y%m%d-%H%M%S)"
fi

run() {
  if [ "$dry_run" = "1" ]; then
    printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

if [ "$dry_run" = "0" ] && ! command -v xcrun >/dev/null 2>&1; then
  echo "ipad-pull-perf: xcrun yok (Xcode komut satırı araçları gerekli)." >&2
  exit 3
fi

if [ "$list_only" = "1" ]; then
  # Kapsayıcıyı gez: --source kökten başlayarak alt dizin (boş = kök).
  sub="${source_path%/*}"
  [ "$sub" = "$source_path" ] && sub=""
  args=(xcrun devicectl device info files --device "$device" --domain-type appDataContainer
        --domain-identifier "$bundle")
  [ -n "$sub" ] && args+=(--subdirectory "$sub")
  run "${args[@]}"
  exit $?
fi

if [ "$dry_run" = "0" ]; then mkdir -p "$dest"; fi
echo "ipad-pull-perf: cihaz=$device bundle=$bundle kaynak=$source_path -> $dest" >&2
run xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
  --domain-identifier "$bundle" --source "$source_path" --destination "$dest"
if [ "$dry_run" = "0" ]; then
  echo "ipad-pull-perf: bitti. Çekilen: $dest (kontrol: ls -la '$dest')" >&2
fi
