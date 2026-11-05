#!/bin/bash
# Export hattı (T-007; ADR-0004). Bash 3.2 uyumlu.
#   tools/export.sh <macos|windows|ios> [--release]   -> build/<platform>/<debug|release>/…
#   tools/export.sh smoke macos [--release]           dışa aktarılan .app'i boş duman sahnesiyle çalıştırır, logu tarar
#   tools/export.sh templates                         şablon durumu (çıkış 0 = macos+windows+ios hepsi var, 4 = eksik)
#   tools/export.sh install-templates <tpz>           elle indirilmiş .tpz'yi SHA-512 doğrulayıp kurar (İNDİRMEZ)
# Çıkış kodları: 0 ok · 1 export/duman başarısız · 2 kullanım/ikili yok · 3 Godot sürümü uyumsuz (godot.sh) ·
#                4 export şablonu yok/yanlış sürüm · 5 SHA-512/boyut doğrulaması başarısız ·
#                6 iOS: IMARO_IOS_TEAM_ID yok/geçersiz veya ikon dosyası yok.
# Şablon İNDİRİLMEZ: indirme kullanıcı onayı gerektirir; eksikse net talimatla 4 ile çıkar.
# İmza kimliği / takım kimliği / provisioning ASLA bu betikte veya export_presets.cfg'de tutulmaz (iOS: T-008).
# iOS (B-060/B-061): takım kimliği YALNIZ ortamdan gelir (IMARO_IOS_TEAM_ID, 10 karakter A-Z0-9; Apple Developer ->
#   Membership). export_presets.cfg'de BOŞ kalır; export süresince Godot'nun kimlik bilgisi dosyasına
#   (.godot/export_credentials.cfg, gitignored) yazılır, çıkışta silinir.
#   İkon: preset `icons/icon_1024x1024` yer tutucu yolundaysa tools/ios-placeholder-icon.py export öncesi üretir
#   (gerçek ikon sahibin kararı); başka bir yola işaret ediyorsa o dosya var olmalı.
# Ana sahne: project.godot run/main_scene = duman sahnesi (test/CI), run/main_scene.template = oyun (dışa aktarılan
#   TÜM ikililer: macOS/Windows/iOS). `smoke macos` duman sahnesini .app içine geçici override.cfg yazarak seçer.
# Ortam: IMARO_EXPORT_TEMPLATES_DIR (şablon kökünü değiştirir; test), IMARO_NO_WINDOW=1 (smoke başsız),
#        IMARO_EXPORT_IMPORT=1 (export öncesi `--import` zorla), IMARO_SMOKE_TIMEOUT (sn, varsayılan 60),
#        IMARO_IOS_TEAM_ID (yalnız ios export; zorunlu).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"

VERSION_DIR="4.7.2.stable"
TPZ_NAME="Godot_v4.7.2-stable_export_templates.tpz"
TPZ_URL="https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$TPZ_NAME"
TPZ_SIZE=1281349702
TEMPLATES_ROOT="${IMARO_EXPORT_TEMPLATES_DIR:-$HOME/Library/Application Support/Godot/export_templates}"
TEMPLATE_DIR="$TEMPLATES_ROOT/$VERSION_DIR"
APP_NAME="ImaroTheMayor"
SMOKE_SCENE="res://src/app/platform_profile_smoke.tscn"
IOS_PLACEHOLDER_ICON="res://build/ios/placeholder-icon.png"

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# .tools ana checkout'ta durur (worktree'de de aynı yere bak): godot.sh ile aynı çözümleme.
main_checkout() {
  local common
  if common="$(cd "$root" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)"; then dirname "$common"; else echo "$root"; fi
}
sums_file() {
  local m; m="$(main_checkout)"
  for f in "$m/.tools/SHA512-SUMS.txt" "$root/.tools/SHA512-SUMS.txt"; do [ -f "$f" ] && { echo "$f"; return; }; done
  return 1
}
expected_sha512() { local f; f="$(sums_file)" || return 1; awk -v n="$TPZ_NAME" '$2==n {print $1}' "$f"; }

# platform -> şablon dosyaları (TEMPLATE_DIR altında)
required_templates() {
  case "$1" in
    macos) echo "macos.zip" ;;
    windows) echo "windows_debug_x86_64.exe windows_release_x86_64.exe" ;;
    ios) echo "ios.zip" ;;
  esac
}

print_template_help() {
  local sha; sha="$(expected_sha512 2>/dev/null || true)"
  {
    echo "export.sh: Godot $VERSION_DIR export şablonu eksik: $TEMPLATE_DIR"
    echo "  Şablon indirmesi KULLANICI ONAYI gerektirir; bu betik indirmez."
    echo "  Resmî kaynak : $TPZ_URL"
    echo "  Dosya        : $TPZ_NAME (~1,19 GiB = $TPZ_SIZE bayt)"
    echo "  Beklenen SHA-512 (resmî sürüm listesi, .tools/SHA512-SUMS.txt): ${sha:-<SUMS dosyası bulunamadı>}"
    echo "  İndirdikten sonra: tools/export.sh install-templates <indirilen>/$TPZ_NAME"
  } >&2
}

