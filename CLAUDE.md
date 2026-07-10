# CLAUDE.md

## Mission

Wolf-FC is a Wolfenstein 3D port that doubles as a flagship FC-language demo. Three constraints shape every decision:

1. **License-clean.** Wolf3D's id source and wolf4sdl are GPLv2. *Our* code must be an original implementation — no copy/paste, no line-for-line paraphrase, no comments naming GPL filenames or functions. Consult those references for *behavior*, then write your own. See feedback memories on copyleft hygiene.
2. **OG-faithful by default, modern where it pays off.** The baseline is the original WL6 / GOODTIMES build: gameplay, timing, scoring, AI, HUD layout, music/SFX cues. We deviate where it clearly helps in a modern context — Hor+ widescreen, supersampling, save slots, the Change View submenu — or via opt-in toggles that ship off-by-default (Mommy Mode, shading, etc.). Two rules: keep the OG path available and bit-stable (the regression suite pins test mode to OG geometry), and call out every divergence explicitly so a player or maintainer can tell what's faithful from what's ours.
3. **Depends on original data files.** `data/*.WL6` are user-supplied from a legitimate Wolf3D install and are *not* committed. The engine reads `.WL6` directly — no asset conversion step.

The project also serves as an end-to-end demo of FC: stdlib usage, modules, generics, C interop (SDL2, OPL2), manual memory management.

## Sibling Repositories

- **`../fc-lang/`** — FC compiler + stdlib. Treat as installed and up-to-date.
  - **`../fc-lang/spec/fc-spec.html`** — full language specification. Authoritative.
  - **`../fc-lang/spec/examples.fc`** — runnable, commented quick reference covering core features. **Read this in full at the start of every new session** to prime your understanding of FC syntax and semantics — don't rely on memory or training data.
  - **`../fc-lang/stdlib/`** — stdlib source (`io`, `math`, `sys`, `text`, `random`, `data`). Installed copy is what the build actually consumes.
  - **`../fc-lang/CLAUDE.md`** — compiler-internal notes; useful when an `fcc` bug needs investigating.

  Use the **installed** `fcc` (on `PATH`). Refresh after compiler changes with `cd ../fc-lang && sudo make install`. `run.sh` auto-derives the stdlib path; `FCC_STDLIB` overrides.

  `sdl2.fc` and `opl2.fc` are vendored from `fc-lang/demos/shared/` so wolf-fc can evolve them independently.

- **`../wolf4sdl/`** — C reference port of Wolf3D. **Read for format details and gameplay correctness; don't transcribe.** GPLv2. See `reference_wolf3d_original_source.md` for the id DOS source at `../wolf3d` (same license rules).

## Build & Run

- **`make`** — Build `./build/<os>/wolf-fc[.exe]`. Incremental. Needs `fcc` on `PATH` and `libsdl2-dev`.
- **`make check`** — Build then run `tests/run-tests.sh`. Always runs against a fresh binary.
- **`make dev`** — `-O0` + debug symbols for gdb.
- **`make install` / `make uninstall`** — `$(PREFIX)/bin` + `$(PREFIX)/share/wolf-fc/data/`. Standard `PREFIX` / `DESTDIR`.
- **`./run.sh [args]`** — `make -s` then exec the binary.
- **`./run.sh --test <cmd>...`** — Headless scripted-play mode (see below).
- Press **`s`** in-game for a screenshot in `~/.wolf-fc/screenshots/`. See `README.md`.
- Data search order: `$WOLF_FC_DATA_DIR` → `./data/` → install location (`$(PREFIX)/share/wolf-fc/data`, baked in via `build/install_path.fc`). Startup banner prints `Data dir: <path>`.

## Headless Test Mode (`--test`)

Runs the engine with no window, no audio, deterministic RNG (both PCG32 streams seeded to 0). Args after `--test` are processed left-to-right with `dt = 1.0 / 35.0` per simulated tick. `ss:path.png` writes a PNG of the current frame with game-state in a tEXt chunk.

**Entry point:** `testmode.run_cmd` in `testmode.fc`. **User-facing reference:** `README.md`.

