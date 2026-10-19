#!/bin/bash
# Thin convenience wrapper around the Makefile. `make` builds the binary
# (incrementally, via fcc + cc); we then exec it with whatever args the
# caller passed. The binary path is per-OS (build/linux/, build/windows/,
# ...), so we ask Make for it instead of hard-coding it — that keeps a
# shared source tree across e.g. WSL + MSYS2 from cross-execing each
# other's binaries. See README.md and `make help` for the full story.
#
# `./run.sh --native [args]` builds and runs the fcc --native binary instead
# (NATIVE=1 in the Makefile); the flag is ours, not passed to the game.
set -e
cd "$(dirname "$0")"
if [ "${1:-}" = "--native" ]; then
    shift
    export NATIVE=1
fi
make -s
exec "$(make -s print-bin)" "$@"
