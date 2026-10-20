/*
 *  Punto de entrada nativo de la app de Android.
 *  El motor (BennuGD2) entra por bgdi_main(), que es su main() renombrado al
 *  compilarlo para Android (ver core/bgdi/main.c), para que no choque con el
 *  main() de esta libreria (el SDL2 lo renombra a SDL_main).
 */
#include "SDL.h"
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

extern int bgdi_main( int argc, char * argv[] );

/* El motor busca el .dcb en el directorio actual: en Android el proceso
   arranca en "/" y ahi no se puede escribir, asi que el Java lo copia a la
   carpeta de la app y nos pasa la ruta con bgd_setup(). */
static char g_dcb[ 1024 ] = "";

JNIEXPORT void JNICALL
Java_org_libsdl_app_SDLActivity_bgd_setup( JNIEnv * env, jclass cls, jstring path )
{
    const char * p = ( *env )->GetStringUTFChars( env, path, 0 );
    snprintf( g_dcb, sizeof( g_dcb ), "%s", p ? p : "" );
    if ( p ) ( *env )->ReleaseStringUTFChars( env, path, p );
}

int SDL_main( int argc, char * argv[] )
{
    char * args[2];

    if ( g_dcb[0] )
    {
        /* se corta el directorio del .dcb y se trabaja ahi */
        char * slash = strrchr( g_dcb, '/' );
        if ( slash ) { *slash = 0; chdir( g_dcb ); *slash = '/'; }
        args[1] = g_dcb;
    }
    else
        args[1] = (char *) "game.dcb";

    args[0] = argv[0];
    return bgdi_main( 2, args );
}
