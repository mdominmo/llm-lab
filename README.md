# llm-lab

Puesta en marcha del MacBook M1 como servidor de inferencia, consumido desde el
PC Linux con OpenCode. El porqué de cada decisión está en [`PLAN.md`](PLAN.md).

Notación: **[MAC]** se ejecuta en el MacBook, **[PC]** en el PC Linux.

---

## Requisitos previos

- Cuenta de Tailscale con los dos equipos en el mismo tailnet.
- Este repo clonado en las dos máquinas.
- `docker compose` v2 en el PC. El `docker-compose` v1 de Python no vale con
  Docker Engine 25+: falla con `KeyError: 'ContainerConfig'`. Instalarlo con
  `mkdir -p ~/.docker/cli-plugins && curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose && chmod +x ~/.docker/cli-plugins/docker-compose`
- Ningún otro `tailscaled` corriendo en el PC. Dos demonios sobre el mismo
  namespace de red se pisan las rutas y las `ip rules` (ver Problemas frecuentes).

---

## FASE 0 — [MAC] Preparación manual

Físicamente delante del Mac. ~10 min.

1. **Ajustes → General → Compartir → Sesión remota: ON**
2. **Tailscale**: descargar la versión *standalone* de
   `tailscale.com/download/mac` — **no** la del App Store. Instalar y hacer login.
3. **LM Studio**: instalar desde `lmstudio.ai`. Solo instalar.
   No hace falta Docker en el Mac.
4. **Ajustes → Usuarios → Auto-login: ON**. Requiere desactivar FileVault.
5. Recoger los datos de la máquina:

   ```bash
   mac/scripts/00-collect-info.sh
   ```

   **Apunta la IP de tailnet** (`100.x.y.z`) que imprime: hace falta en la Fase 1.

---

## FASE 1 — Red y blindaje

### 1.1 [PC] Entrar en el tailnet

Generar una auth key en `https://login.tailscale.com/admin/settings/keys`:

```bash
cp linux/tailscale/.env.example linux/tailscale/.env
$EDITOR linux/tailscale/.env          # pegar TS_AUTHKEY
linux/scripts/00-tailscale-up.sh
```

Una vez dentro, **comentar `TS_AUTHKEY` en el `.env`**: es de un solo uso y la
identidad del nodo ya está en `tailscale-state`. El `TS_AUTH_ONCE: "true"` del
compose evita que un reintento la use al reiniciar, pero dejarla puesta no
aporta nada.

### 1.2 [PC] Registrar el Mac y abrir SSH

```bash
linux/scripts/10-hosts.sh 100.x.y.z   # la IP de la Fase 0
ssh-copy-id USUARIO@macbook
ssh macbook                            # comprobar que entra sin contraseña
```

### 1.3 Consola de Tailscale

En `login.tailscale.com/admin/machines` → nodo del Mac → **Disable key expiry**.

### 1.4 [MAC] Energía y límite de VRAM

```bash
mac/scripts/10-harden.sh              # pide sudo
```

---

## FASE 2 — [MAC] Motor de inferencia

1. Descargar el modelo:

   ```bash
   lms get qwen/qwen3-coder-30b        # variante MLX 4-bit, ~17GB
   ```

2. Arrancar el servidor atado **solo al tailnet**:

   ```bash
   mac/scripts/20-serve.sh
   ```

   El toggle *Serve on Local Network* de la GUI escucha en `0.0.0.0`, y el
   servidor no pide autenticación: eso lo deja abierto a cualquiera que entre
   en el wifi. El script resuelve la IP del tailnet y ata el puerto ahí. Desde
   fuera de casa se llega igual, porque la `100.x` es la misma en todas partes.

   El arranque automático lo cubre `mac/launchd/local.lmstudio.plist`, que
   llama a este script — no hace falta *Run server on login*.

3. **Contexto por defecto: 32k.** Ajuste global, no por modelo:

   ```bash
   mac/scripts/30-context.sh
   ```

   Sin esto nada funciona con OpenCode: manda ~10.700 tokens de prompt de
   sistema y herramientas antes de que escribas nada, y con el valor de fábrica
   (8192) LM Studio aplica `TruncateMiddle` y borra el 97%. El modelo responde
   saludos genéricos porque nunca ve ni tu pregunta ni sus instrucciones.

4. Comprobar desde el PC:

   ```bash
   curl http://macbook:1234/v1/models
   ```

---

## FASE 3 — [PC] Cliente

```bash
linux/scripts/30-install-opencode.sh
linux/scripts/40-link-config.sh
```

OpenCode habla directamente con `macbook:1234`. No hay proxy ni claves: LM Studio
ya sirve la API de OpenAI y expone todos los modelos descargados.

---

## FASE 4 — [PC] Open WebUI (opcional)

Solo si quieres además una interfaz web en el navegador.

```bash
cp linux/stack/.env.example linux/stack/.env
$EDITOR linux/stack/.env              # MACBOOK_IP
linux/scripts/20-stack-up.sh          # http://localhost:3000
```

---

## Comprobación

```bash
linux/scripts/verify.sh               # [PC] recorre las 4 fases
```

Sale 0 cuando todo está en verde. Cada fallo indica el script que lo corrige.

---

## Uso diario

```bash
opencode
```

`macbook/qwen/qwen3-coder-30b` es el modelo por defecto; el subagente `explorer`
usa el mismo. Todo el tráfico se queda en casa.

