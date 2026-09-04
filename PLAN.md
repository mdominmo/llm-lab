# llm-lab — Servidor de inferencia local

MacBook Pro M1 (32GB) como servidor de IA en LAN/tailnet, consumido desde el PC Linux
con OpenCode. Documento autocontenido: no requiere contexto previo.

---

## 1. Objetivo

- Modelo de código corriendo en el Mac, accesible desde cualquier sitio.
- OpenCode en el PC Linux como harness, con el modelo local del Mac.
  (La mitad nube del diseño original queda fuera de alcance; §7 la analiza.)
- Todo contenerizado salvo lo que macOS impide (ver §3).

## 2. Premisas de hardware

| | |
|---|---|
| Máquina | MacBook Pro M1 (Pro o Max), 32GB unificada |
| Ancho de banda | 200 GB/s (Pro) determina tok/s |
| Modelo principal | `Qwen3-Coder-30B-A3B` MLX 4-bit (~17GB, MoE 3B activos) |
| Cliente | PC Linux, repos y toolchain locales |

**Confirmar chip antes de empezar:** `system_profiler SPHardwareDataType | grep Chip`

## 3. Decisiones clave y su porqué

### 3.1 El motor de inferencia va NATIVO (no negociable)

Metal es una API propietaria de macOS. Cualquier contenedor en Mac (Docker, Podman,
Colima, OrbStack, Apple `container`) corre en una **VM de Linux**, cuyo kernel no tiene
—ni puede tener— drivers de Metal. No hay GPU passthrough para Metal.

Confirmado por Docker en feb-2026: su backend `vllm-metal` se ejecuta *en el host*
precisamente por esto. Peticiones abiertas y sin resolver en `apple/container#62` y
`apple/containerization#46`.

En contenedor (CPU en VM) el coste no es marginal:

| | Nativo (Metal) | Docker (CPU en VM) |
|---|---|---|
| Generación | 30-50 tok/s | ~5-12 tok/s |
| **Prefill 30k tokens** | 40-90 s | **5-10 min** |

El prefill es el cuello de botella de un agente de código: cada turno reenvía decenas de
miles de tokens. Contenerizar el motor hace el sistema inutilizable.

*Workaround descartado:* traducción Vulkan→Metal (75-95% del nativo). MLX no habla
Vulkan y el backend Vulkan de llama.cpp en Mac es experimental. Más complejidad para
acabar más lento.

### 3.2 Tailscale va NATIVO en el Mac

Un contenedor Tailscale en Mac pone **la VM** en el tailnet, no macOS. Consecuencia:
sshd, `pmset`, `launchctl` y LM Studio quedan fuera de alcance.

Argumento decisivo, independiente de la red: **si Tailscale vive dentro de Docker,
Docker es tu única vía de acceso.** Docker Desktop necesita sesión iniciada, se
autoactualiza y a veces no arranca tras reiniciar. El acceso remoto debe ser la capa
más baja y simple del stack.

En **Linux sí** va en Docker: el kernel es compartido, así que `network_mode: host` da
el namespace real del host (§6.1).

### 3.3 El agente corre en el PC, no en el Mac

El Mac sirve tokens; el código, los tests y el shell se quedan en el PC. Evita
sincronizar repos y que `pytest` compita con la GPU.

*Excepción:* tareas largas desatendidas → lanzar OpenCode por SSH en `tmux` dentro del Mac.

### 3.4 LiteLLM vive en el PC, no en el Mac

Docker Desktop en el Mac levanta una VM de Linux que **reserva memoria unificada**:
4GB es lo mínimo razonable, y cada GB reservado se lo quita al modelo. Pagar eso por
un proxy HTTP sin estado no tiene sentido.

LiteLLM no necesita ni Metal ni la identidad de red del host: solo hace dos llamadas
salientes, a `macbook:1234` y a la API de Anthropic. Le da igual en qué máquina vive, y
el PC —su único cliente— tiene Docker sin VM y RAM de sobra.

El tailnet se cruza una vez en cualquiera de las dos disposiciones:

```
LiteLLM en el Mac:  PC → tailnet → LiteLLM :4000 → localhost:1234
LiteLLM en el PC:   PC → localhost:4000 → tailnet → macbook:1234
```

