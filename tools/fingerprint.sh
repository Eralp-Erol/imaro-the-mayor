#!/bin/bash
# Oyunla ilgili dosyaların çalışma ağacı içeriğinden tek bir sha256 üretir.
# Kapsam: src/ scenes/ tests/ addons/ assets/ project.godot (izlenen + izlenmeyen, ignore edilmeyen).
# *.uid dosyaları (Godot import ürünü, kendiliğinden oluşur) hariç tutulur.
# İçerik (yol + bayt) hash'lenir; zaman damgası/izin etkilemez. Silinmiş izlenen dosyalar atlanır.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
paths=""
for p in src scenes tests addons assets project.godot; do
  [ -e "$p" ] && paths="$paths $p"
done
[ -n "$paths" ] || { echo "fingerprint: kapsamda dosya yok" >&2; exit 1; }
# shellcheck disable=SC2086
# Toplu hash: dosya başına süreç açmak ~19 sn sürüyordu (SessionStart timeout'u 20 sn); xargs ile ~1 sn.
# Biçim ve sıra eskisiyle aynı ("<sha256>  <yol>", yola göre sıralı) — parmak izi değişmez.
git ls-files -z --cached --others --exclude-standard -- $paths \
  | while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue
      case "$f" in *.uid) continue ;; esac
      printf '%s\0' "$f"
    done \
  | LC_ALL=C sort -z \
  | xargs -0 -n 256 shasum -a 256 \
  | shasum -a 256 | cut -d' ' -f1
