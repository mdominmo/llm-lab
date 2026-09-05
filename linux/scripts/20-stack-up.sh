#!/usr/bin/env bash
# FASE 3 (opcional) — Open WebUI en el PC, interfaz web contra el Mac.
# El motor no necesita nada de esto: OpenCode habla directo con macbook:1234.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
cd "$REPO_ROOT/linux/stack"

if [[ ! -f .env ]]; then
  echo "Falta linux/stack/.env. Copia .env.example y pon MACBOOK_IP." >&2
  exit 1
fi

# El motor tiene que estar arriba antes: esto no lo arranca.
if ! curl -fsS --max-time 5 http://macbook:1234/v1/models >/dev/null; then
  echo "!! LM Studio no responde en macbook:1234." >&2
  echo "   En el Mac: lms server start --port 1234 --bind 0.0.0.0" >&2
  exit 1
fi

compose up -d
echo
compose ps
echo
echo "Open WebUI en http://localhost:3000"
