#!/usr/bin/env bash
# Start everything for hands-free mode:
#   1. speech-server (warm ASR; reused if already up)  2. speak.py  3. listen.py
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p runtime logs

# --- find a Python that already has sounddevice + numpy (no install needed) ---
PYBIN="${PYBIN:-}"
if [ -z "$PYBIN" ]; then
  for c in "$ROOT/.venv/bin/python3" python3.10 python3.11 python3.12 python3.13 python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sounddevice, numpy" >/dev/null 2>&1; then
      PYBIN="$c"; break
    fi
  done
fi
[ -n "$PYBIN" ] || { echo "No Python with sounddevice+numpy found. Run scripts/setup.sh (needs wifi)." >&2; exit 1; }
echo "Using Python: $PYBIN"

# --- speech-server (ASR). Reuse if already healthy; otherwise start + warm it. ---
PORT="$(python3 -c 'import json,re;u=json.load(open("config.json"))["stt"]["server_url"];print(u.rsplit(":",1)[-1])')"
MODEL="$(python3 -c 'import json;print(json.load(open("config.json"))["stt"]["model"])')"
BASE="http://127.0.0.1:${PORT}"
if ! curl -sf "$BASE/health" >/dev/null 2>&1; then
  echo "Starting speech-server on :$PORT ..."
  speech-server --port "$PORT" >> logs/server.log 2>&1 &
  echo $! > runtime/server.pid
  for _ in $(seq 1 60); do curl -sf "$BASE/health" >/dev/null 2>&1 && break; sleep 0.5; done
fi
echo "Warming $MODEL (loads from cache; no download) ..."
ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=r=16000:cl=mono -t 1 -y runtime/warm.wav
curl -s -X POST "$BASE/v1/audio/transcriptions" -F file=@runtime/warm.wav -F model="$MODEL" >/dev/null || true

# --- stop any leftover listener/speaker so we don't double-grab the mic ---
for p in listen speak; do
  [ -f "runtime/$p.pid" ] && kill "$(cat "runtime/$p.pid")" 2>/dev/null || true
done
pkill -f "$ROOT/bin/listen.py" 2>/dev/null || true
pkill -f "$ROOT/bin/speak.py" 2>/dev/null || true

# --- fresh conversation channels + heartbeat (starts the listener's grace window) ---
: > runtime/inbox.jsonl
: > runtime/outbox.jsonl
echo 0 > runtime/.inbox_cursor
rm -f runtime/speaking.lock runtime/cruise.stop
touch runtime/cruise.alive

"$PYBIN" bin/speak.py  >> logs/speak.log  2>&1 &
echo $! > runtime/speak.pid
"$PYBIN" bin/listen.py >> logs/listen.log 2>&1 &
echo $! > runtime/listen.pid

echo "Started: server(:$PORT), listen.py (pid $(cat runtime/listen.pid)), speak.py (pid $(cat runtime/speak.pid))"
echo "Logs: logs/listen.log  logs/speak.log  logs/server.log"
echo "Now run /cruise in Claude Code. (Grant mic permission to the terminal if macOS asks.)"
