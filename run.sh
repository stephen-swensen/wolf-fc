#!/bin/bash
# Build and run Wolf-FC.
# Requires:
#   - fcc (the FC compiler) on PATH. Install from ../fc-lang/ with
#     `make && sudo make install` (or `make install PREFIX=$HOME/.local`).
#     See README.md for the full install story.
#   - SDL2 dev package (libsdl2-dev on Debian/Ubuntu, brew install sdl2 on
#     macOS, mingw-w64-ucrt-x86_64-SDL2 on MSYS2).
set -e
cd "$(dirname "$0")"
WOLF_DIR="$(pwd)"

if ! command -v fcc >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: 'fcc' not found on PATH.

Install the FC compiler before running wolf-fc:
  cd ../fc-lang
  make
  sudo make install                        # default PREFIX=/usr/local
  # ... or for a user-local install (no sudo):
  # make install PREFIX=$HOME/.local       # then put $HOME/.local/bin on PATH

See ../fc-lang/README.md (or wolf-fc's README.md "Installing the FC
compiler" section) for full instructions.
EOF
    exit 1
fi

# Until fcc grows automatic stdlib resolution, we still need to pass the
# stdlib .fc files explicitly. Resolve them from fcc's install prefix:
# `make install` lays out $PREFIX/bin/fcc and $PREFIX/share/fcc/stdlib/
# in lock-step, so following fcc's location on PATH gives us the matching
# stdlib without hardcoding /usr/local. Override with FCC_STDLIB if the
# layout is non-standard.
if [[ -n "$FCC_STDLIB" ]]; then
    STDLIB_DIR="$FCC_STDLIB"
else
    FCC_BIN_PATH="$(command -v fcc)"
    FCC_PREFIX="$(dirname "$(dirname "$FCC_BIN_PATH")")"
    STDLIB_DIR="$FCC_PREFIX/share/fcc/stdlib"
fi
if [[ ! -d "$STDLIB_DIR" ]]; then
    echo "error: FC stdlib not found at '$STDLIB_DIR'." >&2
    echo "Reinstall fcc ('make install' from ../fc-lang/), or set FCC_STDLIB" >&2
    echo "to the directory containing io.fc, text.fc, sys.fc, math.fc, random.fc." >&2
    exit 1
fi

SRCS="$WOLF_DIR/sdl2.fc $WOLF_DIR/opl2.fc $WOLF_DIR/sound.fc \
      $WOLF_DIR/png.fc $WOLF_DIR/data.fc \
      $WOLF_DIR/sfx.fc $WOLF_DIR/ui.fc $WOLF_DIR/save.fc \
      $WOLF_DIR/combat.fc $WOLF_DIR/level.fc $WOLF_DIR/cutscenes.fc \
      $WOLF_DIR/menu.fc $WOLF_DIR/player.fc $WOLF_DIR/render.fc \
      $WOLF_DIR/main.fc \
      $STDLIB_DIR/io.fc $STDLIB_DIR/text.fc $STDLIB_DIR/sys.fc \
      $STDLIB_DIR/math.fc $STDLIB_DIR/random.fc"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        OUTDIR="${TEMP:-/tmp}"
        fcc $SRCS -o "$OUTDIR/wolf-fc.c"
        gcc -std=c11 -Wall -Werror -O2 -Dmain=SDL_main \
            -o "$OUTDIR/wolf-fc.exe" "$OUTDIR/wolf-fc.c" \
            -lmingw32 -lSDL2main -lSDL2 -lm
        echo "Running Wolf-FC..."
        "$OUTDIR/wolf-fc.exe" "$@"
        echo "[exit: $?]"
        ;;
    *)
        fcc $SRCS -o /tmp/wolf-fc.c
        cc -std=c11 -Wall -Werror -O2 -o /tmp/wolf-fc-bin /tmp/wolf-fc.c -lSDL2 -lm
        echo "Running Wolf-FC..."
        /tmp/wolf-fc-bin "$@"
        echo "[exit: $?]"
        ;;
esac
