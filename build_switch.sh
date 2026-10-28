#!/bin/bash
# Compila el reproductor y genera el .nro para la Nintendo Switch (homebrew, con devkitPro):
#   ./build_switch.sh
# Usa el build.sh del motor (objetivo "switch"): enlaza bgdi.elf, y lo empaqueta con el .dcb, los recursos,
# los idiomas y los addons en un romfs. Copia el .nro a la SD, en /switch/mediaplayer/ (o ejecutalo con nxlink).
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${BENNUGD2:-$HOME/BennuGD2}"
BIN="$ENGINE/build/linux-gnu/bin"
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}" DEVKITA64="${DEVKITA64:-/opt/devkitpro/devkitA64}"
export PATH="$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH"
OUT="${OUT:-$HOME/BennuGD2 Media Player/switch}"
set -e
cd "$HERE"

# 1. motor para Switch (si no se pide lo contrario) y .dcb con el bgdc de PC
if [ "${SKIP_ENGINE:-0}" != "1" ]; then
    ( cd "$ENGINE" && ./build.sh switch ) 2>&1 | tail -3
fi
ELF="$ENGINE/build/aarch64-none-elf/bin/bgdi.elf"
[ -f "$ELF" ] || { echo "no esta $ELF: el motor no enlazo"; exit 1; }
LD_LIBRARY_PATH="$BIN" "$BIN/bgdc" mediaplayer.prg | grep -i "error" && exit 1 || true

# 2. romfs: el motor entra en romfs:/ y carga game.dcb de alli
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/romfs/res" "$STAGE/romfs/lang" "$STAGE/romfs/addons" "$STAGE/romfs/videos"
cp mediaplayer.dcb "$STAGE/romfs/game.dcb"
cp res/cacert.pem "$STAGE/romfs/cacert.pem"     # certificados raiz de Mozilla (curl.se/ca): la Switch no tiene almacen del sistema para https
cp res/*.png "$STAGE/romfs/res/" && cp -r res/fonts res/skins "$STAGE/romfs/res/"
cp lang/*.txt "$STAGE/romfs/lang/"
cp lists/*.m3u "$STAGE/romfs/videos/"
for a in plex radio-browser somafm internet-archive peertube youtube jellyfin torrents; do cp -r "addons/$a" "$STAGE/romfs/addons/"; done
cp ADDONS.md ADDONS.es.md "$STAGE/romfs/addons/" 2>/dev/null || true

# 3. icono (256x256 JPEG) y datos de la aplicacion
python3 - "$STAGE/icon.jpg" <<'PY'
import sys
from PIL import Image
Image.open("title/sce_sys/icon0.png").convert("RGB").resize((256, 256), Image.LANCZOS).save(sys.argv[1], quality=92)
PY
VER="$(grep -m1 'APP_VERSION =' mediaplayer.prg | sed 's/.*"\(.*\)".*/\1/')"
nacptool --create "BennuGD2 Media Player" "Rufidj" "$VER" "$STAGE/app.nacp"

# 4. .nro
mkdir -p "$OUT"
elf2nro "$ELF" "$OUT/mediaplayer.nro" --icon="$STAGE/icon.jpg" --nacp="$STAGE/app.nacp" --romfsdir="$STAGE/romfs"
echo "### Listo: $OUT/mediaplayer.nro ($(du -h "$OUT/mediaplayer.nro" | cut -f1)) ###"
echo "### Copialo a la SD: /switch/mediaplayer/mediaplayer.nro ###"