# Çıkış 4: eksik. Boşlukları olan yollar için döngü.
check_templates() {
  local platform="$1" missing=0 f
  if [ ! -f "$TEMPLATE_DIR/version.txt" ] || [ "$(tr -d '[:space:]' <"$TEMPLATE_DIR/version.txt")" != "$VERSION_DIR" ]; then missing=1; fi
  for f in $(required_templates "$platform"); do [ -f "$TEMPLATE_DIR/$f" ] || missing=1; done
  if [ "$missing" = 1 ]; then print_template_help; return 4; fi
  return 0
}

cmd_templates() {
  local rc=0 p f
  echo "şablon dizini: $TEMPLATE_DIR"
  if [ -f "$TEMPLATE_DIR/version.txt" ]; then echo "version.txt  : $(tr -d '[:space:]' <"$TEMPLATE_DIR/version.txt") (beklenen $VERSION_DIR)"; else echo "version.txt  : YOK"; fi
  for p in macos windows ios; do
    for f in $(required_templates "$p"); do
      if [ -f "$TEMPLATE_DIR/$f" ]; then echo "  $p: $f var"; else echo "  $p: $f YOK"; rc=4; fi
    done
  done
  if [ -f "$TEMPLATE_DIR/version.txt" ] && [ "$(tr -d '[:space:]' <"$TEMPLATE_DIR/version.txt")" != "$VERSION_DIR" ]; then rc=4; fi
  [ "$rc" = 0 ] || print_template_help
  return "$rc"
}

cmd_install_templates() {
  local tpz="${1:-}" want size got tmp
  [ -n "$tpz" ] && [ -f "$tpz" ] || { echo "export.sh: install-templates <$TPZ_NAME yolu> gerekli (dosya bulunamadı: ${tpz:-<boş>})" >&2; exit 2; }
  want="$(expected_sha512)" || { echo "export.sh: .tools/SHA512-SUMS.txt yok; doğrulama yapılamaz, kurulum reddedildi" >&2; exit 5; }
  [ -n "$want" ] || { echo "export.sh: SUMS içinde $TPZ_NAME satırı yok; kurulum reddedildi" >&2; exit 5; }
  size="$(stat -f%z "$tpz" 2>/dev/null || stat -c%s "$tpz")"
  if [ "$size" != "$TPZ_SIZE" ]; then echo "export.sh: boyut $size, beklenen $TPZ_SIZE; kurulum reddedildi" >&2; exit 5; fi
  echo "SHA-512 hesaplanıyor (≈1,2 GiB)…"
  got="$(shasum -a 512 "$tpz" | awk '{print $1}')"
  if [ "$got" != "$want" ]; then echo "export.sh: SHA-512 uyuşmuyor (alınan $got, beklenen $want); kurulum reddedildi" >&2; exit 5; fi
  echo "SHA-512 doğrulandı."
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/imaro-tpl.XXXXXX")"
  unzip -q "$tpz" -d "$tmp"
  [ -f "$tmp/templates/version.txt" ] && [ "$(tr -d '[:space:]' <"$tmp/templates/version.txt")" = "$VERSION_DIR" ] \
    || { echo "export.sh: arşivdeki version.txt $VERSION_DIR değil; kurulum reddedildi" >&2; rm -rf "$tmp"; exit 5; }
  mkdir -p "$TEMPLATES_ROOT"; rm -rf "$TEMPLATE_DIR"; mv "$tmp/templates" "$TEMPLATE_DIR"; rm -rf "$tmp"
  echo "kuruldu: $TEMPLATE_DIR"
  cmd_templates
}

preset_of() { case "$1" in macos) echo "macOS" ;; windows) echo "Windows" ;; ios) echo "iOS" ;; esac; }
artifact_of() { case "$1" in macos) echo "$APP_NAME.app" ;; windows) echo "$APP_NAME.exe" ;; ios) echo "$APP_NAME.ipa" ;; esac; }

ensure_import() {
  mkdir -p build; [ -f build/.gdignore ] || : >build/.gdignore   # build/ içi editör taramasına girmesin
  if [ "${IMARO_EXPORT_IMPORT:-0}" = 1 ] || [ ! -d .godot/imported ]; then
    echo "import: .godot/imported yok veya zorlandı; --import çalışıyor…"
    tools/godot.sh --headless --path "$root" --import >"build/import.log" 2>&1 || { echo "export.sh: import başarısız (build/import.log)" >&2; return 1; }
  fi
}

