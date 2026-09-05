#!/usr/bin/env bash
# Regenera la lista de modelos de OpenCode a partir de lo que hay descargado
# en el Mac. Ejecutar EN EL PC despues de un `lms get`.
#
# Por que hace falta: OpenCode NO pregunta al servidor que modelos tiene. Su
# lista sale de un catalogo estatico (models.dev) mas lo que declares en
# `provider.*.models` del opencode.json. Un modelo recien descargado existe en
# `curl macbook:1234/v1/models` pero OpenCode no lo ve hasta que esta aqui.
#
# Se usa /api/v0/models (nativo de LM Studio) en vez de /v1/models porque el
# primero trae el tipo, las capacidades y el contexto maximo; el de OpenAI solo
# devuelve el id.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

HOST="${HOST:-macbook}"
CFG="$REPO_ROOT/linux/opencode/opencode.json"

# Contexto efectivo: LM Studio carga los modelos con `defaultContextLength`, no
# con el maximo de la arquitectura. Si a OpenCode le decimos 262144 no compacta
# nunca, LM Studio trunca por su cuenta y el modelo deja de ver la conversacion.
CTX="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
  "python3 -c \"import json;print(json.load(open('\$HOME/.lmstudio/settings.json'))['defaultContextLength']['value'])\"" \
  2>/dev/null || true)"
[[ "$CTX" =~ ^[0-9]+$ ]] || { CTX=32768; warn "no puedo leer defaultContextLength por ssh; asumo $CTX"; }

MODELOS="$(curl -sf --max-time 10 "http://$HOST:1234/api/v0/models")" || {
  fail "$HOST:1234 no responde. Arranca el motor: mac/scripts/20-serve.sh"; exit 1; }

MODELOS="$MODELOS" python3 - "$CFG" "$CTX" <<'PY'
import json, os, sys

cfg_path, ctx = sys.argv[1], int(sys.argv[2])
remoto = json.loads(os.environ["MODELOS"])["data"]
cfg = json.load(open(cfg_path))
prov = cfg["provider"]["macbook"]
antes = set(prov.get("models", {}))

models = {}
for m in remoto:
    # Los de embeddings no son conversacionales: en el selector solo estorban.
    if m.get("type") == "embeddings":
        continue
    models[m["id"]] = {
        "name": m["id"].split("/")[-1],
        "attachment": m.get("type") == "vlm",
        "tool_call": "tool_use" in (m.get("capabilities") or []),
        "limit": {
            "context": min(ctx, m.get("max_context_length", ctx)),
            "output": 8192,
        },
    }

prov["models"] = models
# Si el modelo por defecto ya no esta descargado, OpenCode arranca sin modelo.
if cfg.get("model", "").removeprefix("macbook/") not in models and models:
    cfg["model"] = "macbook/" + next(iter(models))
    print(f"!! el modelo por defecto ya no existe; ahora es {cfg['model']}")

json.dump(cfg, open(cfg_path, "w"), indent=2)
open(cfg_path, "a").write("\n")

for k in sorted(models):
    marca = "+" if k not in antes else " "
    print(f"  {marca} {k}  ({models[k]['limit']['context']} tokens"
          + (", tools" if models[k]["tool_call"] else "")
          + (", imagenes" if models[k]["attachment"] else "") + ")")
for k in sorted(antes - set(models)):
    print(f"  - {k}  (ya no esta en el Mac)")
PY

ok "$CFG actualizado"
