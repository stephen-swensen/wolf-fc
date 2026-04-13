# CLAUDE.md

## Project Overview

Wolf-FC is a Wolfenstein 3D clone written in FC, intended as a demo of the FC language. It reads original `.WL6` data files (wall textures, maps, sprites, audio) and implements a raycasting engine with SDL2 rendering.

## Build & Run

- **`./run.sh`** — Compile and run. Requires `../fc-lang/` to be present with the FC compiler.
- The FC compiler is at `../fc-lang/fc`; stdlib at `../fc-lang/stdlib/`; shared SDL2/OPL2 bindings at `../fc-lang/demos/shared/`.
- Data files must be in `data/*.WL6` (not committed — users supply their own).

## Source Files

- **`data.fc`** — `namespace wolf_data::` — Data loading (palette, VSWAP, maps with Carmack+RLEW decompression)
- **`main.fc`** — Game loop, DDA raycaster, rendering, input handling

## Key Data Formats

- **VSWAP.WL6**: Pages of wall textures (64x64, column-major, 8-bit indexed), sprites (compressed), and digitized sounds (8-bit PCM @ 7042 Hz). Header: 3 uint16 (num_chunks, sprite_start, sound_start) + offset/length tables.
- **MAPHEAD.WL6**: uint16 RLEW tag + 100 int32 offsets into GAMEMAPS.
- **GAMEMAPS.WL6**: Per-level headers (plane offsets/lengths, dimensions, name) + Carmack+RLEW compressed tile data. 2 planes: plane 0 = walls, plane 1 = objects/spawns.
- **Wall tile mapping**: tile value `t` → horiz texture page `(t-1)*2`, vert texture page `(t-1)*2+1`.
- **Player spawn**: plane 1 tiles 19-22 = player facing N/E/S/W.

## FC Patterns Used

- Indentation-based syntax (4-space indent, no tabs)
- `namespace`/`module` for multi-file organization
- `extern` modules for SDL2 C interop via `any*`
- Heap-allocated slices for game data (`alloc(T[n] {})!`)
- `defer free(...)` for temporary buffers
- Tagged unions for game phases
- `match` for exhaustive state dispatch
- `for i in 0..n` range loops, `loop`/`break` for game loop
- String interpolation (`%d{expr}`, `%s{expr}`)
- `let mut` for mutable state, `&x` for pointer-taking
- No null — `T?` option types with `!` unwrap

## Conventions

- All FC names use lowercase snake_case
- `->` introduces function body (never a return type annotation)
- Match arms (`|`) align with `match` keyword
- File-level `let` bindings for global state
- Pass mutable state via pointers (`game*`)
