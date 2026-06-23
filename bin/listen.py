#!/usr/bin/env python3
"""Mic -> energy VAD (turn ends on a pause) -> warm speech-server (nemotron) -> inbox.jsonl.

No ASR model is loaded in this process. Captured utterances are POSTed to the
already-running `speech-server` (which keeps the cached nemotron model warm), so
there are no downloads and per-turn latency stays low. Stays muted while the
assistant is speaking (runtime/speaking.lock) to avoid transcribing its own voice.

Only depends on `sounddevice` + `numpy` (the rest is stdlib), so it runs on the
Python that already has them (e.g. python3.10).
"""
import collections
import json
import re
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

import numpy as np
import sounddevice as sd

ROOT = Path(__file__).resolve().parent.parent


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def load_config():
    with open(ROOT / "config.json") as f:
        return json.load(f)


def transcribe(wav_path, stt):
    """POST a WAV to the speech-server transcription endpoint; return the text."""
    url = stt["server_url"].rstrip("/") + "/v1/audio/transcriptions"
    proc = subprocess.run(
        ["curl", "-s", "-X", "POST", url,
         "-F", f"file=@{wav_path}",
         "-F", f"model={stt['model']}",
         "-F", f"language={stt['language']}"],
        capture_output=True, text=True,
    )
    try:
        return (json.loads(proc.stdout).get("text") or "").strip()
    except Exception:
        log(f"[listen] transcription error: {proc.stdout[:200]} {proc.stderr[:200]}")
        return ""


# Common ASR hallucinations on silence/noise — dropped if they're the whole turn.
JUNK_TURNS = {
    "you", "thank you", "thank you.", "thanks", "bye", "bye.", ".", "uh", "um",
    "okay", "ok", "yeah", "mm", "mhm", "hmm", "so", "the",
}


def is_junk(text):
    """True if a transcription looks like ASR noise rather than a real utterance."""
    t = text.strip().lower()
    if not t:
        return True
    stripped = t.strip(" .,!?-")
    if stripped in JUNK_TURNS:
        return True
    # A single very short word with no other content is almost always noise.
    if len(stripped) <= 2 and " " not in stripped:
        return True
    return False


# Spoken phrases that end the cruise session (multi-word, to avoid accidental triggers).
STOP_PHRASES = (
    "exit hands free", "exit hands-free", "exit cruise", "exit cruise mode",
    "stop cruise", "end cruise", "stop hands free", "end hands free",
    "stop cruise mode", "stop hands-free", "end hands-free",
)


def is_stop_phrase(text):
    """True if the utterance is a request to end cruise mode."""
    norm = re.sub(r"[^a-z0-9]+", " ", text.lower())
    norm = " ".join(norm.split())
    return any(p in norm for p in STOP_PHRASES)


def main():
    cfg = load_config()
    a, v, stt = cfg["audio"], cfg["vad"], cfg["stt"]

    sr = a["sample_rate"]
    frame_ms = a["frame_ms"]
    frame_len = int(sr * frame_ms / 1000)
    silence_frames = max(1, v["silence_ms"] // frame_ms)
    min_speech_frames = max(1, v["min_speech_ms"] // frame_ms)
    threshold = v["energy_threshold"]

    inbox = ROOT / cfg["paths"]["inbox"]
    lock = ROOT / cfg["paths"]["speaking_lock"]
    heartbeat = ROOT / cfg["paths"].get("heartbeat", "runtime/cruise.alive")
    stop_signal = ROOT / cfg["paths"].get("stop_signal", "runtime/cruise.stop")
    idle_stop = cfg.get("cruise", {}).get("idle_stop_seconds", 60)
    inbox.parent.mkdir(parents=True, exist_ok=True)
    device = a["device"] or None
    # Check the cruise heartbeat about once a second.
    check_every = max(1, int(sr / frame_len))
    frame_count = 0

    preroll = collections.deque(maxlen=max(1, 300 // frame_ms))  # ~300ms lead-in
    voiced = []
    triggered = False
    num_silence = 0

    def rms(frame):
        x = np.frombuffer(frame, dtype=np.int16).astype(np.float32) / 32768.0
        return float(np.sqrt(np.mean(x * x))) if x.size else 0.0

    def emit(frames):
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            path = Path(tmp.name)
        try:
            with wave.open(str(path), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(sr)
                w.writeframes(b"".join(frames))
            text = transcribe(path, stt)
            if text and is_stop_phrase(text):
                stop_signal.touch()
                log(f"[stop] heard '{text}' — ending cruise.")
            elif text and not is_junk(text):
                rec = {"ts": time.time(), "text": text, "final": True}
                with open(inbox, "a") as f:
                    f.write(json.dumps(rec) + "\n")
                log(f"[you] {text}")
            elif text:
                log(f"[skip] {text}")
        finally:
            path.unlink(missing_ok=True)

    log(f"[listen] ready (server={stt['server_url']}, model={stt['model']}). "
        "Talk; pause to send. Ctrl-C to quit.")
    stream = sd.RawInputStream(
        samplerate=sr, blocksize=frame_len, dtype="int16", channels=1, device=device
    )
    stream.start()
    try:
        while True:
            data, _ = stream.read(frame_len)
            frame = bytes(data)

            # Auto-stop (release the mic) once the cruise loop stops refreshing the
            # heartbeat — i.e. shortly after the session ends, however it ended.
            frame_count += 1
            if idle_stop and frame_count % check_every == 0 and heartbeat.exists():
                if time.time() - heartbeat.stat().st_mtime > idle_stop:
                    log("[listen] cruise heartbeat stale — stopping, mic released.")
                    break

            # Mute while the assistant is speaking; discard echo.
            if lock.exists():
                triggered, voiced, num_silence = False, [], 0
                preroll.clear()
                continue

            is_speech = rms(frame) >= threshold
            if not triggered:
                preroll.append(frame)
                if is_speech:
                    triggered = True
                    voiced = list(preroll)
                    preroll.clear()
                    num_silence = 0
            else:
                voiced.append(frame)
                if is_speech:
                    num_silence = 0
                else:
                    num_silence += 1
                    if num_silence >= silence_frames:
                        if len(voiced) - num_silence >= min_speech_frames:
                            emit(voiced)
                        triggered, voiced, num_silence = False, [], 0
    except KeyboardInterrupt:
        pass
    finally:
        stream.stop()
        stream.close()


if __name__ == "__main__":
    main()
