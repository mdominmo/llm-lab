#!/usr/bin/env bash
# Instala el LaunchAgent del servidor de imagenes. Ejecutar EN EL MAC.
# Sin sudo: es un agente del usuario, no un demonio del sistema (Metal exige
# sesion grafica, ver la cabecera del plist).
#
# Independiente del de LM Studio: si uno falla, el otro sigue.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PLIST="$HOME/Library/LaunchAgents/local.drawthings.plist"
mkdir -p "$HOME/Library/LaunchAgents"

sed "s|USUARIO|$(whoami)|g" \
  "$REPO_ROOT/mac/launchd/local.drawthings.plist" > "$PLIST"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo "Agente cargado. Log en /tmp/drawthings-serve.log"
launchctl list | grep drawthings || true
