#!/bin/bash
# Cross-builds the BennuGD2 runtime (bgdi.exe + modules, incl. libmod_video) for Windows x86-64 with mingw-w64.
# Needs: ENGINE=<BennuGD2 checkout with the engine/*.patch files applied>, FT_PREFIX=<static FreeType for mingw>,
#        FFMPEG_DIR=<BtbN ffmpeg-n8.1-latest-win64-lgpl-shared-8.1 (include/ lib/*.dll.a)>.
# The SDL2/SDL2_mixer/sdl-gpu mingw files come from the engine's vendor/ and dependencies/ folders.
set -e
ENGINE=${ENGINE:-$HOME/BennuGD2}
cd $ENGINE
FF=$FFMPEG_DIR
export TARGET=x86_64-w64-mingw32 COMPILER=-MINGW SDL2GPUDIR="../../vendor/sdl-gpu/build/x86_64-w64-mingw32" LIBRARY_BUILD_TYPE=SHARED USE_SDL2_GPU=1
mkdir -p build/$TARGET && cd build/$TARGET
cmake ../.. -DTARGET=$TARGET -DINCLUDE_DIRECTORIES="" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=cmake/Toolchains/Toolchain-cross-mingw32-linux.cmake -DSDL2_INCLUDE_DIR=$ENGINE/vendor/SDL2-2.28.4/x86_64-w64-mingw32/include/SDL2 -DSDL2_LIBRARY=$ENGINE/vendor/SDL2-2.28.4/x86_64-w64-mingw32/lib/libSDL2.dll.a -DSDLMIXER_INCLUDE_DIR=$ENGINE/vendor/SDL2_mixer-2.6.3/x86_64-w64-mingw32/include/SDL2 -DSDLMIXER_LIBRARY=$ENGINE/vendor/SDL2_mixer-2.6.3/x86_64-w64-mingw32/lib/libSDL2_mixer.dll.a \
  -DEXTRA_CFLAGS=" -DUSE_SDL2_GPU=1" -DUSE_SDL2_GPU=1 -DLIBRARY_BUILD_TYPE=SHARED -DBUILD_TARGET=all -DSTDLIBSFLAGS="" "-DSKIP_MODULES=libmod_3d;libmod_wld;libmod_ads;libmod_iap" \
  -DFREETYPE_LIBRARY=$FT_PREFIX/lib/libfreetype.a -DFREETYPE_INCLUDE_DIR_ft2build=$FT_PREFIX/include/freetype2 -DFREETYPE_INCLUDE_DIR_freetype2=$FT_PREFIX/include/freetype2 \
  -DSDL_GPU_LIBRARY=$ENGINE/dependencies/x86_64-w64-mingw32/libSDL2_gpu.dll -DSDL_GPU_INCLUDE_DIR=$ENGINE/vendor/sdl-gpu/include \
  "-DFFMPEG_INCLUDE_DIRS=$FF/include" "-DFFMPEG_LIBRARIES=$FF/lib/libavformat.dll.a;$FF/lib/libavcodec.dll.a;$FF/lib/libswscale.dll.a;$FF/lib/libswresample.dll.a;$FF/lib/libavutil.dll.a"
make -j8 -k 2>&1 | tail -60
