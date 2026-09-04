# Config de OpenCode (PC Linux)

`link-config.sh` enlaza estos ficheros en `~/.config/opencode/`, así que la
configuración vive versionada en el repo y no en el home.

| Fichero | Destino |
|---|---|
| `opencode.json` | `~/.config/opencode/opencode.json` |
| `agent/explorer.md` | `~/.config/opencode/agent/explorer.md` |

`LITELLM_MASTER_KEY` **no** va aquí: es variable de entorno del shell y el JSON
solo la referencia con `{env:...}`.

El esquema de OpenCode cambia con frecuencia: si algo deja de validar,
contrastar con `opencode.ai/docs` antes de pelearse con el fichero.

El subagente `explorer` (§6.7) sirve para **aislar contexto**, no para ir más
rápido: hay una sola GPU, así que el paralelismo reparte throughput en vez de
multiplicarlo (§7). Máximo práctico: 2-3 concurrentes.