# iOS ön kontrolleri (B-060/B-061): takım kimliği ortamdan, ikon dosyası var/üretilebilir. Çıkış 6.
ios_preflight() {
  local icon
  if [ -z "${IMARO_IOS_TEAM_ID:-}" ]; then
    echo "export.sh: iOS export için IMARO_IOS_TEAM_ID gerekli (Apple Developer takım kimliği, 10 karakter A-Z0-9)." >&2
    echo "  Repoya yazılmaz; örn.: IMARO_IOS_TEAM_ID=ABCDE12345 tools/export.sh ios" >&2
    exit 6
  fi
  case "$IMARO_IOS_TEAM_ID" in
    *[!A-Z0-9]*) echo "export.sh: IMARO_IOS_TEAM_ID geçersiz (yalnız A-Z0-9 bekleniyor)." >&2; exit 6 ;;
  esac
  if [ "${#IMARO_IOS_TEAM_ID}" != 10 ]; then echo "export.sh: IMARO_IOS_TEAM_ID 10 karakter olmalı." >&2; exit 6; fi
  icon="$(sed -n 's/^icons\/icon_1024x1024="\(.*\)"$/\1/p' export_presets.cfg | head -n1)"
  if [ -z "$icon" ]; then echo "export.sh: export_presets.cfg iOS ön ayarında icons/icon_1024x1024 yok." >&2; exit 6; fi
  if [ "$icon" = "$IOS_PLACEHOLDER_ICON" ]; then
    mkdir -p build/ios
    python3 -I tools/ios-placeholder-icon.py "build/ios/placeholder-icon.png" >/dev/null \
      || { echo "export.sh: yer tutucu ikon üretilemedi" >&2; exit 6; }
    echo "ikon: YER TUTUCU (gerçek ikon DEĞİL; sahip ikonu bekliyor) — build/ios/placeholder-icon.png"
  else
    [ -f "$root/${icon#res://}" ] || { echo "export.sh: ikon dosyası yok: $icon" >&2; exit 6; }
    echo "ikon: $icon"
  fi
}

# Takım kimliğini Godot'nun KENDİ kimlik bilgisi dosyasıyla (.godot/export_credentials.cfg; gitignored, izlenen hiçbir
# dosya değişmez) yalnız export süresince verir; çıkışta silinir (editörün kendi dosyası varsa yedeklenip geri konur).
# Preset indeksi export_presets.cfg'den ada göre bulunur. B-062: preset'te takım kimliği BOŞ kalır (test zorlar).
CRED_FILE=".godot/export_credentials.cfg"
CRED_BAK=".godot/export_credentials.cfg.imaro-bak"
CRED_MARK="; imaro-export-temp: tools/export.sh yazar ve siler"
ios_cleanup_credentials() {
  if [ -f "$CRED_FILE" ] && head -n1 "$CRED_FILE" | grep -q '^; imaro-export-temp'; then rm -f "$CRED_FILE"; fi
  if [ -f "$CRED_BAK" ]; then mv -f "$CRED_BAK" "$CRED_FILE"; fi
}
ios_write_credentials() {
  local idx
  idx="$(awk '/^\[preset\.[0-9]+\]$/ {gsub(/[^0-9]/, "", $0); cur=$0} /^name="iOS"$/ {print cur; exit}' export_presets.cfg)"
  [ -n "$idx" ] || { echo "export.sh: export_presets.cfg içinde iOS ön ayarı bulunamadı" >&2; exit 1; }
  mkdir -p .godot
  if [ -f "$CRED_FILE" ] && ! head -n1 "$CRED_FILE" | grep -q '^; imaro-export-temp' && [ ! -f "$CRED_BAK" ]; then cp -p "$CRED_FILE" "$CRED_BAK"; fi
  trap ios_cleanup_credentials EXIT
  ( umask 077; printf '%s\n[preset.%s.options]\n\napplication/app_store_team_id="%s"\n' "$CRED_MARK" "$idx" "$IMARO_IOS_TEAM_ID" >"$CRED_FILE" )
  echo "takım kimliği: ortamdan, yalnız export süresince ($CRED_FILE; repoda yok)"
}

