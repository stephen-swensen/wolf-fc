#!/bin/bash
# Build and run Wolf-FC. Requires SDL2 dev package (e.g. libsdl2-dev on Debian/Ubuntu).
# Expects ../fc-lang to contain the FC compiler source.
set -e
cd "$(dirname "$0")"
WOLF_DIR="$(pwd)"
FC_DIR="$WOLF_DIR/../fc-lang"

# Build FC compiler if needed
make -s -C "$FC_DIR" fc

SRCS="$FC_DIR/demos/shared/sdl2.fc $FC_DIR/demos/shared/opl2.fc \
      $WOLF_DIR/png.fc $WOLF_DIR/data.fc $WOLF_DIR/main.fc \
      $FC_DIR/stdlib/io.fc $FC_DIR/stdlib/text.fc $FC_DIR/stdlib/sys.fc \
      $FC_DIR/stdlib/math.fc $FC_DIR/stdlib/random.fc"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        OUTDIR="${TEMP:-/tmp}"
        "$FC_DIR/fc" $SRCS -o "$OUTDIR/wolf-fc.c"
        gcc -std=c11 -Wall -Werror -Dmain=SDL_main \
            -o "$OUTDIR/wolf-fc.exe" "$OUTDIR/wolf-fc.c" \
            -lmingw32 -lSDL2main -lSDL2 -lm
        echo "Running Wolf-FC..."
        "$OUTDIR/wolf-fc.exe"
        echo "[exit: $?]"
        ;;
    *)
        "$FC_DIR/fc" $SRCS -o /tmp/wolf-fc.c
        cc -std=c11 -Wall -Werror -o /tmp/wolf-fc-bin /tmp/wolf-fc.c -lSDL2 -lm
        echo "Running Wolf-FC..."
        /tmp/wolf-fc-bin
        echo "[exit: $?]"
        ;;
esac
