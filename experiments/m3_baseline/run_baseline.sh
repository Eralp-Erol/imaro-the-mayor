#!/bin/bash
# T-077 sarmalayıcı: tek Godot koşusu (tek senaryo) + paylaşılan Godot kilidi + makine yükü kapısı.
# Kullanım: experiments/m3_baseline/run_baseline.sh <ad> -- <probe argümanları>
#   örn: experiments/m3_baseline/run_baseline.sh player-s1467 -- --mode=player --years=5
# - Kilit: mkdir /tmp/imaro-godot.lock (alınamazsa 10 sn bekler, tekrar dener); YALNIZ kendi kilidini rmdir ile bırakır.
# - Yük kapısı: koşudan önce 1 dk yük ortalaması > 8 ise koşuyu ATAR (çıkış 3).
# - uptime önce/sonra raw/<ad>.load.txt içine yazılır. Ham JSON: raw/<ad>.json, Godot günlükleri raw/<ad>.out.log/.err.log.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
name="${1:?kullanım: run_baseline.sh <ad> -- <probe argümanları>}"
shift
[ "${1:-}" = "--" ] && shift
raw="$root/experiments/m3_baseline/raw"
mkdir -p "$raw"
lock=/tmp/imaro-godot.lock
have_lock=0
release() { [ "$have_lock" = 1 ] && rmdir "$lock" 2>/dev/null || true; }
trap release EXIT
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -gt 360 ] && { echo "run_baseline: kilit alınamadı (60 dk)" >&2; exit 4; }
  echo "run_baseline: kilit dolu, 10 sn bekleniyor ($tries)" >&2
  sleep 10
done
have_lock=1
load1() { sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}'; }
l0="$(load1)"
if awk -v l="$l0" 'BEGIN{exit !(l > 8)}'; then
  echo "run_baseline: yük $l0 > 8, koşu atlandı" >&2
  exit 3
fi
{
  echo "ad: $name"
  echo "başlangıç: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "uptime önce: $(uptime)"
} >"$raw/$name.load.txt"
set +e
"$root/tools/godot.sh" --headless --path "$root" --script res://experiments/m3_baseline/m3_baseline_probe.gd -- \
  "--out=$raw/$name.json" "$@" >"$raw/$name.out.log" 2>"$raw/$name.err.log"
rc=$?
set -e
{
  echo "bitiş: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "uptime sonra: $(uptime)"
  echo "godot çıkış kodu: $rc"
} >>"$raw/$name.load.txt"
cat "$raw/$name.load.txt"
exit "$rc"
