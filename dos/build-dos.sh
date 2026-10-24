#!/bin/bash
# Cross-compile wolf-fc for 32-bit protected-mode DOS (DJGPP), and optionally
# run the headless determinism check in DOSBox.
#
# First run (2026-08-22) — the niche.md falsifiable experiment, stage 1:
# the exact build/linux/wolf-fc.c compiled by host gcc and by djgpp-gcc,
# both run `--test wait:35 ss:out.png`, produced BYTE-IDENTICAL PNGs
# (screenshot, raw framebuffer, and display variants), with identical
# game-state tEXt. Zero FC-source, fcc, or generated-C changes; the whole
# port surface is this directory: an inert SDL stub (--test never calls
# SDL), a ~30-line DJGPP libc shim, and CWSDPMI next to the EXE.
#
# Needs: a DJGPP cross toolchain (https://github.com/andrewwutw/build-djgpp),
# DJGPP=~/djgpp by default; CWSDPMI.EXE in the output dir to run; dosbox.
# The C comes from `make dos-c` (run here; needs fcc, as the Linux build
# does): build/dos/wolf-fc.c, the same program with 32-bit slice lengths
# (fcc --len-repr 32), DJGPP's native width. Against the Linux build's
# 64-bit lengths, measured 2026-10-24 in DOSBox (normal core, fixed
# cycles): render 7.5% faster at scale 1, the OPL2 emulator 4.5% faster,
# the EXE 33 KB smaller, --test screenshots byte-identical.
#
# Notes that took debugging to learn:
#  - compile with -std=gnu11, not -std=c11: DJGPP's strict-ANSI mode hides
#    the POSIX errno constants (ENOENT...) and fsync/fileno.
#  - DJGPP's int32_t is `long int`; the SDL stub types its prototypes with
#    int32_t (not int) so the FC extern decls match without warnings.
#  - dos_shim.h fills DJGPP 2.05's gaps: struct timespec + timespec_get +
#    nanosleep, C99 fmin/fmax, glibc's __errno_location.
#  - determinism check must run the reference with HOME pointing at an
#    empty dir, or your ~/.wolf-fc config (e.g. shadow depth) skews it.
set -e
cd "$(dirname "$0")"
DJGPP="${DJGPP:-$HOME/djgpp}"
GCC="$DJGPP/bin/i586-pc-msdosdjgpp-gcc"
GEN_C=../build/dos/wolf-fc.c
[ -x "$GCC" ] || { echo "DJGPP gcc not found at $GCC (set DJGPP=...)"; exit 1; }
make -C .. -s dos-c
# Backend selection: sdl_dos.c is the real DOS backend (VGA mode 13h, INT 9
# keyboard, PIT timing — interactive play works, audio silent for now).
# STUB=1 links the inert sdl_stub.c instead (headless --test only), which is
# what the byte-identical determinism check was first proven with.
BACKEND=sdl_dos.c
[ -n "$STUB" ] && BACKEND=sdl_stub.c
mkdir -p out
"$GCC" -std=gnu11 -O2 -I . -include dos_shim.h "$GEN_C" "$BACKEND" -o out/WOLF.EXE -lm
echo "built out/WOLF.EXE ($(stat -c%s out/WOLF.EXE) bytes, backend $BACKEND)"
echo "to set up: cd $PWD && cp CWSDPMI.EXE out/ && mkdir -p out/data && cp ../data/*.WL6 out/data/"
echo "to play:   cd $PWD && dosbox -conf dosbox.conf -c 'mount c out' -c 'set HOME=C:\\' -c c: -c wolf"
echo "headless:  cd $PWD && dosbox ... -c 'wolf --test wait:35 ss:dos.png' -c exit"
