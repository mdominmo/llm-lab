# plan-imagen — Generación de imágenes local

Segundo servicio del MacBook: Draw Things como motor de difusión, consumido desde el
PC Linux con ComfyUI. Mismo patrón que el motor de texto ([`PLAN.md`](PLAN.md)) pero
**infraestructura separada**: otro binario, otro puerto, otro LaunchAgent, otro
`verify`. No toca nada de lo que ya funciona.

Documento autocontenido. El runbook está en [`README-IMAGEN.md`](README-IMAGEN.md).

---

## 1. Objetivo

**Primera etapa, la que se monta ahora:**

- Motor de difusión en el Mac, atado al tailnet, arrancando solo tras reiniciar.
- ComfyUI en el PC Linux como interfaz y orquestador.
- Accesible también desde scripts, igual que la API de texto.

**Segunda etapa, abierta:** añadir la RTX 4070 del PC como nodo adicional del mismo
ComfyUI, para los modelos que caben en 8 GB. Planteada en §6.B; no se ejecuta ahora y no
condiciona nada de la primera.

---

## 2. Premisas de hardware

| | Mac | PC Linux |
|---|---|---|
| GPU | M1 Pro, 32 GB unificada, ~200 GB/s | RTX 4070 Laptop, **8 GB** VRAM |
| Límite actual | `iogpu.wired_limit_mb` = 24576 | — |
| RAM sistema | compartida con la GPU | 31 GB |
| Papel | motor de difusión | interfaz + modelos que quepan en 8 GB |

---

## 3. La pregunta incómoda: ¿por qué el Mac, si hay una 4070?

Con el LLM la respuesta era trivial: un modelo de 30B ocupa 17 GB y **no cabe** en 8 GB
de VRAM. No había debate.

Con imágenes no se traslada igual, porque los modelos de difusión son mucho más
pequeños:

| Modelo | Tamaño aprox. | ¿Cabe en la 4070 (8 GB)? |
|---|---|---|
| SD 1.5 | ~2 GB | Sí, de sobra |
| SDXL | ~6,6 GB | Sí, justo pero sí |
| SD 3.5 Medium | ~5 GB | Sí |
| Flux.1 dev (fp8) | ~12 GB | No sin descargar pesos a RAM |
| Flux.1 dev (bf16) | ~24 GB | No |
| Qwen-Image / vídeo | 20 GB+ | No |

Y en lo que cabe, **CUDA gana**. Los kernels de difusión están mucho más optimizados
para NVIDIA que para Metal; para SDXL la 4070 va varias veces más rápida que el M1 Pro,
aunque sea una GPU de portátil.

O sea: el Mac **no** es el sitio obvio para generar imágenes pequeñas.

### 3.1 ¿Se pierde calidad usando lo que cabe en 8 GB?

Sí, pero el eje no es el tamaño en GB. "Modelo más pequeño" mezcla dos cosas distintas y
solo una cuesta calidad de verdad.

**Generación del modelo — aquí sí se pierde.** SDXL (2023) frente a Flux.1 (2024) no es un
ajuste fino: Flux sigue mucho mejor las instrucciones complejas, compone escenas con
varios elementos, resuelve manos y anatomía, y escribe texto legible dentro de la imagen.
Quedarse en SDXL *porque es lo que cabe* se nota.

**Cuantización — aquí se pierde poco.** Flux fp8 son ~12 GB y Flux bf16 son ~24 GB, pero
**es el mismo modelo**: lo que cambia es la precisión de los pesos, no la arquitectura. La
degradación es visible comparando a pares, pero mucho menor que el salto SDXL→Flux. Un
Flux cuantizado se parece mucho más a Flux que a SDXL.

De modo que la comparación real no es "Mac = calidad, PC = velocidad":

