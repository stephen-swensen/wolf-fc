# CLAUDE.md

## Project Overview

Wolf-FC is a Wolfenstein 3D clone written in FC, intended as a demo of the FC language. It reads original `.WL6` data files (wall textures, maps, sprites, audio) and implements a raycasting engine with SDL2 rendering. See `TODO.md` for what's implemented and what remains.

## Sibling Repositories

- **`../fc-lang/`** — The FC compiler and stdlib. **Read `../fc-lang/CLAUDE.md` for the full FC language reference** (syntax, type system, module system, C interop, naming conventions, etc.). Key paths:
  - `../fc-lang/fc` — compiler binary
  - `../fc-lang/stdlib/` — standard library (io, math, sys, text, random, data)
  - `../fc-lang/spec/examples.fc` — runnable FC quick reference. **Read this file fully at the start of every session** for a firm grasp on the FC language.

  Wolf-fc depends only on the compiler and stdlib. The SDL2 and OPL2 bindings, originally copied from `fc-lang/demos/shared/`, are now vendored into this repo (`sdl2.fc`, `opl2.fc`) so wolf-fc can evolve them independently of the shared demo copies.
- **`../wolf4sdl/`** — C reference implementation of Wolf3D (SDL2 port). Consult for data format details and rendering correctness, but **don't copy code** (GPL). Key files listed in TODO.md.

## Build & Run

- **`./run.sh`** — Compile FC → C → binary, then run. Requires `../fc-lang/` and `libsdl2-dev`.
- **`./run.sh --test <cmd> ...`** — Headless scripted-play mode (see below). No SDL window, no audio device. Use this for automated verification.
- Press **`s`** in interactive mode to take a screenshot to `~/.wolf-fc/screenshots/ss_NNN.png`. See README.md.
- Data files must be in `data/*.WL6` (not committed — users supply their own from a legitimate Wolf3D copy).

## Headless Test Mode (`--test`)

**Purpose**: run the game engine without a window or audio so gameplay logic can be verified deterministically from a shell script. Used heavily for regression testing; `ss:path.png` during a test script writes a PNG of the current frame with game-state metadata embedded in a tEXt chunk.

**Entry point**: `run_test_cmd` in `main.fc` dispatches each CLI arg to a command handler. After `--test`, args are processed left-to-right with a fixed `dt = 1.0 / 35.0` per simulated tick. The test mode skips SDL init entirely — data loads, game state initializes, commands run, then the program exits.

**User-facing command reference lives in `README.md`.** This section covers the internals and how to extend them.

### `world` — the grouped state handle

Game state, level data, renderer, and audio live in a single `world` struct. Orchestrator functions (`tick`, `render_frame`, `take_screenshot`, `run_test_cmd`) take `w: world*`; narrower functions take just the sub-contexts they need so their dependencies are visible in their signatures.

```fc
struct world =
    g: game*            // player, input, session state
    lv: level*          // tile grid + doors + sprites + push-wall (per-level, rebuilt on transition)
    rc: render_ctx*     // renderer scratch buffers (fb, dbuf, zbuf)
    ac: audio_ctx*      // sound pipeline (vs, ad, sfx chip, digi slots)
```

Factories: `build_level(lv_data, sprite_start)` allocates and initializes a level; `free_level(lv)` tears it down (called on level transition). `build_render_ctx()` allocates the scratch buffers once per process.

### The `tick()` function

All per-frame game updates go through **one** function:

```fc
let tick = (w: world*, dt: float64) ->
    update_player(w->lv, w->g, dt, w->ac)
    update_doors(w->lv, w->g, dt, w->ac)
    update_pushwall(w->lv, dt)
    update_weapon(w->g, dt, w->ac)
    check_pickups(w->lv, w->g, w->ac)
```

Both the interactive game loop and every tick-advancing test command (`fwd`, `back`, `space`, `wait`) call `tick(w, dt)`. **When you add a new per-frame system (e.g. enemy AI), add the call inside `tick` — nowhere else.** This keeps the test mode and interactive mode bit-identical in their per-frame simulation. Earlier in the project, `update_doors` and `update_pushwall` were missing from some test commands and caused silent "animation frozen" bugs during scripted play.

The `goto:X,Y` command is deliberately NOT a full tick — it just teleports and calls `check_pickups` once. That's the right behavior: goto is an instant jump, not time passing.

### Adding a new command

1. Add an `else if` branch to `run_test_cmd` (ordered near related commands for readability).
2. For prefix commands with an argument (e.g. `foo:N`), use `text.starts_with(arg, "foo:")` then `text.parse_int32(arg[4..arg.len])!`. Int literals auto-widen to `int64` in slice indices and comparisons, so `4` works where `int64` is expected — only suffix with `i64` when a binding's type must be `int64` from the start (e.g. `let mut x = 0i64` used in later `int64` arithmetic).
3. For commands that produce textual output (state dumps, debug prints), end the branch with `void()` — `io.write` returns `int64` and `if/else` chains need matching branch types.
4. If the command advances time, call `tick(w, dt)`. If it changes state without advancing time (like `sethp`, `givekeys`, `goto`), don't.
5. Document the command in `README.md`'s Headless Test Mode section.

### Rendering in test mode

`ss:FILE.png` calls `render_frame(w, vs, pal)` (the single-source-of-truth render path also used by the interactive loop and 's' key) and then `save_png` with game-state metadata. If you add a new render layer, add it to `render_frame` — nowhere else.

