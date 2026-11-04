#!/bin/bash
# Doğrulama hattı. Kullanım: tools/verify.sh <quick|full>
#   quick: canon-check, studio-check, area-map, gdlint, import + GdUnit4'ün YALNIZ DEĞİŞEN ALAN testleri ve her zaman koşan
#          "koruma çekirdeği" (tools/verify-areas.tsv, tools/verify-scope.sh). Hedef <= 5 dk. Atlanan testler her koşunun
#          sonunda açıkça yazılır; quick PASS tam doğrulama DEĞİLDİR (JSON'da scope=changed-areas).
#   full : quick'in tüm adımları, ama GdUnit4'ün TÜM testleri (scope=full) + canon-guard (C-07 savunma testi)
#          + pencereli runtime smoke (project.godot'taki run/main_scene; yoksa veya IMARO_NO_WINDOW=1 ise skip). Milestone/teslim.
# Çıktı: insan okur adım satırları (stdout), artifacts/verify/<mode>-latest.json, artifacts/verify/*.log
# Durum: artifacts/verify/quick-base = son BAŞARILI (quick veya full) doğrulamanın HEAD'i; sonraki quick'in "değişen" tabanı.
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
  local rc=0 log="$out/canon-guard.log"
  tools/test-canon-guard.sh >"$log" 2>&1 || rc=$?
  SUMMARY="$(tail -n 3 "$log" | tr '\n' ' ' | cut -c1-200)"
  return "$rc"
}

s_studio() {
  SUMMARY="$(python3.14 -I tools/studio_check.py 2>&1 | tr '\n' ' ' | cut -c1-300)"
  python3.14 -I tools/studio_check.py >/dev/null 2>&1
}

s_areamap() {
  local rc=0
  tools/verify-scope.sh check >"$out/area-map.log" 2>&1 || rc=$?
  SUMMARY="$(tail -n1 "$out/area-map.log")"; return "$rc"
}

