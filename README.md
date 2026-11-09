# jarvis

Personal setup for [OpenJarvis](https://github.com/open-jarvis/OpenJarvis), a local-first personal AI framework, with a voice assistant.

## Setup (Linux)

```bash
./scripts/setup-openjarvis.sh
```

This installs (idempotently):

- `uv` (if missing) and an OpenJarvis source checkout at `~/OpenJarvis` with its Python env
- Ollama (CPU build) as the inference engine, plus the `qwen3.5:2b` starter model
- Voice: Whisper `base` (speech-to-text) and Kokoro (text-to-speech, voice `bm_george`), plus `espeak-ng` / `libportaudio2`
- `~/.openjarvis/config.toml` (engine `ollama`, model `qwen3.5:2b`, `[speech]` section, security profile `personal`)
- the optional Rust extension, and npm 11 for the GUI
- a `jarvis` symlink in `~/.local/bin`

Overrides: `OPENJARVIS_DIR`, `OPENJARVIS_MODEL`, `SKIP_RUST=1`, `SKIP_VOICE=1`.

## Use

```bash
./scripts/start-jarvis.sh   # starts Ollama + the browser GUI at http://127.0.0.1:5173
```

### Voice assistant

- **Browser GUI** (works from any device that can open the GUI): voice is on by default (via `scripts/voice-defaults.patch`; toggles are in Settings → Speech:
  *Speech-to-Text*, *Text-to-Speech*, *Speak replies automatically*). Click the mic next to the
  message box, speak, click it again to stop; the transcript lands in the box, press Enter, and the
  reply is read aloud.
- **Terminal** (needs a mic and speakers on the machine running Jarvis): `jarvis chat --voice`

### Text

```bash
jarvis                 # interactive chat
jarvis ask "Hello"     # one-shot question
jarvis doctor          # health check
```

## Cloud sessions

In Claude Code cloud sessions, use the `jarvis` environment. Its network allowlist includes the
Ollama registry and Hugging Face hosts that the model downloads need, and its setup script runs
`scripts/setup-openjarvis.sh` once this is on the default branch.
