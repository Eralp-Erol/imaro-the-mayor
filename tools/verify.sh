#!/bin/bash
# Doğrulama hattı. Kullanım: tools/verify.sh <quick|full>
#   quick: canon-check, studio-check, gdlint, import, GdUnit4 (başsız, ~25 sn)
#   full : quick + canon-guard (C-07 savunma testi, ~50 sn) + pencereli runtime smoke (project.godot'taki run/main_scene; yoksa veya IMARO_NO_WINDOW=1 ise skip)
# Çıktı: insan okur adım satırları (stdout), artifacts/verify/<mode>-latest.json, artifacts/verify/*.log
# Çıkış: 0 = hepsi geçti, 1 = en az bir adım fail, 2 = kullanım hatası.
set -euo pipefail
mode="${1:-}"
case "$mode" in quick|full) ;; *) echo "kullanım: tools/verify.sh <quick|full>" >&2; exit 2 ;; esac

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/artifacts/verify"
mkdir -p "$out"
godot="$root/tools/godot.sh"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git_head="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
fingerprint="$("$root/tools/fingerprint.sh")"
rows="$(mktemp)"; trap 'rm -f "$rows"' EXIT
overall=pass
SUMMARY=""

# Godot günlüğünde hata sayılan satırlar; BENIGN_RE ile bilinen zararsızlar süzülür.
# (Şu an bilinen zararsız yok: import ve runtime günlükleri temiz çıkıyor. Eklenirse buraya, gerekçesiyle.)
BENIGN_RE='NOPE_NEVER_MATCHES'
strip_ansi() { perl -pe 's/\e\[[0-9;?]*[A-Za-z]//g' "$1"; }
scan_errors() { strip_ansi "$1" | grep -E 'SCRIPT ERROR|Parse Error|(^|[^A-Za-z])ERROR:' | grep -Ev "$BENIGN_RE" || true; }

# run_to <saniye> <log> <komut...>: zaman aşımlı çalıştırır, çıktıyı log'a yazar, kodu döndürür.
run_to() {
  local secs="$1" log="$2" pid watcher rc=0; shift 2
  "$@" >"$log" 2>&1 & pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 & watcher=$!
  wait "$pid" || rc=$?
  pkill -P "$watcher" 2>/dev/null || true
  kill "$watcher" 2>/dev/null || true
  { wait "$watcher"; } 2>/dev/null || true
  return "$rc"
}

# step <ad> <fonksiyon>: fonksiyon 0=pass, 77=skip, diğer=fail döner; SUMMARY'yi doldurur.
step() {
  local name="$1" fn="$2" t0 rc=0 status
  SUMMARY=""; t0="$(date +%s)"
  "$fn" || rc=$?
  case "$rc" in 0) status=pass ;; 77) status=skip ;; *) status=fail; overall=fail ;; esac
  printf '%-4s %-22s %3ss  %s\n' "$(echo "$status" | tr a-z A-Z)" "$name" "$(( $(date +%s) - t0 ))" "$SUMMARY"
  printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$(( $(date +%s) - t0 ))" "$SUMMARY" >>"$rows"
}

s_canon() {
  if [ ! -x tools/canon-check.sh ]; then SUMMARY="tools/canon-check.sh yok veya çalıştırılamaz"; return 77; fi
  SUMMARY="$(tools/canon-check.sh 2>&1 | tail -n1)"; [ "${PIPESTATUS[0]}" = 0 ]
}

s_canon_guard() {
  SUMMARY="$(tools/test-canon-guard.sh 2>&1 | tail -n 3 | tr '\n' ' ' | cut -c1-200)"
  tools/test-canon-guard.sh >/dev/null 2>&1
}

s_studio() {
  SUMMARY="$(python3.14 -I tools/studio_check.py 2>&1 | tr '\n' ' ' | cut -c1-300)"
  python3.14 -I tools/studio_check.py >/dev/null 2>&1
}

