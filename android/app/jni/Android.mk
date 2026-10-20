LOCAL_PATH := $(call my-dir)

# Las librerías del motor y de terceros están en app/libs/<abi>/ (las empaqueta el Gradle).
LIBS_DIR := $(LOCAL_PATH)/../libs/$(APP_ABI)
LIBS_DIR_TARGET := $(LOCAL_PATH)/../libs/$(TARGET_ABI)

# --------------------------------------------------------------- el motor (BennuGD2)
# El motor se compila aparte (build.sh aarch64-linux-android) y aquí solo se
# empaqueta: libbgdi.so es el intérprete y los módulos van en libs/<abi>/.
include $(CLEAR_VARS)
LOCAL_MODULE := bgdi
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libbgdi.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := bgdmod
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libbgdrtm.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := bggfx
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libbggfx.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := bginput
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libbginput.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := bgsound
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libbgsound.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := bgload
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libbgload.so
include $(PREBUILT_SHARED_LIBRARY)

# --------------------------------------------------------------- módulos
include $(CLEAR_VARS)
LOCAL_MODULE := mod_gfx
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libmod_gfx.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := mod_input
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libmod_input.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := mod_misc
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libmod_misc.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := mod_net
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libmod_net.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := mod_sound
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libmod_sound.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := mod_video
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libmod_video.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := mod_debug
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libmod_debug.so
include $(PREBUILT_SHARED_LIBRARY)

# --------------------------------------------------------------- SDL2 y amigos
include $(CLEAR_VARS)
LOCAL_MODULE := SDL2
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libSDL2.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := SDL2_image
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libSDL2_image.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := SDL2_mixer
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libSDL2_mixer.so
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := freetype
LOCAL_SRC_FILES := $(LOCAL_PATH)/../libs/$(APP_ABI)/libfreetype.so
include $(PREBUILT_SHARED_LIBRARY)

# --------------------------------------------------------------- la app
# La libreria nativa de la app: el pegamento JNI del propio SDL2
# (src/core/android/SDL_android.c) mas nuestro punto de entrada, que llama al
# motor (bgdi_main). La ruta del SDL2 se puede cambiar con la variable SDL2_SRC.
SDL2_SRC ?= /home/ruben/BennuGD2/vendor/android/SDL2-2.32.6

include $(CLEAR_VARS)
LOCAL_MODULE := SDL2main
# el pegamento JNI ya va dentro del propio libSDL2.so (el SDL2 lo compila para Android),
# aqui solo el punto de entrada de la app
LOCAL_SRC_FILES := src/Android_main.c
LOCAL_C_INCLUDES := $(SDL2_SRC)/include \
                   $(SDL2_SRC)/src/core/android \
                   $(SDL2_SRC)/src
LOCAL_SHARED_LIBRARIES := bgdi bgdmod bggfx bginput bgsound bgload \
                         mod_gfx mod_input mod_misc mod_net mod_sound mod_video mod_debug \
                         SDL2 SDL2_image SDL2_mixer freetype
LOCAL_LDLIBS := -L$(LIBS_DIR_TARGET) -llog
include $(BUILD_SHARED_LIBRARY)
