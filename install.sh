#!/usr/bin/env bash
# Install the /cruise skill for Claude Code (CLI + Desktop) and set up local config.
# Safe to re-run. No models are downloaded here.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing handsfree-claude from: $ROOT"

# 1. Install the /cruise skill globally, stamping in this project's absolute path.
SKILL_DIR="$HOME/.claude/skills/cruise"
mkdir -p "$SKILL_DIR"
sed "s|__HANDSFREE_DIR__|$ROOT|g" "$ROOT/skill/SKILL.md" > "$SKILL_DIR/SKILL.md"
echo "  ✓ skill installed at $SKILL_DIR/SKILL.md (usable as /cruise in CLI + Desktop)"

# 2. First-run config from the example (never overwrite an existing local config).
if [ ! -f "$ROOT/config.json" ]; then
  cp "$ROOT/config.example.json" "$ROOT/config.json"
  echo "  ✓ created config.json from config.example.json"
else
  echo "  • config.json already exists — left as-is"
fi

# 3. Executable bits + runtime dir.
chmod +x "$ROOT"/bin/*.sh "$ROOT"/scripts/*.sh 2>/dev/null || true
mkdir -p "$ROOT/runtime" "$ROOT/logs"

# 4. Binary prerequisites (non-fatal — you install these once, see README).
echo "Checking prerequisites:"
for b in speech-server ffmpeg curl say; do
  command -v "$b" >/dev/null 2>&1 && echo "  ✓ $b" || echo "  ✗ $b  (missing — see README)"
done

# 5. Self-contained Python venv for the listener (sounddevice + numpy). Deterministic,
#    and start.sh prefers .venv/bin/python3, so the two always line up.
if [ ! -x "$ROOT/.venv/bin/python3" ]; then
  PYBUILD=""
  for c in python3.12 python3.11 python3.13 python3.10 python3; do
    command -v "$c" >/dev/null 2>&1 && { PYBUILD="$c"; break; }
  done
  if [ -z "$PYBUILD" ]; then
    echo "  ✗ no python3 found — install Python 3.10+ and re-run install.sh"
  else
    echo "  • creating .venv with $PYBUILD ..."
    "$PYBUILD" -m venv "$ROOT/.venv"
  fi
fi
if [ -x "$ROOT/.venv/bin/python3" ]; then
  "$ROOT/.venv/bin/python3" -m pip install -q --upgrade pip
  "$ROOT/.venv/bin/python3" -m pip install -q -r "$ROOT/requirements.txt"
  if "$ROOT/.venv/bin/python3" -c "import sounddevice, numpy" >/dev/null 2>&1; then
    echo "  ✓ python deps installed in .venv"
  else
    echo "  ✗ python deps failed to import — check the pip output above"
  fi
fi

echo
echo "Done. Restart Claude Code Desktop to register /cruise, then:"
echo "  $ROOT/scripts/start.sh   # start mic listener + speaker"
echo "  /cruise                  # in Claude Code"