- **stderr vs stdout:** the `bad` helper writes malformed-arg errors to `stderr`; `state`, `facetile`, `ss:` go to `stdout`. Use `2>&1` if you need to see warnings in captured output.
- **Adding a command:** add an `else if` branch in `testmode.run_cmd`. Prefix commands use `text.starts_with` + `text.parse_i32`. Branches that produce text end in `void()` so all arms have matching types. If the command advances time, call `flow.tick(w, dt)`; otherwise don't. Document it in `README.md`.
- **Regression suite:** `tests/run-tests.sh`, with `assert_contains` / `assert_not_contains` / `assert_regex` helpers, grouped by `section "name"` headers. One assertion per test, failing for one clear reason. When you change AI / RNG-consuming logic expect golden-value churn — the failures are loud.
- **Probing landmarks** (level 0, default spawn `(29.5, 57.5)` facing east): door at `(32, 57)`, elevator switch at `(25, 46)`, push-wall at `(10, 13)`, first-aid at `(29, 24)`, cross at `(7, 14)`. The `probe` command dumps bbox tiles + nearby enemies — first stop for movement-blocker reports.

## Architecture: single sources of truth

The orchestrators live in `module flow` (`flow.fc`), plus the test-command dispatcher in `testmode.fc`. **Always extend them, never bypass them:**

- **`flow.tick(w, dt)`** — the *only* per-frame update path. Drives timer decay, then dispatches by `g.phase`: `playing` runs `player.update` → `doors.update` → `pushwall.update` → `player.update_weapon` → `enemies.ai.update_enemies` → `projectiles.update_all` → `pickups.check` → `hud.update_face`; cutscene phases run their own `.tick`. Always ends with `flow.update_phase_transitions`. Both the interactive loop and every tick-advancing `--test` command (`fwd`, `back`, `space`, `wait`, `fire`, …) go through this. Adding per-frame work anywhere else risks the "animation frozen in test mode" class of bug.
- **`flow.render_frame(w, vs, pal)`** — the *only* render path. Phase-dispatches to title / menu / playing / dying / intermission / bj_victory / death_cam / episode_end / endart / high_scores. The 's' screenshot key (via `flow.take_screenshot`), `ss:` test command, and main loop all call it. Add a new render layer here.
- **`testmode.run_cmd(w, arg, pal, dt)`** — the *only* test-mode command dispatcher.

`flow.fc` also owns the phase routing: `advance_next_level`, `restart_current_level`, `start_new_game_here`, `return_to_menu_post_episode`, `update_phase_transitions`. `oldscore` is captured on every level entry and consumed by `restart_current_level` on death-with-lives (matches OG's `gamestate.oldscore`). Level lifecycle (`level.build` / `level.destroy` / `level.reload` / `level.reset_counters`) lives in `level.fc` as the type-associated `module level`.

The `goto:X,Y` test command is intentionally *not* a tick — it teleports + calls `check_pickups` once.

### `world` — the grouped state handle

```fc
struct world =
    g: game*                              // player + input + session state
    lv: level*                            // tilemap, doors, sprites, enemies (rebuilt per level)
    lv_data: maps.level*                  // raw decoded level — kept for respawn / re-spawn lookups
    rc: render_ctx*                       // framebuffers, scale, billboards, pic cache, …
    ac: audio_ctx*                        // VSWAP digi, AUDIOT music/SFX, OPL2 chip, on/off flags
    sm: save_menu_ctx*                    // save/load slot list + edit scratch
    hs: highscore_ctx*                    // top-7 table + name-entry state
    vg: const vgagraph.vgagraph_file*     // VGAGRAPH chunks (fonts, HUD, BJ face, title, menus)
    font: font.info*                      // small UI font (VGAGRAPH chunk 1)
```

Orchestrators take `world*`; narrow functions take only the sub-contexts they touch, so dependencies are visible in signatures. Each ctx struct lives beside its owning subsystem (`game`/`world` in `world.fc`, `level` in `level.fc`, `render_ctx` in `render.fc`, `audio_ctx` in `sfx.fc`, menu ctxs in `save.fc`) with its factory in that file's module: `level.build`, `video.build_render_ctx`, `save.build_menu_ctx`, `highscore.build_ctx`; `level.destroy` runs on level transition (inside `level.reload`).

### No file-scope mutable state

Process-wide mutable state goes on a context struct (`game`, `level`, `render_ctx`, `audio_ctx`, `save_menu_ctx`, `highscore_ctx`, …), reachable through `world`. **Do not add `let mut` at file scope.** Applies to scratch buffers/caches, launch-time config (e.g. `game.mommy_mode` from `--mommy-mode`), and counters (`render_ctx.screenshot_slot`). True constants — fixed tables, tuning parameters, sound-ID enums — stay as file-level `let`s; the rule is about *mutability*, not file scope. This keeps dependencies explicit in function signatures and unlocks future multi-world scenarios (replay, split-screen).

### Hor+ widescreen + supersampling + SSAA

The 3D viewport and framebuffer adapt to display aspect ratio; UI stays 320-wide and centres in `ui_offset_x = (fb_w − 320) / 2`. The framebuffer is upscaled by an integer `rc.scale ∈ [2..6]` (picked at startup from `SDL_GetRendererOutputSize`) to a `screen_w × screen_h` dbuf, then nearest-neighbor stretched. Live geometry is on `render_ctx`: `fb_w`, `fb_h` (200, fixed), `scale`, `screen_w/h`, `view_render_h`, `drawable_w/h`, `ui_offset_x`. FOV-derived math reads `g.plane_factor`, not the constant `fov_factor`.

Optional 2× SSAA on the 3D viewport adds a fourth buffer, `ssaa_buf` (`2·screen_w × 2·view_render_h`, viewport only — HUD is bitmap art). The 3D pipeline (raycaster, billboards, weapon, death-cam sprite) writes through `vbuf` / `vzbuf` slices that alias either dbuf's top rows (SSAA off) or `ssaa_buf` / `ssaa_zbuf` (SSAA on); `video.rebind_vbuf` is the single chokepoint that flips the aliasing. After the 3D pass `overlay.ssaa_downsample` box-filters `ssaa_buf` into dbuf's viewport region (no-op when off); viewport tints / dissolves then operate on dbuf at the cheaper resolution. **When writing 3D-phase pixels, use `rc.vbuf` / `rc.vzbuf` / `rc.vbuf_w` / `rc.vbuf_h` — never `dbuf`/`zbuf`/`screen_w`/`view_render_h` directly.** Those still belong to overlay / HUD / composite code, which runs after the downsample.

Test mode pins `fb_w = 320`, `scale = 2`, SSAA off so the regression suite stays bit-stable. **When touching viewport geometry read `rc.fb_w`/`rc.scale`/`g.plane_factor`, never the file-scope constants.** The CHANGE VIEW menu calls `video.apply_view_mode` / `video.apply_scale_factor` / `video.apply_ssaa_mode` to re-alloc buffers, rescale the player's heading vector (`apply_view_mode` only), and recreate the SDL texture via `video.recreate_texture` when `screen_w/h` changed (`apply_ssaa_mode` doesn't touch the texture since `screen_w/h` are unchanged).

