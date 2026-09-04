# llm-lab

Puesta en marcha del MacBook M1 como servidor de inferencia, consumido desde el
PC Linux con OpenCode. El porqué de cada decisión está en [`PLAN.md`](PLAN.md).

Notación: **[MAC]** se ejecuta en el MacBook, **[PC]** en el PC Linux.

---

## Requisitos previos

- Cuenta de Tailscale con los dos equipos en el mismo tailnet.
- Este repo clonado en las dos máquinas.

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

2. En la app de LM Studio:
   - **Developer → Serve on Local Network: ON**
   - **Developer → Run server on login: ON**
   - Contexto del modelo: **32k**
   - KV cache: **q8**
3. Arrancar el servidor y comprobar desde el PC:

   ```bash
   curl http://macbook:1234/v1/models
   ```

---

## FASE 3 — [PC] LiteLLM

```bash
cp linux/stack/.env.example linux/stack/.env
$EDITOR linux/stack/.env              # LITELLM_MASTER_KEY y MACBOOK_IP
linux/scripts/20-stack-up.sh          # añadir --webui para Open WebUI en :3000
```

Generar la clave maestra con `openssl rand -hex 24`.

---

## FASE 4 — [PC] Cliente

```bash
linux/scripts/30-install-opencode.sh
linux/scripts/40-link-config.sh
echo "export LITELLM_MASTER_KEY='...'" >> ~/.bashrc   # la de linux/stack/.env
source ~/.bashrc
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

`macbook/qwen3-coder` es el modelo por defecto; el subagente `explorer` usa el
mismo. Todo el tráfico se queda en casa.

---

## Mapa de ficheros

| Fichero | Máquina | Qué es |
|---|---|---|
| `mac/launchd/local.iogpu.plist` | MAC | Límite de VRAM: 24576 MB |
| `mac/launchd/local.lmstudio.plist` | MAC | Servidor al iniciar sesión (opcional) |
| `linux/tailscale/docker-compose.yml` | PC | Tailscale |
| `linux/tailscale/.env` | PC | `TS_AUTHKEY` (solo primer arranque) |
| `linux/stack/docker-compose.yml` | PC | LiteLLM y Open WebUI (perfil `webui`) |
| `linux/stack/litellm_config.yaml` | PC | Modelo `qwen3-coder` |
| `linux/stack/.env` | PC | `LITELLM_MASTER_KEY`, `MACBOOK_IP` |
| `linux/opencode/opencode.json` | PC | Providers de OpenCode |
| `linux/opencode/agent/explorer.md` | PC | Subagente de exploración |

Los `.env` no se versionan.

---

## Operación

| Tarea | Comando |
|---|---|
| Estado del tailnet [PC] | `docker exec tailscale tailscale status` |
| Estado del stack [PC] | `cd linux/stack && docker compose ps` |
| Logs de LiteLLM [PC] | `cd linux/stack && docker compose logs -f litellm` |
| Reiniciar LiteLLM [PC] | `cd linux/stack && docker compose restart litellm` |
| Reiniciar el motor [MAC] | `lms server stop && lms server start` |
| Modelo cargado [MAC] | `lms ps` |
| Memoria de la GPU [MAC] | `sysctl iogpu.wired_limit_mb` |

Tras cambiar `linux/stack/litellm_config.yaml` hay que reiniciar el contenedor.

Para subir el límite de VRAM del Mac: cambiar `24576` en
`mac/launchd/local.iogpu.plist`, reejecutar `mac/scripts/10-harden.sh` y
reiniciar. Prueba en caliente, sin reiniciar:
`sudo sysctl iogpu.wired_limit_mb=28672`.

---

## Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `macbook` no resuelve [PC] | Falta la entrada en `/etc/hosts` | `linux/scripts/10-hosts.sh 100.x.y.z` |
| `:1234` no responde desde el PC | *Serve on Local Network* apagado | Activarlo en LM Studio → Developer |
| `:4000` responde 401 | `LITELLM_MASTER_KEY` distinta a la de `linux/stack/.env` | Igualarlas |
| LiteLLM no resuelve `macbook` | `MACBOOK_IP` mal en `linux/stack/.env` | Corregir y `docker compose up -d` |
| LiteLLM no alcanza el modelo | Servidor de LM Studio parado | `lms server start` [MAC] |
| El Mac desaparece del tailnet | Caducó la key del nodo | *Disable key expiry* (Fase 1.3) |
| El Mac se duerme | `pmset` sin aplicar | `mac/scripts/10-harden.sh` |
| Generación muy lenta tras reiniciar | Límite de VRAM sin aplicar | `sysctl iogpu.wired_limit_mb` debe dar 24576 |
