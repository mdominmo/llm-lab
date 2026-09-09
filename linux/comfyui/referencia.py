#!/usr/bin/env python3
"""Genera imagenes usando otras imagenes como referencia.

    linux/comfyui/referencia.py "en la montana, atardecer" \
        --ref entrada1.jpg --ref entrada2.jpg

Sube las referencias a ComfyUI, las encadena y manda el trabajo al servidor
de Draw Things del Mac. Solo libreria estandar.

ABIERTO A CAMBIAR DE MODELO
  Nada esta cableado a un modelo ni a un adaptador concretos: los dos se
  buscan por nombre en el catalogo vivo del Mac (--modelo / --adaptador). Lo
  que NO es portable son los pesos, porque un adaptador sirve solo para la
  arquitectura con la que se entreno; cambiar de modelo obliga a bajar su
  adaptador equivalente. El script lo detecta y lo dice en vez de generar en
  silencio ignorando las referencias.
"""
import argparse, json, mimetypes, os, sys, time, urllib.error, urllib.parse, urllib.request
import uuid

BASE = "http://127.0.0.1:8188"


def pedir(ruta, datos=None, timeout=90, cabeceras=None):
    req = urllib.request.Request(BASE + ruta, data=datos, headers=cabeceras or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def subir(ruta_local):
    """Sube una imagen a la carpeta input de ComfyUI y devuelve su nombre."""
    if not os.path.isfile(ruta_local):
        sys.exit(f"No existe el fichero: {ruta_local}")
    nombre = os.path.basename(ruta_local)
    tipo = mimetypes.guess_type(nombre)[0] or "application/octet-stream"
    limite = "----" + uuid.uuid4().hex
    payload = b"".join([
        f'--{limite}\r\nContent-Disposition: form-data; name="image"; '
        f'filename="{nombre}"\r\nContent-Type: {tipo}\r\n\r\n'.encode(),
        open(ruta_local, "rb").read(),
        f"\r\n--{limite}\r\nContent-Disposition: form-data; name=\"overwrite\"\r\n\r\ntrue\r\n".encode(),
        f"--{limite}--\r\n".encode(),
    ])
    r = pedir("/upload/image", payload, 120,
              {"Content-Type": f"multipart/form-data; boundary={limite}"})
    return r["name"]


def por_defecto(info, clase):
    """Cada entrada con el valor por defecto que declara el nodo.

    Los nodos de Draw Things exigen presentes TODAS sus entradas, no solo las
    que interesan; sin esto ComfyUI rechaza el grafo.
    """
    salida, spec = {}, info[clase]["input"]
    for seccion in ("required", "optional"):
        for k, v in spec.get(seccion, {}).items():
            tipo, meta = v[0], (v[1] if len(v) > 1 else {})
            if isinstance(tipo, list):
                salida[k] = tipo[0] if tipo else ""
            elif "default" in meta:
                salida[k] = meta["default"]
            elif tipo == "STRING":
                salida[k] = ""
            elif tipo in ("INT", "FLOAT"):
                salida[k] = 0
            elif tipo == "BOOLEAN":
                salida[k] = False
    return salida


def buscar(lista, patron, que):
    if not patron:
        return lista[0] if lista else None
    for x in lista:
        if patron.lower() in (x.get("name", "") + " " + x.get("file", "")).lower():
            return x
    sys.exit(f"Ningun {que} coincide con '{patron}'.\nDisponibles:\n" +
             "\n".join(f"  {x.get('name')}  [{x.get('file')}]" for x in lista))


def ajustes_del_modelo(modelo):
    """Valores que dependen de la arquitectura, sacados del propio catalogo.

    Sin esto no vale con cambiar de modelo: Flux es un modelo de flow matching
    y con un sampler de difusion clasica (el primero de la lista) devuelve
    manchas de color sin estructura, sin dar ningun error. Su configuracion
    oficial pide el sampler 10, "Euler A Trailing", y guiado por embedding en
    vez de CFG.

    El catalogo publica `guidance_embed` y `default_scale`, asi que se decide
    con eso y no con el nombre del modelo: cualquier modelo futuro del mismo
    tipo queda cubierto.
    """
    lado = int(modelo.get("default_scale", 8)) * 64
    if modelo.get("guidance_embed"):
        return {"sampler_name": "Euler A Trailing", "cfg": 1.0,
                "guidance_embed": 4.5, "speed_up": True,
                "res_dpt_shift": True, "shift": 1.0,
                "steps": 28, "lado": lado}
    return {"sampler_name": "DPM++ 2M Karras", "cfg": 1.0,
            "steps": 4, "lado": lado}


def main():
    p = argparse.ArgumentParser(description="Genera a partir de imagenes de referencia.")
    p.add_argument("prompt", nargs="?", default="")
    p.add_argument("--ref", action="append", default=[],
                   help="imagen de referencia; repetir para varias (hasta 4)")
    p.add_argument("--negativo", default="deformed, blurry")
    p.add_argument("--modelo", help="parte del nombre; por defecto el primero")
    p.add_argument("--adaptador", default="",
                   help="adaptador del catalogo que consume las referencias")
    p.add_argument("--lora", help="LoRA a aplicar")
    p.add_argument("--peso", type=float, default=0.9,
                   help="fuerza de la referencia, 0-1 (por defecto 0.9)")
    p.add_argument("--peso-lora", type=float, default=0.8)
    # Sin valor por defecto: los pone el modelo (ajustes_del_modelo). Solo si
    # los indicas tu mandan sobre eso.
    p.add_argument("--pasos", type=int)
    p.add_argument("--cfg", type=float)
    p.add_argument("--ancho", type=int)
    p.add_argument("--alto", type=int)
    p.add_argument("--semilla", type=int, default=-1)
    p.add_argument("--servidor", default="macbook")
    p.add_argument("--puerto", default="7859")
    p.add_argument("--listar", action="store_true")
    a = p.parse_args()
    if not a.listar and (not a.prompt or not a.ref):
        p.error("hacen falta un prompt y al menos una --ref (o usa --listar)")
    if len(a.ref) > 4:
        p.error("maximo 4 referencias")

    try:
        info = pedir("/object_info", timeout=60)
    except Exception as e:
        sys.exit(f"ComfyUI no responde en {BASE}: {e}\n"
                 f"Levantalo: cd linux/comfyui && docker compose up -d")

    datos = urllib.parse.urlencode(
        {"server": a.servidor, "port": a.puerto, "use_tls": "false"}).encode()
    try:
        catalogo = pedir("/dt_grpc/files_info", datos, timeout=120)
    except Exception as e:
        sys.exit(f"El Mac no da el catalogo: {e}\nDiagnostico: linux/scripts/verify-imagen.sh")

    modelos = catalogo.get("models", [])
    adaptadores = catalogo.get("controlNets", [])
    loras = catalogo.get("loras", [])

    if a.listar:
        for etiqueta, lista in (("modelos", modelos), ("adaptadores", adaptadores),
                                ("loras", loras)):
            print(f"== {etiqueta} ({len(lista)})")
            for x in lista:
                print(f"   {x.get('name')}   [{x.get('file')}]")
        return

    if not modelos:
        sys.exit("Catalogo vacio: falta 'Acceso a disco completo' en el Mac.")
    modelo = buscar(modelos, a.modelo, "modelo")

    # Un adaptador solo sirve para la arquitectura con la que se entreno. Si se
    # emparejan mal, el servidor NO falla: genera ignorando las referencias en
    # silencio, y desde fuera parece que el flujo funciona. Por eso se filtra
    # por `version` antes de elegir, en vez de coger el primero que haya.
    arq = modelo.get("version")
    compatibles = [x for x in adaptadores if x.get("version") == arq]

    adaptador = None
    if a.adaptador:
        adaptador = buscar(adaptadores, a.adaptador, "adaptador")
        if adaptador.get("version") != arq:
            sys.exit(f"'{adaptador.get('name')}' es de arquitectura "
                     f"'{adaptador.get('version')}' y el modelo "
                     f"'{modelo.get('name')}' es '{arq}'. No son compatibles.")
    elif compatibles:
        adaptador = compatibles[0]

    if adaptador is None:
        otras = {x.get("version") for x in adaptadores}
        print(f"AVISO: no hay adaptador para la arquitectura '{arq}' de "
              f"'{modelo.get('name')}'.\n"
              "       Se genera solo desde el prompt: las referencias NO se usaran.",
              file=sys.stderr)
        if otras:
            print(f"       Hay adaptadores, pero de otras arquitecturas: "
                  f"{', '.join(sorted(otras))}.\n"
                  f"       Elige un modelo de esa arquitectura con --modelo.",
                  file=sys.stderr)

    grafo, n = {}, 0

    def nodo(clase, extra):
        nonlocal n
        n += 1
        grafo[str(n)] = {"class_type": clase,
                         "inputs": {**por_defecto(info, clase), **extra}}
        return str(n)

    id_pos = nodo("DrawThingsPositive", {"positive": a.prompt})
    id_neg = nodo("DrawThingsNegative", {"negative": a.negativo})

    # Una entrada por referencia, encadenadas: cada DrawThingsControlNet
    # acepta otro control_net de entrada, asi que se apilan en cascada.
    cadena = None
    if adaptador is not None:
        for ref in a.ref:
            nombre = subir(ref)
            id_img = nodo("LoadImage", {"image": nombre})
            extra = {
                "control_name": {"value": adaptador},
                "control_input_type": adaptador.get("modifier", "Shuffle").capitalize(),
                "control_weight": a.peso,
                "image": [id_img, 0],
            }
            if cadena:
                extra["control_net"] = [cadena, 0]
            cadena = nodo("DrawThingsControlNet", extra)

    id_lora = None
    if a.lora:
        if not loras:
            sys.exit("Pediste --lora pero no hay ninguno descargado en el Mac.")
        el = buscar(loras, a.lora, "lora")
        id_lora = nodo("DrawThingsLoRA",
                       {"lora_name": {"value": el}, "lora_weight": a.peso_lora})

    prop = ajustes_del_modelo(modelo)
    entradas = {k: v for k, v in prop.items() if k != "lado"}
    entradas.update({
        "server": a.servidor, "port": a.puerto, "use_tls": False,
        "model": {"value": modelo},
        "positive": [id_pos, 0], "negative": [id_neg, 0],
        "width": a.ancho or prop["lado"], "height": a.alto or prop["lado"],
        "steps": a.pasos or prop["steps"],
        "cfg": a.cfg if a.cfg is not None else prop["cfg"],
        "batch_size": 1,
        "seed": a.semilla if a.semilla >= 0 else int(time.time()) % 4294967295,
    })
    if cadena:
        entradas["control_net"] = [cadena, 0]
    if id_lora:
        entradas["lora"] = [id_lora, 0]
    id_sam = nodo("DrawThingsSampler", entradas)
    nodo("SaveImage", {"filename_prefix": "ref", "images": [id_sam, 0]})

    print(f"modelo: {modelo.get('name')}")
    if adaptador is not None:
        print(f"adaptador: {adaptador.get('name')}  x{len(a.ref)} ref(s), peso {a.peso}")
    if id_lora:
        print(f"lora: peso {a.peso_lora}")
    print(f"{entradas['width']}x{entradas['height']}, {entradas['steps']} pasos, "
          f"{entradas['sampler_name']}, cfg {entradas['cfg']}, "
          f"semilla {entradas['seed']}")

    try:
        pid = pedir("/prompt", json.dumps({"prompt": grafo}).encode(), 90)["prompt_id"]
    except urllib.error.HTTPError as e:
        d = json.loads(e.read().decode())
        for nid, err in d.get("node_errors", {}).items():
            for x in err["errors"]:
                clase = grafo.get(nid, {}).get("class_type", "?")
                print(f"  nodo {nid} ({clase}): {x['message']} -> {x['details']}",
                      file=sys.stderr)
        sys.exit(1)

    t0 = time.time()
    while time.time() - t0 < 1800:
        h = pedir(f"/history/{pid}", timeout=30)
        if pid in h:
            estado = h[pid]["status"]
            if estado["status_str"] != "success":
                print("FALLO:", file=sys.stderr)
                for msg in estado.get("messages", []):
                    if msg[0] == "execution_error":
                        print("  ", msg[1].get("exception_message", "").strip(),
                              file=sys.stderr)
                sys.exit(1)
            for _, out in h[pid]["outputs"].items():
                for img in out.get("images", []):
                    print(f"listo en {time.time()-t0:.0f}s: "
                          f"linux/comfyui/data/output/{img['filename']}")
            return
        time.sleep(3)
    sys.exit("sin resultado en 30 min")


if __name__ == "__main__":
    main()
