#!/usr/bin/env bash
# FASE 2 de PLAN-IMAGEN.md — levanta ComfyUI en el PC como cliente del Mac.
# Idempotente.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DIR="$REPO_ROOT/linux/comfyui"
cd "$DIR"

if [[ ! -f .env ]]; then
  echo "Falta $DIR/.env. Copialo de .env.example y rellena MACBOOK_IP." >&2
  echo "El secreto se lee del Mac:  ssh macbook 'cat ~/.drawthings/secret'" >&2
  exit 1
fi

mkdir -p data/output data/input data/workflows

compose build
compose up -d

echo
echo "ComfyUI en http://localhost:8188"
echo "El servidor de imagenes es 'macbook' puerto 7859 (ponlo en el nodo de Draw Things)."
echo "Comprobar todo:  linux/scripts/verify-imagen.sh"
