#!/usr/bin/env bash
# Prepara la app de Android: copia las librerias del motor (ya compiladas para
# Android) y el .dcb del reproductor a donde el Gradle las espera.
#
#   1) compilar el motor para Android (en el checkout de BennuGD2):
#          ANDROID_NDK=$HOME/Android/Sdk/ndk/27.0.12077973 ./build.sh aarch64-linux-android
#          ANDROID_NDK=$HOME/Android/Sdk/ndk/27.0.12077973 ./build.sh x86_64-linux-android
#      (las dependencias de terceros: FreeType, sdl-gpu y FFmpeg se compilan con
#       build-android-deps.sh y quedan en vendor/android/<target>/<abi>)
#   2) en este repositorio:
#          ./android/preparar.sh                (todas las ABIs de abajo)
#          ./android/preparar.sh aarch64-linux-android:arm64-v8a
#   3) montar el APK:
#          cd android && ./gradlew assembleDebug
set -e
ENGINE="${BENNUGD2:-$HOME/BennuGD2}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# pares <target del motor>:<abi de Android>
ALL="aarch64-linux-android:arm64-v8a armv7a-linux-androideabi:armeabi-v7a x86_64-linux-android:x86_64"
PAIRS="${*:-$ALL}"

DEPS="libSDL2.so libSDL2_image.so libSDL2_mixer.so libfreetype.so \
      libavformat.so libavcodec.so libavutil.so libswscale.so libswresample.so \
      libmbedtls.so libmbedx509.so libmbedcrypto.so"
mkdir -p "$HERE/app/src/main/assets"
cp "$HERE/../mediaplayer.dcb" "$HERE/app/src/main/assets/game.dcb"

# los recursos (res/) y los idiomas (lang/) los carga el motor por ruta relativa
# al .dcb: van tambien en los assets y la app los copia a su carpeta
rm -rf "$HERE/app/src/main/assets/res" "$HERE/app/src/main/assets/lang" "$HERE/app/src/main/assets/addons"
cp -r "$HERE/../res" "$HERE/app/src/main/assets/res"
cp -r "$HERE/../lang" "$HERE/app/src/main/assets/lang"
# los addons que trae el reproductor (el motor los busca en ./addons)
cp -r "$HERE/../addons" "$HERE/app/src/main/assets/addons"

for pair in $PAIRS; do
    TARGET="${pair%%:*}"
    ABI="${pair##*:}"
    PREFIX="$ENGINE/vendor/android/$TARGET/$ABI"
    BINS="$ENGINE/build/$TARGET/bin"

    echo "=== $TARGET ($ABI) ==="
    echo "motor:   $BINS"
    echo "deps:    $PREFIX"

    if [ ! -d "$BINS" ]; then
        echo "   !! falta el motor: compilalo con ./build.sh $TARGET" >&2
        continue
    fi

    mkdir -p "$HERE/app/libs/$ABI"
    cp "$BINS"/*.so "$HERE/app/libs/$ABI/"
    for l in $DEPS; do
        if [ -f "$PREFIX/lib/$l" ]; then
            cp "$PREFIX/lib/$l" "$HERE/app/libs/$ABI/"
        else
            echo "   (falta $l)"
        fi
    done
    # el motor grafico (libbggfx.so) usa sdl-gpu, que tambien va en el APK
    GPU="$ENGINE/vendor/sdl-gpu/build/$TARGET/SDL_gpu/lib/libSDL2_gpu.so"
    if [ -f "$GPU" ]; then
        cp "$GPU" "$HERE/app/libs/$ABI/"
    else
        echo "   (falta libSDL2_gpu.so: compilalo con vendor/build-sdl-gpu.sh $TARGET)"
    fi
    echo "listo: $HERE/app/libs/$ABI ($(ls "$HERE/app/libs/$ABI" | wc -l) librerias)"
done
