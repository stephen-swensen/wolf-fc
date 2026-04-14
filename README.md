# Wolf-FC

A Wolfenstein 3D clone written in [FC](https://github.com/stephen-swensen/fc-lang), a modern systems programming language that transpiles to C11. This project serves as a comprehensive demo of FC's capabilities: C interop, module system, manual memory management, and real-time rendering via SDL2.

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
| M | Toggle music |
| S | Save screenshot to `~/.wolf-fc/screenshots/ss_NNN.png` |
| F11 | Toggle fullscreen |
| Escape | Quit |

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
| `givekeys` | Grant gold and silver keys (debug) |
| `facetile` | Print the tile the player is facing and the `next_level` flag (debug) |

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

### Verifying screenshots

Screenshots are PNG files (8-bit RGB, 320×200, uncompressed-deflate) with an optional `tEXt` chunk containing current game state (position, direction, health, ammo, score, level, etc.) as key/value lines. Standard tools open them directly, and the metadata is readable with any PNG inspector — `python3 -c 'import struct,zlib; …'` works with stdlib only.

## Architecture

Wolf-fc depends only on the FC compiler and stdlib (`../fc-lang/`). Every other dependency — SDL2 bindings, the OPL2 emulator, the PNG writer — is vendored into this repo. All project modules are declared at the top level (no namespaces), so they're reachable from any file by qualified name without imports.

- **`main.fc`** — Game engine. DDA raycaster + sprite/weapon/HUD renderer, tick-driven game loop, input handling, player movement with collision radius, item pickups, animated doors, push-walls, weapons, level transitions, screenshot capture. Holds an `audio_ctx` threaded through the update pipeline so any code can trigger a sound without globals.
- **`data.fc`** — Wolf3D asset loading, 5 top-level modules:
  - `bytes` — little-endian uint16/uint32/int32 readers
  - `palette` — 256-entry VGA palette (6-bit → 8-bit ARGB)
  - `vswap` — VSWAP.WL6 (wall textures, sprites, digitized sounds)
  - `maps` — MAPHEAD/GAMEMAPS with Carmack + RLEW decompression
  - `audio` — AUDIOHED/AUDIOT chunk index for music and AdLib SFX
- **`opl2.fc`** — YM3812 FM synth emulator: chip state, register writes, sample generation, AdLib instrument helpers, and a generic `fill_ticked` runner that both sound drivers plug into.
- **`imf.fc`** — IMF music format driver. Owns an OPL2 chip, reads `(reg, val, delay)` quads from AUDIOT chunks at 700 Hz, loops the track at end, mixes samples into the output buffer.
- **`adlib.fc`** — id-Software AdLib SFX driver. Owns a separate OPL2 chip, parses an instrument + note-byte stream from AUDIOT chunks, plays at 140 Hz on channel 0, mixes additively. Chosen as fallback for sound effects that don't exist in the VSWAP digi pack (pickups, knife, etc.).
- **`sdl2.fc`** — SDL2 C bindings (window, renderer, texture, event, audio queue).
- **`png.fc`** — Pure-FC PNG writer (CRC-32, Adler-32, stored deflate, optional tEXt metadata).
- **`run.sh`** — build + run wrapper; handles Linux/macOS and MSYS2/MinGW.

The audio pipeline each frame: zero buffer → `imf.fill` (music) → `adlib.fill` (OPL2 SFX) → `mix_sounds` (8-bit digi PCM from VSWAP) → SDL audio queue (back-pressured via `SDL_GetQueuedAudioSize` to keep latency ≤ ~50 ms).

## License

This project is original code written in FC. It reads Wolfenstein 3D data files but contains no code derived from the original game or GPL-licensed ports. The `.WL6` data files are copyrighted by id Software and are not included in this repository.
