#!/usr/bin/env bash
# Start the Ollama engine and the OpenJarvis browser GUI (with voice) in the background.
# GUI: http://127.0.0.1:5173   API: http://127.0.0.1:8000
# Logs: ~/.openjarvis/logs/{ollama,gui}.log
set -euo pipefail

OJ_DIR="${OPENJARVIS_DIR:-$HOME/OpenJarvis}"
LOGS="$HOME/.openjarvis/logs"
mkdir -p "$LOGS"
unset UV_NATIVE_TLS || true

up() { curl -fsS -o /dev/null "$1" 2>/dev/null; }

if ! up http://127.0.0.1:11434/api/version; then
  echo "Starting Ollama..."
  nohup ollama serve >"$LOGS/ollama.log" 2>&1 &
  for _ in $(seq 30); do up http://127.0.0.1:11434/api/version && break; sleep 1; done
fi

if ! up http://127.0.0.1:5173; then
  echo "Starting OpenJarvis GUI..."
  (cd "$OJ_DIR" && nohup uv run jarvis gui --no-browser >"$LOGS/gui.log" 2>&1 &)
  for _ in $(seq 120); do up http://127.0.0.1:5173 && up http://127.0.0.1:8000/health && break; sleep 2; done
fi

if up http://127.0.0.1:5173; then
  echo "OpenJarvis is ready: http://127.0.0.1:5173"
  echo "Voice: Settings > Speech > turn on Speech-to-Text, Text-to-Speech and 'Speak replies automatically',"
  echo "then use the mic button next to the message box."
else
  echo "GUI did not start; see $LOGS/gui.log" >&2
  exit 1
fi
