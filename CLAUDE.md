# CLAUDE.md

## Project Overview

Wolf-FC is a Wolfenstein 3D clone written in FC, intended as a demo of the FC language. It reads original `.WL6` data files (wall textures, maps, sprites, audio) and implements a raycasting engine with SDL2 rendering. See `TODO.md` for what's implemented and what remains.

## Sibling Repositories

- **`../fc-lang/`** — The FC compiler, stdlib, and shared SDL2/OPL2 bindings. **Read `../fc-lang/CLAUDE.md` for the full FC language reference** (syntax, type system, module system, C interop, naming conventions, etc.). Key paths:
  - `../fc-lang/fc` — compiler binary
  - `../fc-lang/stdlib/` — standard library (io, math, sys, text, random, data)
  - `../fc-lang/demos/shared/sdl2.fc` — SDL2 bindings (namespace `sdl2::`)
  - `../fc-lang/demos/shared/opl2.fc` — OPL2 FM synth emulator (namespace `opl2::`)
  - `../fc-lang/spec/examples.fc` — runnable FC quick reference
- **`../wolf4sdl/`** — C reference implementation of Wolf3D (SDL2 port). Consult for data format details and rendering correctness, but **don't copy code** (GPL). Key files listed in TODO.md.

## Build & Run

- **`./run.sh`** — Compile FC → C → binary, then run. Requires `../fc-lang/` and `libsdl2-dev`.
- **`./run.sh` then pass `--screenshot`** — Renders one frame to `screenshot.ppm` and exits (for debugging without display).
- Data files must be in `data/*.WL6` (not committed — users supply their own from a legitimate Wolf3D copy).

## Source Files

- **`data.fc`** (~307 lines) — `namespace wolf_data::` — Data loading subsystem:
  - `module bytes` — Little-endian uint16/uint32/int32 readers
  - `module palette` — `init()` returns heap-allocated 256-entry ARGB palette from hardcoded 6-bit VGA data
  - `module vswap` — Loads VSWAP.WL6, provides `wall_pixel()` accessor
  - `module maps` — Loads MAPHEAD+GAMEMAPS with Carmack + RLEW decompression
  - `module audio` — Loads AUDIOHED+AUDIOT, provides chunk offset/length accessors

- **`main.fc`** (~865 lines) — Game engine, all in one file (no namespace):
  - Constants (game_w=320, game_h=200, screen_w=640, screen_h=400, actual_h=480, view_h=160)
  - `struct game` — player state (position, direction, camera plane, input, health/ammo/score)
  - `struct sprite_obj` — static objects (position, VSWAP page, distance)
  - Tilemap builder + sprite spawner from level data
  - DDA raycaster (`render_walls`) writing to 320x200 `fb` framebuffer
  - Sprite renderer (`render_sprites`) with compressed t_compshape decoding
  - IMF music sequencer (`music_fill`) driving `opl2.sample()` via SDL2 audio queue
  - HUD renderer with 3x5 bitmap digit font
  - `upscale_2x` — pixel-doubles 320x200 → 640x400 for the SDL texture
  - Display pipeline: 640x400 texture + `SDL_RenderSetLogicalSize(640, 480)` for 4:3 (matching wolf4sdl)
  - Classic Wolf3D input (arrows, alt-strafe, shift-run, space-open, F11-fullscreen, Esc-quit)

## Key Data Formats

- **VSWAP.WL6**: Header (3 uint16: num_chunks=663, sprite_start=106, sound_start=542) + offset/length tables + page data. Wall textures (pages 0-105): 64x64 column-major 8-bit indexed. Sprites (pages 106-541): compressed t_compshape. Sounds (pages 542+): 8-bit unsigned PCM @ 7042 Hz.
- **Sprite format (t_compshape)**: uint16 leftpix, rightpix, then (rightpix-leftpix+1) uint16 column data offsets. Each column has runs of `[endy, newstart, starty]` uint16 triples (terminated by endy=0). Pixel at `shape_bytes[newstart + row]`. **IMPORTANT: `newstart` is SIGNED int16** — small sprites use negative offsets to store pixel data in the header area.
- **Wall tile mapping**: Tile `t` → horiz page `(t-1)*2`, vert page `(t-1)*2+1`. Door textures at pages `sprite_start-8` through `sprite_start-1`.
- **MAPHEAD.WL6**: uint16 RLEW tag + 100 int32 offsets into GAMEMAPS.
- **GAMEMAPS.WL6**: Per-level: 3 int32 plane offsets, 3 uint16 plane lengths, uint16 width/height, char[16] name. Decompression: first uint16 = expanded size, then Carmack expand, then RLEW expand (skip first word).
- **Plane 0** = walls (1-63) and doors (90-101, even=vertical, odd=horizontal). **Plane 1** = objects (19-22=player spawn N/E/S/W, 23-72=static objects, 98=push-wall, 108+=enemies).
- **AUDIOHED/AUDIOT**: uint32 chunk offsets. Chunks 0-86=PC speaker, 87-173=AdLib, 174-260=digi, 261+=music (STARTMUSIC=261). Music format: optional uint16 length prefix, then 4-byte entries [reg, val, delay_lo, delay_hi] at 700 Hz tick rate.
- **Per-level music**: `songs[episode*10 + level]` maps to a music enum (chunk = 261 + songs[i]).
- **Per-level ceiling colors**: `ceil_table[episode*10 + level]` is a palette index.

## Key Learnings / Gotchas

- **Display pipeline**: Must match wolf4sdl: render at 320x200, upscale 2x to 640x400, SDL_RenderSetLogicalSize(640,480) for 4:3. Set SDL_HINT_RENDER_SCALE_QUALITY="nearest" BEFORE SDL_CreateTexture.
- **Sprite newstart is signed**: Read as `(int64) (int16) bytes.u16(...)`. Negative values reach back into header area for pixel data.
- **Doors are incomplete**: Currently rendered as full-tile walls. Proper Wolf3D doors render at tile midpoint with animated open/close. See TODO.md.
- **Shimmer at 320x200 is inherent**: Even the Steam/DOSBox version has some. It's a raycaster artifact.
- **Don't add trailing `return`** at end of void FC functions when the last expression is already void.
- **`from` is a keyword in FC** — cannot use as variable name.
- **FC main signature**: `let main = (args: str[]) ->` (must take str[] parameter).
- **FC float format**: `%8.2f{expr}` — width is required for `%f`.
- **Module-level `alloc` not allowed**: `alloc(...)!` is not a constant expression. Allocate in functions and return, or use file-level (outside modules) lets.
- **FC array literals need matching types**: `uint8[n] { 0, 1, ... }` requires `u8` suffixed literals; use `int32[n]` with plain int literals instead.

## FC Quick Reference (for this project)

```
let x = 42                          // immutable binding (int32)
let mut y = 0                       // mutable binding
struct point = x: int32 / y: int32  // struct
alloc(T[n] {})!                     // heap slice, zero-init, unwrap option
free(slice)                         // free heap memory
defer free(buf)                     // cleanup at scope exit
for i in 0..n                       // range loop (exclusive end)
loop / break                        // infinite loop
if cond then expr else expr         // expression
(int32) float_val                   // explicit cast
(float64) int_val                   // int→float requires explicit cast
ptr->field                          // pointer field access
&mut_var                            // take address (requires let mut)
slice.ptr                           // raw pointer from slice
slice.len                           // length (int64)
module M from "header.h" = ...      // C interop
import M from namespace::           // cross-file import
```
