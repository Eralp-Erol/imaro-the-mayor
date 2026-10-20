#!/bin/bash
# Pencereli render performans ölçümü (T-001 ölçüt 6; ADR-0001). tools/godot/perf_probe.gd sarar.
# Kullanım: tools/perf.sh <ad> [--frames N] [--warmup N] [--resolution WxH] [--scene res://x.tscn] [-- sahneye argümanlar]
# Varsayılan sahne: res://scenes/dev/world_preview.tscn, 1600x900, 360 kare (ilk 60 ısınma).
# Çıktı: artifacts/perf/<YYYYMMDD-HHMMSS>-<ad>.json (+ stdout'ta yol ve özet satırı); makine yükü JSON'a eklenmez,
# özet satırında basılır (yük altında ölçüm ±%40 oynayabilir, ADR-0001).
# Çıkış: 0 = başarı, 2 = kullanım hatası, 1 = Godot hatası.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
name="${1:-}"
[ -n "$name" ] && [[ "$name" != --* ]] || { echo "kullanım: tools/perf.sh <ad> [--frames N] [--warmup N] [--resolution WxH] [--scene res://x.tscn] [-- ekstra]" >&2; exit 2; }
shift
frames=360; warmup=60; resolution="1600x900"; scene="res://scenes/dev/world_preview.tscn"
while [ $# -gt 0 ]; do
  case "$1" in
    --frames) frames="$2"; shift 2 ;;
    --warmup) warmup="$2"; shift 2 ;;
    --resolution) resolution="$2"; shift 2 ;;
    --scene) scene="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "perf: bilinmeyen argüman $1" >&2; exit 2 ;;
  esac
done
out="$root/artifacts/perf/$(date +%Y%m%d-%H%M%S)-$name.json"
mkdir -p "$(dirname "$out")" "$root/artifacts/verify"
load_before="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
"$root/tools/godot.sh" --path "$root" --resolution "$resolution" --script res://tools/godot/perf_probe.gd -- \
  "--scene=$scene" "--out=$out" "--frames=$frames" "--warmup=$warmup" "--name=$name" "$@" \
  >"$root/artifacts/verify/perf.out.log" 2>"$root/artifacts/verify/perf.err.log" || {
  echo "perf: Godot başarısız, bkz artifacts/verify/perf.err.log" >&2; exit 1; }
[ -s "$out" ] || { echo "perf: JSON oluşmadı" >&2; exit 1; }
load_after="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
echo "$out"
jq -r --arg l0 "$load_before" --arg l1 "$load_after" '"perf \(.name): kare ort \(.frame_ms.mean) ms · p95 \(.frame_ms.p95) ms · draw call ort \(.draw_calls.mean) · üçgen \(.primitives.mean) · yük(1dk) \($l0)→\($l1)"' "$out"
