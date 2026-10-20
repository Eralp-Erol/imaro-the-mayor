#!/bin/bash
# İki PNG arasındaki farklı piksel sayısı ve yüzdesi (magick compare -metric AE -fuzz 2%).
# Kullanım: tools/visual-diff.sh a.png b.png [fark.png]   Çıktı: "diff_pixels=N total=M percent=P"
# Çıkış 0 (eşik kararı çağırana ait); araç/dosya hatasında 1, boyut uyuşmazlığında 2.
set -euo pipefail
[ $# -ge 2 ] || { echo "kullanım: tools/visual-diff.sh a.png b.png [out.png]" >&2; exit 1; }
a="$1"; b="$2"; out="${3:-null:}"
for f in "$a" "$b"; do [ -f "$f" ] || { echo "visual-diff: dosya yok: $f" >&2; exit 1; }; done
command -v magick >/dev/null || { echo "visual-diff: magick yok" >&2; exit 1; }
sa="$(magick identify -format '%wx%h' "$a[0]")"; sb="$(magick identify -format '%wx%h' "$b[0]")"
[ "$sa" = "$sb" ] || { echo "visual-diff: boyutlar farklı ($sa vs $sb)" >&2; exit 2; }
# compare farklılık varsa 1 döner; metrik stderr'e yazılır.
diff_px="$(magick compare -metric AE -fuzz 2% "$a" "$b" "$out" 2>&1 || true)"
diff_px="${diff_px%% *}"
case "$diff_px" in ''|*[!0-9]*) echo "visual-diff: magick çıktısı anlaşılamadı: $diff_px" >&2; exit 1 ;; esac
total=$(( ${sa%x*} * ${sa#*x} ))
pct="$(awk -v d="$diff_px" -v t="$total" 'BEGIN { printf "%.4f", d * 100 / t }')"
echo "diff_pixels=$diff_px total=$total percent=$pct"