cmd_export() {
  local platform="$1" kind="$2" preset out_dir out log rc=0 flag errs
  preset="$(preset_of "$platform")"
  check_templates "$platform" || exit $?
  if [ "$platform" = ios ]; then ios_preflight; fi
  ensure_import || exit 1
  out_dir="build/$platform/$kind"; out="$out_dir/$(artifact_of "$platform")"; log="build/$platform/export-$kind.log"
  rm -rf "$out_dir"; mkdir -p "$out_dir"
  flag="--export-debug"; [ "$kind" = release ] && flag="--export-release"
  if [ "$platform" = ios ]; then ios_write_credentials; fi
  tools/godot.sh --headless --path "$root" "$flag" "$preset" "$out" >"$log" 2>&1 || rc=$?
  if [ "$rc" = 2 ] || [ "$rc" = 3 ]; then cat "$log" >&2; exit "$rc"; fi   # godot.sh: ikili yok / sürüm uyumsuz
  errs="$(grep -c -E '^(ERROR|SCRIPT ERROR):' "$log" || true)"
  if [ "$rc" != 0 ]; then echo "export.sh: $platform $kind export BAŞARISIZ (godot çıkış $rc; $errs ERROR satırı) — $log" >&2; grep -E '^(ERROR|SCRIPT ERROR):' "$log" | head -n 8 >&2 || true; exit 1; fi
  if [ ! -e "$out" ] && ! ls "$out_dir"/*.xcodeproj >/dev/null 2>&1; then
    echo "export.sh: $platform $kind: çıktı yok ($out) — $log" >&2; exit 1
  fi
  if [ "$errs" != 0 ]; then echo "export.sh: $platform $kind: godot 0 döndü ama logda $errs ERROR satırı var — $log" >&2; grep -E '^(ERROR|SCRIPT ERROR):' "$log" | head -n 8 >&2; exit 1; fi
  echo "export ok: $out_dir ($(du -sh "$out_dir" | awk '{print $1}')) log: $log"
}

cmd_smoke() {
  local platform="$1" kind="$2" app bin log secs pid rc=0 waited=0 extra=""
  if [ "$platform" != macos ]; then
    echo "export.sh smoke: yalnız macos bu makinede çalıştırılabilir. windows .exe için Windows cihazı, ios için iPad (T-008) gerekir: DOĞRULANMADI." >&2; exit 2
  fi
  app="build/macos/$kind/$APP_NAME.app"
  bin="$(ls "$app"/Contents/MacOS/* 2>/dev/null | head -n1 || true)"
  [ -n "$bin" ] && [ -x "$bin" ] || { echo "export.sh smoke: $app bulunamadı/çalıştırılamaz; önce: tools/export.sh macos $([ "$kind" = release ] && echo --release)" >&2; exit 1; }
  log="build/macos/smoke-$kind.log"; secs="${IMARO_SMOKE_TIMEOUT:-60}"
  [ "${IMARO_NO_WINDOW:-0}" = 1 ] && extra="--headless"
  # Sahne yolu argümanı verilemez (şablon "path override" desteklemez, 4.7.2'de doğrulandı) ve dışa aktarılan
  # ikilinin ana sahnesi artık oyun (run/main_scene.template). Duman sahnesi, .app içine (build/, gitignored)
  # yazılan geçici override.cfg ile seçilir; çıkışta silinir.
  SMOKE_OVERRIDE="$(dirname "$bin")/override.cfg"
  printf '[application]\n\nrun/main_scene.template="%s"\n' "$SMOKE_SCENE" >"$SMOKE_OVERRIDE"
  trap 'rm -f "$SMOKE_OVERRIDE"' EXIT
  "$bin" $extra >"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then kill "$pid" 2>/dev/null || true; echo "export.sh smoke: ${secs}s zaman aşımı — $log" >&2; exit 1; fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid" || rc=$?
  if [ "$rc" != 0 ]; then echo "export.sh smoke: çıkış $rc — $log" >&2; tail -n 12 "$log" >&2; exit 1; fi
  if ! grep -q '^IMARO_SMOKE_OK' "$log"; then echo "export.sh smoke: IMARO_SMOKE_OK satırı yok — $log" >&2; exit 1; fi
  if grep -q -E '^(ERROR|SCRIPT ERROR):' "$log"; then echo "export.sh smoke: logda ERROR satırı var — $log" >&2; grep -E '^(ERROR|SCRIPT ERROR):' "$log" | head -n 8 >&2; exit 1; fi
  echo "smoke ok ($kind): $(grep '^IMARO_SMOKE renderer' "$log" | head -n1) — $log"
}

# --- ayrıştırma ---
[ $# -ge 1 ] || usage
sub="$1"; shift
case "$sub" in
  templates) cmd_templates ;;
  install-templates) cmd_install_templates "${1:-}" ;;
  smoke|macos|windows|ios)
    kind=debug; platform="$sub"
    if [ "$sub" = smoke ]; then platform="${1:-}"; [ -n "$platform" ] || usage; shift; fi
    case "$platform" in macos|windows|ios) ;; *) usage ;; esac
    for a in "$@"; do
      case "$a" in --release) kind=release ;; *) echo "export.sh: bilinmeyen argüman '$a'" >&2; usage ;; esac
    done
    if [ "$sub" = smoke ]; then cmd_smoke "$platform" "$kind"; else cmd_export "$platform" "$kind"; fi ;;
  *) usage ;;
esac
