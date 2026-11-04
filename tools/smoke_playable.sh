#!/bin/bash
# T-030 entegrasyon dumanı. Başsız faz gerçek playable sahnesini açar, T0->sim
# bağını ve demo imar komutunu denetler. Pencereli faz gerçek kare yakalar.
# Ölçemediği render sayaçlarını uydurmaz; bu nedenle m01-perf.json ve SMOKE_OK
# yalnız iki faz da ölçülüp tamamlandığında yazılır.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/artifacts/verify/playable-smoke"
mkdir -p "$out"
godot="$($root/tools/godot.sh --print-path)"

headless_log="$out/headless.log"
echo "smoke: headless playable (T0 stock + sim + HUD + zoning command)"
if ! timeout 600 "$godot" --headless --path "$root" res://scenes/game/playable.tscn -- \
  --demo --quit-after=180 >"$headless_log" 2>&1; then
  echo "smoke: FAIL headless playable; $headless_log" >&2
  tail -80 "$headless_log" >&2 || true
  exit 1
fi
if ! grep -q 'PLAYABLE_ACTION.*queued\|PLAYABLE_ACTION.*accepted' "$headless_log" \
  || ! grep -q 'PLAYABLE_SAVE_LOAD OK' "$headless_log" \
  || ! grep -q 'PLAYABLE_QUIT' "$headless_log"; then
  echo "smoke: FAIL expected playable action/controlled exit missing; $headless_log" >&2
  tail -80 "$headless_log" >&2 || true
  exit 1
fi
if grep -Eq 'SCRIPT ERROR|Parse Error|Abnormal exit|^ERROR:' "$headless_log"; then
  echo "smoke: FAIL script error in headless log; $headless_log" >&2
  exit 1
fi

echo "smoke: T-029 2k/10k/30k save/hash probe"
"$godot" --headless --path "$root" -s res://tests/sim/perf/t029_save_hash_probe.gd \
  >"$out/t029.log" 2>&1

if [ "${IMARO_NO_WINDOW:-0}" = "1" ]; then
  echo "smoke: WINDOW SKIPPED (IMARO_NO_WINDOW=1); no SMOKE_OK or perf acceptance report"
  exit 0
fi

echo "smoke: window capture"
if ! "$root/tools/capture.sh" playable-smoke --frames 180 --resolution 1600x900 \
  --scene res://scenes/game/playable.tscn -- --demo >"$out/capture.path" 2>"$out/capture.err.log"; then
  echo "smoke: FAIL window capture; $out/capture.err.log" >&2
  tail -80 "$out/capture.err.log" >&2 || true
  exit 1
fi
capture="$(cat "$out/capture.path")"
[ -s "$capture" ] || { echo "smoke: FAIL capture missing: $capture" >&2; exit 1; }

echo "smoke: WINDOW_CAPTURED $capture"

# Pencereli perf probu gerçek playable sahnesini (render + TickDriver/facade) ölçer.
# Üç oyuncu görünümü ayrı tutulur; kabul sayısı bunların en kötüsüdür, ortalaması değil (T-064, ADR-0007 §Karar 7):
# core (oyuncunun en uzak ortalı görünümü), district:D1, street:port. Eski `metro` serisi `metro_legacy_bench` +
# `--envelope=legacy` olarak BİLGİ amaçlı sürer (seri kırılmasın); kabule girmez.
run_perf() {
  local name="$1" preset="$2" extra="${3:-}" result
  local args=(--demo "--preset=$preset")
  [ -n "$extra" ] && args+=("$extra")
  result="$("$root/tools/perf.sh" "$name" --frames 180 --warmup 120 --resolution 1600x900 \
    --scene res://scenes/game/playable.tscn -- "${args[@]}")"
  printf '%s\n' "$result" | sed -n '1p'
}
echo "smoke: combined window telemetry (core/district/street + legacy bench info)"
core_json="$(run_perf playable-smoke-core core)"
district_json="$(run_perf playable-smoke-district district:D1)"
street_json="$(run_perf playable-smoke-street street:port)"
legacy_json="$(run_perf playable-smoke-metro-legacy-bench metro_legacy_bench --envelope=legacy)"
for f in "$core_json" "$district_json" "$street_json" "$legacy_json"; do
  [ -s "$f" ] || { echo "smoke: FAIL perf JSON missing: $f" >&2; exit 1; }
done