| | Calidad | Velocidad |
|---|---|---|
| SDXL en la 4070 | generación anterior | muy rápida |
| Flux fp8/nf4 en la 4070 | casi la de Flux | lenta: no cabe en 8 GB y mueve pesos a RAM por PCIe en cada paso |
| Flux bf16 en el Mac | completa | lenta, pero constante: todo residente en los 32 GB unificados |

Lo que aporta el Mac no es "más calidad", es **la calidad sin el castigo de no caber**.
Los dos caminos son lentos, pero por motivos distintos, y el trasiego por PCIe es peor que
el ancho de banda de la memoria unificada.

**Los 8 GB aprietan más en el flujo que en el modelo.** SDXL a 1024×1024 cabe. Subir a
1536, encadenar dos ControlNets o añadir un paso de refinado te echa de la VRAM, y las
salidas de emergencia —bajar resolución, trocear en tiles— sí degradan el resultado de
forma visible. En el día a día esto limita más que la elección del checkpoint.

**Y hay cosas que no arrancan.** Qwen-Image, los Flux grandes a alta resolución y
cualquier modelo de vídeo no entran en 8 GB ni cuantizados. Ahí no se pierde calidad: se
pierde la posibilidad.

### 3.2 Consecuencia: primero el Mac, la 4070 después

Por eso el orden de trabajo es este, y no al revés:

**Primero se monta el servidor de imágenes en el Mac.** Es lo que añade capacidad que hoy
no tienes —los modelos que no caben en 8 GB— y es la parte con piezas nuevas de verdad:
binario, LaunchAgent, puerto, secreto compartido. ComfyUI en el PC se levanta solo como
cliente de ese servidor.

**Después, como segundo paso, se abre la 4070 como nodo adicional del mismo ComfyUI.**
Misma interfaz, mismos flujos: el destino del cómputo pasa a ser un nodo más del grafo, y
se elige por modelo en vez de por infraestructura. Queda planteado en §6 y no se cierra
aquí, pero tampoco se descarta: es la mitad rápida del sistema.

Consecuencia práctica para la primera etapa: **el contenedor de ComfyUI no necesita GPU**.
Todo el cómputo ocurre en el Mac. El paso de la 4070 al contenedor y el NVIDIA Container
Toolkit son trabajo de la segunda etapa (§4.5), y no bloquean nada de la primera.

---

## 4. Decisiones clave y su porqué

### 4.1 El motor va nativo en el Mac (heredado, no negociable)

Mismo argumento que §3.1 de `PLAN.md`: Metal es API de macOS y ningún contenedor en Mac
la ve, porque corre en una VM de Linux. Draw Things es además una app nativa de Apple
Silicon: es precisamente su motivo de existir.

### 4.2 `gRPCServerCLI`, no la app abierta

Draw Things ofrece dos servidores:

| | API HTTP (`:7860`) | `gRPCServerCLI` (`:7859`) |
|---|---|---|
| Forma | dentro de la app, pestaña *Advanced* | binario suelto, sin GUI |
| Estado | usa el modelo y ajustes **seleccionados en la interfaz** | modelo por petición |
| Arranque automático | hay que activarlo a mano tras cada arranque de la app | LaunchAgent |
| Metadatos | no | catálogo de modelos, LoRAs, ControlNets |
| Cliente ComfyUI | wrapper no oficial | extensión **oficial** |

El API HTTP es cómodo para un `curl` suelto, pero es *stateful*: lo que no mandes en la
petición sale de lo que haya seleccionado en la GUI en ese momento. Eso es exactamente el
tipo de configuración invisible que rompe el sistema dos semanas después.

`gRPCServerCLI` es el equivalente de `lms server start`: un proceso, sin ventana, que se
levanta con launchd y no depende de que nadie haya tocado un toggle.

Binario oficial, descarga directa desde las *releases* de `drawthingsai/draw-things-community`
(hoy `v1.20260716.0`, ~192 MB). No hay fórmula de Homebrew para él: la del tap
(`draw-things-cli`) es otra herramienta distinta, de inferencia y entrenamiento locales.

