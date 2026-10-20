#!/bin/bash
# Paralel üretim hatları (lane) için koordinasyon aracı. Kayıt: production/LANES.md (satırlar `LANE|id|sahip|yollar|testler|not`).
# Aynı çalışma ağacında birden çok ajan çalışırken: dosya sahipliği (en uzun önek kazanır), hat bazlı doğrulama, hat bazlı commit.
#   tools/lane.sh status                 hat başına değişen dosya sayısı, sahipsiz dosyalar
#   tools/lane.sh check                  sahipsiz değişiklik varsa çıkış 1
#   tools/lane.sh files <hat>            hattın değişen dosyaları
#   tools/lane.sh verify <hat>           yalnız hattın dosya/testleri: gdlint + GdUnit4 (başka hattın yarım işi bu hattı kırmaz; import adımı yok)
#   tools/lane.sh commit <hat> "<mesaj>" yalnız hattın değişen dosyalarını commit'ler (başka hat dosyasına dokunmaz)
# Bash 3.2 uyumlu.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
REG="production/LANES.md"
[ -f "$REG" ] || { echo "lane: $REG yok" >&2; exit 2; }

# Yok sayılan (izlenmeyen/derleme) yollar
ignored() { case "$1" in artifacts/*|.agents/*|IMARO_GAME_DESIGN_FOUNDATION_*|.claude/worktrees/*|build/*|.godot/*|.tools/*) return 0 ;; esac; return 1; }

lanes() { grep '^LANE|' "$REG" | cut -d'|' -f2; }
field() { grep "^LANE|$1|" "$REG" | head -n1 | cut -d'|' -f"$2"; }   # 3=sahip 4=yollar 5=testler 6=not

changed() { git status --porcelain -uall | sed -E 's/^.. //; s/.* -> //' | sed 's/^"//; s/"$//'; }

# owner_of <dosya>: en uzun öneki eşleşen hattın kimliği; yoksa boş
owner_of() {
  local f="$1" best="" bestlen=0 id p
  for id in $(lanes); do
    local IFS=','
    for p in $(field "$id" 4); do
      p="${p# }"; [ -n "$p" ] || continue
      case "$f" in "$p"*) if [ "${#p}" -gt "$bestlen" ]; then best="$id"; bestlen="${#p}"; fi ;; esac
    done
    unset IFS
  done
  printf '%s' "$best"
}

lane_files() {
  local id="$1" f
  changed | while IFS= read -r f; do
    [ -n "$f" ] || continue; ignored "$f" && continue
    [ "$(owner_of "$f")" = "$id" ] && printf '%s\n' "$f"
  done
}

cmd="${1:-status}"; shift || true
case "$cmd" in
  status|check)
    unowned=""; declare_counts=""
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    changed | while IFS= read -r f; do
      [ -n "$f" ] || continue; ignored "$f" && continue
      printf '%s\t%s\n' "$(owner_of "$f")" "$f"
    done >"$tmp"
    printf '%-14s %-22s %s\n' HAT SAHİP DEĞİŞEN
    for id in $(lanes); do
      n="$(awk -F'\t' -v l="$id" '$1==l' "$tmp" | wc -l | tr -d ' ')"
      printf '%-14s %-22s %s\n' "$id" "$(field "$id" 3)" "$n"
    done
    unowned="$(awk -F'\t' '$1==""{print $2}' "$tmp")"
    if [ -n "$unowned" ]; then echo; echo "SAHİPSİZ değişiklikler (LANES.md'ye ekle ya da geri al):"; echo "$unowned" | sed 's/^/  /'; [ "$cmd" = check ] && exit 1; fi
    [ "$cmd" = check ] && echo "lane check: tüm değişiklikler bir hatta ait"
    exit 0 ;;
  files) lane_files "${1:?hat gerekli}" ;;
  paths) field "${1:?hat gerekli}" 4 ;;
  verify)
    id="${1:?hat gerekli}"; [ -n "$(field "$id" 2)" ] || { echo "lane: bilinmeyen hat $id" >&2; exit 2; }
    godot="$("$root/tools/godot.sh" --print-path)"
    out="$root/artifacts/verify/lane-$id"; mkdir -p "$out"; rm -rf "$out/gdunit"
    rc=0
    # gdlint: hattın yolları arasında .gd barındıran mevcut dizin/dosyalar
    gdl=(); p=""; IFS=','; for p in $(field "$id" 4); do
      p="${p# }"; if [ -e "$p" ]; then case "$p" in src/*|tests/*) gdl+=("$p") ;; esac; fi
    done; unset IFS
    if [ ${#gdl[@]} -gt 0 ]; then
      if uvx --from gdtoolkit==4.5.0 gdlint "${gdl[@]}" >"$out/lint.log" 2>&1; then echo "PASS gdlint        $(tail -n1 "$out/lint.log")"; else echo "FAIL gdlint        $(tail -n1 "$out/lint.log")"; rc=1; fi
    else echo "SKIP gdlint        hattın lint edilecek yolu yok"; fi
    # GdUnit4: hattın test dizinleri
    targs=(); t=""; IFS=','; for t in $(field "$id" 5); do
      t="${t# }"; if [ -d "$t" ]; then targs+=(-a "res://${t%/}"); fi
    done; unset IFS
    if [ ${#targs[@]} -gt 0 ]; then
      urc=0
      ( "$godot" --headless --path "$root" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd "${targs[@]}" -c --ignoreHeadlessMode -rd "artifacts/verify/lane-$id/gdunit" -rc 1 >"$out/unit.log" 2>&1 ) || urc=$?
      sum="$(perl -pe 's/\e\[[0-9;?]*[A-Za-z]//g' "$out/unit.log" | grep 'Overall Summary' | head -n1 | sed 's/Overall Summary: //' || true)"
      bad="$(perl -pe 's/\e\[[0-9;?]*[A-Za-z]//g' "$out/unit.log" | grep -E 'Abnormal exit|SCRIPT ERROR|Parse Error' | head -n1 || true)"
      if [ -z "$sum" ] || [ -n "$bad" ] || { [ "$urc" != 0 ] && [ "$urc" != 101 ]; }; then echo "FAIL gdunit        ${sum:-özet yok} $bad (çıkış $urc)"; rc=1; else echo "PASS gdunit        $sum"; fi
    else echo "SKIP gdunit        hattın test dizini yok"; fi
    [ "$rc" = 0 ] && echo "lane verify $id: pass" || echo "lane verify $id: FAIL ($out/)"
    exit "$rc" ;;
  commit)
    id="${1:?hat gerekli}"; msg="${2:?mesaj gerekli}"
    files="$(lane_files "$id")"; [ -n "$files" ] || { echo "lane commit: $id için değişiklik yok"; exit 0; }
    git reset -q
    echo "$files" | while IFS= read -r f; do git add -- "$f"; done
    git commit -q -m "$msg" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
    echo "lane commit $id: $(git log --oneline -1) ($(echo "$files" | wc -l | tr -d ' ') dosya)" ;;
  *) echo "kullanım: tools/lane.sh status|check|files <hat>|paths <hat>|verify <hat>|commit <hat> \"<mesaj>\"" >&2; exit 2 ;;
esac
