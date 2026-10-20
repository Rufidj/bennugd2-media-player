#!/usr/bin/env bash
# Prepara la app de Android: copia las librerias del motor (ya compiladas para
# Android) y el .dcb del reproductor a donde el Gradle las espera.
#
#   1) compilar el motor para Android (en el checkout de BennuGD2):
#          ANDROID_NDK=$HOME/Android/Sdk/ndk/27.0.12077973 ./build.sh aarch64-linux-android
#      (las dependencias de terceros: FreeType, sdl-gpu y FFmpeg se compilan con
#       build-android-deps.sh y quedan en vendor/android/<target>/<abi>)
#   2) en este repositorio:
#          ./android/preparar.sh [aarch64-linux-android] [arm64-v8a]
#   3) montar el APK:
#          cd android && ./gradlew assembleDebug
set -e
ENGINE="${BENNUGD2:-$HOME/BennuGD2}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-aarch64-linux-android}"
ABI="${2:-arm64-v8a}"
PREFIX="$ENGINE/vendor/android/$TARGET/$ABI"
BINS="$ENGINE/build/$TARGET/bin"

echo "motor:   $BINS"
echo "deps:    $PREFIX"

mkdir -p "$HERE/app/libs/$ABI" "$HERE/app/src/main/assets"
cp "$BINS"/*.so "$HERE/app/libs/$ABI/"
for l in libSDL2.so libSDL2_image.so libSDL2_mixer.so libfreetype.so \
         libavformat.so libavcodec.so libavutil.so libswscale.so libswresample.so; do
    [ -f "$PREFIX/lib/$l" ] && cp "$PREFIX/lib/$l" "$HERE/app/libs/$ABI/" || echo "   (falta $l)"
done
cp "$HERE/../mediaplayer.dcb" "$HERE/app/src/main/assets/game.dcb"
echo "listo: $HERE/app/libs/$ABI"
ls -la "$HERE/app/libs/$ABI" | head -5
