#!/bin/bash
# `verify quick`in kapsam çözücüsü: değişen dosyalardan koşulacak GdUnit suite listesini çıkarır.
# Eşleme verisi: tools/verify-areas.tsv (kural biçimi o dosyanın başında).
#
# Kullanım:
#   tools/verify-scope.sh check                 eşleme tablosunun tutarlılığını denetler (0 = tamam, 1 = hata)
#   tools/verify-scope.sh resolve <çıktı-dizini> [taban-ref]
#       Değişen dosyaları (taban-ref'e göre git diff + izlenmeyen) tabloyla suite'lere çevirir.
#       Yazar: changed.txt, areas.txt, unmapped.txt, run.txt (koşulacak suite, çekirdek dahil),
#              skip.txt (atlanan suite), meta.txt (anahtar=değer: base, base_kind, scope, ...).
#   tools/verify-scope.sh base                  kullanılacak tabanı basar ("<sha> <tür>")
# Önizleme/test: VERIFY_QUICK_CHANGED_FILE=<dosya> verilirse değişen yollar git yerine o dosyadan okunur.
# Taban: VERIFY_QUICK_BASE (ortam) > artifacts/verify/quick-base (son BAŞARILI doğrulamanın HEAD'i,
#        HEAD'in atasıysa) > son başarılı full raporunun HEAD'i > main ile ayrışma noktası > HEAD.
# Güvenli varsayılan: tabloda eşleşmeyen değişen yol => tüm suite'ler (ALL). Hiçbir yol sessizce atlanmaz;
# yalnız tablodaki `ignore` kuralları ve *.uid/*.import/*.md dosyaları kapsam dışıdır.
# bash 3.2 uyumlu.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
table="$root/tools/verify-areas.tsv"
[ -f "$table" ] || { echo "verify-scope: $table yok" >&2; exit 2; }

all_suites() { find tests -name '*_test.gd' -type f | LC_ALL=C sort; }

# expand_spec <belirteç>: dizin (özyinelemeli), dosya veya glob => suite dosyaları (*_test.gd).
expand_spec() {
  local t="$1" f
  if [ "$t" = ALL ]; then all_suites; return 0; fi
  if [ -d "$t" ]; then find "$t" -name '*_test.gd' -type f | LC_ALL=C sort; return 0; fi
  # shellcheck disable=SC2086
  for f in $t; do
    if [ -f "$f" ]; then case "$f" in *_test.gd) echo "$f" ;; esac; fi
  done
  return 0
}

# Tablo okuyucuları (yorum/boş satırları atlar).
rows() { grep -v '^[[:space:]]*#' "$table" | grep -v '^[[:space:]]*$' || true; }
core_specs() { rows | awk -F'\t' '$1=="core"{print $2}' | tr ' ' '\n' | grep -v '^$' || true; }
ignore_prefixes() { rows | awk -F'\t' '$1=="ignore"{print $2}' || true; }
slow_specs() { rows | awk -F'\t' '$1=="slow"{print $2}' | tr ' ' '\n' | grep -v '^$' || true; }
map_rows() { rows | awk -F'\t' '$1=="map"{print $2 "\t" $3}' || true; }

