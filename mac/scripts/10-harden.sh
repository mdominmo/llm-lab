#!/usr/bin/env bash
# FASE 1 — Blindaje del Mac como servidor. Ejecutar EN EL MAC. Pide sudo.
#   - energia: que no se duerma ni pierda la red
#   - limite de VRAM persistente (LaunchDaemon)
#   - LaunchAgent opcional del servidor de LM Studio
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
USER_NAME="$(whoami)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este script es solo para macOS." >&2
  exit 1
fi

echo "== Energia: sin suspension, arranque tras corte, wake-on-LAN =="
sudo pmset -c sleep 0 disablesleep 1 autorestart 1 womp 1
pmset -g custom | sed -n '1,20p'

echo
echo "== LaunchDaemon: limite de VRAM en cada arranque =="
sudo install -m 644 -o root -g wheel \
  "$REPO_ROOT/mac/launchd/local.iogpu.plist" \
  /Library/LaunchDaemons/local.iogpu.plist
sudo launchctl unload /Library/LaunchDaemons/local.iogpu.plist 2>/dev/null || true
sudo launchctl load -w /Library/LaunchDaemons/local.iogpu.plist
echo -n "iogpu.wired_limit_mb = "; sysctl -n iogpu.wired_limit_mb

echo
read -r -p "Instalar tambien el LaunchAgent de LM Studio? (innecesario si usas 'Run server on login') [y/N] " ans
if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
  mkdir -p "$HOME/Library/LaunchAgents"
  sed "s|USUARIO|$USER_NAME|g" \
    "$REPO_ROOT/mac/launchd/local.lmstudio.plist" \
    > "$HOME/Library/LaunchAgents/local.lmstudio.plist"
  launchctl unload "$HOME/Library/LaunchAgents/local.lmstudio.plist" 2>/dev/null || true
  launchctl load -w "$HOME/Library/LaunchAgents/local.lmstudio.plist"
  echo "Instalado para el usuario $USER_NAME."
fi

cat <<'MANUAL'

Queda MANUAL en la interfaz grafica (no hay CLI fiable para esto):

  [ ] Ajustes -> General -> Compartir -> Sesion remota: ON
  [ ] Ajustes -> Usuarios -> Auto-login: ON
      Metal exige sesion grafica. Implica DESACTIVAR FileVault: decision consciente.
  [ ] Consola de Tailscale -> nodo del Mac -> Disable key expiry
      Sin esto, a los ~180 dias el Mac sale del tailnet y te quedas fuera.
  [ ] LM Studio -> Developer -> Serve on Local Network: ON
MANUAL
