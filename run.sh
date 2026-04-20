#!/bin/bash
# Build and run Wolf-FC. Requires SDL2 dev package (e.g. libsdl2-dev on Debian/Ubuntu).
# Expects ../fc-lang to contain the FC compiler source.
set -e
cd "$(dirname "$0")"
WOLF_DIR="$(pwd)"
FC_DIR="$WOLF_DIR/../fc-lang"

# Build a wolf-fc-local copy of the FC compiler with -O2 (~40% faster
# compile step than the default -O0 debug build in fc-lang/fc). Kept in
# .fc-cache/ so it doesn't interfere with fc-lang's own development build
# (which stays at whatever OPT its owner prefers). Only rebuilds when the
# FC source changes.
# Key the cache by uname so WSL (Linux ELF) and MSYS2/MinGW (Windows PE)
# builds off the same source tree don't stomp each other.
FC_CACHE="$WOLF_DIR/.fc-cache/$(uname -s)"
FC_BIN="$FC_CACHE/fc"
mkdir -p "$FC_CACHE"
if [[ ! -x "$FC_BIN" ]] || \
   [[ -n "$(find "$FC_DIR/src" \( -name '*.c' -o -name '*.h' \) -newer "$FC_BIN" 2>/dev/null | head -1)" ]]; then
    echo "Building FC compiler at -O2 -flto=auto -> $FC_BIN"
    cc -std=c11 -O2 -flto=auto -Wall -Wextra -Wpedantic -o "$FC_BIN" "$FC_DIR"/src/*.c
fi

SRCS="$WOLF_DIR/sdl2.fc $WOLF_DIR/opl2.fc $WOLF_DIR/sound.fc \
      $WOLF_DIR/png.fc $WOLF_DIR/data.fc $WOLF_DIR/main.fc \
      $FC_DIR/stdlib/io.fc $FC_DIR/stdlib/text.fc $FC_DIR/stdlib/sys.fc \
      $FC_DIR/stdlib/math.fc $FC_DIR/stdlib/random.fc"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        OUTDIR="${TEMP:-/tmp}"
        "$FC_BIN" $SRCS -o "$OUTDIR/wolf-fc.c"
        gcc -std=c11 -Wall -Werror -O2 -Dmain=SDL_main \
            -o "$OUTDIR/wolf-fc.exe" "$OUTDIR/wolf-fc.c" \
            -lmingw32 -lSDL2main -lSDL2 -lm
        echo "Running Wolf-FC..."
        "$OUTDIR/wolf-fc.exe" "$@"
        echo "[exit: $?]"
        ;;
    *)
        "$FC_BIN" $SRCS -o /tmp/wolf-fc.c
        cc -std=c11 -Wall -Werror -O2 -o /tmp/wolf-fc-bin /tmp/wolf-fc.c -lSDL2 -lm
        echo "Running Wolf-FC..."
        /tmp/wolf-fc-bin "$@"
        echo "[exit: $?]"
        ;;
esac