Consecuencia: **el Mac no ejecuta Docker en absoluto.** Dos procesos, los dos nativos,
los dos obligados a serlo.

## 4. Mapa de componentes

```
            PC LINUX                                  MACBOOK PRO M1
 ┌─────────────────────────────────┐        ┌──────────────────────────────────┐
 │ OpenCode + repos     NATIVO     │        │ Tailscale            NATIVO ⚠️   │
 │ ┌─────────────────────────────┐ │ tailnet│ sshd                 NATIVO      │
 │ │ DOCKER                      │ │◀──────▶│ ┌──────────────────────────────┐ │
 │ │  Tailscale (net: host)   ✅ │ │   P2P  │ │ LM Studio :1234  NATIVO ⚠️   │ │
 │ │  LiteLLM    :4000        ✅ │─┼────────┼▶│ Qwen3-Coder-30B (MLX / Metal)│ │
 │ │  Open WebUI :3000        ✅ │ │  :1234 │ └──────────────────────────────┘ │
 │ └─────────────────────────────┘ │        │                                  │
 └─────────────────────────────────┘        │ Sin Docker: 32GB para el modelo  │
                                             └──────────────────────────────────┘
```

| Componente | Máquina | Dónde | Motivo si nativo |
|---|---|---|---|
| LM Studio + modelo | Mac | **Nativo** ⚠️ | Metal no llega a la VM |
| Tailscale | Mac | **Nativo** ⚠️ | Host en tailnet + salvavidas |
| sshd / pmset / launchd | Mac | Nativo | Servicios del sistema |
| Tailscale | PC Linux | **Docker** ✅ | `network_mode: host` |
| LiteLLM | PC Linux | **Docker** ✅ | — |
| Open WebUI | PC Linux | **Docker** ✅ | — |
| OpenCode | PC Linux | Nativo | Necesita repo, git, toolchain |

**2 excepciones en todo el stack**, ambas en el Mac, ambas por límites de macOS.
El Mac no ejecuta ningún contenedor (§3.4).

---

## FASE 0 — Manual, físicamente en el Mac (~10 min)

Bootstrap: no se puede activar el acceso remoto de una máquina sin acceso remoto.

- [ ] **Ajustes → General → Compartir → Sesión remota: ON**
      (o `sudo systemsetup -setremotelogin on`)
- [ ] **Tailscale**: versión *standalone* de `tailscale.com/download/mac`
      (NO la del App Store, va sandboxed). Login.
- [ ] **LM Studio** desde `lmstudio.ai` (solo instalar).
- [ ] Recoger datos:
      ```bash
      whoami; tailscale ip -4; sw_vers -productVersion
      system_profiler SPHardwareDataType | grep -E "Chip|Memory"
      ```

## FASE 1 — Acceso y blindaje del Mac

- [ ] Tailscale en el PC Linux (§6.1), mismo tailnet.
- [ ] `ssh-copy-id` + entrada en `~/.ssh/config` del PC.
- [ ] **Consola Tailscale → nodo del Mac → Disable key expiry.**
      Sin esto, a los ~180 días el Mac desaparece del tailnet y te quedas fuera.
- [ ] Añadir la IP de tailnet a `/etc/hosts` del PC (§6.1, MagicDNS no funciona
      con Tailscale en contenedor):
      ```
      100.x.y.z   macbook
      ```
- [ ] Energía:
      ```bash
      sudo pmset -c sleep 0 disablesleep 1 autorestart 1 womp 1
      ```
- [ ] Límite de VRAM en cada arranque — LaunchDaemon (§6.2). **24GB**.
      Es un *techo*, no una reserva: no preasigna nada, solo marca hasta dónde puede
      llegar la GPU. 24GB no es un límite estrecho sino holgado — el conjunto de
      trabajo real son ~19GB (modelo 17GB + KV cache de 32k en q8, ~1,5GB) y el resto
      queda para macOS. Subirlo a 28GB no aporta nada mientras no cambies a 64k de
      contexto, a una cuantización mayor o a un segundo modelo en paralelo (§9.3).
