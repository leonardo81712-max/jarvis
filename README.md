# jarvis

Personal setup for [OpenJarvis](https://github.com/open-jarvis/OpenJarvis), a local-first personal AI framework.

## Setup (Linux)

```bash
./scripts/setup-openjarvis.sh
```

This installs (idempotently):

- `uv` (if missing) and an OpenJarvis source checkout at `~/OpenJarvis` with its Python env (`dev` + `server` extras)
- Ollama (CPU build) as the inference engine, plus the `qwen3.5:2b` starter model
- `~/.openjarvis/config.toml` (engine `ollama`, model `qwen3.5:2b`, security profile `personal`)
- the optional Rust extension (skip with `SKIP_RUST=1`)
- a `jarvis` symlink in `~/.local/bin`

Overrides: `OPENJARVIS_DIR`, `OPENJARVIS_MODEL`, `SKIP_RUST=1`.

## Use

```bash
ollama serve > ~/.openjarvis/logs/ollama.log 2>&1 &
jarvis                 # interactive chat
jarvis ask "Hello"     # one-shot question
jarvis doctor          # health check
```

## Cloud sessions

In Claude Code cloud sessions, use the `jarvis` environment. It allows
`registry.ollama.ai`, `ollama.com` and Ollama's download CDN, which model pulls need.
