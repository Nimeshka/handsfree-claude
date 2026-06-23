#!/usr/bin/env bash
# Verify prerequisites. The default path needs NO model downloads — it reuses the
# `speech` ASR server (nemotron, already cached) and macOS `say` for TTS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ok=1
need() { command -v "$1" >/dev/null 2>&1 && echo "  ok: $1" || { echo "  MISSING: $1"; ok=0; }; }

echo "Binaries:"
need speech-server
need ffmpeg
need curl
need say

echo "Python with sounddevice + numpy:"
PYBIN=""
for c in python3.10 python3.11 python3.12 python3.13 python3; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sounddevice, numpy" >/dev/null 2>&1; then
    PYBIN="$c"; echo "  ok: $c ($($c --version 2>&1))"; break
  fi
done
if [ -z "$PYBIN" ]; then
  echo "  none found. On wifi, run:  python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  ok=0
fi

echo
if [ "$ok" = 1 ]; then
  echo "All set — no downloads needed. Run: scripts/start.sh"
else
  echo "Resolve the items above, then re-run scripts/setup.sh"
  exit 1
fi
