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