s_lint() {
  command -v uvx >/dev/null || { SUMMARY="uvx yok"; return 1; }
  local rc=0 dirs=() d
  for d in src tests; do [ -d "$d" ] && dirs+=("$d"); done   # addons/ kasıtlı olarak dışarıda
  [ ${#dirs[@]} -gt 0 ] || { SUMMARY="lint edilecek dizin yok"; return 77; }
  uvx --from gdtoolkit==4.5.0 gdlint "${dirs[@]}" >"$out/lint.log" 2>&1 || rc=$?
  SUMMARY="$(tail -n1 "$out/lint.log")"; return "$rc"
}

s_import() {
  local rc=0
  run_to 180 "$out/import.log" "$godot" --headless --path "$root" --editor --import --quit || rc=$?
  local errs; errs="$(scan_errors "$out/import.log")"
  if [ "$rc" != 0 ]; then SUMMARY="Godot çıkış $rc"; return 1; fi
  if [ -n "$errs" ]; then SUMMARY="$(echo "$errs" | wc -l | tr -d ' ') hata satırı: $(echo "$errs" | head -n1)"; return 1; fi
  SUMMARY="içe aktarma temiz"
}

s_unit() {
  local rc=0 errs
  rm -rf "$out/gdunit"
  # -d (debugger) kullanılmaz: parse hatasında Godot "debug>" isteminde asılı kalabiliyor.
  run_to 300 "$out/unit.log" "$godot" --headless --path "$root" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    -a res://tests -c --ignoreHeadlessMode -rd artifacts/verify/gdunit -rc 1 || rc=$?
  SUMMARY="$(strip_ansi "$out/unit.log" | grep 'Overall Summary' | head -n1 | sed 's/Overall Summary: //')"
  # Çıkış kodu tek başına güvenilmez: GdUnit4 çöktüğünde de 0 dönebiliyor (2026-10-20 E2E-B bulgusu).
  errs="$(strip_ansi "$out/unit.log" | grep -E 'Abnormal exit|SCRIPT ERROR|Parse Error' | head -n1)"
  if [ -z "$SUMMARY" ]; then SUMMARY="GdUnit4 özeti yok (çıkış $rc) ${errs}"; return 1; fi
  if [ -n "$errs" ]; then SUMMARY="$SUMMARY · $errs"; return 1; fi
  # 101 = yalnızca uyarı: geçer. 0 = temiz.
  case "$rc" in 0) ;; 101) SUMMARY="$SUMMARY (uyarılar)" ;; *) SUMMARY="$SUMMARY (çıkış $rc)"; return 1 ;; esac
}

# Pencereli adımlar ortak: no-window kontrolü, günlükte SCRIPT ERROR taraması.
no_window() { [ "${IMARO_NO_WINDOW:-0}" = 1 ] && { SUMMARY="IMARO_NO_WINDOW=1"; return 0; }; return 1; }

s_runtime() {
  no_window && return 77
  local main; main="$(grep -E '^run/main_scene=' project.godot 2>/dev/null || true)"
  if [ -z "$main" ]; then SUMMARY="no main scene yet"; return 77; fi
  local rc=0
  run_to 120 "$out/runtime.log" "$godot" --path "$root" --quit-after 180 || rc=$?
  local errs; errs="$(scan_errors "$out/runtime.log")"
  if [ "$rc" != 0 ]; then SUMMARY="Godot çıkış $rc"; return 1; fi
  if [ -n "$errs" ]; then SUMMARY="$(echo "$errs" | wc -l | tr -d ' ') hata satırı: $(echo "$errs" | head -n1)"; return 1; fi
  SUMMARY="180 kare hatasız"
}

echo "verify $mode · head ${git_head:0:9} · fingerprint ${fingerprint:0:12}"
step canon-check s_canon
step studio-check s_studio
step gdlint s_lint
step import s_import
step unit-gdunit s_unit
if [ "$mode" = full ]; then
  step canon-guard s_canon_guard
  step runtime-smoke s_runtime
fi

jq -R -s --arg mode "$mode" --arg started "$started_at" --arg head "$git_head" --arg fp "$fingerprint" --arg result "$overall" '
  {mode: $mode, started_at: $started, git_head: $head, fingerprint: $fp,
   steps: (split("\n") | map(select(length > 0) | split("\t")
          | {name: .[0], status: .[1], seconds: (.[2] | tonumber), summary: (.[3] // "")})),
   result: $result}' "$rows" >"$out/$mode-latest.json"
echo "SONUÇ: $overall · rapor: artifacts/verify/$mode-latest.json"
[ "$overall" = pass ]
