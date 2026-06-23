#!/usr/bin/env python3
"""Watch outbox.jsonl and speak new replies. Pluggable TTS engine (config.json -> tts.engine):

  "say"    macOS built-in `say` (no download, instant)            [default]
  "kokoro" `speech kokoro` (Kokoro-82M CoreML) -> afplay          [downloads model on 1st use]
  "speak"  `speech speak --play` (Qwen3-TTS etc.)                  [downloads model on 1st use]

Holds runtime/speaking.lock while talking so listen.py mutes itself (no echo).
Only uses stdlib, so it runs on any Python.
"""
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def load_config():
    with open(ROOT / "config.json") as f:
        return json.load(f)


def synthesize(text, tts):
    engine = tts.get("engine", "say")
    if engine == "say":
        cmd = ["say", "-r", str(tts.get("rate", 190))]
        if tts.get("voice"):
            cmd += ["-v", tts["voice"]]
        cmd.append(text)
        subprocess.run(cmd)
    elif engine == "speak":
        subprocess.run(["speech", "speak", text, "--play"])
    elif engine == "kokoro":
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            wav = tmp.name
        try:
            subprocess.run(
                ["speech", "kokoro", text, "-o", wav,
                 "--voice", tts.get("kokoro_voice", "af_heart")]
            )
            subprocess.run(["afplay", wav])
        finally:
            Path(wav).unlink(missing_ok=True)
    else:
        subprocess.run(["say", text])


def main():
    cfg = load_config()
    tts = cfg["tts"]
    outbox = ROOT / cfg["paths"]["outbox"]
    lock = ROOT / cfg["paths"]["speaking_lock"]
    outbox.parent.mkdir(parents=True, exist_ok=True)
    outbox.touch(exist_ok=True)

    pos = outbox.stat().st_size  # start at end — don't replay backlog
    log(f"[speak] ready (engine={tts.get('engine', 'say')}).")
    try:
        while True:
            size = outbox.stat().st_size
            if size < pos:       # truncated (new session)
                pos = 0
            if size > pos:
                with open(outbox) as f:
                    f.seek(pos)
                    chunk = f.read()
                    pos = f.tell()
                for line in chunk.splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    text = (rec.get("text") or "").strip()
                    if not text:
                        continue
                    log(f"[claude] {text}")
                    lock.touch()
                    try:
                        synthesize(text, tts)
                    finally:
                        time.sleep(0.3)  # let the tail of audio decay
                        lock.unlink(missing_ok=True)
            time.sleep(0.15)
    except KeyboardInterrupt:
        lock.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
