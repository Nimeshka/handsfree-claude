#!/usr/bin/env bash
# Block until the next finished user utterance(s) appear in inbox.jsonl, print their
# text (one per line), and exit. A line cursor ensures each call returns only NEW turns.
# Exits empty after $1 seconds (default 270) so the caller can simply call again.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INBOX="$ROOT/runtime/inbox.jsonl"
CURSOR="$ROOT/runtime/.inbox_cursor"
HEARTBEAT="$ROOT/runtime/cruise.alive"
STOP="$ROOT/runtime/cruise.stop"
TIMEOUT="${1:-270}"

mkdir -p "$ROOT/runtime"
touch "$INBOX" "$HEARTBEAT"
[ -f "$CURSOR" ] || echo 0 > "$CURSOR"

start=$(date +%s)
while true; do
  touch "$HEARTBEAT"   # tell the listener the cruise loop is still alive
  # End-of-session signal (spoken stop phrase, or scripts/end.sh): tell Claude to exit.
  if [ -f "$STOP" ]; then
    rm -f "$STOP"
    echo "__CRUISE_EXIT__"
    exit 0
  fi
  total=$(wc -l < "$INBOX" | tr -d ' ')
  seen=$(cat "$CURSOR")
  if [ "$total" -gt "$seen" ]; then
    sed -n "$((seen + 1)),${total}p" "$INBOX" | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        t = json.loads(line).get("text", "").strip()
        if t:
            print(t)
    except Exception:
        pass
'
    echo "$total" > "$CURSOR"
    exit 0
  fi
  now=$(date +%s)
  if [ "$((now - start))" -ge "$TIMEOUT" ]; then
    exit 0
  fi
  sleep 0.2
done
