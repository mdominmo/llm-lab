#!/usr/bin/env bash
# FASE 3 — Levanta LiteLLM en el PC.
#   ./20-stack-up.sh          -> solo LiteLLM
#   ./20-stack-up.sh --webui  -> LiteLLM + Open WebUI en :3000
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
cd "$REPO_ROOT/linux/stack"

if [[ ! -f .env ]]; then
  echo "Falta linux/stack/.env. Copia .env.example y rellenalo." >&2
  exit 1
fi

# El motor tiene que estar arriba antes: LiteLLM no lo arranca.
if ! curl -fsS --max-time 5 http://macbook:1234/v1/models >/dev/null; then
  echo "!! LM Studio no responde en macbook:1234." >&2
  echo "   Arrancalo en el Mac y comprueba 'Serve on Local Network'." >&2
  exit 1
fi

args=(up -d)
[[ "${1:-}" == "--webui" ]] && args=(--profile webui "${args[@]}")
compose "${args[@]}"

echo
compose ps
echo
echo "Comprueba con: linux/scripts/verify.sh"
