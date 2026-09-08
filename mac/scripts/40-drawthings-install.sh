#!/usr/bin/env bash
# Instala el servidor gRPC de Draw Things. Ejecutar EN EL MAC.
#
# Es el binario OFICIAL de drawthingsai/draw-things-community, no la app.
# La app se usa solo para descargar modelos; el servidor no la necesita para
# funcionar (§4.2 de PLAN-IMAGEN.md).
#
# Va a ~/.drawthings/bin y no a /usr/local/bin para no pedir sudo: esto lo
# lanza un LaunchAgent del usuario, no un demonio del sistema.
set -euo pipefail

VERSION="v1.20260716.0"
DEST="$HOME/.drawthings"
BIN="$DEST/bin/gRPCServerCLI-macOS"
URL="https://github.com/drawthingsai/draw-things-community/releases/download/$VERSION/gRPCServerCLI-macOS"

mkdir -p "$DEST/bin"

if [[ -x "$BIN" ]]; then
  echo "Ya instalado: $BIN"
else
  echo "Descargando $VERSION (~192 MB)..."
  curl -fL --retry 3 --progress-bar -o "$BIN.tmp" "$URL"
  mv "$BIN.tmp" "$BIN"
  chmod +x "$BIN"
fi

# Sin esto Gatekeeper bloquea el binario: viene de internet y no esta notarizado
# como app. Falla en silencio si el atributo no esta, que es lo normal en curl.
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true

# El secreto compartido. Segunda barrera tras el tailnet: a diferencia de
# LM Studio, este servidor si sabe autenticar (--shared-secret).
SECRET="$DEST/secret"
if [[ ! -f "$SECRET" ]]; then
  umask 077
  head -c 32 /dev/urandom | xxd -p -c 64 > "$SECRET"
  echo "Secreto generado en $SECRET"
fi
chmod 600 "$SECRET"

echo
"$BIN" --help 2>&1 | head -3 || true
echo
echo "Instalado. Arrancar con: mac/scripts/50-drawthings-serve.sh"
