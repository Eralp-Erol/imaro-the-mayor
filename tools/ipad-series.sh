#!/bin/bash
# iPad ölçüm serisi (TD koşu kitabı: production/log/2026-11-06-teknik-direktor-busy-bimodal.md §3).
# Gerekli ortam: IPAD (donanım UDID), CD (CoreDevice UUID), IMARO_IOS_TEAM_ID. Repoya kimlik YAZILMAZ.
# Sahip ön koşulları (şarj, Düşük Güç Modu kapalı, Otomatik Kilit "Hiçbir Zaman", Rahatsız Etme açık, arka plan yok)
# onaylayınca başlatmak için: touch "${IMARO_SERIES_GO:-/tmp/ipad-series.go}"
cd "$(dirname "$0")/.." || exit 1
: "${IPAD:?IPAD (donanim UDID) gerekli}" "${CD:?CD (CoreDevice UUID) gerekli}" "${IMARO_IOS_TEAM_ID:?IMARO_IOS_TEAM_ID gerekli}"
export IPAD CD IMARO_IOS_TEAM_ID
GO="${IMARO_SERIES_GO:-/tmp/ipad-series.go}"
LOGDIR="${IMARO_SERIES_LOGDIR:-/tmp}"
P=s$(date +%m%d)   # seri ön eki
log() { echo "$(date +%T) $*"; }
wake() { timeout 60 xcrun devicectl device info details --device "$CD" >/dev/null 2>&1; }
sidecar() { # A4: kosu oncesi/sonrasi cihaz yan kaydi (icerik dogrulanmadi)
  mkdir -p artifacts/perf/ipad-$1; for c in displays lockState; do timeout 60 xcrun devicectl device info $c --device "$CD" --json-output artifacts/perf/ipad-$1/side-$2-$c.json >/dev/null 2>&1; done; }
launch_retry() { # ad, bayraklar... ; kilitliyse 5 dk'da bir dener
  n=$1; shift
  while true; do wake; out=$(tools/ios-install.sh --launch-only --device "$IPAD" -- -- "$@" 2>&1)
    echo "$out" | grep -q "Launched application" && return 0
    log "LAUNCH_FAIL $n ($(echo "$out" | grep -oE 'BSErrorCodeDescription = [A-Za-z]+' | head -1)) 5 dk sonra"; sleep 300; done; }
run() { # ad maxbekleme bayraklar...
  n=$1; w=$2; shift 2; full=$P-$n; rm -rf artifacts/perf/ipad-$full; sidecar $full pre
  t0=$(date +%s); log "RUN $full start"; launch_retry $full --demo --perf-log=ipad-$full.json "$@"
  f=artifacts/perf/ipad-$full/ipad-$full.json
  for t in $(seq 1 $((w/15))); do sleep 15; wake; tools/ipad-pull-perf.sh --device "$IPAD" --dest artifacts/perf/ipad-$full >/dev/null 2>&1 || continue
    [ -f "$f" ] || continue
    st=$(jq -r '.started_unix // 0' "$f" | cut -d. -f1)
    [ "$st" -ge $((t0-5)) ] 2>/dev/null && [ "$(jq -r .complete "$f")" = true ] && break; done
  sidecar $full post
  st=$(jq -r '.started_unix // 0' "$f" 2>/dev/null | cut -d. -f1); fresh=no; [ "$st" -ge $((t0-5)) ] 2>/dev/null && fresh=yes
  log "RUN $full done fresh=$fresh complete=$(jq -r .complete "$f" 2>/dev/null) reason=$(jq -r .reason "$f" 2>/dev/null) hz=$(jq -r .refresh_hz "$f" 2>/dev/null) hzc=$(jq -r .refresh_hz_changed "$f" 2>/dev/null) modes=$(jq -c .mode_windows "$f" 2>/dev/null) is_mean=$(jq -r '.stable.is_ms_mean // "n/a"' "$f" 2>/dev/null) is_p95=$(jq -r '.stable.is_ms_p95 // "n/a"' "$f" 2>/dev/null) rest=$(jq -r '.stable.rest_ms_mean // "n/a"' "$f" 2>/dev/null) over=$(jq -r '.stable.over_interval_frac // "n/a"' "$f" 2>/dev/null) probe=$(jq -c '.cpu_probe_us // "n/a"' "$f" 2>/dev/null | head -c 80)"
}
log "WAIT_GO (sahip on kosullari onaylayinca: touch $GO)"
until [ -f "$GO" ]; do sleep 20; done
rm -f "$GO"
log GO; wake
tools/ios-install.sh --device "$IPAD" --release --no-export >"$LOGDIR/ipad-install.log" 2>&1 || { log INSTALL_FAIL; exit 1; }
log "INSTALLED; 15 dk sogutma"; sleep 900
for i in 1 2 3 4 5; do run S$i 240 --perf-log-frames=6000; sleep 60; done
run S6 240 --perf-log-frames=6000 --perf-log-no-render-measure; sleep 60
run U1 420 --perf-log-thermal=300; sleep 30
for i in 7 8 9; do run S$i 240 --perf-log-frames=6000; sleep 60; done
log SERIES_DONE
