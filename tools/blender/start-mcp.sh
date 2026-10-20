#!/bin/bash
# Launch Blender (GUI) with the MCP bridge for interactive exploration.
# Usage: tools/blender/start-mcp.sh [file.blend]
# Stop: quit Blender normally (Cmd+Q) or `kill $(cat /tmp/imaro-blender-mcp.pid)`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER="${BLENDER_BIN:-/Applications/Blender.app/Contents/MacOS/Blender}"
PORT="${BLENDER_PORT:-9876}"
PIDFILE="${TMPDIR:-/tmp}/imaro-blender-mcp.pid"
LOG="${TMPDIR:-/tmp}/imaro-blender-mcp.log"

[ -x "$BLENDER" ] || { echo "Blender not found: $BLENDER (set BLENDER_BIN)" >&2; exit 1; }
if nc -z localhost "$PORT" 2>/dev/null; then
  echo "Port $PORT already has a listener; not starting a second Blender." >&2; exit 1
fi

export BLENDERMCP_NO_UPDATE_CHECK=1 BLENDER_PORT="$PORT"
# --factory-startup: do not load the user's prefs/enabled addons (a separately installed
# blender_mcp addon would otherwise grab the port with an older protocol) and never write
# prefs on exit. Nothing here touches ~/Library/Application Support/Blender.
ARGS=(--factory-startup)
if [ $# -ge 1 ]; then ARGS+=("$1"); fi
ARGS+=(--python "$HERE/start_mcp_blender.py")

"$BLENDER" "${ARGS[@]}" >"$LOG" 2>&1 &
echo $! >"$PIDFILE"
echo "Blender started (pid $(cat "$PIDFILE"), log $LOG); waiting for port $PORT ..."
for _ in $(seq 1 60); do
  if nc -z localhost "$PORT" 2>/dev/null; then echo "MCP bridge listening on localhost:$PORT"; exit 0; fi
  kill -0 "$(cat "$PIDFILE")" 2>/dev/null || { echo "Blender exited early; see $LOG" >&2; exit 1; }
  sleep 1
done
echo "Timed out waiting for port $PORT; see $LOG" >&2; exit 1
