# wolf-fc / DOS (DJGPP)

Wolf-FC running as a 32-bit protected-mode DOS program, **playable in DOSBox** —
without touching the FC source or the generated C. The whole port is this
directory, linked against the exact `build/linux/wolf-fc.c` the Linux build uses:

- `SDL2/SDL.h` — stub header declaring the SDL2 surface wolf-fc binds
  (struct layouts match `src/sdl2.fc`; this header *is* the ABI here).
- `sdl_dos.c` — the real DOS backend behind that API: VGA mode 13h with
  dynamic palette allocation (15-bit nearest-color cache), raw INT 9 keyboard
  with scancode→SDLK translation and typematic-repeat tagging, uclock()/PIT
  timing, vsync-paced Present that point-samples the game's supersampled ARGB
  buffer down to 320×200. Audio is deliberately absent for now (the game
  detects "no driver" and runs silent).
- `sdl_stub.c` — inert no-op backend (`STUB=1 ./build-dos.sh`) for headless
  `--test` work; this is the backend the byte-identical determinism proof used.
- `dos_shim.h` — the complete DJGPP 2.05 libc-gap list for wolf-fc + stdlib:
  `struct timespec`/`timespec_get`/`nanosleep`, `fmin`/`fmax`, `__errno_location`.
- `build-dos.sh` — build + run instructions, with the hard-won notes
  (`-std=gnu11` not `c11`; DJGPP's `int32_t` is `long int`; CWSDPMI required).

## Prerequisites

- **DJGPP cross toolchain** — prebuilt Linux binaries from
  <https://github.com/andrewwutw/build-djgpp> (tested with v3.4 / gcc 12.2.0),
  extracted to `~/djgpp` (or set `DJGPP=/path/to/it`).
- **CWSDPMI.EXE** — the DPMI host DJGPP executables need (plain DOSBox does
  not provide one; without it the EXE dies with "no DPMI"). Not committed to
  the repo — download `csdpmi7b.zip` from
  <http://www.delorie.com/pub/djgpp/current/v2misc/csdpmi7b.zip>
  (mirror: <https://www.mirrorservice.org/sites/ftp.delorie.com/pub/djgpp/current/v2misc/csdpmi7b.zip>)
  and unzip `bin/CWSDPMI.EXE` into this directory:

  ```sh
  curl -LO http://www.delorie.com/pub/djgpp/current/v2misc/csdpmi7b.zip
  unzip -j csdpmi7b.zip bin/CWSDPMI.EXE -d . && rm csdpmi7b.zip
  ```
- **dosbox** to run it.

## Quick start

```sh
./build-dos.sh                       # cross-compiles -> out/WOLF.EXE
cp CWSDPMI.EXE out/
mkdir -p out/data && cp ../data/*.WL6 out/data/
dosbox -conf dosbox.conf -c "mount c out" -c "set HOME=C:\\" -c c: -c wolf
```

Controls are the usual: arrows move/turn, Ctrl fires, Space opens doors,
Enter/Esc drive the menus, `s` saves a screenshot (lands in
`out/.WOL/SCREENSH/` — the `~/.wolf-fc/screenshots` path after DOS 8.3
truncation).

## Status / known gaps

- **Verified 2026-08-23 (DOSBox 0.74-3, cycles=max):** menus, episode select,
  in-game rendering with correct palette, movement, firing (ammo/HUD update),
  the engine's own PNG screenshots, and the headless `--test` determinism
  check (byte-identical to the Linux build from the same generated C).
- No audio yet — a Sound Blaster DMA backend can later drive the game's
  existing SDL-style audio callback from the SB IRQ.
- F11 fullscreen and window management are no-ops (there is no window).
- Config/screenshot paths land under `C:\.WOL` via `HOME=C:\`.
- Speed is untuned for real hardware: the game renders at its minimum
  supersample (640×400) and Present downsamples; a native 320×200 path
  (scale=1) would roughly quarter the raycasting work if real-386 targets
  ever matter. DOSBox at `cycles=max` is comfortable.
