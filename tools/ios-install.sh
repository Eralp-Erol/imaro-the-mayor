#!/bin/bash
# iPad/iPhone kurulum hattı (B-060). Bash 3.2 uyumlu. Export -> xcodebuild -> devicectl kurulum -> başlatma.
#   tools/ios-install.sh --device <UDID|ad> [--release] [--no-export] [--register-device]   derle + kur + başlat
#   tools/ios-install.sh --build-only [--release] [--no-export]                              yalnız derle (imzasız, cihaz GEREKMEZ)
#   tools/ios-install.sh --list-devices                                                       xcrun devicectl list devices
#   tools/ios-install.sh --launch-only --device <id> [-- <uygulama argümanları>]               kurulu uygulamayı başlat
#     Bu betiğin ilk `--` işareti yutulur; kalanı AYNEN `devicectl ... process launch <bundle>` sonuna eklenir
#     (örn. `-- -- --demo --perf-log` -> devicectl'e `-- --demo --perf-log`). Godot oyun bayraklarını yalnız kendi `--`
#     ayracından sonra okur; devicectl'in `--`'yi yutup yutmadığı cihazda DOĞRULANMADI (production/tasks/T-076.md
#     adım 4 iki varyantı dener). Ortam değişkeni: DEVICECTL_CHILD_<AD>=<değer>.
# Ortam (repoya YAZILMAZ; varsayılan sabit yok):
#   IMARO_IOS_TEAM_ID  Apple Developer takım kimliği (10 karakter A-Z0-9). --list-devices dışında zorunlu.
#   IMARO_IOS_DEVICE   cihaz kimliği/adı (--device yerine). Kurulum/başlatma için zorunlu.
#   IMARO_IOS_BUNDLE_ID  varsayılan com.imaro.themayor (export_presets.cfg ile aynı olmalı).
# --register-device: xcodebuild'e -allowProvisioningDeviceRegistration verir (cihazı geliştirici hesabına KAYDEDER;
#   yalnız cihaz sahibinin onayıyla, ilk kurulumda). --allowProvisioningUpdates her zaman verilir (otomatik imza).
# Çıkış: 0 ok · 1 derleme/kurulum/başlatma hatası · 2 kullanım/araç yok · 6 takım kimliği/cihaz eksik/geçersiz.
# DURUM: gerçek cihaza kurulum bu betikle henüz TEST EDİLMEDİ (--build-only derlemesi doğrulandı); bkz. tools/README.md.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"

BUNDLE_ID="${IMARO_IOS_BUNDLE_ID:-com.imaro.themayor}"
SCHEME="ImaroTheMayor"
mode=install; kind=debug; do_export=1; register=0; device="${IMARO_IOS_DEVICE:-}"
launch_args=()

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --device) [ $# -ge 2 ] || usage; device="$2"; shift 2 ;;
    --release) kind=release; shift ;;
    --no-export) do_export=0; shift ;;
    --register-device) register=1; shift ;;
    --build-only) mode=build; shift ;;
    --launch-only) mode=launch; shift ;;
    --list-devices) mode=list; shift ;;
    -h|--help) usage ;;
    --) shift; launch_args=("$@"); break ;;
    *) echo "ios-install.sh: bilinmeyen argüman '$1'" >&2; usage ;;
  esac
done

command -v xcrun >/dev/null 2>&1 || { echo "ios-install.sh: xcrun yok (Xcode gerekli)" >&2; exit 2; }
if [ "$mode" = list ]; then exec xcrun devicectl list devices; fi

need_team() {
  if [ -z "${IMARO_IOS_TEAM_ID:-}" ]; then
    echo "ios-install.sh: IMARO_IOS_TEAM_ID gerekli (10 karakter A-Z0-9; repoya yazılmaz)." >&2; exit 6
  fi
  case "$IMARO_IOS_TEAM_ID" in *[!A-Z0-9]*) echo "ios-install.sh: IMARO_IOS_TEAM_ID geçersiz." >&2; exit 6 ;; esac
  [ "${#IMARO_IOS_TEAM_ID}" = 10 ] || { echo "ios-install.sh: IMARO_IOS_TEAM_ID 10 karakter olmalı." >&2; exit 6; }
}
need_device() {
  if [ -z "$device" ]; then
    echo "ios-install.sh: cihaz gerekli: --device <UDID|ad> veya IMARO_IOS_DEVICE. Liste: tools/ios-install.sh --list-devices" >&2; exit 6
  fi
}

config=Debug; [ "$kind" = release ] && config=Release
proj_dir="build/ios/$kind"
derived="build/ios/derived-$kind"
app="$derived/Build/Products/$config-iphoneos/$SCHEME.app"

launch() {
  echo "başlatılıyor: $BUNDLE_ID"
  xcrun devicectl device process launch --device "$device" --terminate-existing "$BUNDLE_ID" \
    ${launch_args[@]+"${launch_args[@]}"}
}

if [ "$mode" = launch ]; then need_device; launch; exit 0; fi

need_team
[ "$mode" = build ] || need_device

if [ "$do_export" = 1 ]; then
  if [ "$kind" = release ]; then tools/export.sh ios --release; else tools/export.sh ios; fi
fi
[ -d "$proj_dir/$SCHEME.xcodeproj" ] || { echo "ios-install.sh: $proj_dir/$SCHEME.xcodeproj yok; önce tools/export.sh ios (veya --no-export'u kaldır)" >&2; exit 1; }

mkdir -p build/ios
build_log="build/ios/xcodebuild-$kind.log"
echo "xcodebuild: $config ($build_log)"
if [ "$mode" = build ]; then
  # İmzasız derleme: yalnız derlemenin çalıştığını gösterir; cihaza kurulabilir paket DEĞİL.
  xcodebuild -project "$proj_dir/$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration "$config" \
    -destination 'generic/platform=iOS' -derivedDataPath "$derived" \
    DEVELOPMENT_TEAM="$IMARO_IOS_TEAM_ID" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$build_log" 2>&1 \
    || { echo "ios-install.sh: xcodebuild BAŞARISIZ — $build_log" >&2; grep -E "error:" "$build_log" | head -n 8 >&2 || true; exit 1; }
  echo "derleme ok (imzasız, KURULMAZ): $app"
  exit 0
fi

reg_flag=""; [ "$register" = 1 ] && reg_flag="-allowProvisioningDeviceRegistration"
# shellcheck disable=SC2086
xcodebuild -project "$proj_dir/$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration "$config" \
  -destination "id=$device" -derivedDataPath "$derived" \
  DEVELOPMENT_TEAM="$IMARO_IOS_TEAM_ID" -allowProvisioningUpdates $reg_flag build >"$build_log" 2>&1 \
  || { echo "ios-install.sh: xcodebuild BAŞARISIZ — $build_log" >&2; grep -E "error:" "$build_log" | head -n 8 >&2 || true
       echo "  İlk kurulumda cihaz hesaba kayıtlı değilse --register-device ekle (cihaz sahibinin onayıyla)." >&2; exit 1; }
[ -d "$app" ] || { echo "ios-install.sh: derlenen .app bulunamadı: $app" >&2; exit 1; }

echo "kuruluyor: $app -> $device"
xcrun devicectl device install app --device "$device" "$app"
launch