- [ ] **Auto-login** (Ajustes → Usuarios). Metal exige sesión gráfica: un LaunchDaemon
      no puede usar GPU. ⚠️ **Implica desactivar FileVault** — decisión consciente.

## FASE 2 — Motor (nativo)

- [ ] Descargar modelo:
      ```bash
      lms get qwen/qwen3-coder-30b        # variante MLX 4-bit
      ```
- [ ] LM Studio → Developer → **Serve on Local Network: ON**
      (por defecto escucha solo en `127.0.0.1`; sin esto no lo alcanza ni el PC ni Docker)
- [ ] Contexto **32k** y **KV cache en q8** (64k+ dispara prefill y memoria).
- [ ] Arranque automático: LM Studio → Developer → *Run server on login*.
      Alternativa por LaunchAgent en §6.3.
- [ ] Verificar desde el PC:
      ```bash
      curl http://macbook:1234/v1/models
      ```

## FASE 3 — Stack Docker en el PC Linux (§3.4)

- [ ] `docker-compose.yml` (§6.4) + `litellm_config.yaml` (§6.5).
- [ ] `LITELLM_MASTER_KEY` y `MACBOOK_IP` en `.env` (fuera de git).
- [ ] Verificar:
      ```bash
      curl http://localhost:4000/v1/models -H "Authorization: Bearer $LITELLM_KEY"
      ```

## FASE 4 — Cliente en el PC Linux

- [ ] Instalar OpenCode.
- [ ] `~/.config/opencode/opencode.json` (§6.6).
- [ ] Subagente de exploración con modelo local (§6.7).
- [ ] Prueba end-to-end sobre un repo real.

---

## 6. Ficheros de configuración

### 6.1 Tailscale en el PC Linux (Docker)

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    hostname: linux-dev
    network_mode: host
    cap_add: [NET_ADMIN, SYS_MODULE]
    devices: ["/dev/net/tun:/dev/net/tun"]
    volumes:
      - ./tailscale-state:/var/lib/tailscale   # imprescindible: identidad del nodo
    environment:
      TS_STATE_DIR: /var/lib/tailscale
      TS_AUTHKEY: ${TS_AUTHKEY}                # solo primer arranque
      TS_EXTRA_ARGS: --accept-dns=false
    restart: unless-stopped
```

`--accept-dns=false` porque tailscaled escribiría el `/etc/resolv.conf` *del contenedor*,
no el del host → MagicDNS no llega. Se resuelve con `/etc/hosts` (Fase 1).
CLI: `docker exec tailscale tailscale status`.

### 6.2 LaunchDaemon de VRAM (Mac)

`/Library/LaunchDaemons/local.iogpu.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.iogpu</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/sbin/sysctl</string>
    <string>iogpu.wired_limit_mb=24576</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
```

```bash
sudo chown root:wheel /Library/LaunchDaemons/local.iogpu.plist
sudo launchctl load -w /Library/LaunchDaemons/local.iogpu.plist
```

### 6.3 LaunchAgent del servidor (alternativa al toggle de LM Studio)

`~/Library/LaunchAgents/local.lmstudio.plist` — **Agent**, no Daemon (Metal necesita
sesión de usuario). Sin `KeepAlive`: `lms server start` arranca y termina.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.lmstudio</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/USUARIO/.lmstudio/bin/lms</string>
    <string>server</string><string>start</string>
    <string>--port</string><string>1234</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
```

### 6.4 `docker-compose.yml` (PC Linux)

```yaml
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    network_mode: host
    volumes:
      - ./litellm_config.yaml:/app/config.yaml
      - ./litellm-data:/app/data
    environment:
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
    extra_hosts: ["macbook:${MACBOOK_IP}"]
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    restart: unless-stopped
```

`network_mode: host` en vez de publicar el puerto: así el contenedor usa `tailscale0`
directamente y no depende de que el forwarding entre el bridge de Docker y el tailnet
esté bien resuelto. LiteLLM escucha en el `:4000` del propio host.

`extra_hosts` es obligatorio aunque el nombre `macbook` ya esté en el `/etc/hosts` del
host: el contenedor tiene su propio *mount namespace* y no ve ese fichero. De ahí la
variable `MACBOOK_IP` en el `.env`.

