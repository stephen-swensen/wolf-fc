# Wolf-FC

A Wolfenstein 3D clone written in [FC](https://github.com/your-repo/fc-lang), a modern systems programming language that transpiles to C11. This project serves as a comprehensive demo of FC's capabilities: C interop, module system, manual memory management, and real-time rendering via SDL2.

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
| Space | Use / open doors |
| Escape | Quit |
| M | Toggle music |
| Tab | Automap (if implemented) |

## Headless Test Mode

The binary supports a `--test` flag that runs the game engine without opening a window or audio device. Commands are passed as additional arguments and executed left-to-right; each tick-advancing command simulates one frame at a fixed `dt = 1/35s`. This enables scripted, reproducible "play" from the shell — useful for regression testing, verifying gameplay logic, or generating screenshots from specific positions.

### Usage

```bash
./run.sh --test <command> [<command> ...]
```

Or run the built binary directly after a normal `./run.sh` to avoid rebuilding:

```bash
/tmp/wolf-fc-bin --test fwd:20 turnr:90 space wait:30 ss:out.ppm state
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
| `ss:FILE` | Render current frame and save as PPM to `FILE` |
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
./wolf-fc-bin --test fwd:15 space wait:40 ss:door.ppm
```

### Verifying screenshots

Screenshots are saved as binary PPM (P6) files. They can be converted with standard tools (`convert`, `ffmpeg`) or inspected programmatically in Python — the format is a short ASCII header (`P6`, width/height, maxval) followed by raw RGB bytes, so reading specific pixels for regression checks is a few lines of code. See existing tests in session history for examples.

## Architecture

The project is organized into two FC source files plus shared SDL2/OPL2 bindings from the fc-lang demos:

- **`data.fc`** (`namespace wolf_data::`) — Data loading subsystem
  - `module bytes` — Little-endian binary readers
  - `module palette` — Wolf3D 256-color VGA palette (6-bit to ARGB conversion)
  - `module vswap` — VSWAP.WL6 page manager (wall textures, sprites, sounds)
  - `module maps` — MAPHEAD/GAMEMAPS loader with Carmack + RLEW decompression

- **`main.fc`** — Game engine
  - DDA raycasting with textured walls
  - Streaming SDL2 texture for pixel rendering at 320x200, scaled to window
  - Classic Wolf3D movement and controls
  - Game loop with delta-time physics

- **Shared modules** (from `fc-lang/demos/shared/`)
  - `sdl2.fc` — SDL2 C bindings
  - `opl2.fc` — OPL2 FM synthesis emulator for IMF music

## License

This project is original code written in FC. It reads Wolfenstein 3D data files but contains no code derived from the original game or GPL-licensed ports. The `.WL6` data files are copyrighted by id Software and are not included in this repository.
