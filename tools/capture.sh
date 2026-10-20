#!/bin/bash
# Ana projeyi PENCERELİ çalıştırıp tek kare PNG alır.
# Kullanım: tools/capture.sh <ad> [--frames N] [--resolution WxH] [--scene res://x.tscn] [-- oyuna geçecek ekstra argümanlar]
# --scene yoksa project.godot'taki run/main_scene; o da yoksa mesaj + çıkış 0 (skip), stdout boş.
# Çıktı: artifacts/screenshots/captures/<YYYYMMDD-HHMMSS>-<ad>.png (yol stdout'a basılır)
# Çıkış: 0 = başarı, 2 = kullanım hatası, diğer = Godot/yakalama hatası.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:-}"
[ -n "$name" ] && [[ "$name" != --* ]] || { echo "kullanım: tools/capture.sh <ad> [--frames N] [--resolution WxH] [--scene res://x.tscn] [-- ekstra]" >&2; exit 2; }
shift
frames=30
resolution=""
scene=""
while [ $# -gt 0 ]; do
  case "$1" in
    --frames) frames="$2"; shift 2 ;;
    --resolution) resolution="$2"; shift 2 ;;
    --scene) scene="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "capture: bilinmeyen argüman $1" >&2; exit 2 ;;
  esac
done
if [ -z "$scene" ] && ! grep -qE '^run/main_scene=' "$root/project.godot" 2>/dev/null; then
  echo "capture: SKIP: no main scene yet (--scene res://x.tscn verin)" >&2; exit 0
fi
out="$root/artifacts/screenshots/captures/$(date +%Y%m%d-%H%M%S)-$name.png"
mkdir -p "$(dirname "$out")" "$root/artifacts/verify"
args=(--path "$root")
[ -n "$resolution" ] && args+=(--resolution "$resolution")
args+=(--script res://tools/godot/capture_frame.gd -- "--out=$out" "--frames=$frames")
[ -n "$scene" ] && args+=("--scene=$scene")
[ $# -gt 0 ] && args+=("$@")
"$root/tools/godot.sh" "${args[@]}" >/dev/null 2>"$root/artifacts/verify/capture.err.log" || {
  echo "capture: Godot başarısız, bkz artifacts/verify/capture.err.log" >&2; exit 1; }
[ -s "$out" ] || { echo "capture: PNG oluşmadı" >&2; exit 1; }
echo "$out"
