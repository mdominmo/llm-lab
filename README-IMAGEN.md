# llm-lab — Generación de imágenes

Draw Things en el MacBook como motor de difusión, consumido desde el PC Linux con
ComfyUI. El porqué de cada decisión está en [`PLAN-IMAGEN.md`](PLAN-IMAGEN.md).

Infraestructura **separada** de la del texto ([`README.md`](README.md)): otro binario,
otro puerto, otro LaunchAgent, otro `verify`. Comparten el tailnet y nada más — es la
misma red y las mismas IPs, solo cambia el puerto de destino.

Notación: **[MAC]** se ejecuta en el MacBook, **[PC]** en el PC Linux.

---

## Requisitos previos

Todo lo de [`README.md`](README.md) hasta la Fase 1 incluida: los dos equipos en el
tailnet, `macbook` en `/etc/hosts` del PC y SSH sin contraseña. Si `linux/scripts/verify.sh`
sale en verde, está cubierto.

Además, en el PC hace falta el **plugin buildx** de Docker, no solo compose v2. Sin él
`docker compose build` no falla: se queda colgado indefinidamente y sin mensaje.

```bash
mkdir -p ~/.docker/cli-plugins
curl -fsSL -o ~/.docker/cli-plugins/docker-buildx \
  https://github.com/docker/buildx/releases/latest/download/buildx-v0.37.0.linux-amd64
chmod +x ~/.docker/cli-plugins/docker-buildx
docker buildx version
```

---

## FASE 0 — [MAC] Preparación manual

Delante del Mac, con ratón. Es la única parte que no se puede hacer por SSH: la app
solo se distribuye por la App Store.

1. Instalar **Draw Things** desde la App Store (gratis).
2. Abrirlo una vez. Eso crea el directorio de modelos.
3. Descargar al menos un modelo desde la propia app. Para validar el montaje conviene
   uno pequeño y rápido: **SDXL Turbo** genera en pocos segundos.
4. Cerrar la app. El servidor **no** la necesita para funcionar; solo se usa para
   gestionar el catálogo (§4.6 del plan).

Los modelos quedan en:

```
~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models
```

### 0.b Acceso a disco completo — sin esto no funciona nada

Ese directorio está **dentro del contenedor de otra app**, y macOS exige consentimiento
explícito para leerlo. Un proceso lanzado por launchd no tiene a quien preguntar: se
queda colgado al enumerarlo y deja de responder a todo el mundo, **sin dar ningún error**.
El síntoma es que el servidor arranca, el puerto responde, y el catálogo llega vacío.

Hay que concederlo a mano, una sola vez, después de ejecutar la Fase 1 (el binario tiene
que existir para poder seleccionarlo):

1. **Ajustes del Sistema → Privacidad y seguridad → Acceso a disco completo**
2. Pulsar **`+`**
3. En el selector, pulsar **`Cmd` `Shift` `G`** — abre una barra para escribir una ruta
4. Escribir `~/.drawthings/bin` y Enter. **El paso 3 es imprescindible**: la carpeta
   empieza por punto y el Finder no muestra las ocultas, así que sin eso no aparece
5. Seleccionar **`gRPCServerCLI-macOS`** y activar su interruptor

Después, reiniciar el servidor:

```bash
launchctl kickstart -k gui/$(id -u)/local.drawthings
```

No sirve dárselo a la Terminal ni a la app de Draw Things: el permiso lo necesita **ese
binario**, que es quien lee el directorio.

---

## FASE 1 — [MAC] Motor

```bash
mac/scripts/40-drawthings-install.sh     # binario oficial
mac/scripts/60-drawthings-autostart.sh   # LaunchAgent: arranca al iniciar sesion
```

El primero baja `gRPCServerCLI-macOS` de las *releases* oficiales a `~/.drawthings/bin`
y genera un secreto aleatorio en `~/.drawthings/secret`, que por defecto **no se usa**:
la extensión oficial de ComfyUI no tiene campo para enviarlo. Queda disponible con
`DT_USE_SECRET=1` para clientes propios.

El segundo instala el agente que llama a `mac/scripts/50-drawthings-serve.sh`, que es
quien espera al tailnet y ata el servidor a esa IP. Por defecto `gRPCServerCLI` escucha
en `0.0.0.0`, o sea abierto a cualquiera en el wifi de casa; el script lo evita.

Para arrancarlo a mano sin el agente: `mac/scripts/50-drawthings-serve.sh`.

Comprobar desde el PC:

```bash
nc -z -w3 macbook 7859 && echo ok
```

---

## FASE 2 — [PC] Cliente

```bash
cp linux/comfyui/.env.example linux/comfyui/.env
$EDITOR linux/comfyui/.env               # MACBOOK_IP
linux/scripts/60-comfyui-up.sh           # http://localhost:8188
```

ComfyUI se construye aquí en vez de usar una imagen de terceros. En esta primera etapa
va **sin GPU**: todo el cómputo ocurre en el Mac, así que torch se instala en su versión
de CPU y el contenedor pesa una fracción.

Escucha en `127.0.0.1:8188`, no en el tailnet: es una interfaz de escritorio, no un
servicio que haya que exponer.

---

## Comprobación

```bash
linux/scripts/verify-imagen.sh           # [PC] recorre las 5 fases
```

Sale 0 cuando todo está en verde. Cada fallo indica el script que lo corrige.

---

## Uso diario

ComfyUI **no arranca solo** al encender el PC, a proposito: es una interfaz que se abre
cuando quieres generar algo, no un servicio de fondo. Se levanta y se para a mano.

```bash
cd linux/comfyui && docker compose up -d     # levantar
cd linux/comfyui && docker compose down      # parar al terminar
```

