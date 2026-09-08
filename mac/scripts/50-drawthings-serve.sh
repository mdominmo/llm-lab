#!/usr/bin/env bash
# Arranca el servidor de Draw Things atado SOLO a la IP del tailnet.
# Lo llama el LaunchAgent (mac/launchd/local.drawthings.plist).
#
# Mismo patron que 20-serve.sh para LM Studio, y por los mismos motivos:
#   - `--address` por defecto es 0.0.0.0, o sea abierto al wifi de casa.
#   - La IP se resuelve en cada arranque; si el nodo se reregistra, cambia.
#   - El bucle existe porque launchd puede adelantarse a que tailscaled
#     levante la interfaz, y sin IP el bind falla.
#
# Las dos banderas de la extension oficial de ComfyUI no son opcionales:
#   --model-browser            para que el cliente vea el catalogo del Mac
#   --no-response-compression  la extension no descomprime
set -uo pipefail

PORT="${PORT:-7859}"
DT="$HOME/.drawthings"
BIN="$DT/bin/gRPCServerCLI-macOS"
SECRET_FILE="$DT/secret"
MODELS="${MODELS:-$HOME/Library/Containers/com.liuliu.draw-things/Data/Documents/Models}"

TS_CANDIDATOS=(
  /Applications/Tailscale.app/Contents/MacOS/Tailscale
  /usr/local/bin/tailscale
  /opt/homebrew/bin/tailscale
)

[[ -x "$BIN" ]] || { echo "No esta el servidor. Ejecuta 40-drawthings-install.sh" >&2; exit 1; }
[[ -d "$MODELS" ]] || { echo "No existe $MODELS. ¿Abriste Draw Things al menos una vez?" >&2; exit 1; }

for c in "${TS_CANDIDATOS[@]}"; do
  [[ -x "$c" ]] && TS="$c" && break
done
[[ -n "${TS:-}" ]] || { echo "No encuentro el CLI de Tailscale." >&2; exit 1; }

# Hasta 2 minutos esperando a que el tailnet este listo.
for _ in $(seq 1 60); do
  IP="$("$TS" ip -4 2>/dev/null | head -1)"
  [[ "$IP" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
  IP=""
  sleep 2
done
[[ -n "$IP" ]] || { echo "El tailnet no levanto en 2 min; no ato el servidor a una IP publica." >&2; exit 1; }

# Texto e imagen no caben a la vez en los 24 GB de limite de GPU: qwen ocupa
# ~17 GB y Flux en bf16 pediria ~24 GB. Soltar el LLM aqui lo hace explicito
# en vez de dejarlo al TTL de LM Studio (§4.7 de PLAN-IMAGEN.md).
LMS="$HOME/.lmstudio/bin/lms"
[[ -x "$LMS" ]] && "$LMS" unload --all >/dev/null 2>&1 || true

ARGS=(
  "$MODELS"
  --address "$IP"
  --port "$PORT"
  --name "macbook-imagen"
  --model-browser
  --no-response-compression
)
[[ -s "$SECRET_FILE" ]] && ARGS+=(--shared-secret "$(cat "$SECRET_FILE")")

echo "Atando Draw Things a $IP:$PORT (solo tailnet). Modelos: $MODELS"
exec "$BIN" "${ARGS[@]}"