# K8 iki temsili aynı kamera, çözünürlük ve ışıkta ayırır. 1,500 m görsel
# LOD geçişinin sonudur; gölge 700 m'de bağımsız kapandığı için karşılaştırma
# gölge farkını değil mesh sadakatini ölçer.
echo "smoke: K8 LOD0/LOD1 visual diff"
lod0="$("$root/tools/capture.sh" playable-smoke-k8-lod0 --frames 120 --resolution 1600x900 \
  --scene res://scenes/dev/world_preview.tscn -- --preset=street:port --distance=1500 \
  --bld-no-lod1 --bld-no-hlod1 --bld-no-hlod2 --lod0-end=5000)"
lod1="$("$root/tools/capture.sh" playable-smoke-k8-lod1 --frames 120 --resolution 1600x900 \
  --scene res://scenes/dev/world_preview.tscn -- --preset=street:port --distance=1500 \
  --bld-no-lod0 --bld-no-hlod1 --bld-no-hlod2 --lod0-end=100)"
[ -s "$lod0" ] && [ -s "$lod1" ] || { echo "smoke: FAIL K8 capture missing" >&2; exit 1; }
k8_line="$("$root/tools/visual-diff.sh" "$lod0" "$lod1" "$out/k8-diff.png")"
k8_pct="$(printf '%s\n' "$k8_line" | sed -n 's/.*percent=\([0-9.]*\).*/\1/p')"
[ -n "$k8_pct" ] || { echo "smoke: FAIL K8 metric missing: $k8_line" >&2; exit 1; }

perf_file="$root/artifacts/verify/m01-perf.json"
hash_ms="$(jq -r '.samples[] | select(.parcels == 10000) | .state_hash_ms' "$out/../t029-perf.json" 2>/dev/null || true)"
save_ms="$(jq -r '.samples[] | select(.parcels == 10000) | .save_load_ms' "$out/../t029-perf.json" 2>/dev/null || true)"
# t029 probe writes the canonical artifact outside the smoke directory.
if [ -z "$hash_ms" ] || [ "$hash_ms" = "null" ]; then
  hash_ms="$(jq -r '.samples[] | select(.parcels == 10000) | .state_hash_ms' "$root/artifacts/verify/t029-perf.json")"
  save_ms="$(jq -r '.samples[] | select(.parcels == 10000) | .save_load_ms' "$root/artifacts/verify/t029-perf.json")"
fi
jq -n --slurpfile core "$core_json" --slurpfile district "$district_json" --slurpfile street "$street_json" \
  --slurpfile legacy "$legacy_json" \
  --argjson k8 "$k8_pct" --argjson hash "$hash_ms" --argjson save "$save_ms" \
  --arg capture "$capture" --arg lod0 "$lod0" --arg lod1 "$lod1" \
  '{frame_avg_ms: ([$core[0].frame_ms.mean, $district[0].frame_ms.mean, $street[0].frame_ms.mean] | max),
    frame_p95_ms: ([$core[0].frame_ms.p95, $district[0].frame_ms.p95, $street[0].frame_ms.p95] | max),
    draw_calls_max: ([$core[0].draw_calls.max, $district[0].draw_calls.max, $street[0].draw_calls.max] | max),
    local_phase_triangles_max: ([$core[0].primitives.max, $district[0].primitives.max, $street[0].primitives.max] | max),
    k8_lod0_lod1_diff_pct: $k8, state_hash_ms_10k_parcels: $hash,
    save_load_ms_10k_parcels: $save,
    evidence: {playable_capture: $capture, k8_lod0: $lod0, k8_lod1: $lod1,
      core: $core[0], district: $district[0], street: $street[0], metro_legacy_bench_info: $legacy[0]}}' >"$perf_file"

if ! jq -e '
  .frame_avg_ms <= 8 and .frame_p95_ms <= 16.6 and .draw_calls_max <= 600 and
  .local_phase_triangles_max <= 900000 and .k8_lod0_lod1_diff_pct <= 5 and
  .state_hash_ms_10k_parcels <= 500 and .save_load_ms_10k_parcels <= 1500
' "$perf_file" >/dev/null; then
  echo "smoke: FAIL acceptance limits; $perf_file" >&2
  jq '{frame_avg_ms,frame_p95_ms,draw_calls_max,local_phase_triangles_max,k8_lod0_lod1_diff_pct,state_hash_ms_10k_parcels,save_load_ms_10k_parcels}' "$perf_file" >&2
  exit 1
fi
echo "SMOKE_OK $perf_file"
