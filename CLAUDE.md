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

**Error output goes to stderr.** The `bad` helper in `run_test_cmd` writes malformed-arg messages (e.g. `bad arg 'fwd:oops': expected integer tick count`) to `stderr`; `state`, `facetile`, and `ss:` go to `stdout`. This keeps golden-file diffs clean, but it means `cmd > out.txt` or `cmd | tail` will silently drop warnings from the captured output — use `2>&1` when debugging or when writing a harness that needs to notice errors.

**User-facing command reference lives in `README.md`.** This section covers the internals and how to extend them.

### `world` — the grouped state handle

Game state, level data, renderer, and audio live in a single `world` struct. Orchestrator functions (`tick`, `render_frame`, `take_screenshot`, `run_test_cmd`) take `w: world*`; narrower functions take just the sub-contexts they need so their dependencies are visible in their signatures.

```fc
struct world =
    g: game*            // player, input, session state
    lv: level*          // tile grid + doors + sprites + push-wall (per-level, rebuilt on transition)
    rc: render_ctx*     // renderer scratch buffers (fb, dbuf, zbuf, title_bg, ...)
    ac: audio_ctx*      // sound pipeline (vs, ad, sfx chip, digi slots)
    sm: save_menu_ctx*  // save/load menu cache + scratch
```

Factories: `build_level(lv_data, sprite_start, difficulty, no_dogs)` allocates and initializes a level; `free_level(lv)` tears it down (called on level transition). `build_render_ctx(vg, pal)` allocates the scratch buffers + pre-decodes the title backdrop once per process. `build_save_menu_ctx()` allocates the save-slot cache + label/hex scratch.

### No file-scope mutable state

Process-wide mutable state must live **on one of the context structs** (`game`, `level`, `render_ctx`, `audio_ctx`, `save_menu_ctx`, ...), reachable through `world`. **Do not add `let mut` at file scope.** The rule applies to:

- **Scratch buffers / caches** reused across frames or calls (e.g. `render_ctx.title_bg`, `save_menu_ctx.label_scratch`). Put them on the context that owns the feature, and initialize them in the context's factory.
- **Launch-time config** parsed from CLI / env (e.g. `game.no_dogs` set from `--no-dogs`). Put them on `game` and set them when the game is allocated in `main`.
- **Counters** that persist across calls (e.g. `render_ctx.screenshot_slot`).

True constants — fixed tables (`songs`, `ceil_table`, `dir_vx`), tuning parameters (`door_speed`, `move_speed`), sound-ID enums — stay as file-level `let`s. The rule is about *mutability*, not file scope.

This keeps dependencies visible in function signatures: if a function reads `rc->title_bg`, its `render_ctx*` parameter makes that dependency explicit, whereas reaching for a file-level global hides it. It also unlocks multi-world scenarios (save/load state round-tripping, future split-screen or replay) without having to disentangle hidden globals.

Existing file-level `let mut` bindings were migrated in sequence:
- `save_slots` / `label_scratch` / `hex_scratch` → `save_menu_ctx` on `world`.
- `title_bg_cache` → `render_ctx.title_bg`.
- `screenshot_slot` → `render_ctx.screenshot_slot`.
- `no_dogs` → `game.no_dogs`.

When you add a new buffer or config, follow the same pattern: find (or add) the right context struct, give it a field, and initialize it in the factory.

### The `tick()` function

All per-frame game updates go through **one** function:

```fc
let tick = (w: world*, dt: float64) ->
    update_player(w->lv, w->g, dt, w->ac)
    update_doors(w->lv, w->g, dt, w->ac)
    update_pushwall(w->lv, dt)
    update_weapon(w, dt)
    update_enemies(w, dt)
    check_pickups(w->lv, w->g, w->ac)
```

Both the interactive game loop and every tick-advancing test command (`fwd`, `back`, `space`, `wait`, `fire`) call `tick(w, dt)`. **When you add a new per-frame system, add the call inside `tick` — nowhere else.** This keeps the test mode and interactive mode bit-identical in their per-frame simulation. Earlier in the project, `update_doors` and `update_pushwall` were missing from some test commands and caused silent "animation frozen" bugs during scripted play.

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
- **`probe` test command**: dumps the player's bbox tiles with wall/door state + any live enemy within 2.5 tiles. Use when a movement-related bug is reported — reveals whether a door, wall, or enemy is the blocker.

### Regression test suite

`tests/run-tests.sh` runs a set of scripted `--test` scenarios and asserts on their stdout. In `--test` mode both PCG32 RNG streams are seeded with 0, so scripted outputs reproduce bit-identically. When you change AI or any RNG-consuming path, expect to update expected HP / state values — the failures are loud, not silent.

Helpers defined in the script: `assert_contains NAME "CMD" "SUBSTRING"`, `assert_not_contains`, `assert_regex` (posix-extended). Tests are grouped with `section "name"` headers. Add new tests at the bottom of the relevant section; each test should be a single assertion that fails for one clear reason.

