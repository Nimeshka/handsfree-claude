#!/usr/bin/env bash
# Queue a spoken reply: append one JSON line to outbox.jsonl for speak.py to voice.
# Usage: bin/reply.sh "Done — I added the login route. Want a test for it?"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTBOX="$ROOT/runtime/outbox.jsonl"
mkdir -p "$ROOT/runtime"

TEXT="$*"
[ -n "$TEXT" ] || { echo "usage: reply.sh <text>" >&2; exit 1; }

python3 -c '
import json, sys, time
print(json.dumps({"ts": time.time(), "text": sys.argv[1]}))
' "$TEXT" >> "$OUTBOX"
