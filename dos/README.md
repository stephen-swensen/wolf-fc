# wolf-fc / DOS (DJGPP)

Wolf-FC running as a 32-bit protected-mode DOS program, **playable in DOSBox** —
without touching the FC source or the generated C. The whole port is this
directory, linked against the exact `build/linux/wolf-fc.c` the Linux build uses:

- `SDL2/SDL.h` — stub header declaring the SDL2 surface wolf-fc binds
  (struct layouts match `src/sdl2.fc`; this header *is* the ABI here).
- `sdl_dos.c` — the real DOS backend behind that API: VGA mode 13h with
  a frame-earned dynamic palette (Present histograms the frame through a
  15-bit cache; when too many pixels lack an exact DAC slot, the palette
  is rebuilt from the frame's 256 most popular colors, with the DAC
  reprogram landing in that frame's vertical retrace — hysteresis keeps
  stable scenes from ever rebuilding), raw INT 9 keyboard
  with scancode→SDLK translation and typematic-repeat tagging, uclock()/PIT
  timing, vsync-paced Present. The 320×200 drawable makes the game auto-pick
  supersample scale 1 (native-resolution render — supersampling would be
  discarded by the point-sampling Present anyway), so Present degenerates to
  a straight quantize-copy into VGA memory. Audio is Sound Blaster 16:
  16-bit signed stereo auto-init DMA at 8000 Hz, the SB IRQ driving the
  game's SDL-style mixer callback per half-buffer (BLASTER env parsed;
  no SB detected → the game runs silent as before). 8000 Hz because the
  game synthesizes its music through an OPL2 *emulator* written in FC,
  which costs ~18 µs of emulated CPU per sample under DOSBox — 44.1 kHz
  would eat the whole machine, 8 kHz keeps the mixer near 15%.
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

DOSBox starts fullscreen (`dosbox.conf`: `fullscreen=true`,
`fullresolution=desktop`, `output=opengl`, `aspect=true`) — the program just
writes 320×200 VGA memory and DOSBox owns all scaling, including the 1.2×
vertical stretch a real 4:3 CRT would apply to mode 13h's non-square pixels
(`aspect=true`; without it the picture is subtly squashed). Alt+Enter toggles
back to a window.

Controls are the usual: arrows move/turn, Ctrl fires, Space opens doors,
Enter/Esc drive the menus, `s` saves a screenshot (lands in
`out/.WOL/SCREENSH/` — the `~/.wolf-fc/screenshots` path after DOS 8.3
truncation).

## Status / known gaps

- **Verified 2026-08-23 (DOSBox 0.74-3, cycles=max):** menus, episode select,
  in-game rendering with correct palette, movement, firing (ammo/HUD update),
  the engine's own PNG screenshots, and the headless `--test` determinism
  check (byte-identical to the Linux build from the same generated C).
- Audio plays (music + digitized SFX) through the SB16 DMA backend at
  8000 Hz. The fidelity ceiling is the FC OPL2 emulator's per-sample cost
  under CPU emulation; routing the music's register stream to the Sound
  Blaster's *real* OPL2 at port 388h instead (DOSBox synthesizes it for
  free) would give authentic AdLib quality and a higher digi rate, at the
  cost of a small game-side hook.
- F11 fullscreen and window management are no-ops (there is no window).
- Config/screenshot paths land under `C:\.WOL` via `HOME=C:\`.
- The game renders natively at 320×200 (supersample scale 1, auto-picked
  from the drawable — verified via the engine's own in-DOS screenshot
  coming out 320×200). That's ~¼ the raycasting work of the old scale-2
  minimum, whose extra pixels the point-sampling Present threw away anyway.
  DOSBox at `cycles=max` is comfortable; real-386 viability is untested.
