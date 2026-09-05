#!/usr/bin/env bash
# Comprobacion end-to-end desde el PC. No cambia nada.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

HOST="${MACBOOK_HOST:-macbook}"
rc=0

echo "== FASE 1: red =="
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx tailscale; then
  ok "contenedor tailscale arriba"
else
  fail "contenedor tailscale caido -> linux/scripts/00-tailscale-up.sh"; rc=1
fi
if grep -qE '\bmacbook\b' /etc/hosts; then
  ok "/etc/hosts: $(grep -E '\bmacbook\b' /etc/hosts | head -1 | tr -s ' \t' ' ')"
else
  fail "sin entrada 'macbook' en /etc/hosts -> linux/scripts/10-hosts.sh <ip>"; rc=1
fi
if ping -c1 -W2 "$HOST" >/dev/null 2>&1; then ok "$HOST responde a ping"; else fail "$HOST inalcanzable"; rc=1; fi
if nc -z -w2 "$HOST" 22 2>/dev/null; then ok "sshd en $HOST:22"; else warn "sshd en $HOST:22 no responde"; fi

echo
echo "== FASE 2: motor nativo (LM Studio) =="
models=$(curl -fsS --max-time 5 "http://$HOST:1234/v1/models" 2>/dev/null)
if [[ -n "$models" ]]; then
  ok "LM Studio en $HOST:1234"
  echo "$models" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | sed 's/.*"\([^"]*\)"$/        \1/'
else
  fail "sin respuesta en $HOST:1234 (¿'Serve on Local Network' activado?)"; rc=1
fi

echo
echo "== FASE 3: generacion end-to-end =="
gen=$(curl -fsS --max-time 180 "http://$HOST:1234/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"'"${MODELO:-qwen/qwen3-coder-30b}"'","max_tokens":16,"messages":[{"role":"user","content":"di OK"}]}' 2>/dev/null)
if [[ -n "$gen" ]]; then
  ok "el modelo responde"
  echo "$gen" | grep -oE '"content"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/^/        /'
else
  fail "sin generacion en $HOST:1234 (¿modelo descargado? 'lms ls' en el Mac)"; rc=1
fi

echo
echo "== FASE 4: cliente =="
command -v opencode >/dev/null 2>&1 && ok "opencode: $(opencode --version 2>&1 | head -1)" \
  || { fail "opencode no instalado -> linux/scripts/30-install-opencode.sh"; rc=1; }
[[ -L "$HOME/.config/opencode/opencode.json" ]] && ok "config enlazada al repo" \
  || warn "$HOME/.config/opencode/opencode.json no enlazado -> linux/scripts/40-link-config.sh"

echo
[[ $rc -eq 0 ]] && echo "Todo en verde." || echo "Hay pasos pendientes (ver FALLO arriba)."
exit $rc
