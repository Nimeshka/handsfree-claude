# handsfree-claude (`/cruise`)

**Hands-free voice mode for Claude Code.** Speak to it, Claude listens, does the work, and
talks back — no button presses, no reading the screen. Useful any time your hands or eyes
are busy, or as a more comfortable way to work by voice. Runs **fully local / offline** on
Apple Silicon.

> **Why this exists / how it differs from the built-in.** Claude Code now has official
> [voice dictation](https://code.claude.com/docs/en/voice-dictation) — but it's
> **push-to-talk, speech-to-text only**, and streams audio to the cloud. This project is
> **continuous and hands-free** (no key per turn — voice-activity detection ends a turn on
> a pause), **two-way** (it speaks replies back), and **fully on-device**. It's built for
> eyes-off, hands-free use. There are also nice community projects in this space
> (e.g. [voicemode](https://github.com/mbailey/voicemode),
> [voice-mcp](https://github.com/shreyaskarnik/voice-mcp)); this is one take, tuned for
> hands-free use and privacy.

## Requirements

- **macOS on Apple Silicon** (uses CoreML/Neural-Engine speech models and `say`).
- **[`speech`](https://github.com/soniqo/speech) toolkit** (provides `speech-server`):
  `brew install soniqo/tap/speech`
- **`ffmpeg`** (`brew install ffmpeg`) and **`curl`** (built in).
- **Python 3.10+** with `sounddevice` + `numpy` (`pip install -r requirements.txt`).
- **Claude Code** (CLI or Desktop), signed in.

First run downloads the small ASR model (nemotron) once. TTS uses macOS `say` (no
download); a premium voice is optional (see Config).

## How it works

Three pieces talk through plain files, so any one can restart without breaking the others:

```
mic → listen.py ───────────────▶ runtime/inbox.jsonl ─▶ /cruise (Claude) ─▶ runtime/outbox.jsonl ─▶ speak.py ─▶ speaker
       energy-VAD finds the          append-only,         reads the turn,        concise spoken         say / kokoro
       end of your turn, then         timestamped         does the work,         summary
       POSTs the clip to the                              replies
       warm speech-server (ASR)
```

- **`bin/listen.py`** captures the mic, detects end-of-turn by a short pause, and POSTs the
  utterance to the warm `speech-server` (`/v1/audio/transcriptions`, nemotron). No ASR
  model is loaded in-process — the server keeps it warm. Needs only `sounddevice`+`numpy`.
- **`bin/next_turn.sh`** is the trick that lets Claude "keep reading the file": it *blocks*
  until your next finished utterance lands, prints it, and exits. Claude calls it in a
  loop, so it waits on I/O instead of busy-polling.
- **`bin/speak.py`** watches `runtime/outbox.jsonl` and speaks each new reply. While
  talking it drops `runtime/speaking.lock` so the listener mutes itself and doesn't
  transcribe Claude's own voice.
- **`skill/SKILL.md`** is the `/cruise` skill — the loop plus the rules that make Claude
  speak like a conversational assistant, not dump walls of text. `install.sh` puts it in
  `~/.claude/skills/` so `/cruise` works in both Claude Code CLI and Desktop.

## Install

```bash
git clone https://github.com/Nimeshka/handsfree-claude.git
cd handsfree-claude
./install.sh
```

`install.sh` does everything: creates a self-contained `.venv` with the Python deps,
installs the `/cruise` skill into `~/.claude/skills/` (so it works in both CLI and
Desktop), and copies `config.example.json` → `config.json`. It's re-runnable. Then
**restart Claude Code Desktop** so it registers `/cruise`.

You still need the system prerequisites from [Requirements](#requirements) first
(`speech` toolkit, `ffmpeg`, Python 3.10+).

## Use

1. Start the daemons (also starts/warms the ASR server):
   ```bash
   scripts/start.sh
   ```
2. In Claude Code (in this project), run:  `/cruise`
3. Talk. Pause when done; Claude replies out loud.
4. **End the session — three ways:**
   - **Speech:** say **"exit cruise"** / "stop cruise" / "exit hands-free" (detected by the
     listener directly, so it's reliable).
   - **Command:** run `scripts/end.sh` from any terminal (ends cleanly on the next turn).
   - **Hard stop:** `scripts/stop.sh` (add `--server` to also stop the ASR server).

## Config (`config.json`)

| Key | Meaning |
|---|---|
| `vad.energy_threshold` | RMS above this counts as speech (default 0.012). Raise it in a noisy room. |
| `vad.silence_ms` | Pause length that ends your turn (default 1500ms). |
| `vad.min_speech_ms` | Ignore blips shorter than this. |
| `stt.server_url` / `stt.model` | speech-server endpoint + ASR model (`nemotron` cached; also `omnilingual`, `qwen3`, `parakeet`). |
| `stt.language` | `en-US`. |
| `tts.engine` | `say` (default, no download) · `kokoro` · `speak`. |
| `tts.voice` / `tts.rate` | macOS voice (e.g. `Samantha`) and words/min for `say`. |
| `tts.kokoro_voice` | Voice for the `kokoro` engine (e.g. `af_heart`). |

## Models

Speech-to-text uses `speech-server`'s **`Nemotron ASR Streaming 0.6B`** (CoreML), which
stays warm so per-turn latency is low. Other engines the server supports (`omnilingual`,
`qwen3`, `parakeet`) work too — set `stt.model`. The model downloads once on first use.

**Voice quality:** the default `say` engine sounds great with a **premium/enhanced** macOS
voice. Download one in *System Settings → Accessibility → Read & Speak → System Voice →
Manage Voices* (e.g. `Evan (Enhanced)`, `Ava (Premium)`), then set `tts.voice` to its exact
name. This stays **instant** (~0.1s to first audio) and offline — the recommended setup.

The `kokoro` / `speak` engines exist but the `speech` **CLI reloads its model on every
call (~25s/reply)**, so they're not usable per-reply. Warm neural TTS would require using
the server's WebSocket Realtime API (`/v1/realtime`) — a future upgrade, not wired up.

## Notes

- **Echo:** the `speaking.lock` mute assumes the mic can't be fully suppressed while TTS
  plays over speakers. Headphones or a device with echo cancellation help.
- **Tuning VAD:** if turns end too early/late, adjust `vad.silence_ms`; if background noise
  triggers false turns, raise `vad.energy_threshold`.
- **Safety:** transcription is imperfect; the skill tells Claude to confirm before doing
  anything destructive on a garbled instruction.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and [ROADMAP.md](ROADMAP.md) for
what's next.

## Acknowledgements

- [`soniqo/speech`](https://github.com/soniqo/speech) — the on-device Apple Silicon speech
  toolkit (`speech-server`, nemotron ASR) this builds on.
- Claude Code's skill system and the broader community of voice-for-Claude-Code projects.

## License

[MIT](LICENSE) © 2026 Nimeshka Srimal