Solo levanta el contenedor; no reconstruye nada. El motor del Mac sigue su propio
ciclo y no depende de esto.

1. Abrir `http://localhost:8188`.
2. En el nodo `DrawThingsSampler`: **server `macbook`**, **port `7859`**, y
   **`use_tls` desactivado** (ver más abajo el porqué).
3. Elegir modelo del catálogo que sirve el Mac, escribir el prompt y generar.

Las imágenes salen en `linux/comfyui/data/output/`, los flujos guardados en
`data/workflows/`. Referencia: SDXL Turbo a 512×512 y 4 pasos tarda **~15 s**.

**`use_tls` va desactivado a propósito.** El certificado que genera el servidor es
`CN=localhost` y su lista de nombres válidos es `localhost`, `127.0.0.1` y `0.0.0.0`:
asume que el cliente corre en la misma máquina. Conectando a `macbook` la verificación
falla siempre, y el binario no admite otro certificado. No se pierde cifrado — el tailnet
ya es WireGuard de extremo a extremo.

**Añadir un modelo**: se descarga desde la app Draw Things en el Mac. No hace falta
reiniciar el servidor ni tocar nada en el PC — `--model-browser` lee el directorio en
cada consulta.

**Cuidado con las descargas interrumpidas.** Un fichero `.partial` en la carpeta de
modelos **cuelga el servidor entero**: intenta leerlo y deja de responder a todo el
mundo, sin error. Si una descarga se corta, sácalo de `Models` antes de seguir.
`verify-imagen.sh` lo detecta.

**Texto e imagen no conviven en memoria.** Qwen ocupa ~17 GB cargado y el límite de GPU
está en 24576 MB, así que `50-drawthings-serve.sh` ejecuta `lms unload --all` antes de
arrancar. Si generas imágenes y luego vuelves a OpenCode, LM Studio recarga el modelo
solo en la primera petición (~30 s).

---

## Mapa de ficheros

| Fichero | Máquina | Qué es |
|---|---|---|
| `mac/scripts/40-drawthings-install.sh` | MAC | Baja el binario oficial y genera el secreto |
| `mac/scripts/50-drawthings-serve.sh` | MAC | Arranca el servidor atado al tailnet |
| `mac/scripts/60-drawthings-autostart.sh` | MAC | Instala el LaunchAgent |
| `mac/launchd/local.drawthings.plist` | MAC | Servidor al iniciar sesión |
| `~/.drawthings/bin/gRPCServerCLI-macOS` | MAC | El servidor. Necesita *Acceso a disco completo* |
| `~/.drawthings/secret` | MAC | Secreto compartido, sin usar por defecto. **No se versiona** |
| `linux/comfyui/Dockerfile` | PC | Imagen de ComfyUI + extensión oficial |
| `linux/comfyui/docker-compose.yml` | PC | ComfyUI en `:8188`, sin GPU |
| `linux/comfyui/.env` | PC | `MACBOOK_IP`. **No se versiona** |
| `linux/scripts/60-comfyui-up.sh` | PC | Levanta el cliente |
| `linux/scripts/verify-imagen.sh` | PC | Comprobación por fases |

---

## Operación

| Tarea | Comando |
|---|---|
| Estado del servidor [MAC] | `launchctl list \| grep drawthings` |
| Log del servidor [MAC] | `tail -f /tmp/drawthings-serve.log` |
| Reiniciar el motor [MAC] | `launchctl kickstart -k gui/$(id -u)/local.drawthings` |
| Comprobar el bind [MAC] | `lsof -nP -iTCP:7859 -sTCP:LISTEN` — debe decir `100.x.y.z:7859` |
| Modelos en el Mac [PC] | `ssh macbook 'ls ~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models'` |
| Log de ComfyUI [PC] | `docker logs -f comfyui` |
| Reiniciar el cliente [PC] | `cd linux/comfyui && docker compose restart` |

---

## Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `:7859` no responde desde el PC | El servidor no está arrancado | `launchctl list \| grep drawthings` [MAC]; si no sale, `mac/scripts/60-drawthings-autostart.sh` |
| El log repite `Address already in use (errno: 48)` | Hay otra instancia con el puerto cogido, normalmente una lanzada a mano | `pgrep -f gRPCServerCLI` [MAC] y matar la que no sea del agente |
| El servidor responde pero el catálogo llega **vacío** | Falta *Acceso a disco completo* para `gRPCServerCLI-macOS`: no puede leer el contenedor de la app | Fase 0.b de este documento. Es la causa más probable |
| El servidor acepta la conexión pero **no contesta nunca** (`timed out before receiving SETTINGS frame`) | Hay un `.partial` en la carpeta de modelos | Sacarlo de `Models` [MAC] y reiniciar el servidor |
| El servidor no arranca al encender el Mac | El tailnet tardó más de 2 min | `/tmp/drawthings-serve.log` [MAC] y relanzar |
| ComfyUI no resuelve `macbook` | `MACBOOK_IP` mal en `linux/comfyui/.env` | Corregir y `docker compose up -d`. El contenedor no hereda el `/etc/hosts` del host: la IP se le inyecta con `extra_hosts` |
| Generar tarda muchísimo o falla por memoria | El LLM sigue cargado en el Mac | `ssh macbook '~/.lmstudio/bin/lms unload --all'` |
| Se acumulan ficheros `.partial` en el Mac | Descargas de modelos interrumpidas | Sacarlos de `Models`: cuelgan el servidor y no se reanudan solos |
| `docker compose build` se queda colgado sin decir nada | Falta el plugin buildx | Ver Requisitos previos |
| `sharedSecretMissing` al pedir el catálogo | El servidor arrancó con `--shared-secret` y la extensión no sabe enviarlo | Arrancar sin `DT_USE_SECRET=1` |
