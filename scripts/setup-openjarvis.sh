#!/usr/bin/env bash
# Install OpenJarvis (https://github.com/open-jarvis/OpenJarvis) from source on Linux,
# with Ollama as the local inference engine and a small starter model.
# Idempotent: re-running skips steps that are already done.
#
# Env overrides:
#   OPENJARVIS_DIR    where to clone OpenJarvis   (default: $HOME/OpenJarvis)
#   OPENJARVIS_MODEL  Ollama model to pull/use     (default: qwen3.5:2b)
#   SKIP_RUST=1       skip building the optional Rust extension (~2.5 min)
set -euo pipefail

OJ_DIR="${OPENJARVIS_DIR:-$HOME/OpenJarvis}"
MODEL="${OPENJARVIS_MODEL:-qwen3.5:2b}"
unset UV_NATIVE_TLS || true

log() { printf '\n==> %s\n' "$*"; }

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
log "Syncing Python environment"
(cd "$OJ_DIR" && uv sync --extra dev --extra server)

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
if [ ! -f "$HOME/.openjarvis/config.toml" ]; then
  log "Writing ~/.openjarvis/config.toml"
  (cd "$OJ_DIR" && uv run jarvis init --engine ollama --no-download --no-scan --no-analytics --force)
  sed -i "s/^default_model = .*/default_model = \"$MODEL\"/" "$HOME/.openjarvis/config.toml"
  grep -q '^\[security\]' "$HOME/.openjarvis/config.toml" ||
    printf '\n[security]\nprofile = "personal"\n' >>"$HOME/.openjarvis/config.toml"
fi

# 6. Optional Rust extension
if [ "${SKIP_RUST:-0}" != "1" ] && command -v cargo >/dev/null 2>&1; then
  if ! (cd "$OJ_DIR" && uv run python -c "import openjarvis_rust" >/dev/null 2>&1); then
    log "Building Rust extension"
    (cd "$OJ_DIR" && uv run maturin develop --release \
      --manifest-path rust/crates/openjarvis-python/Cargo.toml)
  fi
fi

# 7. Put `jarvis` on PATH
mkdir -p "$HOME/.local/bin"
ln -sf "$OJ_DIR/.venv/bin/jarvis" "$HOME/.local/bin/jarvis"

log "Done. Start the engine with:  ollama serve &   then run:  jarvis"