### 4.3 Atado al tailnet, no a `0.0.0.0`

`gRPCServerCLI` escucha en `0.0.0.0` **por defecto**. Es el mismo agujero que tenía LM
Studio con *Serve on Local Network*: cualquiera en el wifi de casa llega al servidor.

Se ata con `--address`, resolviendo la IP igual que hace `mac/scripts/20-serve.sh`:

```
--address "$(tailscale ip -4 | head -1)"
```

Sobre el papel hay además autenticación (`--shared-secret`), que LM Studio no ofrece. **En
la práctica no se puede usar con este cliente:** ver §4.4.

### 4.4 Sin secreto compartido y sin TLS — comprobado, no asumido

Las dos defensas que `gRPCServerCLI` ofrece por encima del tailnet resultaron
inservibles con la extensión oficial de ComfyUI. Se documentan porque parecen descuidos
y no lo son.

**El secreto compartido.** El nodo de ComfyUI expone tres entradas: `server`, `port` y
`use_tls`. No hay campo para el secreto ni forma de inyectarlo. Con `--shared-secret`
puesto, el servidor responde a cualquier petición con `sharedSecretMissing` y el catálogo
llega vacío: no se puede ni elegir modelo. Queda *opt-in* con `DT_USE_SECRET=1` para el
día en que el cliente sea un script propio que sepa mandarlo.

**TLS.** Va encendido por defecto, pero el certificado que genera el servidor es:

```
subject=CN=localhost   SAN: DNS:localhost, DNS:*, IP:127.0.0.1, IP:0.0.0.0
```

Asume que el cliente corre en la misma máquina. Conectando a `macbook` desde el PC la
verificación de nombre falla siempre (`Hostname Verification failed`), y el binario no
admite ni un nombre alternativo ni aportar un certificado propio. Se apaga con `--no-tls`.

No se pierde cifrado: **el tailnet ya es WireGuard de extremo a extremo**. El TLS de aquí
solo añadiría una segunda capa sobre un canal ya cifrado, con un certificado que además
no se puede validar.

*Alternativa descartada:* túnel SSH para que el destino sea `localhost` y el certificado
cuadre. Funciona, pero mete una pieza que tiene que estar levantada antes que ComfyUI y
reconectar sola. No compensa.

**Conclusión:** la barrera real es la misma que la del motor de texto — el puerto solo
escucha en `100.x`. Quien no esté en el tailnet no llega.

### 4.5 ComfyUI en el PC, en Docker, primero **sin GPU**

ComfyUI es Python y corre en Linux sin fricción, así que va en Docker como el resto del
stack del PC.

En la primera etapa el contenedor **no necesita GPU**: todo el cómputo ocurre en el Mac y
ComfyUI solo construye peticiones y recoge imágenes. Eso quita del camino crítico el
NVIDIA Container Toolkit, que es lo único que habría que instalar fuera de contenedor.

En la segunda etapa (§3.2) se le pasa la 4070 al mismo contenedor y los nodos CUDA
normales de ComfyUI quedan disponibles junto a los de Draw Things. Es aditivo: se cambia
el `docker-compose.yml` y se recrea el contenedor, sin tocar el Mac ni los flujos ya
guardados.

Extensión: `drawthingsai/draw-things-comfyui`, la **oficial**. Existe una anterior de la
comunidad (`Jokimbe/ComfyUI-DrawThings-gRPC`) que está marcada como deprecada y remite a
esta. Exige arrancar el servidor con dos banderas concretas:

```
gRPCServerCLI-macOS <modelos> --no-response-compression --model-browser
```

`--model-browser` es obligatorio para que ComfyUI vea los modelos locales del Mac.

### 4.6 Los modelos se descargan con la app, no por CLI

No hay equivalente a `lms get`. El catálogo se gestiona desde la app Draw Things en el
Mac, que deja los ficheros en:

```
~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models
```