## Source Files

All project modules are declared at the top level (no namespaces), so they're accessible from anywhere by qualified name with no imports required. Only stdlib (`std::`) imports are needed in `main.fc`.

Subsystem files were extracted from `main.fc` in a large 2026-04 refactor. The file names and modules they contain:

| File | Modules | What's in it |
|---|---|---|
| `sdl2.fc` | `sdl2` | SDL2 C-interop bindings (window, renderer, texture, event, audio). |
| `opl2.fc` | `opl2` | YM3812 FM synth emulator + AdLib helpers + `fill_ticked` driver runner. |
| `png.fc` | `png` | Pure-FC PNG writer (CRC-32, Adler-32, deflate, optional tEXt). |
| `sound.fc` | `imf`, `adlib`, `digi`, `mixer` | Wolf3D sound-format drivers. |
| `data.fc` | `bytes`, `palette`, `vswap`, `maps`, `vgagraph`, `audio` | Wolf3D data-file loading. |
| `sfx.fc` | `sfx` (with nested `id`) | Sound-effect trigger helpers + the 73 sound IDs + `digi_slot` / `adlib_chunk` lookup tables. |
| `ui.fc` | `music`, `pics` (with nested `id`), `font`, `hud` | UI primitives: music track IDs + per-level `songs[]` table, VGAGRAPH pic blitter (incl. `get_psyched_*` overlay config + `pics.trigger_get_psyched`), font, status bar + BJ face animation (incl. `got_gatling_time`). |
| `save.fc` | `paths`, `save` | Save/load slot I/O + encoding; `save.num_slots` constant, `save.slot_info` struct. `paths` is a leaf module holding `wolf_data_dir`/`ensure_save_dir` (shared with `overlay`). |
| `combat.fc` | `dir`, `enemies` (with nested `ai`), `projectiles`, `hitscan` | Enemy data + AI + projectiles + player hitscan. |
| `level.fc` | `difficulty`, `tilemap`, `areas`, `spawn`, `doors`, `pushwall`, `pickups` | Level geometry + enemy/sprite spawning + door / pushwall animation + pickup collection. `difficulty` holds the 4 picker constants. |
| `cutscenes.fc` | `bj_victory`, `death_cam` (with nested `sub`), `intermission`, `episode_end`, `victory_screen`, `game_over`, `title_screen` | Per-phase state machines + renderers. `intermission` owns the scoring constants + `par_times[]` table + `compute_*` helpers. |
| `menu.fc` | `menu` (with nested `nav`) | Main menu + submenus (episode, difficulty, map, save/load slot list). |
| `render.fc` | `raycaster`, `billboards`, `overlay` | DDA raycaster (owns `ceil_table[]`), billboard sort+draw, viewport tints / dissolve / upscale / screenshot pipeline. |
| `player.fc` | `player` (with nested `cheats`) | Player movement / collision / camera / weapon firing + MLI/BAT/IDDQD cheats. Owns `move_speed`/`run_mult`/`back_mult`/`strafe_mult`/`turn_speed`/`radius`, the player-lifecycle timing constants (`elevator_wait_time`, `death_fade_time`, `death_anim_time`, `respawn_fade_time`, `damage_flash_time`), and the per-life / new-game / input-clear reset helpers (`reset_for_life`, `reset_for_new_game`, `clear_input_keys`). |

### FC module restrictions hit during the refactor

- **Non-entry-point files can only contain modules.** Every `.fc` file other than `main.fc` must put every declaration inside a `module X = ...` block. File-scope `let`/`struct`/`union` is only allowed in the file that defines `let main`.
- **Modules can't have circular references.** Two cycles came up and both were broken by narrowing the contract between modules:
  - `player ↔ doors`: `player.blocked_by_map` uses `doors.passable` for collision, and `doors.update` needs the player's collision radius for its bbox-based auto-close check. Fix: `doors.update(...)` takes `player_radius` as a parameter instead of reaching into `module player`. `tick()` in main.fc (the single caller) already has `player.radius` in scope.
  - `overlay ↔ save` (transitive via cutscenes): `overlay.take_screenshot` needed `save.wolf_data_dir` for the screenshots directory, and `save.from_slot` calls `intermission.enter` / `episode_end.enter` which call `overlay.*` renderers. Fix: extract `wolf_data_dir` + `ensure_save_dir` into a leaf `module paths` at the top of save.fc that depends on nothing downstream; both `save` and `overlay` reach for it.

### `main.fc` — entry point + orchestration

Everything left in `main.fc` is either a cross-subsystem constant, a core
data struct, a factory, a phase-transition routing helper, or one of the
three top-level dispatchers (`tick`, `render_frame`, `run_test_cmd`) +
`main`. Anything specific to one subsystem now lives in that subsystem's
module (see the table above).

