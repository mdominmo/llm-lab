#!/usr/bin/env bash
# FASE 1 — Mete el PC en el tailnet (contenedor, network_mode: host).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
cd "$REPO_ROOT/linux/tailscale"

if [[ ! -f .env && ! -d tailscale-state ]]; then
  echo "Primer arranque sin .env: haria falta TS_AUTHKEY." >&2
  echo "Copia .env.example a .env y genera la clave en" >&2
  echo "  https://login.tailscale.com/admin/settings/keys" >&2
  exit 1
fi

compose up -d
sleep 3
docker exec tailscale tailscale status || true
echo
echo "Siguiente: ./10-hosts.sh <ip-tailnet-del-mac>"
