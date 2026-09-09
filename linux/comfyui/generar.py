#!/usr/bin/env python3
"""Genera una imagen desde la terminal, sin tocar la interfaz de ComfyUI.

    linux/comfyui/generar.py "un gato naranja durmiendo en un sofa"
    linux/comfyui/generar.py "retrato a lapiz" --pasos 8 --ancho 768 --alto 768

Manda el trabajo a ComfyUI (PC), que a su vez lo manda al servidor de Draw
Things del Mac. Solo libreria estandar: no hay nada que instalar.

Por que el campo `model` no es un nombre: el nodo DrawThingsSampler espera el
objeto entero del catalogo, {"value": {...}}, no la cadena del fichero. Se
saca de /dt_grpc/files_info, que es lo que consulta la propia interfaz.
"""
import argparse, json, sys, time, urllib.error, urllib.parse, urllib.request

BASE = "http://127.0.0.1:8188"


def pedir(ruta, datos=None, timeout=60):
    req = urllib.request.Request(BASE + ruta, data=datos)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def por_defecto(info, clase):
    """Cada entrada con el valor por defecto que declara el propio nodo.

    El sampler exige las ~40 entradas presentes, no solo las que te interesan.
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
    p = argparse.ArgumentParser(description="Genera una imagen en el Mac.")
    p.add_argument("prompt", nargs="?", default="")
    p.add_argument("--negativo", default="")
    p.add_argument("--modelo", help="parte del nombre; por defecto, el primero")
    # Sin valor por defecto: lo pone el modelo (ajustes_del_modelo). Solo si
    # los indicas tu mandan sobre eso.
    p.add_argument("--pasos", type=int)
    p.add_argument("--cfg", type=float)
    p.add_argument("--ancho", type=int)
    p.add_argument("--alto", type=int)
    p.add_argument("--semilla", type=int, default=42)
    p.add_argument("--servidor", default="macbook")
    p.add_argument("--puerto", default="7859")
    p.add_argument("--listar", action="store_true", help="solo listar modelos")
    a = p.parse_args()
    if not a.prompt and not a.listar:
        p.error("hace falta un prompt (o --listar)")

    try:
        info = pedir("/object_info", timeout=30)
    except Exception as e:
        sys.exit(f"ComfyUI no responde en {BASE}: {e}\n"
                 f"Levantalo con: linux/scripts/60-comfyui-up.sh")

    datos = urllib.parse.urlencode(
        {"server": a.servidor, "port": a.puerto, "use_tls": "false"}).encode()
    try:
        catalogo = pedir("/dt_grpc/files_info", datos, timeout=90)
    except Exception as e:
        sys.exit(f"El Mac no da el catalogo: {e}\n"
                 f"Diagnostico: linux/scripts/verify-imagen.sh")

    modelos = catalogo.get("models", [])
    if not modelos:
        sys.exit("Catalogo vacio. Falta 'Acceso a disco completo' para "
                 "gRPCServerCLI-macOS en el Mac (Fase 0.b de README-IMAGEN.md).")

    if a.listar:
        for m in modelos:
            print(f"  {m.get('name')}   [{m.get('file')}]")
        return

    modelo = modelos[0]
    if a.modelo:
        coincide = [m for m in modelos
                    if a.modelo.lower() in (m.get("name", "") + m.get("file", "")).lower()]
        if not coincide:
            sys.exit(f"Ningun modelo coincide con '{a.modelo}'. Usa --listar.")
        modelo = coincide[0]

    prop = ajustes_del_modelo(modelo)
    sampler = por_defecto(info, "DrawThingsSampler")
    sampler.update({k: v for k, v in prop.items() if k != "lado"})
    sampler.update({
        "server": a.servidor, "port": a.puerto, "use_tls": False,
        "model": {"value": modelo},
        "positive": ["1", 0], "negative": ["2", 0],
        "width": a.ancho or prop["lado"], "height": a.alto or prop["lado"],
        "steps": a.pasos or prop["steps"],
        "cfg": a.cfg if a.cfg is not None else prop["cfg"],
        "seed": a.semilla, "batch_size": 1,
    })

    grafo = {
        "1": {"class_type": "DrawThingsPositive",
              "inputs": {**por_defecto(info, "DrawThingsPositive"), "positive": a.prompt}},
        "2": {"class_type": "DrawThingsNegative",
              "inputs": {**por_defecto(info, "DrawThingsNegative"), "negative": a.negativo}},
        "3": {"class_type": "DrawThingsSampler", "inputs": sampler},
        "4": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": "cli", "images": ["3", 0]}},
    }

    print(f"modelo: {modelo.get('name')}  |  "
          f"{sampler['width']}x{sampler['height']}, {sampler['steps']} pasos, "
          f"{sampler['sampler_name']}, cfg {sampler['cfg']}")
    try:
        pid = pedir("/prompt", json.dumps({"prompt": grafo}).encode(), 60)["prompt_id"]
    except urllib.error.HTTPError as e:
        d = json.loads(e.read().decode())
        for n, err in d.get("node_errors", {}).items():
            for x in err["errors"]:
                print(f"  nodo {n}: {x['message']} -> {x['details']}", file=sys.stderr)
        sys.exit(1)

    t0 = time.time()
    while time.time() - t0 < 900:
        h = pedir(f"/history/{pid}", timeout=20)
        if pid in h:
            estado = h[pid]["status"]
            if estado["status_str"] != "success":
                print("FALLO:", file=sys.stderr)
                for msg in estado.get("messages", []):
                    if msg[0] == "execution_error":
                        print("  ", msg[1].get("exception_message", "").strip(), file=sys.stderr)
                sys.exit(1)
            for _, out in h[pid]["outputs"].items():
                for img in out.get("images", []):
                    print(f"listo en {time.time()-t0:.0f}s: "
                          f"linux/comfyui/data/output/{img['filename']}")
            return
        time.sleep(2)
    sys.exit("sin resultado en 15 min")


if __name__ == "__main__":
    main()
