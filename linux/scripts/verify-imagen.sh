#!/usr/bin/env bash
# Comprobacion end-to-end del servidor de imagenes, desde el PC. No cambia nada.
# El equivalente de verify.sh para la infraestructura de PLAN-IMAGEN.md.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

HOST="${MACBOOK_HOST:-macbook}"
PORT="${DT_PORT:-7859}"
rc=0

echo "== FASE 1: red =="
if ping -c1 -W2 "$HOST" >/dev/null 2>&1; then ok "$HOST responde a ping"; else fail "$HOST inalcanzable -> linux/scripts/verify.sh"; rc=1; fi

echo
echo "== FASE 2: motor de imagen (Draw Things) =="
if nc -z -w3 "$HOST" "$PORT" 2>/dev/null; then
  ok "gRPC en $HOST:$PORT"
else
  fail "sin respuesta en $HOST:$PORT -> mac/scripts/50-drawthings-serve.sh [MAC]"; rc=1
fi

# Atado al tailnet y no a 0.0.0.0: el servidor no es publico aunque escuche.
bind=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
       "lsof -nP -iTCP:$PORT -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print \$9; exit}'" 2>/dev/null)
if [[ -z "$bind" ]]; then
  warn "no puedo leer el bind (sin ssh o servidor parado)"
elif [[ "$bind" == 100.* ]]; then
  ok "atado al tailnet: $bind"
else
  fail "atado a $bind: abierto al wifi de casa -> mac/scripts/50-drawthings-serve.sh"; rc=1
fi

echo
echo "== FASE 3: modelos en el Mac =="
mods=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
       'ls ~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models/*.ckpt 2>/dev/null' 2>/dev/null)
if [[ -n "$mods" ]]; then
  ok "$(wc -l <<<"$mods") ficheros de modelo descargados"
else
  fail "sin modelos: abrir Draw Things en el Mac y descargar uno"; rc=1
fi

# Un .partial cuelga el servidor: intenta leerlo y deja de contestar a todos.
# No es cosmetico, es fatal.
part=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
       'ls ~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models/*.partial 2>/dev/null | wc -l' 2>/dev/null)
if [[ "${part:-0}" -gt 0 ]]; then
  fail "$part descarga(s) a medias (.partial): cuelgan el servidor, sacalas de Models"; rc=1
fi

echo
echo "== FASE 4: cliente (ComfyUI) =="
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx comfyui; then
  ok "contenedor comfyui arriba"
else
  fail "comfyui caido -> linux/scripts/60-comfyui-up.sh"; rc=1
fi
if curl -fsS --max-time 5 -o /dev/null http://127.0.0.1:8188/ 2>/dev/null; then
  ok "ComfyUI en http://localhost:8188"
else
  fail "ComfyUI no responde en :8188"; rc=1
fi
ext=$(docker exec comfyui ls /opt/comfyui/custom_nodes 2>/dev/null | grep -c draw-things)
[[ "${ext:-0}" -gt 0 ]] && ok "extension de Draw Things instalada" \
  || { fail "sin la extension oficial en custom_nodes"; rc=1; }

echo
echo "== FASE 5: catalogo end-to-end =="
# La prueba de verdad: el cliente le pide el catalogo al Mac por gRPC.
# Aqui se ve si falta "Acceso a disco completo" para gRPCServerCLI-macOS,
# porque entonces el servidor responde pero sin ningun modelo.
cat=$(curl -fsS --max-time 60 -X POST "http://127.0.0.1:8188/dt_grpc/files_info" \
      -d "server=$HOST&port=$PORT&use_tls=false" 2>/dev/null)
n=$(python3 -c "
import json,sys
try: print(len(json.loads(sys.argv[1]).get('models',[])))
except Exception: print(-1)
" "$cat" 2>/dev/null)
if [[ "${n:-0}" -gt 0 ]]; then
  ok "ComfyUI ve $n modelo(s) servidos por el Mac"
  python3 -c "
import json,sys
for m in json.loads(sys.argv[1])['models']: print('       ', m.get('name'))
" "$cat" 2>/dev/null
elif [[ "${n:-0}" == "0" ]]; then
  fail "el servidor responde con catalogo vacio: falta 'Acceso a disco completo' para gRPCServerCLI-macOS [MAC]"; rc=1
else
  fail "sin respuesta al pedir el catalogo (¿servidor colgado por un .partial?)"; rc=1
fi

echo
[[ $rc -eq 0 ]] && echo "Todo en verde." || echo "Hay pasos pendientes (ver FALLO arriba)."
exit $rc