### Useful patterns for verification

- **State checks after time-passing commands**: `fwd:20 state` prints position, health, etc. Grep the output.
- **Pixel sampling from screenshots**: the Read tool can open PNGs directly. For per-pixel regression checks, Python with `struct` + `zlib` can decode pixel data in ~15 lines.
- **Level-0 coordinates**: player spawn is `(29.5, 57.5)` facing east. Known landmarks: door at `(32, 57)`, elevator switch at `(25, 46)`, push-wall at `(10, 13)`, first-aid at `(29, 24)`, cross at `(7, 14)`.

## Source Files

All project modules are declared at the top level (no namespaces), so they're accessible from anywhere by qualified name with no imports required. Only stdlib (`std::`) imports are needed in `main.fc`.

- **`sdl2.fc`** (`module sdl2`) — C-interop bindings for SDL2 (window, renderer, texture, event, audio). Vendored from `fc-lang/demos/shared/`.
- **`png.fc`** (`module png`) — Pure-FC PNG writer (CRC-32, Adler-32, deflate stored blocks, optional tEXt metadata). Used for screenshots.
- **`opl2.fc`** (`module opl2`) — YM3812 FM synth emulator (`chip`, `init`, `write`, `sample`) plus AdLib helpers (`load_instrument`, `note_on`, `note_off`). The generic `fill_ticked(chip, buf, count, sample_rate, tick_rate, &tick_accum, advance_closure)` runner factors out the sample/tick loop used by the OPL2-based drivers. Standalone / not wolf-specific.
- **`sound.fc`** — Wolf3D sound-format drivers, three top-level modules. Each exposes `init(...)` / `fill(p, buf, count, sample_rate)` and mixes additively (saturating) into the output buffer:
  - `module imf` — IMF music. Owns an OPL2 chip. Events are `[reg, val, delay_lo, delay_hi]` quads at 700 Hz; loops at end of track.
  - `module adlib` — id-Software AdLib SFX. Owns an OPL2 chip. One voice on channel 0 at 140 Hz; note stream parsed from AUDIOT chunk format.
  - `module digi` — 8-bit PCM from VSWAP. No chip; up to 4 simultaneous slots, nearest-neighbor resampled 7042 Hz → output rate.
- **`data.fc`** — Wolf3D data loading, five top-level modules:
  - `module bytes` — Little-endian uint16/uint32/int32 readers
  - `module palette` — `init()` returns heap-allocated 256-entry ARGB palette from hardcoded 6-bit VGA data
  - `module vswap` — Loads VSWAP.WL6, provides `wall_pixel()` accessor
  - `module maps` — Loads MAPHEAD+GAMEMAPS with Carmack + RLEW decompression
  - `module audio` — Loads AUDIOHED+AUDIOT, provides chunk offset/length accessors

- **`main.fc`** — Game engine, no namespace:
  - Constants (game_w=320, game_h=200, screen_w=640, screen_h=400, actual_h=480, view_h=160, sample_rate=44100)
  - `struct world` — the god-handle: `{g: game*, lv: level*, rc: render_ctx*, ac: audio_ctx*}`. Only orchestrators take `world*`; narrow functions take just the fields they touch.
  - `struct game` — player state (position, direction, camera plane, input, health/ammo/score)
  - `struct level` — per-level mutable state: tilemap, pushwall_tiles, sprites[], doors[], door_pos[], pushwall animation. Rebuilt on level transition.
  - `struct render_ctx` — `{fb, dbuf, zbuf}` renderer scratch buffers, process-wide.
  - `struct audio_ctx` — `{vs, ad, sfx, digi}` bundle so `trigger_sound` / pickup / door code can fire sounds without globals.
  - `struct sprite_obj` — static objects (position, VSWAP page, distance)
  - Factories: `build_render_ctx()`, `build_level(lv_data, sprite_start)`, `free_level(lv)`.
  - DDA raycaster (`render_walls`) writing to `rc->fb` (320x200 framebuffer)
  - Sprite renderer (`render_sprites`) with compressed t_compshape decoding
  - Audio output path: zero buffer → `imf.fill` (music) → `adlib.fill` (AdLib SFX) → `digi.fill` (8-bit PCM) → SDL queue (back-pressured via `queued_audio_size`)
  - HUD renderer with 3x5 bitmap digit font
  - `upscale_2x` — pixel-doubles 320x200 → 640x400 for the SDL texture
  - Display pipeline: 640x400 texture + `SDL_RenderSetLogicalSize(640, 480)` for 4:3 (matching wolf4sdl)
  - Classic Wolf3D input (arrows, alt-strafe, shift-run, space-open, ctrl-fire, F11-fullscreen, s-screenshot, m-music toggle, 1-4 weapon select, Esc-quit)

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
- **Doors must block rays from their perpendicular side, too**: A vertical door only renders its midpoint for rays entering via X-step; a horizontal door only for Y-step. But a ray entering via the *wrong* side (e.g. Y-step into a vertical door, which happens when geometry allows the ray to approach the door tile from its N/S edge) must still be blocked — otherwise it leaks through the door tile and hits whatever is beyond, causing "door-side texture bleed" onto far walls when the door is closed. The raycaster sets a `door_side_hit` flag in this case and renders the door tile with the DOORWALL+2/+3 (track-side) texture.
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