`gRPCServerCLI` recibe ese directorio como argumento y sirve lo que haya. La app se abre
para descargar y se cierra; el servidor no la necesita para funcionar.

Consecuencia práctica: **la app hay que instalarla y abrirla al menos una vez**, igual que
pasó con LM Studio y `lms bootstrap`. Es un paso manual de Fase 0.

### 4.7 No conviven con el LLM en memoria

Confirmado contigo: no vas a usar los dos a la vez. Aun así conviene que sea explícito y
no un accidente.

El límite de GPU está en 24576 MB. Qwen ocupa ~17 GB cargado y Flux en bf16 pediría ~24 GB:
no caben juntos. Con `jitModelTTL` LM Studio suelta el modelo a la hora sin uso, pero eso
es esperar, no gestionar.

Un `lms unload --all` antes de generar lo resuelve, y va en el script de arranque del
motor de imagen.

---

## 5. Topología

Primera etapa — lo que se monta ahora:

```
   PC Linux                              MacBook M1 Pro
   ─────────                             ──────────────
   ComfyUI (Docker, :8188, sin GPU)
     └─ nodos Draw Things ── tailnet ──► gRPCServerCLI :7859 (TLS + secreto)
                                            └─► Metal, 32 GB unificada
                                                [ Flux bf16, Qwen-Image, vídeo ]

   OpenCode ──────────────── tailnet ──► LM Studio :1234   (ya montado, intacto)
```

Segunda etapa — se añade sin tocar lo anterior:

```
   ComfyUI (Docker, :8188)
     ├─ nodos CUDA ──────► RTX 4070      [ SDXL y lo que quepa en 8 GB, rápido ]
     └─ nodos Draw Things ── tailnet ──► gRPCServerCLI :7859
```

Puertos en el Mac: `1234` texto, `7859` imagen. Independientes.

---

## 6. Plan de despliegue

Dos etapas. **La primera es la que se ejecuta ahora**; la segunda queda planteada y
abierta, y no depende de nada que se decida hoy.

Ficheros **nuevos**. Ninguno de los existentes se modifica.

---

## 6.A Primera etapa — servidor de imágenes en el Mac

Objetivo: generar desde el PC con el M1 Pro haciendo el cómputo. Al terminar esta etapa
el sistema está completo y es usable por sí solo.

### Fase 0 — Manual en el Mac

1. Instalar Draw Things (gratis, App Store o `drawthings.ai`).
2. Abrirlo una vez y descargar un modelo de prueba (SDXL Turbo, ~7 GB, rápido de validar).
3. Cerrarlo.

### Fase 1 — Motor en el Mac

| Fichero nuevo | Qué hace |
|---|---|
| `mac/scripts/40-drawthings-install.sh` | Descarga `gRPCServerCLI-macOS` de la release fijada, verifica el SHA, lo deja en `/usr/local/bin`, `chmod +x`, quita la cuarentena de Gatekeeper |
| `mac/scripts/50-drawthings-serve.sh` | Espera al tailnet (mismo bucle de 2 min que `20-serve.sh`), descarga los modelos de LM Studio, y lanza el servidor atado a la IP del tailnet con `--model-browser --no-response-compression --no-tls` |
| `mac/launchd/local.drawthings.plist` | LaunchAgent que llama al anterior al iniciar sesión. Agent y no Daemon: Metal exige sesión gráfica |
| `mac/.drawthings-secret` | El secreto compartido, generado al vuelo. **No se versiona** |

### Fase 2 — Cliente en el PC

| Fichero nuevo | Qué hace |
|---|---|
| `linux/comfyui/docker-compose.yml` | ComfyUI en `:8188` **sin GPU**, volúmenes para flujos y salidas, `extra_hosts` para `macbook` |
| `linux/comfyui/.env.example` | `MACBOOK_IP`, `DT_SHARED_SECRET` |
| `linux/scripts/60-comfyui-up.sh` | Levanta el stack e instala la extensión oficial en `custom_nodes` |
| `linux/scripts/verify-imagen.sh` | Verificación por fases, con la misma forma que `verify.sh`: tailnet → `:7859` responde → la extensión ve el catálogo de modelos → ComfyUI arriba |

