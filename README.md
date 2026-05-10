# Wolf-FC

A feature-complete Wolfenstein 3D clone written in [FC](https://github.com/stephen-swensen/fc-lang), a modern systems programming language that transpiles to C11. Gameplay mechanics are faithful to the original — six episodes, every weapon, the original enemy AI and difficulty filtering, cheat codes, BJ-victory and per-episode endart cutscenes, the high-scores screen. Tested and running smoothly on native Linux and Windows (MSYS2 UCRT64).

The engine is software-rendered and software-mixed end-to-end: a DDA raycaster paints into a CPU framebuffer in pure FC, an emulated OPL2 (YM3812) FM synth and an in-process audio mixer drive the original's IMF music and AdLib + digitized SFX, and SDL2 is reduced to a thin host shim — open a window, blit one streaming texture per frame, surface keyboard events. No GPU shaders, no per-sprite textures, no `SDL_mixer` or `SDL_image`. The project doubles as a comprehensive demo of FC's capabilities: C interop, module system, manual memory management, and real-time systems work.

## Development Transparency

Wolf-FC was developed with heavy AI assistance — primarily **Anthropic's Claude Opus 4.6** (and earlier Opus/Sonnet models) driven through **[Claude Code](https://claude.com/claude-code)**. The human author (Stephen Swensen) designed the project, set direction, reviewed every change, drove architectural decisions, and took responsibility for correctness, style, and the licensing posture described below. The AI generated the bulk of the FC code, test scaffolding, and documentation under that direction.

This is disclosed up front because the project is also intended as a demonstration of what a well-directed human/AI collaboration can produce on a non-trivial systems programming task (FC is a niche language with no training-data precedent for a full raycasting engine), and because readers evaluating the code or using it as a reference for FC deserve to know how it was written.

## Requirements

- **FC compiler (`fcc`)** — must be on your `PATH`. See [Installing the FC compiler](#installing-the-fc-compiler) below if `command -v fcc` doesn't already work.
- **SDL2** development package
  - Debian/Ubuntu: `sudo apt install libsdl2-dev`
  - macOS: `brew install sdl2`
  - MSYS2: `pacman -S mingw-w64-ucrt-x86_64-SDL2`
- **C compiler** — gcc or clang with C11 support
- **Wolfenstein 3D data files** — `.WL6` files from a legitimate copy of Wolfenstein 3D (e.g. the Steam version). See [Required data files](#required-data-files) for the list and the supported layouts.

### Windows: MSYS2 is required

Wolf-FC on Windows currently runs only inside an [MSYS2](https://www.msys2.org/) UCRT64 shell — there is no vanilla-Windows install path yet. Practically that means:

- You build, install, and launch the game from inside an MSYS2 UCRT64 terminal (the `wolf-fc.exe` binary `make install` produces lives at `/usr/local/bin/wolf-fc.exe` under MSYS2's tree, e.g. `C:\msys64\usr\local\bin\wolf-fc.exe`).
- A double-clicked `wolf-fc.exe` from Windows Explorer (or a desktop shortcut) **will not work** because the binary dynamically links against MSYS2's `libSDL2-2.0.dll` plus a few mingw runtime DLLs, and an Explorer-launched process doesn't inherit MSYS2's `PATH`.
- The compile-time install data path (`$(PREFIX)/share/wolf-fc/data/`) is also baked relative to MSYS2's filesystem root, so even with the DLLs sorted the binary would only find data files when run with MSYS2 mounted at the same location.

A proper redistributable Windows build (bundled SDL2 + runtime DLLs, exe-relative data lookup, optional installer / shortcut) is out of scope for now. If you want to play wolf-fc on Windows today, install MSYS2 UCRT64 and follow the Linux/Unix-style instructions below from inside that shell.

### Required data files

The eight `.WL6` files Wolf-FC needs:

```
VSWAP.WL6      Wall textures, sprites, and digitized sounds
MAPHEAD.WL6    Level header / offsets
GAMEMAPS.WL6   Level tile data (compressed)
AUDIOHED.WL6   Audio chunk offsets
AUDIOT.WL6     Music and sound data
VGADICT.WL6    VGAGRAPH Huffman dictionary
VGAHEAD.WL6    VGAGRAPH chunk offsets
VGAGRAPH.WL6   UI graphics + fonts + endart text
```

Wolf-FC searches for these files in three locations, in priority order:

1. **`$WOLF_FC_DATA_DIR`** (env override). Highest priority — useful for ad-hoc runs and CI: `WOLF_FC_DATA_DIR=/path/to/wl6 wolf-fc`. On MSYS2/Windows, use a Windows-style mixed path (e.g. `C:/msys64/home/me/wl6`) since the binary's `fopen()` is a Windows C-runtime call that doesn't translate POSIX mounts. `cygpath -m /your/path` prints the right form.
2. **`./data/`** (relative to the current working directory). The dev workflow: drop the files in the project's `data/` directory and `./run.sh` / `make` / `./build/wolf-fc` find them.
3. **`$(PREFIX)/share/wolf-fc/data/`** (compile-time install location). The fallback baked into the binary at build time. `make install` will copy `./data/*.WL6` here automatically when present; otherwise put them there manually after install.

The startup banner prints `Data dir: <path>` so you can see which layout the running binary picked.

### Installing the FC compiler

If `command -v fcc` works in your shell already, skip this section. Otherwise, clone and install [fc-lang](https://github.com/stephen-swensen/fc-lang):

```bash
git clone https://github.com/stephen-swensen/fc-lang.git
cd fc-lang
make                                    # release build (-O2)
sudo make install                       # installs to /usr/local by default

# ... or for a user-local install (no sudo):
# make install PREFIX=$HOME/.local      # then ensure $HOME/.local/bin is on PATH
```

This puts the `fcc` binary in `$PREFIX/bin/` and the FC stdlib in `$PREFIX/share/fcc/stdlib/`. Wolf-FC's `Makefile` resolves the stdlib path automatically by following `fcc`'s install prefix on `PATH`; override with `FCC_STDLIB=/path/to/stdlib` if you have a non-standard layout. Re-run `make install` from `fc-lang` after pulling compiler updates.

See [`fc-lang/README.md`](https://github.com/stephen-swensen/fc-lang) (or `make help` in that repo) for full compiler-build options, including dev (`-O0`) builds and packaging-style installs (`PREFIX`, `DESTDIR`, `bindir`, `datadir`).

## Build and Run

The project uses a GNU Makefile (the same convention as `fc-lang`):

```bash
make                    # build the binary at ./build/<os>/wolf-fc
./run.sh                # build (if needed) and run
make check              # build (if needed) and run the regression suite
make dev                # clean rebuild at -O0 with debug symbols
make help               # list every target and variable
```

Build artifacts land in `./build/<os>/` (e.g. `build/linux/`, `build/windows/`) so a single source tree shared across two OSes — for example WSL Linux and MSYS2 on the same Windows box accessing the WSL filesystem via `\\wsl.localhost\...` — can hold both binaries without one stomping the other. `./run.sh` and `make check` use `make print-bin` to find the right binary for whichever OS they're running on.

### Installing system-wide

```bash
sudo make install                   # default PREFIX=/usr/local
make install PREFIX=$HOME/.local    # user-local (no sudo)
make uninstall                      # remove the binary + share/wolf-fc/ tree
```

`make install` copies the binary to `$(PREFIX)/bin/wolf-fc`. If `./data/*.WL6` is present at install time, it's also copied to `$(PREFIX)/share/wolf-fc/data/` — that's the location the installed binary falls back to when run from a directory without `./data/`.

### Options

| Flag | Effect |
|------|--------|
| `--no-dogs` | Skip spawning all dog enemies (for sensitive players). Works in both interactive and `--test` modes; may appear before or after `--test`. |
| `--level=N` | Skip the title / menu and drop straight into map N in playing phase. `N` is `0..59` (six episodes of ten maps). Handy for jumping to a specific boss fight — see table below. |
| `--difficulty=N` | Override the starting difficulty: `0` = Can I play Daddy, `1` = Don't Hurt Me, `2` = Bring 'Em On, `3` = I Am Death Incarnate (default). Combines with `--level`. |
| `--near-boss` | After the level loads, teleport the player to an open tile adjacent to the first boss enemy on the map, facing the boss. No-op on maps without a boss. Combine with `--level=N` to start a specific boss fight immediately. |
| `--near-goldkey` / `--near-silverkey` / `--near-gibs` | Same idea but for the first gold-key / silver-key / gibs pickup on the map. Handy for eyeballing HUD changes and the gibs-at-low-HP branch without playing through. First gibs map is `E1M2` (`--level=1 --near-gibs`). |
| `--cheat` | Pre-activate both Doom-style cheats (`IDDQD` god mode + `IDKFA` all-keys / all-weapons / full non-depleting ammo / locked score) from the very first frame. The gifts re-apply on every death while the IDKFA latch stays on. |
| `--max-scale=N` | Cap the auto-picked supersample factor at N (default 6, floor 2). Lower for older CPUs that stutter at the auto-pick; raise on high-end machines where 4K+ panels could put more rays to good use. See [Display pipeline](#display-pipeline) below. |

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

And the original game's TAB-held cheats (hold TAB, press another key). The original gated these behind a `-debugmode` command-line flag; we leave them always available:

| Combo | Effect |
|-------|--------|
| TAB + G | Toggle god mode (same flag as IDDQD, plain "God mode" banner) |
| TAB + I | Free items: heal to 100, +50 ammo (cap 99), bump weapon one tier, +100 000 score |
| TAB + N | Toggle no-clip (walk through walls, doors, enemies, static decorations) |
| TAB + E | End level (skip straight to the intermission screen) |
| TAB + H | Hurt self for 16 damage |

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
| `kill` | Instant-kill the player; transitions straight to the dying phase. Leaves `killer_active` false, so the death-cam swing is a no-op. |
| `killby:X,Y` | Like `kill`, but latches `(X, Y)` as the killer's world position so the dying-phase camera swing has a target to rotate toward. |
| `arrows` | Print every plane-1 ICONARROWS path-marker tile (`x,y` and dir 0..7) |
| `exittiles` | Print every plane-1 EXITTILE marker (`x,y`) on the current map — boss-map exits that fire the BJ-victory cutscene when stepped on |
| `pickups` | Print every live pickup sprite on the current map (`[idx] (tx,ty) kind=<name>`), filtering out static decorations. Enemy drops show up after the corpse lands. |
| `setlevel:N` | Load level N (0..59) and enter gp_playing |
| `setepisode:N` | Jump to the start of episode N (0..5) — level=N*10 |
| `setdifficulty:N` | Re-apply difficulty N (0..3) to the current level, re-running spawn filtering |
| `setphase:X` | Force phase: `title` / `menu` / `epmenu` / `diffmenu` / `savemenu` / `loadmenu` / `playing` / `viewscores` (View Scores entry into the high-scores screen) |
| `hs_qualify:S,L,E` | Drive the high-scores entry path with a synthetic `(score, level, episode)` triple — same as a real death routing through CheckHighScore. |
| `hs_name:STR` | Type a name into the high-scores edit buffer (only meaningful while the screen is in edit mode). Followed by `advance` to commit. |
| `hs_state` | Dump every row of the high-scores table + the current edit state. |
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

Wolf-fc depends only on the installed FC compiler (`fcc`) and stdlib — see [Installing the FC compiler](#installing-the-fc-compiler). Every other dependency — SDL2 bindings, the OPL2 emulator, the PNG writer — is vendored into this repo. All project modules are declared at the top level (no namespaces), so they're reachable from any file by qualified name without imports.

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

SDL2's role in wolf-fc is deliberately minimal — it's a host abstraction, not a rendering framework. Each frame, the engine draws into a `uint32[]` ARGB framebuffer entirely in FC, then uploads it as a single streaming texture via `SDL_UpdateTexture` + `SDL_RenderCopy` + `SDL_RenderPresent`; the scale-quality hint is pinned to `nearest` for crisp upscaling. The 2D renderer is never asked to draw geometry — no `SDL_RenderFillRect`, no per-sprite textures, no shaders. Audio is equally bare: `SDL_QueueAudio` receives raw S16 PCM that our own mixer produced (no `SDL_AudioCallback`, no `SDL_mixer`). Input is keyboard-only, driven by `SDL_PollEvent` against `SDL_KEYDOWN`/`SDL_KEYUP`. No `SDL_image`, `SDL_ttf`, `SDL_mixer`, or `SDL_net` — just core `SDL2`, linked dynamically.

### Display pipeline

Wolf-fc renders one ARGB frame per tick entirely in FC, then hands it to SDL2 as a single streaming texture. Two CPU buffers do the work:

- **`fb`** (`fb_w × 200`) — logical framebuffer for the HUD, menus, fonts, and low-resolution viewport overlays (banner messages, GET PSYCHED!). Stable layout — UI code never has to know about supersampling.
- **`dbuf`** (`screen_w × screen_h`, where `screen_w = scale × fb_w` and `screen_h = scale × 200`) — the supersampled buffer that walks out to SDL.

3D phases (playing / dying / bj_victory / death_cam) write the viewport directly into `dbuf` at full supersampled resolution; HUD work funnels through `fb`. Two compositor passes merge them at the end of the frame:

```
   raycaster.render_walls       ─┐
   billboards.render             ├─  high-res writes               dbuf
   player.render_weapon          │     (screen_w × screen_h)
   overlay.viewport_tint        ─┘
                                                                    fb
   hud.render                   ─┐                                  (fb_w × 200)
   hud.render_message            ├─  logical-resolution writes
   pics.render_get_psyched      ─┘
                                  ↓ overlay.composite_view_overlay
                                  ↓ overlay.composite_hud
                                  ↓ SDL_UpdateTexture (one ARGB texture)
   logical surface                screen_w × (screen_h × 1.2)        VGA pixel aspect
                                  ↓ SDL letterbox into drawable
   drawable                       out_w × out_h                      real panel pixels
```

Non-3D phases (title / main menu / intermission / endart / high scores) skip the dbuf intermediate: everything draws into `fb`, then `overlay.upscale_nx` paints the whole thing into `dbuf` in one pass.

**Hor+ widescreen.** `fb_w` is dynamic and the horizontal FOV scales with it (Hor+: same vertical FOV, more peripheral world; wall verticals stay perspective-correct). UI elements stay anchored in a 320-wide region centred inside the wider framebuffer.

**Two pickers in Main Menu → Change View** drive the geometry, side by side, with a four-line footer that prints the live numbers for every stage so you can see exactly how the choices map down to your monitor:

- **Aspect Ratio** — `Auto` queries the SDL display, computes `fb_w = round(320 × display_aspect / (4/3))`, and clamps to `[320, 640]` (even values only). Any aspect ratio works — ultrawide, vertical, exotic — not just the named presets. `Original (4:3)` pins `fb_w = 320`. `Widescreen (16:10)` pins 384. `Widescreen (16:9)` pins 428.
- **Scale Factor** — `Auto` picks the largest integer in `[2 .. max_scale]` (default `max_scale = 6`, override with `--max-scale=N`) that fits inside the actual pixel drawable in both axes after the 1.2× VGA-aspect stretch, so the texture matches the panel as closely as possible before SDL's downstream stretch. Or pin to a specific `2x .. 12x` if you want deterministic behaviour regardless of window size.

Both choices persist in `~/.wolf-fc/config` and apply on the fly without a restart. The auto pick re-runs on cross-monitor moves between different-DPI displays (Windows per-monitor v2) and on aspect-ratio changes (the binding axis differs at fb_w=320 vs 384 vs 428 against the same drawable).

The raycaster casts `screen_w` rays per frame, so a 16:10 panel at 1920×1200 in Auto sees ~5× the ray density of a fixed 320-column reference — more sample points per wall column means visibly less near-vertical edge stairstep and far-distance texture shimmer.

Reference points at native pixel resolutions in **Auto** (the aspect picker matches `fb_w` to the panel, so SDL's downstream stretch is minimal):

| Drawable    | Auto fb_w  | scale     | Texture     | Notes |
|-------------|------------|-----------|-------------|-------|
| 1280 × 720  | 428 (16:9) | 2         |  856 × 400  | small panel — supersampling capped by horizontal pixels |
| 1920 × 1080 | 428 (16:9) | 4         | 1712 × 800  | clean 16:9 fit |
| 1920 × 1200 | 384 (16:10)| 5         | 1920 × 1000 | perfect 1:1 to drawable |
| 2560 × 1440 | 428 (16:9) | 5         | 2140 × 1000 | horizontally bound |
| 3840 × 2160 | 428 (16:9) | 6 (clamp) | 2568 × 1200 | natural pick is 8; `--max-scale=8` to unlock |

**Render-side optimizations.** At supersample factor `N` the raycaster casts `N×` as many rays and writes `N²×` as many viewport pixels as a fixed-320 reference, so the 3D viewport is the hot path by a wide margin. Several layers of work conspire to keep it cheap:

- **DDA wall raycaster.** One ray per `dbuf` column. Door midplane test, push-wall ray-vs-AABB intersection, side-face dimming (Y-faces shaded 25% darker) are all folded into the per-column setup.
- **Tile-rasterized 16-column blocks.** Columns are processed in groups of 16 (one cache line of dwords on x86_64). Phase 1 runs the per-column DDA + texture setup for all 16 columns and stashes per-column state in stack-local arrays. Phase 2 walks the y-range and writes 16 adjacent dbuf positions per row, so per-pixel store traffic collapses from one cache line per write to one cache line per 16 writes.
- **Fast / edge band split.** Phase 2 partitions each block into three y-bands. The fast band runs only when every column in the block is active — the inner k-loop has zero per-pixel skip / range branches and gcc unrolls it cleanly. Edge bands above and below keep the full per-pixel tests for partial-coverage rows.
- **Pre-shaded column LUT.** Each column pre-shades all 64 source rows into a stack-local 64-entry LUT before the per-pixel loop, so the inner loop is a single `dbuf[…] = lut[tex_y]` table lookup — no shade math, no palette indirection, no `vs->raw` bounds check per pixel.
- **Pre-shaded `pal_dim`.** With distance shading off (the OG-faithful default), `shade` is exactly `1.0` (X-faces) or `0.75` (Y-faces) per column. We precompute `pal_dim = pal × 0.75` once per frame and the LUT setup picks the right palette directly, skipping ~64 `shade_color` calls per column. Distance shading on (Options → Shadow Depth > 0) keeps the original per-pixel path.
- **Sprite z-buffer.** The wall pass populates a `screen_w`-wide z-buffer of perpendicular distances; billboard sprites column-test against it so they clip correctly behind walls without per-pixel z work.
- **Pic cache.** `pics.draw` lazily decodes each VGAGRAPH chunk into ARGB once and caches the result, so HUD / menu / intermission frames after the first are flat memcpys.
- **Pre-decoded title backdrop.** `TITLEPIC` is decoded once at startup and every menu frame just copies it.
- **Conditional backbuffer clear.** SDL's letterbox / pillarbox bars only need to be drawn when the logical surface doesn't fully tile the drawable; the per-frame `SDL_RenderClear` is skipped otherwise (~33 MB/frame saved at 4K).

**Platform notes.** On native Windows, wolf-fc declares per-monitor v2 DPI awareness so the renderer reports real pixels (not OS-DPI-scaled coordinates). On Linux/X11 with fractional-scaling compositors (Cinnamon, GNOME), the X canvas is what SDL sees — typically a render-larger-then-downscale arrangement (e.g. 1920×1080 panel @ 150% reports as 2560×1440), and the compositor applies a final downscale invisible to clients. That free-supersampling path costs CPU but yields a smoother panel image; cap with `--max-scale` if it's too expensive. WSLg's XWayland reports its own client-area size and ignores Windows DPI hints — there's no SDL2 path that surfaces real-pixel resolution from inside a WSLg client.

### Audio pipeline

Wolf-fc generates one stereo audio batch per frame entirely in FC, then pushes it to SDL2 via `SDL_QueueAudio`. The output is **44.1 kHz signed 16-bit interleaved stereo** at 1024 frames per batch (~23 ms). No `SDL_AudioCallback`, no `SDL_mixer` — the main loop drives sample generation and decides when to produce.

Three format drivers in [`sound.fc`](sound.fc), each consuming bytes from a Wolf3D audio chunk and mixing additively into a shared `int32` buffer:

- **`imf`** (music) — id Music Format. A flat sequence of `(reg, val, delay)` events written to a YM3812 OPL2 chip at a 700 Hz tick rate. Loops the track at end-of-stream. Has a `volume` knob for level-end fade-out. Owns a dedicated chip so its register state never collides with SFX.
- **`adlib`** (SFX fallback) — id-Software AdLibSound chunks. A 23-byte header (length, priority, 16-byte instrument, block) followed by one F-number byte per 140 Hz tick. One voice on channel 0. Owns a separate OPL2 chip so SFX never disrupts the music chip. Used as the fallback for sounds that have no digitized version.
- **`digi`** (PCM SFX, preferred) — 8-bit unsigned PCM straight from the trailing pages of `VSWAP.WL6`, recorded at 7042 Hz, nearest-neighbor resampled to 44.1 kHz. Up to 4 simultaneous slots (matches the original Sound Blaster mixing). No chip involved.

Each `sfx.id` constant has both a `digi_slot[id]` and an `adlib_chunk[id]`; `sfx.trigger` prefers digi, falls through to AdLib if no digi exists for that ID. The two SFX paths use different chips, so a fast retrigger of an AdLib effect cleanly preempts itself without ever touching the music chip.

```
   mix_buf := 0                                 int32[2048]   stereo, ~23 ms
       ↓ imf.fill           music chip → mono, duplicated L = R
       ↓ adlib.fill         SFX chip   → mono, duplicated L = R
       ↓ digi.fill          4 slots    → per-slot pan → L, R independently
       ↓ mixer.soft_clip_to_int16                int16[2048]
       ↓ SDL_QueueAudio
   SDL device queue                             44.1 kHz, S16 stereo
```

`mix_buf` is `int32` so the three additive fills can sum freely without per-stage clipping starving later stages of headroom (digi, last in line, was the biggest loser before we widened the intermediate). The final soft-clip is a rational asymptotic curve — linear up to ±24000, then `y = knee + over × range / (range + over)` toward an asymptote at ±32767 — so a single source peak gets ~1.5 dB of compression and three sources peaking together still don't hard-clip. Mirrors how Sound Blaster hardware summed FM and PCM in the analog domain.

**Ticked event-driven generation.** The OPL2 chip in [`opl2.fc`](opl2.fc) runs at the output sample rate. Both `imf` and `adlib` route their per-sample work through one shared helper, `opl2.fill_ticked`, that advances a `tick_accum` counter every emitted sample and invokes the driver's `advance` closure once per event tick:

```
samples_per_tick = sample_rate / tick_rate
                 = 44100 / 700  =  63   IMF music
                 = 44100 / 140  = 315   AdLib SFX
```

So one chip sample → push to buf → maybe advance one event. The same loop body works at any chip / tick-rate combination, which is why both drivers reuse it unmodified.

**OPL2 emulator.** [`opl2.fc`](opl2.fc) is a from-scratch YM3812 emulator: 18 operators, 9 channels, 4 waveforms, ADSR envelopes, KSL/KSR, feedback FM, soft tremolo / vibrato. The pieces that audibly differentiate OPL2 from a generic FM synth — log-domain envelopes (linear in dB), EGT-controlled sustain release, fast key-scale rate, 256-entry log-sin table per quadrant — are modeled directly. The pieces Wolf3D doesn't use (rhythm mode, CSM, NTS) are skipped on purpose. Two independent chip instances run simultaneously, one for music and one for AdLib SFX, so triggering an effect never glitches the music's register state.

**Stereo and panning.** OPL2 is mono, so `fill_ticked` duplicates each generated sample to both channels. Digi slots carry per-slot `gain_l` / `gain_r` derived from the pan parameter and add into L and R independently. `sfx.trigger_at` projects the source-to-player vector onto the camera-plane axis to compute pan, so an enemy visible on the right of the screen pans right — same projection the raycaster uses to place its sprite, by design.

**Slot management.**

- **AdLib SFX** runs one chunk at a time on its dedicated chip. New triggers honour an `SD_PlaySound`-style priority gate: a strictly lower priority is dropped, equal-or-greater preempts. So an incidental wall bump can't trample an in-flight pickup confirmation, but cross→cross retriggers restart audibly.
- **Digi** has 4 slots. Slot selection is: (1) if the same `sound_num` is already playing in any slot, rewind that slot in place and update its pan — no overlap, no stacking; (2) otherwise pick the first idle slot; (3) otherwise steal slot 0. The dedup in step 1 keeps held-down wall-bump retriggers from burning through all four slots in a few hundred ms — that used to disconnect the SDL queue stream entirely on PulseAudio backends.

**Loudness alignment.** Digi's `pcm_scale = 172` is chosen so a centered 8-bit PCM peak hits ~±22000 in `mix_buf` — the same scale OPL2's `sample` function emits at full envelope. Music, AdLib SFX, and digi therefore sit at roughly equal hardware-mixer loudness without any explicit gain matching, mirroring what the original Sound Blaster delivered through its analog mixer.

**Backpressure.** The main loop watches `SDL_GetQueuedAudioSize` and skips `mixer.fill_frame` entirely when the device queue already holds ≥ 8192 bytes (~46 ms of stereo). Peak depth is ~70 ms (one full fill above the threshold). Underruns on WASAPI / DirectSound are a momentary stutter; on PulseAudio / PipeWire they can disconnect the queue stream, so the threshold is tuned with a generous cushion. Music chunk swaps (phase change) destroy the old IMF player and load the new chunk without flushing the device queue — the in-flight samples drain naturally into the new track, which sounds cleaner than the underrun a hard flush causes.

### Customising the quit prompt

Selecting **QUIT** from the main menu opens an "are you sure?" modal with a randomly-rolled tagline (a nod to the original game's tongue-in-cheek confirm prompts). The built-in pool ships twenty-seven wholesome / playful taglines. To use your own pool, drop a newline-delimited file at `~/.wolf-fc/quit-prompts` — one tagline per line; blank lines and surrounding whitespace are ignored. A missing file or a file with no non-blank lines falls back to the built-in pool.

## License

The wolf-fc source code is licensed under the **BSD 2-Clause License** — see [`LICENSE`](LICENSE) for the full text. Copyright © 2026 Stephen Swensen.

Wolfenstein 3D itself has a complicated licensing history: the original id Software source release is under id's "Limited Use Software License" (educational use only, no commercial exploitation), and the widely-used port **Wolf4SDL** is under the **GPL v2**. Both are copyleft relative to BSD and would be incompatible with this project's license if we incorporated code from them. We've been careful to avoid that.

### What is original

All engine logic in this repo is written from scratch in FC. In particular:

- **Rendering** — the DDA raycaster, sprite renderer (`t_compshape` decoder), HUD, weapon overlay, dynamic-factor supersample upscaler, and distance shading are original implementations.
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
