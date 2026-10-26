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
cp res/*.png "$STAGE/res/"
cp -r res/fonts "$STAGE/res/"
cp lang/*.txt "$STAGE/lang/"
cp lists/*.m3u "$STAGE/videos/"
if [ -d samples ]; then cp samples/* "$STAGE/videos/" 2>/dev/null || true; fi
mkdir -p "$STAGE/addons"
for a in plex radio-browser somafm internet-archive peertube youtube; do cp -r "addons/$a" "$STAGE/addons/"; done  # incluye logo.png
cp ADDONS.md ADDONS.es.md "$STAGE/addons/" 2>/dev/null || true

# sce_sys: el empaquetador pide los dos fondos de presentacion (3840x2160 BC7 DX10, sin mipmaps)
# o ninguno, asi que se quitan cuando falta alguno o no tienen el tamano que espera el validador
# PS5_NO_PICS=1 los quita siempre: el Convert de ps5upload copia los fondos al contenido del pkg pero
# no rehace la tabla de hashes, y entonces la consola instala el pkg pero no lo abre.
PIC_BYTES=8294548   # 148 de cabecera + (3840/4)*(2160/4)*16 de BC7
mkdir -p "$STAGE/sce_sys"
cp title/sce_sys/* "$STAGE/sce_sys/"
if [ "${PS5_NO_PICS:-0}" = "1" ]; then
    rm -f "$STAGE/sce_sys/pic0.dds" "$STAGE/sce_sys/pic1.dds"
    echo "titulo sin fondos de presentacion (PS5_NO_PICS=1)"
elif [ "$(stat -c%s "$STAGE/sce_sys/pic0.dds" 2>/dev/null)" != "$PIC_BYTES" ] || \
   [ "$(stat -c%s "$STAGE/sce_sys/pic1.dds" 2>/dev/null)" != "$PIC_BYTES" ]; then
    rm -f "$STAGE/sce_sys/pic0.dds" "$STAGE/sce_sys/pic1.dds"
    echo "aviso: se genera el titulo sin fondos de presentacion (hacen falta pic0.dds y pic1.dds en 3840x2160 BC7 DX10)"
fi

# TITLE_ID=PPSA000NN (y opcionalmente TITLE_NAME) construye una variante con otro id, para probar sin tocar el titulo instalado
TITLE_ID="${TITLE_ID:-PPSA00090}"; TITLE_NAME="${TITLE_NAME:-BennuGD2 Media Player}"
if [ "$TITLE_ID" != "PPSA00090" ] || [ "$TITLE_NAME" != "BennuGD2 Media Player" ]; then
    NUM="${TITLE_ID#PPSA}"
    sed -i "s/PPSA00090/$TITLE_ID/g; s/\"conceptId\": \"00090\"/\"conceptId\": \"$NUM\"/; s/\"titleName\": \"BennuGD2 Media Player\"/\"titleName\": \"$TITLE_NAME\"/" "$STAGE/sce_sys/param.json"
fi

# 3. motor + eboot + carpeta del titulo
cd "$ENGINE"
PS5_TITLE_ID="$TITLE_ID" \
PS5_TITLE_NAME="$TITLE_NAME" \
PS5_SCE_SYS="$STAGE/sce_sys" \
PS5_DCB="$HERE/mediaplayer.dcb" \
PS5_ASSETS="$STAGE" \
PS5_OUT="${OUT:-$HOME/BennuGD2 Media Player/$TITLE_ID}" \
./build.sh ps5
