#!/usr/bin/env bash
# FASE 4 — Instala OpenCode (binario standalone; no usa el node del sistema).
set -euo pipefail

if command -v opencode >/dev/null 2>&1; then
  echo "OpenCode ya instalado: $(command -v opencode) — $(opencode --version 2>&1 | head -1)"
  exit 0
fi

echo "Descargando el instalador oficial de opencode.ai ..."
curl -fsSL https://opencode.ai/install | bash

hash -r
command -v opencode >/dev/null 2>&1 \
  && opencode --version \
  || echo "Instalado, pero no esta en el PATH de esta shell: abre una nueva (suele ir a ~/.opencode/bin)."