Añadir un modelo son dos pasos: `lms get <modelo>` en el Mac, y una entrada más
en `models` de `linux/opencode/opencode.json`. LM Studio lo carga solo al recibir
la primera petición, con los 32k de `defaultContextLength` — el contexto **no**
hay que fijarlo modelo a modelo.

El modelo cargado se descarga solo a la hora sin uso (`jitModelTTL`), y al cargar
otro se libera el anterior (`unloadPreviousJITModelOnLoad`). No hay que gestionar
memoria a mano.

---

## Mapa de ficheros

| Fichero | Máquina | Qué es |
|---|---|---|
| `mac/launchd/local.iogpu.plist` | MAC | Límite de VRAM: 24576 MB |
| `mac/launchd/local.lmstudio.plist` | MAC | Servidor al iniciar sesión (opcional) |
| `mac/scripts/20-serve.sh` | MAC | Arranca el servidor atado al tailnet |
| `mac/scripts/30-context.sh` | MAC | Contexto por defecto global (32k) |
| `linux/tailscale/docker-compose.yml` | PC | Tailscale |
| `linux/tailscale/.env` | PC | `TS_AUTHKEY` (solo primer arranque) |
| `linux/stack/docker-compose.yml` | PC | Open WebUI (opcional) |
| `linux/stack/.env` | PC | `MACBOOK_IP` |
| `linux/opencode/opencode.json` | PC | Providers de OpenCode |
| `linux/opencode/agent/explorer.md` | PC | Subagente de exploración |

Los `.env` no se versionan.

---

## Operación

| Tarea | Comando |
|---|---|
| Estado del tailnet [PC] | `docker exec tailscale tailscale status` |
| Estado del stack [PC] | `cd linux/stack && docker compose ps` |
| Modelos disponibles [PC] | `curl -s http://macbook:1234/v1/models` |
| Liberar un modelo de memoria [MAC] | `lms unload <modelo>` |
| Reiniciar el motor [MAC] | `lms server stop && mac/scripts/20-serve.sh` |
| Modelo cargado y su contexto [MAC] | `lms ps` |
| Memoria de la GPU [MAC] | `sysctl iogpu.wired_limit_mb` |

Para subir el límite de VRAM del Mac: cambiar `24576` en
`mac/launchd/local.iogpu.plist`, reejecutar `mac/scripts/10-harden.sh` y
reiniciar. Prueba en caliente, sin reiniciar:
`sudo sysctl iogpu.wired_limit_mb=28672`.

---

## Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `macbook` no resuelve [PC] | Falta la entrada en `/etc/hosts` | `linux/scripts/10-hosts.sh 100.x.y.z` |
| `ping macbook` falla pero `docker exec tailscale tailscale ping macbook` da pong | El nodo va en *userspace-networking*: el túnel existe pero el kernel del host no lo ve. `ip -br addr show tailscale0` sale vacío o sin IPv4 | Comprobar `TS_USERSPACE: "false"` en `linux/tailscale/docker-compose.yml` y recrear el contenedor |
| `tailscale0` pierde la IP cada minuto; logs con `ip rule deleted` | Hay un segundo `tailscaled` en el host (otro proyecto en `network_mode: host`) | `docker ps \| grep tailscale` y parar el que sobre |
| Tras reiniciar el PC, el contenedor reinicia en bucle con `invalid key` y el nodo queda deslogueado | `containerboot` reintentó autenticar con la `TS_AUTHKEY`, que es de un solo uso | `TS_AUTH_ONCE: "true"` en el compose y comentar `TS_AUTHKEY` en `.env`. Para recuperar la sesión, visitar el enlace que sale en `docker logs tailscale` |
| `:1234` no responde desde el PC | El servidor no está atado al tailnet | `mac/scripts/20-serve.sh` [MAC]; comprobar con `lsof -nP -iTCP:1234 -sTCP:LISTEN`, debe decir `100.x.y.z:1234` |
| El servidor no arranca al encender el Mac | El tailnet tardó más de 2 min en levantar | Ver `/tmp/lmstudio-serve.log` [MAC] y relanzar `mac/scripts/20-serve.sh` |
| `lms: command not found` [MAC] | LM Studio sin instalar, o instalado pero nunca abierto: el CLI vive dentro del bundle y `bootstrap` exige un primer arranque | Instalar, abrir la app una vez y `"/Applications/LM Studio.app/Contents/Resources/app/.webpack/lms" bootstrap` |
| Open WebUI no resuelve `macbook` | `MACBOOK_IP` mal en `linux/stack/.env` | Corregir y `docker compose up -d` |
| El modelo responde saludos genéricos y no ve tu pregunta | Contexto por defecto (8192) menor que el prompt de OpenCode (~10.700 tokens): `TruncateMiddle` borra casi todo | Subir `defaultContextLength` a 32768 (Fase 2.3). Confirmar en los logs: `grep TruncateMiddle ~/.lmstudio/server-logs/*/*.log` [MAC] |
| Un modelo no carga y da error de memoria | El guardarraíl `modelLoadingGuardrails` en modo `high` bloquea la carga | `lms unload <otro-modelo>` [MAC] |
| El Mac desaparece del tailnet | Caducó la key del nodo | *Disable key expiry* (Fase 1.3) |
| El Mac se duerme | `pmset` sin aplicar | `mac/scripts/10-harden.sh` |
| Generación muy lenta tras reiniciar | Límite de VRAM sin aplicar | `sysctl iogpu.wired_limit_mb` debe dar 24576 |