# covers <önek> <yol>: yol önek'in kendisi veya altındaysa 0.
covers() { [ "$2" = "$1" ] || case "$2" in "$1"/*) return 0 ;; *) return 1 ;; esac; }

# best_rule <yol>: en uzun önekli map kuralının "önek<TAB>testler" satırını basar (yoksa hiçbir şey).
best_rule() {
  local p="$1" best="" bestlen=0 pre specs
  while IFS=$'\t' read -r pre specs; do
    [ -n "$pre" ] || continue
    if covers "$pre" "$p" && [ "${#pre}" -gt "$bestlen" ]; then best="$pre"$'\t'"$specs"; bestlen=${#pre}; fi
  done <<EOF
$(map_rows)
EOF
  [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}

is_builtin_ignored() { case "$1" in *.uid|*.import|*.md) return 0 ;; *) return 1 ;; esac; }

# is_ignored <yol>: tablodaki `ignore` önekleri (yerleşik: *.uid, *.import, *.md). Eşleşen bir `map` kuralı her zaman ignore'dan önce gelir.
is_ignored() {
  local p="$1" pre
  is_builtin_ignored "$p" && return 0
  while IFS= read -r pre; do
    [ -n "$pre" ] || continue
    covers "$pre" "$p" && return 0
  done <<EOF
$(ignore_prefixes)
EOF
  return 1
}

pick_base() {
  local state="$root/artifacts/verify/quick-base" sha
  if [ -n "${VERIFY_QUICK_BASE:-}" ]; then
    sha="$(git rev-parse --verify -q "${VERIFY_QUICK_BASE}^{commit}")" || { echo "verify-scope: VERIFY_QUICK_BASE geçersiz" >&2; exit 2; }
    echo "$sha ortam-değişkeni"; return 0
  fi
  if [ -f "$state" ]; then
    sha="$(tr -d '[:space:]' <"$state")"
    if [ -n "$sha" ] && git cat-file -e "${sha}^{commit}" 2>/dev/null && git merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
      echo "$sha son-başarılı-doğrulama"; return 0
    fi
  fi
  # Taban kaydı yoksa (yeni worktree): son BAŞARILI tam doğrulamanın HEAD'i (tüm testler o duruma karşı geçmişti).
  if [ -f "$root/artifacts/verify/full-latest.json" ] && command -v jq >/dev/null; then
    sha="$(jq -r 'select(.result == "pass") | .git_head // empty' "$root/artifacts/verify/full-latest.json" 2>/dev/null || true)"
    if [ -n "$sha" ] && git cat-file -e "${sha}^{commit}" 2>/dev/null && git merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
      echo "$sha son-başarılı-full"; return 0
    fi
  fi
  if sha="$(git merge-base main HEAD 2>/dev/null)" && [ -n "$sha" ]; then echo "$sha main-ayrışma"; return 0; fi
  echo "$(git rev-parse HEAD) HEAD"
}

cmd_check() {
  local errs=0 pre specs spec n d first
  # 1) core: her belirteç en az bir suite'e çözülmeli
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    n="$(expand_spec "$spec" | wc -l | tr -d ' ')"
    if [ "$n" = 0 ]; then echo "HATA core: '$spec' hiçbir suite'e çözülmüyor" >&2; errs=$((errs + 1)); fi
  done <<EOF
$(core_specs)
EOF
  # 2) map kuralları: önek var olmalı, her test belirteci en az bir suite'e çözülmeli
  while IFS=$'\t' read -r pre specs; do
    [ -n "$pre" ] || continue
    if [ ! -e "$pre" ]; then echo "HATA map: önek yok: $pre" >&2; errs=$((errs + 1)); fi
    for spec in $specs; do
      n="$(expand_spec "$spec" | wc -l | tr -d ' ')"
      if [ "$n" = 0 ]; then echo "HATA map $pre: '$spec' hiçbir suite'e çözülmüyor" >&2; errs=$((errs + 1)); fi
    done
  done <<EOF
$(map_rows)
EOF
  # 3) src ve tests altındaki .gd içeren HER dizin bir kurala bağlı olmalı (yeni dizin eşlemesiz bırakılamaz)
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    first="$(find "$d" -maxdepth 1 -name '*.gd' -type f | head -n1)"
    [ -n "$first" ] || continue
    if [ -z "$(best_rule "$d/x.gd")" ]; then
      echo "HATA dizin: '$d' hiçbir map kuralına bağlı değil (tools/verify-areas.tsv'ye ekle)" >&2; errs=$((errs + 1))
    fi
  done <<EOF
$(find src tests -type d | LC_ALL=C sort)
EOF
  # 4) data/, scenes/ ikinci düzey dizinleri: eşlemesizse uyarı (çalışırken güvenli yol ALL)
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -z "$(best_rule "$d/x")" ] && ! is_ignored "$d/x"; then echo "UYARI: '$d' eşlemesiz (değişirse quick tüm suite'leri koşar)" >&2; fi
  done <<EOF
$(find data scenes assets -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)
EOF
  if [ "$errs" -gt 0 ]; then echo "area-map: $errs hata" >&2; return 1; fi
  echo "area-map: $(map_rows | wc -l | tr -d ' ') kural, $(core_specs | wc -l | tr -d ' ') çekirdek belirteci, src dizinlerinin hepsi eşli"
}

cmd_resolve() {
  local out="$1" base_arg="${2:-}" base kind line p rule pre specs all=0 total
  mkdir -p "$out"
  if [ -n "$base_arg" ]; then base="$(git rev-parse "$base_arg^{commit}")"; kind="argüman"
  else line="$(pick_base)"; base="${line%% *}"; kind="${line#* }"; fi
  if [ -n "${VERIFY_QUICK_CHANGED_FILE:-}" ]; then
    # Önizleme/test: değişen yol listesi git yerine bu dosyadan (satır başına bir yol) okunur.
    LC_ALL=C sort -u "$VERIFY_QUICK_CHANGED_FILE" >"$out/changed.txt"
  else
    { git -c core.quotepath=false diff --name-only --no-renames "$base" -- 2>/dev/null; git -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null; } \
      | LC_ALL=C sort -u >"$out/changed.txt"
  fi
  : >"$out/areas.txt"; : >"$out/unmapped.txt"; : >"$out/run.raw"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if is_builtin_ignored "$p"; then continue; fi
    case "$p" in
      tests/*_test.gd) [ -f "$p" ] && echo "$p" >>"$out/run.raw"; echo "$p" | awk -F/ '{print $1"/"$2}' >>"$out/areas.txt"; continue ;;
    esac
    rule="$(best_rule "$p")"
    if [ -z "$rule" ]; then
      if is_ignored "$p"; then continue; fi
      echo "$p" >>"$out/unmapped.txt"; all=1; continue
    fi
    pre="${rule%%$'\t'*}"; specs="${rule#*$'\t'}"
    echo "$pre" >>"$out/areas.txt"
    for s in $specs; do
      if [ "$s" = ALL ]; then all=1; else expand_spec "$s" >>"$out/run.raw"; fi
    done
  done <"$out/changed.txt"
  # çekirdek her zaman
  while IFS= read -r s; do [ -n "$s" ] && expand_spec "$s" >>"$out/run.raw"; done <<EOF
$(core_specs)
EOF
  all_suites >"$out/all.txt"
  : >"$out/slow_skipped.txt"
  if [ "$all" = 1 ]; then
    cp "$out/all.txt" "$out/run.txt"
  else
    LC_ALL=C sort -u "$out/run.raw" >"$out/run.txt"
    # Yavaş suite'ler: alan değişince bile quick'ten çıkarılır (süre bütçesi). Muaf: çekirdek, bu koşuda DEĞİŞMİŞ test
    # dosyasının kendisi, VERIFY_QUICK_SLOW=1. Atlananlar slow_skipped.txt'e yazılır ve ATLANDI satırında açıkça görünür.
    if [ "${VERIFY_QUICK_SLOW:-0}" != 1 ]; then
      : >"$out/slow.txt"; : >"$out/exempt.txt"
      while IFS= read -r s; do [ -n "$s" ] && expand_spec "$s" >>"$out/slow.txt"; done <<EOF
$(slow_specs)
EOF
      while IFS= read -r s; do [ -n "$s" ] && expand_spec "$s" >>"$out/exempt.txt"; done <<EOF
$(core_specs)
EOF
      grep -E '^tests/.*_test\.gd$' "$out/changed.txt" >>"$out/exempt.txt" || true
      LC_ALL=C sort -u "$out/slow.txt" -o "$out/slow.txt"
      LC_ALL=C sort -u "$out/exempt.txt" -o "$out/exempt.txt"
      LC_ALL=C comm -12 "$out/run.txt" "$out/slow.txt" | LC_ALL=C comm -23 - "$out/exempt.txt" >"$out/slow_skipped.txt"
      LC_ALL=C comm -23 "$out/run.txt" "$out/slow_skipped.txt" >"$out/run.tmp"
      mv "$out/run.tmp" "$out/run.txt"
    fi
  fi
  LC_ALL=C sort -u "$out/areas.txt" -o "$out/areas.txt"
  LC_ALL=C comm -23 "$out/all.txt" "$out/run.txt" >"$out/skip.txt"
  total="$(wc -l <"$out/all.txt" | tr -d ' ')"
  {
    echo "base=$base"
    echo "base_kind=$kind"
    echo "all=$all"
    echo "suites_total=$total"
    echo "suites_run=$(wc -l <"$out/run.txt" | tr -d ' ')"
    echo "suites_skipped=$(wc -l <"$out/skip.txt" | tr -d ' ')"
  } >"$out/meta.txt"
  rm -f "$out/run.raw"
}

case "${1:-}" in
  check) cmd_check ;;
  resolve) [ -n "${2:-}" ] || { echo "kullanım: verify-scope.sh resolve <çıktı-dizini> [taban-ref]" >&2; exit 2; }; cmd_resolve "$2" "${3:-}" ;;
  base) pick_base ;;
  *) echo "kullanım: tools/verify-scope.sh <check|resolve|base> ..." >&2; exit 2 ;;
esac
