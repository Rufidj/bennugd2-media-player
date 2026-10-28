#!/bin/bash
# Genera el instalador de Windows con NSIS (makensis.exe ejecutado con wine).
#   NSIS=<carpeta con makensis.exe>  SRC=<carpeta del paquete de Windows>  OUT=<instalador.exe>
HERE="$(cd "$(dirname "$0")" && pwd)"
NSIS="${NSIS:?indica la carpeta de NSIS (donde esta makensis.exe)}"
SRC="${SRC:-/tmp/bennugd2-media-player-windows-x86_64}"
OUT="${OUT:-$HOME/Escritorio/BennuGD2-MediaPlayer-Setup.exe}"
VER="$(grep -m1 'APP_VERSION =' "$HERE/mediaplayer.prg" | sed 's/.*"\(.*\)".*/\1/')"
cd "$HERE/windows"
wine "$NSIS/makensis.exe" -V2 "/DSRC=Z:$SRC" "/DVERSION=$VER" "/DOUT=Z:$OUT" installer.nsi
