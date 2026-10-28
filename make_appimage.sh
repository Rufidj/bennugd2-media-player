#!/bin/bash
# Genera el AppImage de Linux (x86-64) del reproductor. Necesita:
#   ENGINE=<BennuGD2 compilado para Linux>        por defecto $HOME/BennuGD2
#   FF=<FFmpeg LGPL "shared" de BtbN para Linux>  (ffmpeg-n8.1-latest-linux64-lgpl-shared-8.1)
#   APPIMAGETOOL=<appimagetool-x86_64.AppImage>
#   STAGE=<paquete de Linux ya montado por make_release.sh>   por defecto /tmp/bennugd2-media-player-linux-x86_64
#   OUT=<archivo .AppImage de salida>
# libmod_video se recompila aqui contra ese FFmpeg (LGPL), en lugar del FFmpeg del sistema (con piezas GPL).
HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${ENGINE:-$HOME/BennuGD2}"
FF="${FF:?indica FF}"; APPIMAGETOOL="${APPIMAGETOOL:?indica APPIMAGETOOL}"
STAGE="${STAGE:-/tmp/bennugd2-media-player-linux-x86_64}"
OUT="${OUT:-$HOME/Escritorio/BennuGD2-MediaPlayer-x86_64.AppImage}"
LIN="$ENGINE/build/linux-gnu/bin"
set -e
AD=/tmp/mp-AppDir; rm -rf "$AD" /tmp/mp-modvideo
mkdir -p "$AD/usr/bin" "$AD/usr/lib" "$AD/usr/share/mediaplayer" /tmp/mp-modvideo

# --- libmod_video contra el FFmpeg LGPL
INC="-I/usr/include/SDL2 -I$ENGINE/core/include -I$ENGINE/core/bgdrtm -I$ENGINE/modules/libbggfx -I$ENGINE/modules/libsdlhandler -I$ENGINE/modules/libmod_video -I$ENGINE/vendor/sdl-gpu/include -I$FF/include"
for f in dlna libmod_video libmod_video_hwdec torrent upload; do
  cc -O3 -DNDEBUG -fPIC -DUSE_SDL2_GPU=1 -Dmod_video_EXPORTS $INC -c "$ENGINE/modules/libmod_video/$f.c" -o /tmp/mp-modvideo/$f.o
done
cc -fPIC -O3 -shared -Wl,-soname,libmod_video.so -o /tmp/mp-modvideo/libmod_video.so /tmp/mp-modvideo/*.o \
   -Wl,-rpath,'$ORIGIN' /usr/lib/x86_64-linux-gnu/libSDL2.so "$ENGINE/dependencies/linux-gnu/libSDL2_gpu.so" /usr/lib/x86_64-linux-gnu/libSDL2_mixer.so \
   "$LIN/libbggfx.so" -L"$FF/lib" -lavformat -lavcodec -lswscale -lswresample -lavutil \
   /usr/lib/x86_64-linux-gnu/libtheoradec.so /usr/lib/x86_64-linux-gnu/libvorbis.so /usr/lib/x86_64-linux-gnu/libogg.so \
   "$LIN/libsdlhandler.so" "$LIN/libbgdrtm.so" -lz /usr/lib/x86_64-linux-gnu/libfreetype.so

# --- programa y datos
cp "$STAGE/bgdi" "$AD/usr/bin/"
cp "$STAGE"/lib/*.so "$AD/usr/lib/"
cp /tmp/mp-modvideo/libmod_video.so "$AD/usr/lib/"
cp -a "$FF"/lib/libav{codec,format,util}.so.* "$FF"/lib/libsw{resample,scale}.so.* "$AD/usr/lib/"
rm -f "$AD"/usr/lib/lib{avcodec,avformat,avutil,swresample,swscale}.so   # solo las versiones con numero
for x in mediaplayer.dcb LICENSE ADDONS.md ADDONS.es.md lang res addons lists; do cp -r "$STAGE/$x" "$AD/usr/share/mediaplayer/"; done
cp "$FF/LICENSE.txt" "$AD/usr/share/mediaplayer/FFMPEG-LICENSE.txt" 2>/dev/null || true

# --- librerias de terceros (todo menos lo basico del sistema, que lleva cada distribucion)
EXCL='^(linux-vdso|ld-linux|libc\.so|libm\.so|libdl|libpthread|librt|libutil|libresolv|libnsl|libGL\.|libGLX|libGLdispatch|libOpenGL|libEGL|libdrm|libgbm|libX11|libxcb|libXau|libXdmcp|libXext|libXrender|libXfixes|libXi\.|libXcursor|libXrandr|libXss|libwayland|libstdc\+\+|libgcc_s|libmvec|libasound|libpulse|libjack|libpipewire|libsystemd|libdbus|libcap|libapparmor|libselinux|libudev|libffi|libgmp|libnettle|libhogweed|libgnutls|libp11|libtasn1|libidn2|libunistring|libkrb5|libk5crypto|libgssapi|libkeyutils|libcom_err|libOpenCL)'
for f in "$AD"/usr/bin/bgdi "$AD"/usr/lib/*.so "$AD"/usr/lib/*.so.*; do
  LD_LIBRARY_PATH="$AD/usr/lib:$LIN" ldd "$f" 2>/dev/null | awk '/=> \//{print $1, $3}'
done | sort -u | while read n p; do
  echo "$n" | grep -Eq "$EXCL" && continue
  case "$p" in "$AD"/*|"$LIN"/*|"$ENGINE"/*) continue;; esac
  [ -e "$AD/usr/lib/$n" ] || cp -L "$p" "$AD/usr/lib/$n"
done

# --- lanzador, escritorio e icono
cat > "$AD/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:$LD_LIBRARY_PATH"
export MP_STORE="${MP_STORE:-$HOME/.local/share/bennugd2-media-player}"
export MEDIA_DIR="${MEDIA_DIR:-$HOME/Videos}"
mkdir -p "$MP_STORE"
cd "$HERE/usr/share/mediaplayer" && exec "$HERE/usr/bin/bgdi" mediaplayer.dcb "$@"
EOF
chmod +x "$AD/AppRun"
cat > "$AD/mediaplayer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=BennuGD2 Media Player
Comment=Media player for gamepad and TV
Exec=AppRun %U
Icon=mediaplayer
Categories=AudioVideo;Video;Player;
Terminal=false
EOF
python3 -c "
from PIL import Image
Image.open('$HERE/title/sce_sys/icon0.png').convert('RGBA').resize((256, 256), Image.LANCZOS).save('$AD/mediaplayer.png')"
cp "$AD/mediaplayer.png" "$AD/.DirIcon"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$AD" "$OUT"
echo "### $OUT ($(du -h "$OUT" | cut -f1)) ###"