## Source Files

All project `.fc` sources live in `src/` (the Makefile's `SRCS_FC` prefixes them with `src/`). All project modules are top-level (no namespace), so they're reachable from anywhere by qualified name with no imports. Only stdlib (`std::`) imports appear in `main.fc`.

| File | Modules | What's in it |
|---|---|---|
| `sdl2.fc` | `sdl2` | SDL2 C-interop bindings (+ top-level `sdl_display_mode` mirror struct). |
| `opl2.fc` | `opl2` | YM3812 FM synth emulator + AdLib driver runner. |
| `png.fc` | `png` | Pure-FC PNG writer with optional tEXt. |
| `sound.fc` | `imf`, `adlib`, `digi`, `mixer`, `spsc`, `audio_q` | Wolf3D sound-format drivers + the lock-free ring the audio thread consumes. |
| `data.fc` | `bytes`, `palette`, `vswap`, `maps`, `vgagraph`, `audio`, `data_path` | `.WL6` loaders + decompressors (Carmack/RLEW/Huffman). |
| `world.fc` | `game_phase`, `episode`, `score` | Cross-cutting game vocabulary: `union game_phase` + companion module (`game_phase.code` for the diag log), `struct game`, `struct world`; episode structure + per-episode stat accounting; score/extra-life rules (`score.add` is the single score chokepoint — honors IDKFA lock + 40k extra-life). |
| `video.fc` | `video` | Display geometry: fb_w-from-aspect, supersample-scale pick, `render_ctx` alloc/resize, SSAA buffer rebind, on-the-fly `apply_view_mode`/`apply_scale_factor`/`apply_ssaa_mode`, texture rebuild; `struct video_state` (window/renderer/texture handles). |
| `sfx.fc` | `sfx` (nested `id`), `audio_thread` | `struct audio_ctx`; SFX trigger helpers + 73 sound IDs + `digi_slot` / `adlib_chunk` tables; the command-ring consumer (`audio_thread.drain`) + SDL audio callback. |
| `ui.fc` | `music`, `pics` (nested `id`), `font`, `hud` | Music track IDs + per-level `songs[]`, VGAGRAPH pic blitter, font, status bar, BJ face animation. |
| `save.fc` | `paths`, `diag`, `save`, `config`, `highscore` | `struct save_menu_ctx` / `highscore_ctx` + factories; save slot I/O, config file, high-score persistence, crash-surviving diag log. `paths` is a leaf module (shared with `overlay` / `flow` / `quit_prompts`). |
| `combat.fc` | `dir`, `enemies` (nested `ai`), `projectiles`, `hitscan` | Enemy data + AI + projectiles + player hitscan. |
| `level.fc` | `difficulty`, `tilemap`, `areas`, `spawn`, `doors`, `pushwall`, `pickups`, `level` | `struct level` + geometry, spawning, doors/pushwall, pickup collection, and the type-associated lifecycle module (`level.build`/`destroy`/`reload`/`reset_counters`). |
| `cutscenes.fc` | `bj_victory`, `death_cam` (nested `sub`), `intermission`, `episode_end`, `endart_screen`, `pg13_screen`, `high_scores_screen`, `title_screen` | Per-phase state machines + renderers. `endart_screen` parses the OG article-markup language. |
| `menu.fc` | `menu` (nested `nav`), `quit_prompts` | Main menu and submenus + the quit-confirm prompt pool. |
| `render.fc` | `raycaster`, `billboards`, `overlay` | `struct billboard` / `render_ctx`; DDA raycaster, billboard sort+draw, viewport tints/dissolve/upscale, 2× SSAA box-downsample, PNG screenshot encode. |
| `player.fc` | `player` (nested `cheats`) | Movement, collision, camera, weapon firing, MLI/BAT/IDDQD cheats, life/respawn helpers, `give_full_kit`. |
| `flow.fc` | `flow` | Orchestrators: `tick`, `render_frame`, phase routing, `take_screenshot` (see above). |
| `input.fc` | `input` | SDL event pump + every per-phase key binding (`input.handle_events`, called once per main-loop iteration). |
| `testmode.fc` | `testmode` | The `--test` command interpreter (`testmode.run_cmd`). |

### `main.fc` — entry point only

`main.fc` is the platform shell — nothing game-logic-shaped lives there anymore:

- **Program-wide constants** (the one legitimate use of entry-file top-level `let`s — bare names visible to every module): `game_w`/`game_h` (320×200, the UI grid), `view_h` (160, 3D viewport), `map_size` (64), `fov_factor` (`tan(36°)` ≈ 0.7269; the OG horizontal half-FOV), audio-callback sizing.
- **`main`** — CLI parsing, `.WL6` asset loading, `world` assembly, SDL window/renderer/texture/audio-device wiring, the interactive game-loop skeleton (dt snap, `input.handle_events`, `flow.tick`, music swap, frame-skip predicate, `flow.render_frame`, present), and the deliberately-minimal shutdown.

On `union game_phase` (world.fc): WL6 has no all-episodes-cleared cutscene; episode 6's endart returns to main menu via the high-scores screen. Death with no lives routes straight to `high_scores`.

### FC module rules that bite

- **Only the entry-point file (`main.fc`) may have top-level `let` bindings.** Top-level `struct`/`union`/`module` are allowed in *any* `.fc` file. Entry-file top-level `let`s are visible to every `global::` module — but reserve them for program-wide *constants*. Shared helpers belong in real (usually leaf) modules so the module DAG stays honest; entry-file scope sits outside the module graph, and parking helpers there is how main.fc once grew to 4.5k lines.
- **No circular module references.** When two modules mutually need each other, break the cycle properly: (a) parameterize the contract (e.g. `doors.update` takes `player_radius`), (b) extract the shared piece into a leaf module (`paths` in `save.fc`; `score`/`episode` in `world.fc`), or (c) move the function to its right altitude (`take_screenshot` orchestrates `render_frame`, so it lives in `flow`, not `overlay`).
- **Type-associated modules** (a module sharing a *struct*'s or *union*'s name, e.g. `struct level` + `module level`, `union game_phase` + `module game_phase`) work at top level, even across files. For unions, variant fall-through resolves through the companion: `game_phase.playing` still finds the variant with `module game_phase` present (fcc fix, 2026-07; previously union companions only worked module-nested).
- `free` is an FC builtin and can't be a module-member name — hence `level.destroy`.

## Key Data Formats (since wolf4sdl is GPL, document here)

- **VSWAP.WL6** — Header: 3 × u16 (`num_chunks=663`, `sprite_start=106`, `sound_start=542`), then offset/length tables, then page data. Walls (pages 0–105): 64×64 column-major 8-bit indexed. Sprites (106–541): `t_compshape` (see below). Sounds (542+): 8-bit unsigned PCM @ 7042 Hz.
- **Sprite (`t_compshape`)** — u16 `leftpix`, `rightpix`, then `(rightpix − leftpix + 1)` u16 column offsets. Each column is runs of `[endy, newstart, starty]` u16 triples (terminator `endy=0`). Pixel = `shape_bytes[newstart + row]`. **`newstart` is signed i16** — small sprites reach back into the header. Read as `(i64) (i16) bytes.u16(...)`.
- **Wall tile mapping** — tile `t` → horiz page `(t−1)*2`, vert page `(t−1)*2+1`. Door textures at pages `sprite_start − 8 .. sprite_start − 1`.
- **MAPHEAD.WL6** — u16 RLEW tag + 100 × i32 offsets into GAMEMAPS.
- **GAMEMAPS.WL6** — Per level: 3 × i32 plane offsets, 3 × u16 plane lengths, u16 width/height, char[16] name. Decompression: first u16 = expanded size, then Carmack expand, then RLEW expand (skip the first word).
- **Plane 0** — walls (1–63) + doors (90–101, even=vertical, odd=horizontal). **Plane 1** — objects (19–22=player spawn N/E/S/W, 23–72=statics, 98=pushwall, 108+=enemies).
- **AUDIOHED/AUDIOT** — u32 chunk offsets. Chunks 0–86=PC speaker, 87–173=AdLib, 174–260=digi, 261+=music (`STARTMUSIC=261`). Music: optional u16 length prefix, then 4-byte entries `[reg, val, delay_lo, delay_hi]` at 700 Hz tick rate.
- **Per-level music:** `songs[episode*10 + level]` → music enum (chunk = `261 + songs[i]`).
- **Per-level ceiling colors:** `ceil_table[episode*10 + level]` is a palette index.

## Wolf3D Gotchas

- **Display pipeline must match the OG path** — render at 320-wide × 200, upscale by `scale`, present via `SDL_RenderSetLogicalSize` for 4:3 letterboxing. Set `SDL_HINT_RENDER_SCALE_QUALITY="nearest"` **before** `SDL_CreateTexture`.
- **Doors block rays from their perpendicular side too.** A vertical door only renders its midpoint slice for X-step rays; a horizontal door only for Y-step. But a ray that arrives from the *wrong* axis must still be solid — otherwise the closed door leaks onto the wall behind it. The raycaster sets `door_side_hit` and renders that hit with DOORWALL+2/+3 (track-side) textures.
- **320×200 raycaster shimmer is inherent.** Even Steam/DOSBox has it. Don't chase it as a bug; the mitigations are supersampling (`rc.scale`) for ray density and 2× SSAA (`g.ssaa`) for edge AA after the raycast.
- **Vertical projection scale comes from horizontal viewport width, not viewport height.** The OG's `heightnumerator` works out to a focal length of `viewwidth · facedist` (≈ 218.75 logical px at fb_w=320), so a 1-tile object at perpendicular distance 1 projects to ~218 px vertically — taller than the 160-row 3D viewport, which is why walls fill the screen up close. Both the raycaster (`line_h`) and world billboards (`spr_h`/`spr_w`) compute `focal_px = vbuf_w / (2·plane_factor)` and divide by perp distance / ty. Don't substitute `view_render_h` here — that flattens the world to ~73 % of the OG's vertical aspect (squat-and-wide doors). Weapon and death-cam sprites are HUD-style fill-viewport overlays and *do* track `view_render_h`; they aren't perspective-projected.
- **OG WL6 is GOODTIMES.** Features inside `#ifndef GOODTIMES` (e.g. the "Read This!" menu entry) are dead in our target — don't wire them as "fidelity gaps".

## FC Reminders (project-specific)

Anything general about FC syntax/semantics: **read `../fc-lang/spec/examples.fc` (or `fc-spec.html`) instead of guessing or relying on memory.** The points below are wolf-fc-specific patterns or compiler corners we've actually hit:

- `let main = (args: str[]) ->` — must take `str[]`.
- `i32` literals auto-widen to `i64` in slice indices, comparisons, and call args. Only use the `i64` suffix when a binding's *type* needs to be i64 from the start (e.g. `let mut x = 0i64` used in later i64 arithmetic).
- `%f` interpolation requires an explicit width: `"%8.2f{expr}"`.
- `from` is a reserved word; don't use as a variable name.
- Module-level `let`s are limited to constant expressions. `alloc(...)!` is *not* a constant expression — keep buffers/caches on context structs, allocate in their factories. Array literals at module scope require literal lengths and matching element-type suffixes (e.g. `u8[n] { 0u8, 1u8, ... }`); when in doubt use `i32[n]` with plain int literals.