Open WebUI (opcional) sí va en bridge con `3000:8080`, y alcanza a LiteLLM por
`host.docker.internal:host-gateway`.

### 6.5 `litellm_config.yaml`

```yaml
model_list:
  - model_name: qwen3-coder                     # local
    litellm_params:
      model: openai/qwen/qwen3-coder-30b        # = id de /v1/models de LM Studio
      api_base: http://macbook:1234/v1              # por el tailnet
      api_key: "lm-studio"                      # no se usa, pero no puede ir vacío

litellm_settings:
  drop_params: true
  success_callback: ["sqlite"]                  # log de todas las peticiones

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

### 6.6 `~/.config/opencode/opencode.json` (PC Linux)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "macbook": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "MacBook M1",
      "options": {
        "baseURL": "http://localhost:4000/v1",
        "apiKey": "{env:LITELLM_MASTER_KEY}"
      },
      "models": {
        "qwen3-coder": { "name": "Qwen3 Coder 30B (local)" }
      }
    }
  },
  "model": "macbook/qwen3-coder"
}
```

El esquema de OpenCode cambia con frecuencia → contrastar con `opencode.ai/docs`.

Para añadir un modelo de nube más adelante: una entrada en `model_list` (§6.5) y otro
provider aquí. El resto del stack no se entera.

### 6.7 Subagente local

`~/.config/opencode/agent/explorer.md`

```markdown
---
description: Localiza dónde está implementado algo en el repo
mode: subagent
model: macbook/qwen3-coder
tools: { write: false, edit: false }
---
Eres un agente de búsqueda. Localiza los ficheros y símbolos relevantes
y devuelve rutas con números de línea. No modifiques nada.
```

Aísla contexto: el agente principal no se llena de rutas y grep fallidos.

---

## 7. Expectativas realistas

**Rinde bien:** autocompletado FIM ilimitado, mensajes de commit, resúmenes de diffs,
generación de tests y boilerplate, refactors mecánicos, lotes nocturnos, RAG sobre
repos, código bajo NDA que no puede salir de casa.

**No sustituye a la nube:** loops agénticos largos (20-30 pasos, repo desconocido,
decisiones de arquitectura, recuperación de errores). La brecha es cualitativa, y en un
M1 cada iteración fallida cuesta mucho más que en la nube por el prefill.

**Modelo mental correcto:** híbrido. El Mac absorbe el 80% del volumen barato; la nube
resuelve el 20% difícil. LiteLLM en medio hace ese reparto explícito y medible.

**Subagentes:** máximo práctico 2-3 concurrentes. Una sola GPU: el paralelismo reparte
throughput, no lo multiplica. Su valor real es **aislar contexto**, no ir más rápido.

## 8. Mitigaciones obligatorias del prefill

- Cache de prefijo activada (por defecto en LM Studio; `--cache-reuse 256` en llama.cpp).
- KV cache en q8 (`-ctk q8_0 -ctv q8_0 -fa`): mitad de memoria, pérdida inapreciable.
- Contexto acotado a 32k.
- Ethernet por USB-C si es posible: el Wi-Fi de macOS baja de potencia en idle.

## 9. Experimentos pendientes del laboratorio

1. **Docker Model Runner `vllm-metal`** (Docker Desktop 4.62+) vs LM Studio.
   Se gestiona con `docker model pull/run` —encaja mejor con el enfoque contenerizado—
   aunque ejecuta en el host igualmente. Su batching continuo + paged attention debería
   aguantar subagentes concurrentes mejor. Contra: ~1.2-1.3x más lento que llama.cpp
   y muy reciente. Cambiar de motor = una línea en `litellm_config.yaml`.
2. **Pi vs OpenCode** con modelo local: ~1.000 vs ~6.900 tokens de overhead fijo.
   Con prefill lento y un modelo de 30B (que se diluye con prompts largos), la
   diferencia puede pesar más que en los benchmarks publicados, hechos con modelos nube.
3. **llama-server en paralelo** en :8080 para el endpoint FIM (`/infill`) de
   autocompletado con un modelo 1.5B. LiteLLM unifica ambos.
4. Medir tok/s reales de prefill y generación, y tasa de éxito por tipo de tarea.
