#!/bin/bash
# Compila el reproductor y genera la carpeta del titulo PS5 en el escritorio, todo con un solo comando:
#   ./build_ps5.sh
# Usa el build.sh del motor (rama ps5): recompila las librerias, enlaza el eboot y monta la carpeta.
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${BENNUGD2:-$HOME/BennuGD2}"
BIN="$ENGINE/build/linux-gnu/bin"
set -e
cd "$HERE"

# 1. .dcb con el bgdc actual
LD_LIBRARY_PATH="$BIN" "$BIN/bgdc" mediaplayer.prg | grep -i "error" && exit 1 || true

# 2. recursos del titulo: iconos y fuentes + listas y videos de muestra (cada carpeta recibe su .index)
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/res" "$STAGE/videos"
mkdir -p "$STAGE/lang"
cp res/*.png res/fonttest.txt "$STAGE/res/"
cp -r res/fonts "$STAGE/res/"
cp lang/*.txt "$STAGE/lang/"
cp lists/*.m3u samples/* "$STAGE/videos/"
mkdir -p "$STAGE/addons"
for a in plex radio-browser somafm internet-archive peertube youtube; do cp -r "addons/$a" "$STAGE/addons/"; done  # incluye logo.png
cp ADDONS.md ADDONS.es.md "$STAGE/addons/" 2>/dev/null || true

# 3. motor + eboot + carpeta del titulo
cd "$ENGINE"
PS5_TITLE_ID=PPSA00090 \
PS5_TITLE_NAME="BennuGD2 Media Player" \
PS5_SCE_SYS="$HERE/title/sce_sys" \
PS5_DCB="$HERE/mediaplayer.dcb" \
PS5_ASSETS="$STAGE" \
PS5_OUT="${OUT:-$HOME/BennuGD2 Media Player/PPSA00090}" \
./build.sh ps5
