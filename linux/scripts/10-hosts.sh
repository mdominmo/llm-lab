#!/usr/bin/env bash
# FASE 1 — Fija `macbook` en /etc/hosts.
# Necesario porque con Tailscale en contenedor MagicDNS no llega al host (§6.1).
#   ./10-hosts.sh 100.x.y.z
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

IP="${1:-}"
if [[ ! "$IP" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Uso: $0 <ip-tailnet-del-mac>   (rango 100.x.y.z; sale de 'tailscale ip -4' en el Mac)" >&2
  exit 1
fi

if grep -qE '^\S+\s+macbook\b' /etc/hosts; then
  echo "Ya existe una entrada 'macbook'; la actualizo a $IP."
  sudo sed -i -E "s|^\S+(\s+)macbook\b.*|$IP\1macbook|" /etc/hosts
else
  printf '%s\tmacbook\n' "$IP" | sudo tee -a /etc/hosts >/dev/null
fi

grep -E '\bmacbook\b' /etc/hosts
ping -c1 -W2 macbook >/dev/null 2>&1 && echo "macbook responde." || echo "macbook no responde todavia (normal si el Mac esta apagado)."
