#!/bin/bash
# Thin convenience wrapper around the Makefile. `make` builds the binary
# (incrementally, via fcc + cc); we then exec it with whatever args the
# caller passed. See README.md and `make help` for the full build story.
set -e
cd "$(dirname "$0")"
make -s
exec ./build/wolf-fc "$@"
