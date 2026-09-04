#!/usr/bin/env bash
# FASE 0 — Recogida de datos. Ejecutar en el Mac, sin sudo.
# Solo lee: no cambia nada.
set -uo pipefail

echo "== Usuario =="
whoami

echo
echo "== Hardware (confirmar chip y memoria antes de seguir) =="
system_profiler SPHardwareDataType | grep -E "Chip|Memory"

echo
echo "== macOS =="
sw_vers -productVersion

echo
echo "== Tailscale =="
if command -v tailscale >/dev/null 2>&1; then
  tailscale ip -4
else
  echo "!! tailscale no encontrado en PATH."
  echo "   Instalar la version STANDALONE de tailscale.com/download/mac"
  echo "   (la del App Store va sandboxed y no sirve)."
fi

echo
echo "== Sesion remota (sshd) =="
sudo -n systemsetup -getremotelogin 2>/dev/null || systemsetup -getremotelogin 2>/dev/null \
  || echo "   (requiere sudo: sudo systemsetup -getremotelogin)"

echo
echo "== Limite actual de VRAM =="
sysctl iogpu.wired_limit_mb 2>/dev/null || echo "   sin fijar (0 = por defecto del sistema)"

echo
echo "Apunta la IP de tailnet: hace falta para /etc/hosts del PC (FASE 1)."
