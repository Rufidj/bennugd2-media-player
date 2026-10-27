#!/bin/bash
# ---------------------------------------------------------------------------------------------
# Genera los paquetes de distribucion del BennuGD2 Media Player:
#   ~/Escritorio/bennugd2-media-player-linux-x86_64.tar.gz   (Linux)
#   ~/Escritorio/bennugd2-media-player-windows-x86_64.zip    (Windows)
#
# El .tar.gz de Linux se monta con el runtime del motor ya compilado en <ENGINE>/build/linux-gnu.
# El .zip de Windows necesita el runtime de mingw (<ENGINE>/build/x86_64-w64-mingw32) y las DLL de
# terceros (SDL2, FFmpeg...). Esas DLL se toman del paquete de la release anterior (WINBASE) o de
# un directorio propio (WIN_DEPS).
#
# Variables de entorno:
#   ENGINE=<checkout de BennuGD2>        por defecto $HOME/BennuGD2
#   OUT=<directorio de salida>            por defecto $HOME/Escritorio
#   WINBASE=<zip de la release anterior>  por defecto $OUT/bennugd2-media-player-windows-x86_64.zip
#   WIN_DEPS=<directorio con las DLL>     tiene prioridad sobre WINBASE
#   FF=<paquete FFmpeg para Windows>      por defecto "" (solo hace falta para recompilar libmod_video)
#
# Uso:  ./make_release.sh
# ---------------------------------------------------------------------------------------------
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE=${ENGINE:-$HOME/BennuGD2}
OUT=${OUT:-$HOME/Escritorio}
WINBASE=${WINBASE:-$OUT/bennugd2-media-player-windows-x86_64.zip}
WIN_DEPS=${WIN_DEPS:-}
FF=${FF:-}

LIN=$ENGINE/build/linux-gnu/bin
WIN=$ENGINE/build/x86_64-w64-mingw32/bin
NAME=bennugd2-media-player
ADDONS="torrents demo internet-archive jellyfin peertube plex radio-browser somafm youtube"

# ------------------------------------------------------------------------------------- .dcb
echo "== compilando el reproductor =="
LD_LIBRARY_PATH="$LIN" "$LIN/bgdc" mediaplayer.prg | grep -i "error" && exit 1 || true
cp mediaplayer.dcb /tmp/mediaplayer-release.dcb

# ------------------------------------------------------------------------------------- Linux
echo "== montando el paquete de Linux =="
STAGE=/tmp/$NAME-linux-x86_64
rm -rf "$STAGE" && mkdir -p "$STAGE"/{lib,lang,res,addons,lists}
cp "$LIN/bgdi" "$STAGE/"
for l in libbgdrtm libbggfx libbginput libbgload libbgsound \
         libmod_gfx libmod_input libmod_misc libmod_net libmod_sound libmod_video libsdlhandler; do
  cp "$LIN/$l.so" "$STAGE/lib/"
