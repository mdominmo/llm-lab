# ComfyUI como cliente del servidor de Draw Things del Mac.
#
# Imagen propia y no una de terceros: lo unico que hace falta es Python,
# ComfyUI y la extension oficial. Construirla aqui evita confiar en una
# imagen de un tercero para algo tan pequeno.
#
# PRIMERA ETAPA: sin GPU. Todo el computo ocurre en el Mac, asi que torch
# va en su version de CPU (~200 MB en vez de ~2.5 GB con CUDA). Cuando se
# aborde la segunda etapa (§6.B de PLAN-IMAGEN.md) se cambia el indice de
# torch por el de CUDA y se le pasa la 4070 al contenedor.
FROM python:3.12-slim

ARG COMFYUI_REF=master
ARG EXT_REF=main

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone --depth 1 --branch "$COMFYUI_REF" \
      https://github.com/comfyanonymous/ComfyUI.git comfyui

WORKDIR /opt/comfyui

# El indice de CPU es deliberado: ver cabecera.
RUN pip install --no-cache-dir \
      --extra-index-url https://download.pytorch.org/whl/cpu \
      torch torchvision torchaudio \
 && pip install --no-cache-dir -r requirements.txt

# La extension OFICIAL. La de la comunidad (Jokimbe/ComfyUI-DrawThings-gRPC)
# esta deprecada y remite a esta.
RUN git clone --depth 1 --branch "$EXT_REF" \
      https://github.com/drawthingsai/draw-things-comfyui.git \
      custom_nodes/draw-things-comfyui \
 && if [ -f custom_nodes/draw-things-comfyui/requirements.txt ]; then \
      pip install --no-cache-dir -r custom_nodes/draw-things-comfyui/requirements.txt; \
    fi

EXPOSE 8188

# --cpu porque en esta etapa no hay GPU local: sin el, ComfyUI aborta al no
# encontrar CUDA. --listen para que sea alcanzable fuera del contenedor.
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--cpu"]
