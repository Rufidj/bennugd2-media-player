#!/bin/bash
# Compila y ejecuta el reproductor en PC / Builds and runs the player on the PC.
#   BGD=/path/to/BennuGD2/build/linux-gnu/bin ./run.sh [file-or-url]
B=${BGD:-$HOME/BennuGD2/build/linux-gnu/bin}
export LD_LIBRARY_PATH="$B:$LD_LIBRARY_PATH"
cd "$(dirname "$0")" && "$B/bgdc" mediaplayer.prg | grep -i "error\|warn" ; "$B/bgdi" mediaplayer.dcb "$@"