done
cp "$ENGINE/dependencies/linux-gnu/libSDL2_gpu.so" "$STAGE/lib/"
cp /tmp/mediaplayer-release.dcb "$STAGE/mediaplayer.dcb"
cp LICENSE ADDONS.md ADDONS.es.md "$STAGE/"
cp lang/*.txt "$STAGE/lang/"
cp res/*.png "$STAGE/res/" && mkdir -p "$STAGE/res/fonts" && cp res/fonts/* "$STAGE/res/fonts/"
cp lists/*.m3u "$STAGE/lists/"
for a in $ADDONS; do mkdir -p "$STAGE/addons/$a" && cp -r "addons/$a"/* "$STAGE/addons/$a/"; done

cat > "$STAGE/mediaplayer.sh" <<'EOF'
#!/bin/bash
# BennuGD2 Media Player - Linux launcher
HERE="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$HERE/lib:$LD_LIBRARY_PATH"
export MP_STORE="${MP_STORE:-$HOME/.local/share/bennugd2-media-player}"
export MEDIA_DIR="${MEDIA_DIR:-$HOME/Videos}"
mkdir -p "$MP_STORE"
cd "$HERE" && exec "$HERE/bgdi" mediaplayer.dcb "$@"
EOF
chmod +x "$STAGE/mediaplayer.sh"

cat > "$STAGE/README.txt" <<'EOF'
BennuGD2 Media Player - Linux x86-64
====================================

Run:   ./mediaplayer.sh [file or URL]
Start folder: MEDIA_DIR (default ~/Videos).  Settings, lists and addon data: MP_STORE (default ~/.local/share/bennugd2-media-player).

Requirements (Ubuntu 24.04 / Debian 13 style package names):
  sudo apt install libsdl2-2.0-0 libsdl2-mixer-2.0-0 libfreetype6 libssl3 \
                   libavformat60 libavcodec60 libavutil58 libswscale7 libswresample4

Built on Ubuntu 24.04 (glibc 2.39). Needs an OpenGL 3.x capable desktop session.
Controls: arrows move, Enter = open, Esc/Backspace = back, M = options/mute, S = subtitles,
          Space = pause, N / P = -10 s / +10 s, A = next audio track.
Mouse: click = open / press, wheel = scroll or volume, double click = full screen, right click = back (pause while playing).
Keys while playing: Left / Right skip, Page Up / Down = 1 min, Up / Down volume, M mute, F11 full screen.
Addons: copy a folder with a main.addon file into  $MP_STORE/addons/  (tutorial: ADDONS.md / ADDONS.es.md),
        or install them from the built-in Store (Internet Archive, PeerTube, Plex, Radio Browser, SomaFM, YouTube).
The Store also offers free TV and radio channel lists (M3U) to download into  $MP_STORE/listas/  (tutorial: ADDONS.md).

Source and releases: https://github.com/Rufidj/bennugd2-media-player
License: MIT (player). FFmpeg is LGPL (https://ffmpeg.org); SDL2, SDL2_mixer and the BennuGD2 runtime keep their own licenses.
EOF

(cd "$(dirname "$STAGE")" && tar czf "$OUT/$NAME-linux-x86_64.tar.gz" "$NAME-linux-x86_64")
echo "   $OUT/$NAME-linux-x86_64.tar.gz"

# ----------------------------------------------------------------------------------- Windows
echo "== montando el paquete de Windows =="
STAGE=/tmp/$NAME-windows-x86_64
rm -rf "$STAGE"
if [ -n "$WIN_DEPS" ]; then
  mkdir -p "$STAGE" && cp "$WIN_DEPS"/* "$STAGE"/
elif [ -f "$WINBASE" ]; then
  rm -rf /tmp/winbase && mkdir -p /tmp/winbase && (cd /tmp/winbase && unzip -q "$WINBASE")
  mkdir -p "$STAGE" && cp -r /tmp/winbase/$NAME-windows-x86_64/. "$STAGE/"
else
  echo "   no hay DLL de terceros: indica WIN_DEPS o WINBASE" >&2; exit 1
fi

# el runtime recien compilado (bgdi, bgdc y modulos) sustituye al del paquete base; solo lo que ya traia el paquete
for f in "$WIN"/*.dll "$WIN"/*.exe; do [ -f "$STAGE/$(basename "$f")" ] && cp "$f" "$STAGE/"; done

# el modulo de video con el reloj de video corregido (si hay paquete de FFmpeg para recompilarlo)
if [ -n "$FF" ] && [ -d "$ENGINE/modules/libmod_video" ]; then
  echo "   recompilando libmod_video.dll para Windows..."
  OBJS=/tmp/winmodvideo && rm -rf $OBJS && mkdir -p $OBJS
  INC="-I$ENGINE/vendor/SDL2-2.28.4/x86_64-w64-mingw32/include/SDL2 -I$ENGINE/core/include -I$ENGINE/core/bgdrtm -I$ENGINE/modules/libbggfx -I$ENGINE/modules/libsdlhandler -I$ENGINE/modules/libmod_video -I$ENGINE/vendor/sdl-gpu/include -I$ENGINE/vendor/SDL2_mixer-2.6.3/x86_64-w64-mingw32/include/SDL2 -I$FF/include"
  for f in libmod_video.c libmod_video_hwdec.c; do
    x86_64-w64-mingw32-gcc -O3 -DNDEBUG -DUSE_SDL2_GPU=1 -Dmod_video_EXPORTS $INC \
      -c "$ENGINE/modules/libmod_video/$f" -o "$OBJS/$(basename $f .c).o"
  done
  x86_64-w64-mingw32-gcc -O3 -DNDEBUG -shared -o "$STAGE/libmod_video.dll" -Wl,--out-implib,$OBJS/libmod_video.dll.a \
    -Wl,--major-image-version,0,--minor-image-version,0 $OBJS/*.o \
    "$ENGINE/vendor/SDL2-2.28.4/x86_64-w64-mingw32/lib/libSDL2.dll.a" \
    "$ENGINE/dependencies/x86_64-w64-mingw32/libSDL2_gpu.dll" \
    "$ENGINE/vendor/SDL2_mixer-2.6.3/x86_64-w64-mingw32/lib/libSDL2_mixer.dll.a" \
    "$WIN/libbggfx.dll.a" \
    "$FF/lib/libavformat.dll.a" "$FF/lib/libavcodec.dll.a" "$FF/lib/libswscale.dll.a" \
    "$FF/lib/libswresample.dll.a" "$FF/lib/libavutil.dll.a" \
    "$ENGINE/dependencies/x86_64-w64-mingw32/libSDL2_gpu.dll" -lpthread -lopengl32 \
    "$WIN/libsdlhandler.dll.a" "$ENGINE/vendor/SDL2-2.28.4/x86_64-w64-mingw32/lib/libSDL2.dll.a" \
    "$WIN/libbgdrtm.dll.a"
fi

cp /tmp/mediaplayer-release.dcb "$STAGE/mediaplayer.dcb"
cp LICENSE ADDONS.md ADDONS.es.md "$STAGE/"
cp lang/*.txt "$STAGE/lang/"
rm -rf "$STAGE/res" && mkdir -p "$STAGE/res/fonts"
cp res/*.png "$STAGE/res/" && cp res/fonts/* "$STAGE/res/fonts/"
cp lists/*.m3u "$STAGE/lists/"
for a in $ADDONS; do rm -rf "$STAGE/addons/$a"; mkdir -p "$STAGE/addons/$a" && cp -r "addons/$a"/* "$STAGE/addons/$a/"; done

cat > "$STAGE/README.txt" <<'EOF'
BennuGD2 Media Player - Windows x86-64
======================================

Run:   double-click mediaplayer.bat   (or:  bgdi.exe mediaplayer.dcb)
Start folder: MEDIA_DIR (default: your Videos folder).
Settings, lists and addon data: MP_STORE (default %APPDATA%\bennugd2-media-player).

Everything needed is in this folder (FFmpeg 8.1 LGPL build with Windows TLS for https, SDL2, SDL2_mixer, sdl-gpu).
Needs a graphics driver with OpenGL 3.x. Windows 10 or later.

Controls: arrows move, Enter = open, Esc/Backspace = back, M = options/mute, S = subtitles,
          Space = pause, N / P = -10 s / +10 s, A = next audio track.
Mouse: click = open / press, wheel = scroll or volume, double click = full screen, right click = back (pause while playing).
Keys while playing: Left / Right skip, Page Up / Down = 1 min, Up / Down volume, M mute, F11 full screen. A gamepad works too.
Addons: copy a folder with a main.addon file into  %MP_STORE%\addons\  (tutorial: ADDONS.md / ADDONS.es.md),
        or install them from the built-in Store (Internet Archive, PeerTube, Plex, Radio Browser, SomaFM, YouTube).
The Store also offers free TV and radio channel lists (M3U) to download into  %MP_STORE%\listas\  (tutorial: ADDONS.md).

NOTE: this Windows build was tested under Wine on Linux (UI, local video/audio, http and https streams),
not on a real Windows machine yet. Please report problems on the project page.

Source and releases: https://github.com/Rufidj/bennugd2-media-player
License: MIT (player). FFmpeg is LGPL (https://ffmpeg.org, build by BtbN); SDL2, SDL2_mixer and the BennuGD2 runtime keep their own licenses.
EOF

(cd "$(dirname "$STAGE")" && rm -f "$OUT/$NAME-windows-x86_64.zip" && zip -qr9 "$OUT/$NAME-windows-x86_64.zip" "$NAME-windows-x86_64")
echo "   $OUT/$NAME-windows-x86_64.zip"

echo "== listo =="
