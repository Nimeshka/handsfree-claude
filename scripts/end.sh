#!/usr/bin/env bash
# End the current cruise session from anywhere (e.g. another terminal).
# Drops a stop signal; next_turn.sh sees it and tells Claude to exit the loop, which
# then runs stop.sh. (For an immediate hard stop, just run scripts/stop.sh directly.)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/runtime"
touch "$ROOT/runtime/cruise.stop"
echo "Stop signal sent — cruise will end on the next turn."
