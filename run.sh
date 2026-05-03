#!/bin/bash
# Thin convenience wrapper around the Makefile. `make` builds the binary
# (incrementally, via fcc + cc); we then exec it with whatever args the
# caller passed. The binary path is per-OS (build/linux/, build/windows/,
# ...), so we ask Make for it instead of hard-coding it — that keeps a
# shared source tree across e.g. WSL + MSYS2 from cross-execing each
# other's binaries. See README.md and `make help` for the full story.
set -e
cd "$(dirname "$0")"
make -s
exec "$(make -s print-bin)" "$@"
