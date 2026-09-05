#!/usr/bin/env bash
# Fija el contexto por defecto de LM Studio. Ejecutar EN EL MAC.
#   ./30-context.sh [tokens]     (por defecto 32768)
#
# Es un ajuste GLOBAL: vale para todos los modelos, presentes y futuros.
# No hay que configurarlo modelo a modelo.
#
# Por que hace falta: OpenCode manda ~10.700 tokens de prompt de sistema y
# definiciones de herramientas antes de que el usuario escriba nada. Con el
# valor de fabrica (8192) LM Studio no falla: aplica `TruncateMiddle` y borra
# ~10.400 tokens. El modelo recibe unos 300, no ve ni la pregunta ni sus
# instrucciones, y responde saludos genericos. Se comprueba en:
#   grep TruncateMiddle ~/.lmstudio/server-logs/*/*.log
set -euo pipefail

TOKENS="${1:-32768}"
SETTINGS="$HOME/.lmstudio/settings.json"

[[ "$TOKENS" =~ ^[0-9]+$ ]] || { echo "Uso: $0 [tokens]" >&2; exit 1; }
[[ -f "$SETTINGS" ]] || { echo "No existe $SETTINGS. ¿LM Studio instalado?" >&2; exit 1; }

# Con la app abierta, el fichero se sobrescribe al salir y el cambio se pierde.
if pgrep -f "MacOS/LM Studio" >/dev/null; then
  echo "Cerrando LM Studio (si no, sobrescribe el ajuste al salir)..."
  pkill -f "LM Studio" 2>/dev/null || true
  sleep 8
fi

python3 - "$SETTINGS" "$TOKENS" <<'PY'
import json, sys
p, tokens = sys.argv[1], int(sys.argv[2])
s = json.load(open(p))
print("antes: ", s.get("defaultContextLength"))
s["defaultContextLength"] = {"type": "custom", "value": tokens}
json.dump(s, open(p, "w"), indent=2)
print("ahora: ", json.load(open(p))["defaultContextLength"])
PY

echo
echo "Relanzando LM Studio y el servidor..."
open /Applications/LM\ Studio.app
sleep 25
"$(dirname "${BASH_SOURCE[0]}")/20-serve.sh"
echo
echo "Comprobar con 'lms ps' tras la primera peticion: CONTEXT debe dar $TOKENS."
