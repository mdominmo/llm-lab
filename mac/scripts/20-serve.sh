#!/usr/bin/env bash
# Arranca el servidor de LM Studio atado SOLO a la IP del tailnet.
# Lo llama el LaunchAgent (mac/launchd/local.lmstudio.plist) al iniciar sesion.
#
# Por que no `--bind 0.0.0.0`: el servidor no pide autenticacion, asi que
# escuchar en todas las interfaces lo deja abierto a cualquiera que entre en
# el wifi de casa. Atado al tailnet solo llegan tus equipos, esten donde esten.
#
# Por que no la IP a pelo: si algun dia el nodo se reregistra, la IP cambia y
# el bind fallaria. Se resuelve en cada arranque.
#
# Por que el bucle: al iniciar sesion, launchd puede adelantarse a que
# tailscaled levante la interfaz. Sin IP, el bind falla y no hay servidor.
set -uo pipefail

PORT="${PORT:-1234}"
LMS="$HOME/.lmstudio/bin/lms"
TS_CANDIDATOS=(
  /Applications/Tailscale.app/Contents/MacOS/Tailscale
  /usr/local/bin/tailscale
  /opt/homebrew/bin/tailscale
)

for c in "${TS_CANDIDATOS[@]}"; do
  [[ -x "$c" ]] && TS="$c" && break
done
if [[ -z "${TS:-}" ]]; then
  echo "No encuentro el CLI de Tailscale." >&2
  exit 1
fi

# Hasta 2 minutos esperando a que el tailnet este listo.
for _ in $(seq 1 60); do
  IP="$("$TS" ip -4 2>/dev/null | head -1)"
  [[ "$IP" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
  IP=""
  sleep 2
done

if [[ -z "$IP" ]]; then
  echo "El tailnet no levanto en 2 min; no ato el servidor a una IP publica." >&2
  exit 1
fi

echo "Atando LM Studio a $IP:$PORT (solo tailnet)."
exec "$LMS" server start --port "$PORT" --bind "$IP"
