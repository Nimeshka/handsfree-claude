#!/usr/bin/env bash
# Stop the listener and speaker. Leaves speech-server running by default (it's reusable
# and slow to warm); pass --server to stop it too.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

procs="listen speak"
[ "${1:-}" = "--server" ] && procs="$procs server"

for p in $procs; do
  pf="$ROOT/runtime/$p.pid"
  if [ -f "$pf" ]; then
    kill "$(cat "$pf")" 2>/dev/null || true
    rm -f "$pf"
  fi
done
rm -f "$ROOT/runtime/speaking.lock" "$ROOT/runtime/cruise.alive" "$ROOT/runtime/cruise.stop"
echo "Stopped: $procs"
