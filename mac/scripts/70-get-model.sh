#!/usr/bin/env bash
# Descarga modelos de Draw Things sin abrir la app. Ejecutar EN EL MAC.
#   ./70-get-model.sh flux_1_dev_q5p.ckpt t5_xxl_encoder_q6p.ckpt ...
#
# La app es lo normal, pero solo se maneja con raton. Los ficheros ya
# convertidos al formato de Draw Things estan publicados en su CDN, y los
# nombres salen de los metadata.json de drawthingsai/community-models.
#
# Descarga a un temporal FUERA de la carpeta de modelos y solo mueve al
# terminar. Es deliberado: un fichero a medias dentro de Models cuelga el
# servidor entero -- acepta la conexion y no contesta nunca (§7 del plan).
set -euo pipefail

CDN="https://static.libnnc.org"
MODELS="$HOME/Library/Containers/com.liuliu.draw-things/Data/Documents/Models"
TMP="$HOME/.drawthings/descargas"

[[ $# -gt 0 ]] || { echo "Uso: $0 <fichero.ckpt> [fichero.ckpt ...]" >&2; exit 1; }
[[ -d "$MODELS" ]] || { echo "No existe $MODELS" >&2; exit 1; }
mkdir -p "$TMP"

for f in "$@"; do
  if [[ -f "$MODELS/$f" ]]; then
    echo "ya esta: $f"
    continue
  fi
  echo "bajando $f ..."
  # -C - reanuda si se corto una descarga anterior; el fichero vive en $TMP,
  # asi que aunque quede a medias no afecta al servidor.
  curl -fL --retry 5 --retry-delay 5 -C - --progress-bar -o "$TMP/$f" "$CDN/$f" || {
    echo "!! fallo bajando $f (queda en $TMP para reanudar)" >&2; exit 1; }
  mv "$TMP/$f" "$MODELS/$f"
  echo "listo: $f  ($(du -h "$MODELS/$f" | cut -f1))"
done

echo
echo "Modelos en el Mac:"
ls -1 "$MODELS"/*.ckpt | sed 's|.*/|  |'
echo
echo "El servidor los ve sin reiniciar (--model-browser lee en cada consulta)."
