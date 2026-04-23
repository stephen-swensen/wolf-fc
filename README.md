# Wolf-FC

A Wolfenstein 3D clone written in [FC](https://github.com/stephen-swensen/fc-lang), a modern systems programming language that transpiles to C11. This project serves as a comprehensive demo of FC's capabilities: C interop, module system, manual memory management, and real-time rendering via SDL2.

## Development Transparency

Wolf-FC was developed with heavy AI assistance — primarily **Anthropic's Claude Opus 4.6** (and earlier Opus/Sonnet models) driven through **[Claude Code](https://claude.com/claude-code)**. The human author (Stephen Swensen) designed the project, set direction, reviewed every change, drove architectural decisions, and took responsibility for correctness, style, and the licensing posture described below. The AI generated the bulk of the FC code, test scaffolding, and documentation under that direction.

This is disclosed up front because the project is also intended as a demonstration of what a well-directed human/AI collaboration can produce on a non-trivial systems programming task (FC is a niche language with no training-data precedent for a full raycasting engine), and because readers evaluating the code or using it as a reference for FC deserve to know how it was written.

## Requirements

- **FC compiler** — clone `fc-lang` alongside this repo (i.e. `../fc-lang/`)
- **SDL2** development package
  - Debian/Ubuntu: `sudo apt install libsdl2-dev`
  - macOS: `brew install sdl2`
  - MSYS2: `pacman -S mingw-w64-ucrt-x86_64-SDL2`
- **C compiler** — gcc or clang with C11 support
- **Wolfenstein 3D data files** — place `.WL6` files in the `data/` directory from a legitimate copy of Wolfenstein 3D (e.g. the Steam version)

### Required data files

```
data/VSWAP.WL6      Wall textures, sprites, and digitized sounds
data/MAPHEAD.WL6    Level header / offsets
data/GAMEMAPS.WL6   Level tile data (compressed)
data/AUDIOHED.WL6   Audio chunk offsets
data/AUDIOT.WL6     Music and sound data
```

## Build and Run

```bash
./run.sh
```

This compiles the FC source to C, then to a native binary, and runs it. The game expects to find its data files relative to the working directory (`data/*.WL6`).

### Options

| Flag | Effect |
|------|--------|
| `--no-dogs` | Skip spawning all dog enemies (for sensitive players). Works in both interactive and `--test` modes; may appear before or after `--test`. |
| `--level=N` | Skip the title / menu and drop straight into map N in playing phase. `N` is `0..59` (six episodes of ten maps). Handy for jumping to a specific boss fight — see table below. |
| `--difficulty=N` | Override the starting difficulty: `0` = Can I play Daddy, `1` = Don't Hurt Me, `2` = Bring 'Em On, `3` = I Am Death Incarnate (default). Combines with `--level`. |
| `--near-boss` | After the level loads, teleport the player to an open tile adjacent to the first boss enemy on the map, facing the boss. No-op on maps without a boss. Combine with `--level=N` to start a specific boss fight immediately. |
| `--cheat` | Pre-activate both Doom-style cheats (`IDDQD` god mode + `IDKFA` all-keys / all-weapons / full non-depleting ammo / locked score) from the very first frame. The gifts re-apply on every death while the IDKFA latch stays on. |

### Jump-to-boss cheat sheet

Each episode ends on map 8 (map 9 is the secret level). Add `--near-boss` to also teleport directly in front of the boss instead of landing at the map's designed spawn point:

| Boss | Episode | Map (0-indexed) | CLI |
|------|---------|-----------------|-----|
| Hans Grosse | E1 | 8 | `./run.sh --level=8 --near-boss` |
| Dr. Schabbs | E2 | 18 | `./run.sh --level=18 --near-boss` |
| Adolf Hitler | E3 | 28 | `./run.sh --level=28 --near-boss` |
| Otto Giftmacher | E4 | 38 | `./run.sh --level=38 --near-boss` |
| Gretel Grosse | E5 | 48 | `./run.sh --level=48 --near-boss` |
| General Fettgesicht | E6 | 58 | `./run.sh --level=58 --near-boss` |

The same functionality is available from the main menu: **NEW GAME → Episode → Map → BOSS FIGHT** picks map 9 of the chosen episode and teleports you next to the boss. Picking a regular map (1–10) starts at the map's designed spawn.

## Controls

Classic Wolfenstein 3D controls:

| Key | Action |
|-----|--------|
| Up / Down arrows | Move forward / backward |
| Left / Right arrows | Turn left / right |
| Alt + Left/Right | Strafe left / right |
| Left Shift | Run (2x speed) |
| Left Ctrl | Fire weapon |
| Space | Use / open doors / activate elevator / push wall |
| 1 – 4 | Select weapon (knife / pistol / machine gun / chain gun) |
| S | Save screenshot to `~/.wolf-fc/screenshots/ss_NNN.png` |
| F11 or Alt + Enter | Toggle fullscreen |
| Escape | Quit |

### Secret cheat codes

As in the original, two chord cheats work during gameplay — hold all three keys at once:

| Chord | Effect |
|-------|--------|
| M + L + I | Refill: 100 health, 99 ammo, both keys, chaingun; score zeroed |
| B + A + T | Flavor message only (no gameplay effect) |

There are also two Doom-style sequence cheats (type the letters in order, no need to hold):

| Sequence | Effect |
|----------|--------|
| I D D Q D | Toggle god mode (silently absorbs all damage; refills health on activation). Status bar grows a yellow outline while active. |
| I D K F A | Toggle "all keys, full arsenal": grants both keys, chain gun, 99 ammo on activation, and latches non-depleting ammo + locked score until toggled off |

> **Note:** On Windows, rapid Ctrl presses trigger the Sticky Keys accessibility popup. If this gets in your way during combat, turn off Sticky Keys in Settings → Accessibility → Keyboard.

## Headless Test Mode

The binary supports a `--test` flag that runs the game engine without opening a window or audio device. Commands are passed as additional arguments and executed left-to-right; each tick-advancing command simulates one frame at a fixed `dt = 1/35s`. This enables scripted, reproducible "play" from the shell — useful for regression testing, verifying gameplay logic, or generating screenshots from specific positions.

### Usage

```bash
./run.sh --test <command> [<command> ...]
```

Or run the built binary directly after a normal `./run.sh` to avoid rebuilding:

```bash
/tmp/wolf-fc-bin --test fwd:20 turnr:90 space wait:30 ss:out.png state
```

Since `run.sh` rebuilds on every invocation, invoking the pre-built binary directly is faster for iterative testing.

### Commands

| Command | Effect |
|---------|--------|
| `fwd:N` | Hold forward for N ticks (≈ N/35 seconds) |
| `back:N` | Hold backward for N ticks |
| `turnl:N` / `turnr:N` | Turn left / right by N degrees (instant) |
| `run` | Toggle the shift/run modifier |
| `space` | Press space once (open door, elevator, push wall) |
| `wait:N` | Advance N ticks with no input (for door/push-wall animation) |
| `ss:FILE` | Render current frame and save as PNG to `FILE` (with game-state metadata in a `tEXt` chunk) |
| `state` | Print position, direction, health, ammo, score, lives, level, keys |
| `goto:X,Y` | Teleport player to tile center `(X+0.5, Y+0.5)` and run a pickup check |
| `sethp:N` | Set health to N (debug) |
| `setammo:N` | Set ammo count to N (debug) |
| `setweapon:N` | Select weapon slot 0-3 (knife/pistol/MG/chain) |
| `fire` | Press fire once (1 tick); hitscans enemies, decrements ammo, plays weapon SFX |
| `givekeys` | Grant gold and silver keys (debug) |
| `mli` | Fire the M+L+I cheat effect (refill + chaingun + score reset) |
| `bat` | Fire the B+A+T flavor-message cheat |
| `iddqd` | Toggle Doom-style god mode (also refills health on activation) |
| `idkfa` | Toggle Doom-style "all keys, full arsenal" cheat: both keys, chain gun + 99 ammo on activation, and latched non-depleting ammo + locked score until toggled off |
| `psyched` | Force the "GET PSYCHED!" full-screen load overlay timer (debug — bypasses the test-mode gate so `ss:` can capture it) |
| `gotgatling` | Force the GOTGATLINGPIC face-cell swap timer (debug — paints over the BJ face slot in render_hud for the duration) |
| `facetile` | Print the tile the player is facing and the `next_level` flag (debug) |
| `enemies` | Print totals per enemy kind and per state |
| `enemylist` | Print each enemy: index, tile, kind, state, direction, hp, area number |
| `killenemy:N` | Overkill enemy at index N via `damage_enemy` (drops, score, kill counter all fire as if shot) |
| `arrows` | Print every plane-1 ICONARROWS path-marker tile (`x,y` and dir 0..7) |
| `exittiles` | Print every plane-1 EXITTILE marker (`x,y`) on the current map — boss-map exits that fire the BJ-victory cutscene when stepped on |
| `setlevel:N` | Load level N (0..59) and enter gp_playing |
| `setepisode:N` | Jump to the start of episode N (0..5) — level=N*10 |
| `setdifficulty:N` | Re-apply difficulty N (0..3) to the current level, re-running spawn filtering |
| `setphase:X` | Force phase: `title` / `menu` / `epmenu` / `diffmenu` / `savemenu` / `loadmenu` / `playing` |
| `music` | Print the AUDIOT chunk that should be playing for the current phase (no audio device required) |
| `endepisode` | Set `next_level` on current level (quick path to intermission/episode-end screens) |
| `advance` | Simulate the ack-key press on intermission / episode-end / victory / game-over (intermission accepts any key in interactive mode) |
| `save:N` | Write the running world to save slot N (0..9) under `~/.wolf-fc/saves/` |
| `load:N` | Read save slot N back into the world (level reloaded, state overlaid) |
| `listsaves` | Dump each save slot (`slot N: E<ep>M<lvl> diff=... score=... label=...` or `EMPTY`) |
| `counters` | Print kills/secrets/treasures counters + par time + phase |
| `phase` | Print current phase + timer + lives |

### Examples

Walk forward, open a door, walk through:

```bash
./wolf-fc-bin --test fwd:15 space wait:40 fwd:20 state
```

Verify an item pickup (player starts at 100 HP; food only picks up below max):

```bash
./wolf-fc-bin --test sethp:50 goto:29,51 state
# → health=60 (food gave +10)
```

Exercise the elevator switch on E1M1:

```bash
./wolf-fc-bin --test goto:25,47 turnl:90 space facetile
# → facing=(25,46) tile=21 next_level=1
```

Capture a screenshot of an opened door:

```bash
./wolf-fc-bin --test fwd:15 space wait:40 ss:door.png
```

### Output streams

Normal output (`state`, `facetile`, `ss:` confirmations, load progress) goes to **stdout**. Bad-argument warnings (e.g. `bad arg 'fwd:oops': expected integer tick count`) go to **stderr** so they don't contaminate stdout-based diffs. Use `2>&1` if you want them merged when debugging.

### Verifying screenshots

Screenshots are PNG files (8-bit RGB, 320×200, uncompressed-deflate) with an optional `tEXt` chunk containing current game state (position, direction, health, ammo, score, level, etc.) as key/value lines. Standard tools open them directly, and the metadata is readable with any PNG inspector — `python3 -c 'import struct,zlib; …'` works with stdlib only.

### Regression tests

A scripted test suite lives in [`tests/run-tests.sh`](tests/run-tests.sh) and exercises spawn tables, pickups, doors, hitscan combat, enemy AI, and the movement edge cases that have previously regressed (door straddle, mutual deadlock with a chasing enemy).

```bash
./tests/run-tests.sh          # run everything
./tests/run-tests.sh -k door  # only tests whose name contains 'door'
./tests/run-tests.sh -v       # print each test's output even on success
```

The tests rely on the enemy RNG's fixed seed for reproducibility — scripted scenarios reproduce bit-identically, so assertions on exact HP/score/position values are safe. When AI changes shift the RNG-call order, expected values will need updating; the failures are loud rather than silent.

## Architecture

Wolf-fc depends only on the FC compiler and stdlib (`../fc-lang/`). Every other dependency — SDL2 bindings, the OPL2 emulator, the PNG writer — is vendored into this repo. All project modules are declared at the top level (no namespaces), so they're reachable from any file by qualified name without imports.

- **`main.fc`** — Game engine. DDA raycaster + sprite/weapon/HUD renderer, tick-driven game loop, input handling, player movement with collision radius, item pickups, animated doors, push-walls, weapons, level transitions, screenshot capture. Game state, level data, renderer scratch/caches, audio pipeline, and save-menu scratch are grouped into a `world` struct (`{g, lv, rc, ac, sm}`); orchestrators take `world*`, narrower functions take just the sub-contexts they touch. No file-scope mutable state — buffers, caches, counters, and launch-time config all live on one of these context structs.
- **`data.fc`** — Wolf3D asset loading, 5 top-level modules:
  - `bytes` — little-endian uint16/uint32/int32 readers
  - `palette` — 256-entry VGA palette (6-bit → 8-bit ARGB)
  - `vswap` — VSWAP.WL6 (wall textures, sprites, digitized sounds)
  - `maps` — MAPHEAD/GAMEMAPS with Carmack + RLEW decompression
  - `audio` — AUDIOHED/AUDIOT chunk index for music and AdLib SFX
- **`opl2.fc`** — YM3812 FM synth emulator: chip state, register writes, sample generation, AdLib instrument helpers, and a generic `fill_ticked` runner that both OPL2-based drivers plug into. Standalone, not wolf-specific.
- **`sound.fc`** — Wolf3D sound-format drivers, three top-level modules:
  - `imf` — IMF music. Owns an OPL2 chip, reads `(reg, val, delay)` quads from AUDIOT chunks at 700 Hz, loops the track at end.
  - `adlib` — AdLib SFX. Owns a separate OPL2 chip, parses instrument + note-byte chunks, plays at 140 Hz on channel 0. Used as the fallback for sounds that don't have a digitized version.
  - `digi` — 8-bit PCM from VSWAP. Up to 4 simultaneous slots, nearest-neighbor resampled 7042 Hz → output rate. Preferred over AdLib for sounds that have a digi version (door open/close, pistol, machine gun, pain).
- **`sdl2.fc`** — Flat `extern` FFI against `SDL2/SDL.h`: lifecycle, window (incl. fullscreen-desktop + high-DPI), the accelerated 2D renderer (used only as a blit primitive for one streaming ARGB8888 texture), keyboard events, and the audio device.
- **`png.fc`** — Pure-FC PNG writer (CRC-32, Adler-32, stored deflate, optional tEXt metadata).
- **`run.sh`** — build + run wrapper; handles Linux/macOS and MSYS2/MinGW.

The audio pipeline each frame: zero buffer → `imf.fill` (music) → `adlib.fill` (AdLib SFX) → `digi.fill` (8-bit PCM) → SDL audio queue (back-pressured via `SDL_GetQueuedAudioSize` to keep latency ≤ ~50 ms).

SDL2's role in wolf-fc is deliberately minimal — it's a host abstraction, not a rendering framework. Each frame, the engine draws into a `uint32[]` ARGB framebuffer entirely in FC, then uploads it as a single 320×200 streaming texture via `SDL_UpdateTexture` + `SDL_RenderCopy` + `SDL_RenderPresent`; `SDL_RenderSetLogicalSize(640, 480)` handles 4:3 letterboxing and the scale-quality hint is pinned to `nearest` for crisp upscaling. The 2D renderer is never asked to draw geometry — no `SDL_RenderFillRect`, no per-sprite textures, no shaders. Audio is equally bare: `SDL_QueueAudio` receives raw S16 PCM that our own mixer produced (no `SDL_AudioCallback`, no `SDL_mixer`). Input is keyboard-only, driven by `SDL_PollEvent` against `SDL_KEYDOWN`/`SDL_KEYUP`. No `SDL_image`, `SDL_ttf`, `SDL_mixer`, or `SDL_net` — just core `SDL2`, linked dynamically.

## License

The wolf-fc source code is licensed under the **BSD 2-Clause License** — see [`LICENSE`](LICENSE) for the full text. Copyright © 2026 Stephen Swensen.

Wolfenstein 3D itself has a complicated licensing history: the original id Software source release is under id's "Limited Use Software License" (educational use only, no commercial exploitation), and the widely-used port **Wolf4SDL** is under the **GPL v2**. Both are copyleft relative to BSD and would be incompatible with this project's license if we incorporated code from them. We've been careful to avoid that.

### What is original

All engine logic in this repo is written from scratch in FC. In particular:

- **Rendering** — the DDA raycaster, sprite renderer (`t_compshape` decoder), HUD, weapon overlay, 2× upscaler, and distance shading are original implementations.
- **Audio** — the OPL2 (YM3812) FM synth in [`opl2.fc`](opl2.fc) is from-scratch, not a port of Nuked OPL3 (LGPL, used by Wolf4SDL) or MAME's OPL cores. The IMF / AdLib SFX / digitized-sound drivers in [`sound.fc`](sound.fc) are original.
- **PNG writer** ([`png.fc`](png.fc)) — pure-FC implementation of the PNG + zlib specs (CRC-32, Adler-32, stored deflate).
- **Game code** — player movement, collision, door/push-wall animation, pickups, weapon cycling, level transitions, and the test-mode command interpreter are original.
- **SDL2 bindings** ([`sdl2.fc`](sdl2.fc)) — author-written FC declarations against SDL2's C headers. SDL2 itself is zlib-licensed and linked dynamically, not vendored.

No file in this repo is a translation, transcription, or line-by-line port of any file in Wolf4SDL or the id Software release.

### Honest caveats

A handful of small **data tables** that encode the original game's design are present verbatim, because any faithful reproduction needs the same values:

- The 256-entry VGA palette in [`data.fc`](data.fc) (identical to Wolf4SDL's `wolfpal.inc` and id's original palette).
- `ceil_table` in [`main.fc`](main.fc) (per-level ceiling colors — identical to `vgaCeiling[]` in Wolf4SDL's `wl_draw.cpp`).
- `songs` in [`main.fc`](main.fc) (per-level music assignments — identical to `songs[]` in Wolf4SDL's `wl_play.cpp`).

These are short tables of indices and color values, not code. The U.S. copyright view of small factual data tables is limited (*Feist v. Rural*), but the selection and ordering of music per level is arguably a creative choice, so we flag it rather than hand-wave it. Anyone who needs maximum licensing purity can replace these tables without touching engine code.

The **Carmack and RLEW decompressors** in [`data.fc`](data.fc) implement publicly-documented file-format algorithms (the Wolf3D map formats, described in third-party modding references). Our code was written against those descriptions and naturally has the same algorithmic structure as every other implementation — including Wolf4SDL's — because the format dictates the steps. No code was copied.

### Game data files

The `.WL6` data files are copyrighted by id Software and are **not** included in this repository. Users must supply their own from a legitimately-obtained copy of Wolfenstein 3D (e.g. the Steam or GOG release). The wolf-fc binary is useless without them.

### Summary

The wolf-fc engine is BSD-2 and not encumbered by GPL or id's Limited Use License. The small data tables noted above are the only part of the repo that could be argued to trace back to id's original release; the rest is original FC code.
