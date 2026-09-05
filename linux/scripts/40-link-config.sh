#!/usr/bin/env bash
# FASE 4 — Enlaza la config versionada en ~/.config/opencode.
# Idempotente. Si ya hay ficheros reales (no enlaces), los guarda con sufijo .bak.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DST="$HOME/.config/opencode"
mkdir -p "$DST/agent"

link() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    mv "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
    echo "  copia de seguridad de $dst"
  fi
  ln -sfn "$src" "$dst"
  echo "  $dst -> $src"
}

link "$REPO_ROOT/linux/opencode/opencode.json" "$DST/opencode.json"
link "$REPO_ROOT/linux/opencode/agent/explorer.md" "$DST/agent/explorer.md"

echo "OpenCode apunta directo a macbook:1234. No hace falta ninguna clave."