s_lint() {
  command -v uvx >/dev/null || { SUMMARY="uvx yok"; return 1; }
  local rc=0 dirs=() d files=() f
  if [ "$mode" = quick ] && ! grep -qx 'gdlintrc' "$scope_dir/changed.txt"; then
    # quick: yalnız değişen .gd dosyaları (tüm ağaç ~50 sn; değişmeyen dosyanın lint sonucu kendiliğinden değişmez). full tümünü tarar.
    while IFS= read -r f; do
      case "$f" in src/*.gd|tests/*.gd) [ -f "$f" ] && files+=("$f") ;; esac
    done <"$scope_dir/changed.txt"
    if [ ${#files[@]} -eq 0 ]; then SUMMARY="değişen .gd yok (tüm ağaç: verify full)"; return 0; fi
    uvx --from gdtoolkit==4.5.0 gdlint "${files[@]}" >"$out/lint.log" 2>&1 || rc=$?
    SUMMARY="[${#files[@]} dosya] $(tail -n1 "$out/lint.log")"; return "$rc"
  fi
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
  local rc=0 errs f timeout_s args=() n_run=0
  rm -rf "$out/gdunit"
  if [ "$mode" = quick ]; then
    # Yalnız kapsamdaki suite'ler (çekirdek + değişen alan); liste tools/verify-scope.sh çıktısıdır.
    while IFS= read -r f; do [ -n "$f" ] && args+=(-a "res://$f") && n_run=$((n_run + 1)); done <"$scope_dir/run.txt"
    [ "$n_run" -gt 0 ] || { SUMMARY="kapsamda çalıştırılacak suite yok"; return 1; }
    timeout_s="${VERIFY_UNIT_TIMEOUT:-1200}"
  else
    args=(-a res://tests)
    timeout_s="${VERIFY_UNIT_TIMEOUT:-2400}"
  fi
  # -d (debugger) kullanılmaz: parse hatasında Godot "debug>" isteminde asılı kalabiliyor.
  # Zaman aşımı kalite eşiği DEĞİL, yalnız takılma koruması (tam koşu yük altında ~21 dk sürebiliyor; bkz.
  # production/log/2026-10-30-test-sure-profili.md).
  run_to "$timeout_s" "$out/unit.log" "$godot" --headless --path "$root" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    "${args[@]}" -c --ignoreHeadlessMode -rd artifacts/verify/gdunit -rc 1 || rc=$?
  SUMMARY="$(strip_ansi "$out/unit.log" | grep 'Overall Summary' | head -n1 | sed 's/Overall Summary: //')"
  # Çıkış kodu tek başına güvenilmez: GdUnit4 çöktüğünde de 0 dönebiliyor (2026-10-20 E2E-B bulgusu).
  errs="$(strip_ansi "$out/unit.log" | grep -E 'Abnormal exit|SCRIPT ERROR|Parse Error' | head -n1)"
  if [ -z "$SUMMARY" ]; then SUMMARY="GdUnit4 özeti yok (çıkış $rc) ${errs}"; return 1; fi
  if [ -n "$errs" ]; then SUMMARY="$SUMMARY · $errs"; return 1; fi
  # 101 = yalnızca uyarı: geçer. 0 = temiz.
  case "$rc" in 0) ;; 101) SUMMARY="$SUMMARY (uyarılar)" ;; *) SUMMARY="$SUMMARY (çıkış $rc)"; return 1 ;; esac
  if [ "$mode" = quick ]; then SUMMARY="[kapsam: $n_run suite] $SUMMARY"; fi
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

# --- kapsam (yalnız quick) -------------------------------------------------------------------
scope_dir="$out/quick-scope"
scope_label="tam"; scope_kind="full"
if [ "$mode" = quick ]; then
  rm -rf "$scope_dir"
  tools/verify-scope.sh resolve "$scope_dir"
  scope_kind="changed-areas"
  # shellcheck disable=SC1091
  . "$scope_dir/meta.txt"   # base, base_kind, all, suites_total, suites_run, suites_skipped
  if [ "$all" = 1 ]; then scope_label="değişen alan (eşlemesiz yol var: tüm suite'ler)"; else scope_label="değişen alan"; fi
fi

# Önizleme/ölçüm koşusu (VERIFY_QUICK_CHANGED_FILE) stop-verify-gate'in okuduğu quick-latest.json'u EZMEZ.
report_name="$mode"
if [ -n "${VERIFY_QUICK_CHANGED_FILE:-}" ]; then report_name="quick-preview"; fi

echo "verify $mode · head ${git_head:0:9} · fingerprint ${fingerprint:0:12}"
if [ "$mode" = quick ]; then
  areas_txt="$(tr '\n' ' ' <"$scope_dir/areas.txt" | sed 's/ *$//')"
  echo "kapsam: $scope_label + koruma çekirdeği · alanlar: ${areas_txt:-yok (değişiklik yok)} · taban ${base:0:9} ($base_kind) · $suites_run/$suites_total suite"
  if [ -s "$scope_dir/unmapped.txt" ]; then echo "UYARI eşlemesiz yol (tools/verify-areas.tsv'ye ekle): $(head -n3 "$scope_dir/unmapped.txt" | tr '\n' ' ')"; fi
fi
step canon-check s_canon
step studio-check s_studio
step area-map s_areamap
step gdlint s_lint
step import s_import
step unit-gdunit s_unit
canon_guard_skipped=""
if [ "$mode" = full ]; then
  step canon-guard s_canon_guard
  step runtime-smoke s_runtime
else
  # quick: canon-guard (C-07 hook savunma testi, ~35-70 sn) yalnız koruma hook'ları/kanon araçları/kanon dizini değiştiyse ya da
  # VERIFY_QUICK_CANON_GUARD=1 ile koşar. Kanon bütünlüğü (canon-check) ise HER koşuda yukarıda çalışır.
  if [ "${VERIFY_QUICK_CANON_GUARD:-0}" = 1 ] || grep -qE '^(\.claude/(hooks|settings)|tools/(canon-check|test-canon-guard)|design/foundation)' "$scope_dir/changed.txt"; then
    step canon-guard s_canon_guard
  else
    canon_guard_skipped="canon-guard (hook/kanon aracı değişmedi; zorlamak: VERIFY_QUICK_CANON_GUARD=1)"
  fi
fi

# --- atlanan testler (quick) ------------------------------------------------------------------
skipped_line=""; tests_skipped_est=0
if [ "$mode" = quick ]; then
  slow_line=""
  if [ -s "$scope_dir/slow_skipped.txt" ]; then
    slow_line="YAVAŞ suite (alan değişti ama atlandı; koşmak: VERIFY_QUICK_SLOW=1): $(sed 's#^tests/##' "$scope_dir/slow_skipped.txt" | paste -sd',' - | sed 's/,/, /g')"
  fi
  if [ "$suites_skipped" -gt 0 ]; then
    summary_rows="$(while IFS= read -r f; do printf '%s\t%s\n' "$(dirname "$f")" "$(grep -c '^func test_' "$f" || true)"; done <"$scope_dir/skip.txt" \
      | awk -F'\t' '{split($1, a, "/"); k=a[1] "/" a[2]; s[k]++; t[k]+=$2; T+=$2} END{for(d in s) printf "%s (%d suite, ~%d test)\n", d, s[d], t[d]; printf "@@TOTAL %d\n", T}' | LC_ALL=C sort)"
    tests_skipped_est="$(echo "$summary_rows" | grep '^@@TOTAL' | awk '{print $2}')"
    skipped_line="$(echo "$summary_rows" | grep -v '^@@TOTAL' | paste -sd';' - | sed 's/;/; /g')"
  fi
  if [ -n "$canon_guard_skipped" ]; then skipped_line="${skipped_line}${skipped_line:+; }$canon_guard_skipped"; fi
  if [ -n "$slow_line" ]; then skipped_line="${skipped_line}${skipped_line:+; }$slow_line"; fi
fi

extra="$(jq -n --arg scope "$scope_kind" --arg label "$scope_label" --arg base "${base:-}" --arg bk "${base_kind:-}" \
  --arg areas "$([ "$mode" = quick ] && tr '\n' ' ' <"$scope_dir/areas.txt" | sed 's/ *$//' || true)" \
  --arg skipped "$skipped_line" --argjson run "${suites_run:-0}" --argjson total "${suites_total:-0}" \
  --argjson skipn "${suites_skipped:-0}" --argjson skipt "$tests_skipped_est" '
  {scope: $scope, scope_label: $label, base: $base, base_kind: $bk, areas: ($areas | split(" ") | map(select(length > 0))),
   suites_run: $run, suites_total: $total, suites_skipped: $skipn, tests_skipped_estimate: $skipt, skipped: $skipped,
   full_verification: ($scope == "full")}')"

jq -R -s --arg mode "$mode" --arg started "$started_at" --arg head "$git_head" --arg fp "$fingerprint" --arg result "$overall" \
  --argjson extra "$extra" '
  {mode: $mode, started_at: $started, git_head: $head, fingerprint: $fp,
   steps: (split("\n") | map(select(length > 0) | split("\t")
          | {name: .[0], status: .[1], seconds: (.[2] | tonumber), summary: (.[3] // "")})),
   result: $result} + $extra' "$rows" >"$out/$report_name-latest.json"

# Son BAŞARILI doğrulamanın HEAD'i: sonraki quick'in "değişen" tabanı. Yalnız geçince yazılır (fail tabanı ilerletmez).
# (VERIFY_QUICK_CHANGED_FILE = önizleme/ölçüm: kapsam yapay olduğundan tabanı ilerletmez.)
if [ "$overall" = pass ] && [ -z "${VERIFY_QUICK_CHANGED_FILE:-}" ]; then echo "$git_head" >"$out/quick-base"; fi

if [ "$mode" = quick ]; then
  if [ -n "$skipped_line" ]; then
    echo "ATLANDI: $suites_skipped suite, ~$tests_skipped_est test: $skipped_line; tam doğrulama: tools/verify.sh full"
  else
    echo "ATLANDI: yok (kapsam tüm suite'leri içeriyor); tam doğrulama: tools/verify.sh full"
  fi
  echo "SONUÇ: $overall · kapsam: $scope_label (TAM DOĞRULAMA DEĞİL) · rapor: artifacts/verify/$report_name-latest.json"
else
  echo "SONUÇ: $overall · kapsam: tam · rapor: artifacts/verify/$report_name-latest.json"
fi
[ "$overall" = pass ]