### Fase 3 — Documentación

`README-IMAGEN.md`, con la misma estructura que `README.md`: fases, comprobación, uso
diario, mapa de ficheros y tabla de problemas frecuentes.

---

## 6.B Segunda etapa (abierta) — la 4070 como nodo adicional

**No se ejecuta ahora.** Queda planteada aquí para que la primera etapa no cierre puertas.

Objetivo: que el mismo ComfyUI pueda además generar en local con la RTX 4070, y que el
destino del cómputo se elija por modelo (§3.2) en vez de por infraestructura.

Trabajo previsto, todo en el PC:

- Instalar NVIDIA Container Toolkit.
- Añadir la reserva de GPU al `docker-compose.yml` de ComfyUI y recrear el contenedor.
- Un volumen para los checkpoints locales (SDXL y compañía) y su descarga.
- Ampliar `verify-imagen.sh` con una fase más: la GPU visible dentro del contenedor.

Por qué es aditivo y no un rediseño: la extensión de Draw Things y los nodos CUDA conviven
en el mismo grafo. Se añade un camino, no se sustituye ninguno. Los flujos guardados en la
primera etapa siguen funcionando igual, y el Mac no se toca.

---

## 7. Riesgos conocidos

**El sandbox de la app — se confirmó, y es el paso manual que faltaba.** Los modelos viven
bajo `~/Library/Containers/`. Lanzado por launchd, `gRPCServerCLI` **se cuelga** al
enumerar ese directorio: macOS pide consentimiento para leer datos de otra app y un
agente de fondo no tiene a quien preguntar. No da error — deja de contestar a todo el
mundo, y desde fuera parece un problema de red. El mismo binario contra el mismo
directorio funciona lanzado desde una sesión SSH, lo que despista todavía más.

Se arregla dando *Acceso a disco completo* a `gRPCServerCLI-macOS`, a mano, una vez
(Fase 0.b del runbook). Intento descartado: servir un espejo de enlaces simbólicos fuera
del contenedor. No vale, porque el script que construiría el espejo corre también bajo
launchd y tampoco puede listar el directorio — salió con cero ficheros.

**Un `.partial` cuelga el servidor.** Una descarga de modelo interrumpida deja un fichero
`.partial` en la carpeta, y al construir el catálogo el servidor intenta leerlo y se
bloquea: acepta la conexión TCP pero nunca contesta
(`timed out before receiving SETTINGS frame`). Mismo síntoma que el problema de TCC y
causa distinta. `verify-imagen.sh` comprueba las dos.

**El secreto viaja en la línea de comandos.** `--shared-secret` es un argumento, así que
cualquier `ps` en el Mac lo muestra en claro. `gRPCServerCLI` no admite leerlo de una
variable de entorno ni de un fichero. En un Mac de un solo usuario el impacto es
pequeño —quien pueda hacer `ps` ya tiene tu sesión— pero conviene saberlo y no tratar
ese secreto como si fuera fuerte. El fichero `~/.drawthings/secret` sí está en `600`.

**8 GB son 8 GB.** Riesgo de la segunda etapa, no de la primera. Con SDXL a resoluciones
altas o varios ControlNets, la 4070 se queda sin VRAM. No es un fallo del montaje: es la
señal de cuándo mandar el trabajo al Mac.

**Vídeo.** Ni la 4070 ni el M1 Pro son cómodos ahí. Fuera de alcance por ahora.

---

## 8. Qué queda fuera

- La 4070 como nodo local: no está descartada, está planificada en §6.B como segunda etapa.
- Entrenamiento de LoRAs (el `draw-things-cli` del tap de Homebrew lo hace; otro día).
- Exponer el servicio fuera del tailnet.
- Cola de trabajos o multiusuario.