- **Resolution constants**: `game_w`/`game_h` (320×200 internal framebuffer), `screen_w`/`screen_h` (640×400 doubled), `actual_h` (480 for 4:3 letterboxing), `view_h` (160, 3D viewport height), `map_size`/`tex_size` (64), `tile_area` (107, first non-solid tile), `fov_factor` (0.66 — `tan(33°)` for ~66° FOV).
- **`module episode`** — `levels_per` (10), `count` (6), `back_to[6]` (per-episode return target for secret-level exits), `title(ep)` (human-readable episode names), `next_level_num(level_num, went_secret)` (elevator-routing rule).
- **Phase enum**: `union game_phase` — the top-level phase state machine, variants `title`, `main_menu`, `playing`, `dying`, `intermission`, `bj_victory`, `death_cam`, `episode_end`, `victory`, `game_over`. Accessed as `game_phase.playing` etc. (variants that share a name with a cutscenes module like `bj_victory` / `death_cam` resolve fine in match patterns — pattern scope is separate from expression scope).
- **Core data structs**:
  - `struct world` — god-handle `{g: game*, lv: level*, rc: render_ctx*, ac: audio_ctx*, sm: save_menu_ctx*}`. Only orchestrators take `world*`; narrow functions take just the fields they touch.
  - `struct game` — player state (position, direction, camera plane, input keys, health/ammo/score, phase timers, RNG channels, `no_dogs` / `test_mode` CLI flags).
  - `struct level` — per-level mutable state: tilemap, pushwall_tiles, path_arrows, sprites[], doors[] + door_pos[] + pushwall state, enemies[], projectiles[], tile_areas + area_connect + area_by_player (area-flood reachability). Rebuilt on level transition.
  - `struct render_ctx` — `{fb, dbuf, zbuf, billboards, title_bg, pic_cache, screenshot_slot}` renderer scratch + caches, process-wide. `billboards[]` is rebuilt/sorted each frame from live enemies + live sprites; `title_bg` is the pre-decoded TITLEPIC backdrop (blitted by `pics.blit_title_bg` on every menu frame); `pic_cache[chunk]` is lazily populated on first `pics.draw` call with the chunk's ARGB pixels, so subsequent HUD / intermission / menu draws skip the Huffman decode + palette remap; `screenshot_slot` wraps at `screenshot_max_slots`.
  - `struct audio_ctx` — `{vs, ad, sfx, digi}` bundle so `sfx.trigger` / pickup / door code can fire sounds without globals.
  - `struct save_menu_ctx` — `{slots, label_scratch, hex_scratch}` for the save/load menu. `slots[]` (of `save.slot_info`) is refreshed on menu entry; `label_scratch`/`hex_scratch` are reusable buffers for slot-label rendering and per-nibble save-file writes.
  - `struct billboard` — per-frame entry for the back-to-front sprite draw; built by `billboards.build` (in `render.fc`) from live enemies + live sprites + live projectiles.
- **Factories**: `build_render_ctx(vg, pal)`, `build_save_menu_ctx()`, `build_level(lv_data, sprite_start, difficulty, no_dogs)`, `free_level(lv)`.
- **Cross-subsystem helpers** (kept at file scope in main.fc so any module can call them unqualified without adding new cross-module edges): `add_score(g, amount)` — one chokepoint for score gains (pickups / kills / intermission bonus); honors the IDKFA lock and grants the 40k-score extra life. `give_full_kit(g)` — 100 HP + 99 ammo + chain gun + both keys; shared by MLI, IDKFA activation, the `--cheat` launch flag, and `player.reset_for_life`'s IDKFA respawn branch.
- **Phase-transition routing** (the glue between subsystems): `reset_level_counters`, `reload_level_data`, `advance_next_level`, `advance_next_episode`, `restart_current_level`, `restart_full_game`, `start_new_game_here`, `update_phase_transitions`. Single-owner helpers that these dispatchers call live in their owning modules: `player.reset_for_life` / `reset_for_new_game` / `clear_input_keys`, `pics.trigger_get_psyched`, `episode.next_level_num`.
- **Dispatchers**:
  - `tick(w, dt)` — the single per-frame update entry. Runs `player.update` → `doors.update` → `pushwall.update` → `player.update_weapon` → `enemies.ai.update_enemies` → `enemies.ai.update_dying_enemies` → `projectiles.update_all` → `pickups.check`. **When adding a new per-frame system, add the call here, not elsewhere** — it keeps interactive and `--test` modes bit-identical.
  - `render_frame(w, vs, pal)` — the single render entry. Dispatches by phase: title / menu / playing (raycaster + billboards + HUD + damage flash + elevator fade) / dying (red stipple collapse) / intermission / bj_victory / death_cam / episode_end / victory / game_over.
  - `run_test_cmd(w, arg, pal, dt)` — headless `--test` mode command dispatcher (movement, state dump, save/load, facetile queries, screenshot capture).
- **`main(args)`** — SDL init, data loading, factories, the interactive frame loop, `--test`-mode branch.

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
