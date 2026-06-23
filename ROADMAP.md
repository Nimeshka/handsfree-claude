# Roadmap

Where handsfree-claude is and where it could go. Ordered by impact-to-effort, with the
honest reasoning behind each item. Nothing here is required for v1 to be useful — it works
today. This is the "make it excellent" list.

## v1.0 — shipped
- Continuous, hands-free voice loop (no push-to-talk): mic → energy-VAD turn detection →
  warm nemotron ASR (`speech-server`) → `/cruise` skill → macOS `say` (Evan Enhanced).
- File-decoupled processes (inbox/outbox JSONL); blocking `next_turn.sh` so Claude waits on
  I/O instead of polling.
- Heartbeat-scoped mic lifecycle; multi-modal session exit (speech / signal file / command).
- Fully local / offline on Apple Silicon. ~0.1s TTS time-to-first-audio.

## v1.1 — robustness & polish (low risk, high value)
- **Silero VAD option** (`speech vad-stream`) as an alternative to energy-VAD — far more
  reliable turn detection in noisy rooms; energy-VAD stays the zero-dep default.
- **Persistent conversation log** — archive `inbox.jsonl` / `outbox.jsonl` to
  `logs/transcript-<timestamp>.jsonl` on session end instead of truncating, so the voice
  side is greppable later (complements the Claude Code transcript).
- **Config validation** on startup — fail fast with a clear message on a bad `config.json`
  (unknown engine, unreachable server, missing voice) instead of silent no-audio.
- **Single-instance guard** — detect/replace a stale listener reliably so two never fight
  for the mic.
- **Latency + health metrics** — optional timing logs (capture→ASR→inbox, reply→audio) to
  make tuning data-driven.

## v2.0 — the experience leap
- **Warm neural TTS via the WebSocket Realtime API** (`speech-server` `/v1/realtime`).
  Today neural voices (kokoro/qwen3-tts) reload per call (~25s) so we use `say`. A persistent
  WS client would give natural neural voice at sub-second latency. Biggest single upgrade;
  also the most involved (stateful protocol, audio streaming, playback buffering).
- **Barge-in / interruption** — let the user talk over a reply and have it stop and re-listen.
  Requires acoustic echo cancellation (the `speech` toolkit has `denoise`/`restore`) so the
  mic isn't dominated by the assistant's own audio; the current `speaking.lock` mute is the
  simple stand-in.
- **Streaming replies** — speak Claude's summary as it's generated rather than after, to cut
  perceived latency on longer answers.
- **Wake-word activation** (`speech wake`) — optional "listen only after the hotword" mode so
  the mic isn't continuously transcribing during a session.

## v3.0 — reach & packaging
- **Provider abstraction** for STT and TTS — clean interfaces so backends are swappable
  (local `speech` toolkit, whisper.cpp, cloud APIs) via config, not code edits.
- **Cross-platform** — Linux/Windows capture + STT/TTS backends (currently macOS/Apple
  Silicon only). The file-bus architecture is already OS-agnostic; only the edges aren't.
- **Speaker diarization** (`speech diarize`) — ignore other voices / only act on the primary
  speaker, for shared or noisy spaces.
- **Packaging** — a one-command installer or menu-bar controller (start/stop/status), and a
  Homebrew formula.
- **Tests + CI** — unit tests for VAD segmentation, stop-phrase matching, the cursor/loop
  protocol, and the IPC contract; lint + shellcheck in CI.

## Non-goals (for now)
- Cloud-first operation — local/offline is a core value of the project.
- Replacing Claude Code's official voice dictation — this is a different shape (continuous,
  two-way, on-device); it complements it.
- Telemetry — no usage tracking; everything stays on the machine.

## Principles to keep
- Local-first and private by default.
- Decoupled processes + plain-file IPC — easy to reason about, debug, and restart.
- Degrade gracefully — a missing optional model should never brick the basic loop.
