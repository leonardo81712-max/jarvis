#!/usr/bin/env bash
# Install OpenJarvis (https://github.com/open-jarvis/OpenJarvis) from source on Linux,
# with Ollama as the local inference engine, a small starter model, and voice
# (Whisper speech-to-text + Kokoro text-to-speech).
# Idempotent: re-running skips steps that are already done.
#
# Env overrides:
#   OPENJARVIS_DIR    where to clone OpenJarvis   (default: $HOME/OpenJarvis)
#   OPENJARVIS_MODEL  Ollama model to pull/use     (default: qwen3.5:2b)
#   SKIP_RUST=1       skip building the optional Rust extension (~2.5 min)
#   SKIP_VOICE=1      skip voice dependencies and voice model downloads
set -euo pipefail

OJ_DIR="${OPENJARVIS_DIR:-$HOME/OpenJarvis}"
MODEL="${OPENJARVIS_MODEL:-qwen3.5:2b}"
CONFIG="$HOME/.openjarvis/config.toml"
unset UV_NATIVE_TLS || true

log() { printf '\n==> %s\n' "$*"; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# 1. uv
if ! command -v uv >/dev/null 2>&1; then
  log "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

# 2. Source checkout + Python deps
if [ ! -d "$OJ_DIR/.git" ]; then
  log "Cloning OpenJarvis into $OJ_DIR"
  git clone --depth 1 https://github.com/open-jarvis/OpenJarvis.git "$OJ_DIR"
fi
# GUI defaults: voice input/output on, skip the analytics/giveaway popup
PATCH="$(cd "$(dirname "$0")" && pwd)/voice-defaults.patch"
if [ "${SKIP_VOICE:-0}" != "1" ] && [ -f "$PATCH" ] &&
   git -C "$OJ_DIR" apply --check "$PATCH" 2>/dev/null; then
  log "Applying GUI voice defaults"
  git -C "$OJ_DIR" apply "$PATCH"
fi
EXTRAS=(--extra dev --extra server)
if [ "${SKIP_VOICE:-0}" != "1" ]; then
  EXTRAS+=(--extra desktop --extra voice)
  # espeak-ng: Kokoro's fallback phonemizer; libportaudio2: mic/speakers for `jarvis chat --voice`
  if command -v apt-get >/dev/null 2>&1 && ! command -v espeak-ng >/dev/null 2>&1; then
    log "Installing voice system packages"
    $SUDO apt-get install -y espeak-ng libportaudio2 ||
      { $SUDO apt-get update -qq && $SUDO apt-get install -y espeak-ng libportaudio2; }
  fi
fi
log "Syncing Python environment"
# --inexact keeps the separately built Rust extension installed
(cd "$OJ_DIR" && uv sync --inexact "${EXTRAS[@]}")

# 3. Ollama (binary tarball from GitHub releases; CPU-only, GPU libs skipped)
if ! command -v ollama >/dev/null 2>&1; then
  log "Installing Ollama"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/ollama.tar.zst" \
    https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst
  uv run --no-project --with zstandard python -I - "$tmp/ollama.tar.zst" /usr/local <<'PY'
import sys, tarfile, zstandard
with open(sys.argv[1], "rb") as f, tarfile.open(
        fileobj=zstandard.ZstdDecompressor().stream_reader(f), mode="r|") as t:
    for m in t:
        if any(s in m.name for s in ("/cuda_", "/rocm", "/vulkan")):
            continue
        t.extract(m, sys.argv[2], filter="tar")
PY
  rm -rf "$tmp"
fi

# 4. Pull the model (start a temporary server if none is running)
mkdir -p "$HOME/.openjarvis/logs"
started_server=""
if ! curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
  ollama serve >"$HOME/.openjarvis/logs/ollama.log" 2>&1 &
  started_server=$!
  for _ in $(seq 30); do
    curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
    sleep 1
  done
fi
log "Pulling model $MODEL"
ollama pull "$MODEL"
if [ -n "$started_server" ]; then kill "$started_server" 2>/dev/null || true; fi

# 5. OpenJarvis config
if [ ! -f "$CONFIG" ]; then
  log "Writing $CONFIG"
  (cd "$OJ_DIR" && uv run jarvis init --engine ollama --no-download --no-scan --no-analytics --force)
  sed -i "s/^default_model = .*/default_model = \"$MODEL\"/" "$CONFIG"
  grep -q '^\[security\]' "$CONFIG" || printf '\n[security]\nprofile = "personal"\n' >>"$CONFIG"
fi

# 6. Voice: config + model download (Whisper "base" and Kokoro, from Hugging Face)
if [ "${SKIP_VOICE:-0}" != "1" ]; then
  if ! grep -q '^\[speech\]' "$CONFIG"; then
    cat >>"$CONFIG" <<'TOML'

[speech]
backend = "faster-whisper"
model = "base"
device = "cpu"
compute_type = "int8"
tts_backend = "kokoro"
voice_id = "bm_george"
TOML
  fi
  log "Downloading and checking voice models"
  (cd "$OJ_DIR" && uv run python - <<'PY'
from openjarvis.speech.faster_whisper import FasterWhisperBackend
from openjarvis.speech.kokoro_tts import KokoroTTSBackend

audio = KokoroTTSBackend().synthesize("Voice check.")
text = FasterWhisperBackend(compute_type="int8").transcribe(audio.audio, format=audio.format).text
print("voice check heard:", text)
PY
  )
fi

# 7. Optional Rust extension
if [ "${SKIP_RUST:-0}" != "1" ] && command -v cargo >/dev/null 2>&1; then
  if ! (cd "$OJ_DIR" && uv run python -c "import openjarvis_rust" >/dev/null 2>&1); then
    log "Building Rust extension"
    (cd "$OJ_DIR" && uv run maturin develop --release \
      --manifest-path rust/crates/openjarvis-python/Cargo.toml)
  fi
fi

# 8. The GUI frontend requires npm 11
if command -v npm >/dev/null 2>&1 && [ "$(npm --version | cut -d. -f1)" -lt 11 ]; then
  log "Upgrading npm to 11 (required by the GUI)"
  npm install -g npm@11
fi

# 9. Put `jarvis` on PATH
mkdir -p "$HOME/.local/bin"
ln -sf "$OJ_DIR/.venv/bin/jarvis" "$HOME/.local/bin/jarvis"

log "Done. Start everything with scripts/start-jarvis.sh"
