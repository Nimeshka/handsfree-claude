# handsfree-claude — Architecture

Hands-free voice mode for Claude Code (`/cruise`). You talk, Claude listens, does the
work, and talks back — no button presses, no looking at the screen. Built to run
**fully on-device** with **no per-session downloads**.

## Design principle: decoupled processes + plain files

Three independent processes never call each other directly. They communicate through
append-only files on disk. Any one can crash and restart without breaking the others, and
Claude (running in the Claude Code app) participates just by reading/writing those files.

```
 ┌────────────┐   mic     ┌──────────────┐   utterance.wav (HTTP)   ┌────────────────┐
 │   You 🎤   │ ────────▶ │  listen.py   │ ───────────────────────▶ │  speech-server │
 └────────────┘           │ energy-VAD:  │                          │  (warm ASR)    │
        ▲                  │ end-of-turn  │ ◀─────────────────────── │  nemotron      │
        │                  │ on a pause   │      transcribed text    └────────────────┘
        │ 🔊               └──────┬───────┘
        │                         │ append {ts,text}
        │                         ▼
 ┌────────────┐          runtime/inbox.jsonl
 │  speak.py  │                   │
 │ say: Evan  │                   │ next_turn.sh BLOCKS, prints the new line(s)
 │ (Enhanced) │                   ▼
 └─────▲──────┘          ┌──────────────────────┐
       │ read           │  Claude  (/cruise)    │   the loop:
       │                │  in Claude Code app    │   1. next_turn.sh  (wait for you)
 runtime/outbox.jsonl ◀─┤  reads inbox,          │   2. do the work (normal tools)
       reply.sh appends │  does work, replies    │   3. reply.sh  (speak a summary)
                        └──────────────────────┘   4. repeat
```

## Components

### 1. `bin/listen.py` — microphone → text
- Captures the mic with **`sounddevice`** (16 kHz mono, 30 ms frames) on **`python3.10`**
  (the interpreter on this machine that already has `sounddevice` + `numpy`).
- **Turn detection** is **energy-based VAD**: RMS per frame vs `vad.energy_threshold`;
  after `vad.silence_ms` of trailing silence it finalizes the utterance (with a ~300 ms
  pre-roll so the first word isn't clipped).
- Sends the finalized clip to the warm ASR server via `curl` (no model loaded in-process).
- `is_junk()` drops common single-word ASR hallucinations ("you", "thanks", "uh", …).
- Appends `{"ts", "text", "final"}` to `runtime/inbox.jsonl`.
- **Mute-while-speaking:** if `runtime/speaking.lock` exists, it discards audio (so it
  never transcribes Claude's own voice — important when output plays over speakers).
- **Auto-stop:** watches `runtime/cruise.alive`; if that heartbeat goes stale
  (`cruise.idle_stop_seconds`, default 60s) it exits and releases the mic.

### 2. `speech-server` + nemotron — speech-to-text (warm)
- The `speech` toolkit's HTTP server (`speech-server`, Apple-Silicon, port 8089).
- Endpoint used: **`POST /v1/audio/transcriptions`** (OpenAI-compatible, multipart WAV).
- Keeps the ASR model **warm** across the whole session, so per-utterance latency is low.
- Started/warmed by `scripts/start.sh`; left running between cruises (it never touches the
  mic, so it's not a privacy concern).

### 3. `bin/next_turn.sh` — the "Claude keeps reading the file" trick
- **Blocks** until the next finished utterance lands in `inbox.jsonl`, prints it, exits.
- A line **cursor** (`runtime/.inbox_cursor`) ensures each call returns only new turns and
  batches any that arrived while Claude was working.
- Every poll it touches `runtime/cruise.alive` — this heartbeat is what keeps `listen.py`
  alive during a session and lets it auto-stop shortly after the loop ends.
- This is why Claude isn't busy-polling: it waits on I/O, returning only when you've spoken.

### 4. `bin/reply.sh` + `bin/speak.py` — text → voice
- `reply.sh` appends `{"ts","text"}` to `runtime/outbox.jsonl`.
- `speak.py` tails the outbox and speaks each new line. While speaking it holds
  `runtime/speaking.lock` (the mute signal for the listener).
- **Engine: macOS `say`** with the **`Evan (Enhanced)`** voice — Siri-grade quality,
  ~0.1s to first audio, offline. (Engine is pluggable: `say` | `kokoro` | `speak`.)

### 5. `.claude/skills/cruise/SKILL.md` — the conversation behavior
- Installed **globally** at `~/.claude/skills/cruise/` so `/cruise` works in both Claude
  Code **CLI and Desktop**, from any directory. Uses **absolute paths** to the scripts.
- Encodes the loop and the "talk like a colleague, not a document" speaking rules
  (1–4 sentences, lead with the outcome, never read code/paths aloud, one question at a
  time, confirm before anything destructive on a garbled instruction).

## Lifecycle (mic is hot only during a cruise)

| Event | Effect |
|---|---|
| `/cruise` | `start.sh` clean-restarts a fresh `listen.py` + `speak.py`, ensures/warms server, resets channels + heartbeat |
| During the session | `next_turn.sh` refreshes `cruise.alive` continuously → listener stays alive even through long silences |
| "exit hands-free" | `stop.sh` kills listener + speaker immediately; mic released |
| Session closed / abandoned | heartbeat goes stale → `listen.py` self-exits within ~60s; mic released |

## Models & tools used

| Role | What | Notes |
|---|---|---|
| **STT model** | `Nemotron-3.5-ASR-Streaming-0.6B` (CoreML INT8) | via `speech-server`, kept warm; cached locally |
| **STT server** | `speech-server` (from `soniqo/tap/speech`) | OpenAI-compatible `/v1/audio/transcriptions` |
| **VAD** | Energy/RMS, custom in `listen.py` | zero-dependency; `speech vad-stream` (Silero) is a possible upgrade |
| **Audio capture** | `sounddevice` + `numpy` on `python3.10` | 16 kHz mono, 30 ms frames |
| **TTS** | macOS `say`, voice `Evan (Enhanced)` | ~0.1s latency, offline; pluggable to neural engines |
| **Orchestration** | Claude Code skill `/cruise` + blocking `next_turn.sh` | global skill, absolute paths |
| **Config** | `config.json` (stdlib JSON) | chosen over TOML so it works on py3.10 (no `tomllib`) |

### Considered but not used
- **faster-whisper** (small/medium cached) — replaced by the warm nemotron server (lower
  latency, no in-process model load, no extra Python deps).
- **kokoro / qwen3-tts** neural voices — the `speech` CLI reloads the model **per call
  (~25s)**, unusable per-reply. Warm neural TTS would need the server's WebSocket Realtime
  API (`/v1/realtime`) — a future upgrade.

## Files at runtime

```
runtime/
  inbox.jsonl       you → Claude   (append-only, timestamped utterances)
  outbox.jsonl      Claude → you   (append-only spoken replies)
  .inbox_cursor     next_turn.sh's read position
  speaking.lock     present while speak.py is talking (listener mutes)
  cruise.alive      heartbeat; stale ⇒ listener self-stops
  *.pid             daemon process ids
```

## Possible future upgrades
- **Warm neural TTS** via `speech-server` WebSocket Realtime API (best voice + low latency).
- **Silero VAD** (`speech vad-stream`) for more robust turn detection in noisy environments.
- **Barge-in** (interrupt Claude mid-sentence by talking) using hardware echo cancellation.
- **Wake word** (`speech wake`) instead of always-listening during a cruise.
