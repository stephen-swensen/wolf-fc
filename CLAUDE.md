# CLAUDE.md

## Mission

Wolf-FC is a Wolfenstein 3D port that doubles as a flagship FC-language demo. Three constraints shape every decision:

1. **License-clean.** Wolf3D's id source and wolf4sdl are GPLv2. *Our* code must be an original implementation — no copy/paste, no line-for-line paraphrase, no comments naming GPL filenames or functions. Consult those references for *behavior*, then write your own. See feedback memories on copyleft hygiene.
2. **OG-faithful by default, modern where it pays off.** The baseline is the original WL6 / GOODTIMES build as shipped in id Software's DOS source release at `../wolf3d` — **"OG" always means that code, never wolf4sdl or any other port** (ports carry their own fixes and behavior changes). Gameplay, timing, scoring, AI, HUD layout, music/SFX cues all follow it. We deviate where it clearly helps in a modern context — Hor+ widescreen, supersampling, save slots, the Change View submenu — or via opt-in toggles that ship off-by-default (Mommy Mode, shading, etc.). Two rules: keep the OG path available and bit-stable (the regression suite pins test mode to OG geometry), and call out every divergence explicitly so a player or maintainer can tell what's faithful from what's ours.
3. **Depends on original data files.** `data/*.WL6` are user-supplied from a legitimate Wolf3D install and are *not* committed. The engine reads `.WL6` directly — no asset conversion step.

The project also serves as an end-to-end demo of FC: stdlib usage, modules, generics, C interop (SDL2, OPL2), manual memory management.

## Sibling Repositories

- **`../fc-lang/`** — FC compiler + stdlib. Treat as installed and up-to-date.
  - **`../fc-lang/spec/fc-spec.html`** — full language specification. Authoritative.
  - **`../fc-lang/spec/examples.fc`** — runnable, commented quick reference covering core features. **Read this in full at the start of every new session** to prime your understanding of FC syntax and semantics — don't rely on memory or training data.
  - **`../fc-lang/stdlib/`** — stdlib source (`io`, `math`, `sys`, `text`, `random`, `data`). Installed copy is what the build actually consumes.
  - **`../fc-lang/CLAUDE.md`** — compiler-internal notes; useful when an `fcc` bug needs investigating.

  Use the **installed** `fcc` (on `PATH`). Refresh after compiler changes with `cd ../fc-lang && sudo make install`. `run.sh` auto-derives the stdlib path; `FCC_STDLIB` overrides.

  `sdl2.fc`, `opl2.fc`, and `opl2_tables.fc` are vendored from `fc-lang/demos/shared/` so wolf-fc can evolve them independently. `opl2_tables.fc` is GENERATED — never hand-edit; regenerate with `tools/mk_opl2_tables.fc` (byte-identical twin of fc-lang's copy; see its header for the invocation — wolf-fc passes no namespace argument).

- **`../wolf3d/WOLFSRC/`** — id Software's original DOS source release. **This is what "OG" means throughout the project.** Behavior questions (AI, timing, scoring, sight/wake rules) are settled here; when it and a port disagree, this wins, and where the id code is undefined or buggy that shipped behavior is still the baseline — mirror it or flag the divergence explicitly. Files are CRLF; `grep`/`sed` with `tr -d '\r'`. Same license rules as below: read for behavior, never transcribe.
- **`../wolf4sdl/`** — later C port. Useful as a more readable reference for file formats and for confirming an obscure path, **not** a behavior baseline. GPLv2 — read, don't transcribe.

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
| `world.fc` | `game_phase`, `mommy`, `episode`, `score` | Cross-cutting game vocabulary: `enum game_phase` + companion module (`game_phase.code` for the diag log), `struct game`, `struct world`; episode structure + per-episode stat accounting; score/extra-life rules (`score.add` is the single score chokepoint — honors IDKFA lock + 40k extra-life). Also home to every closed-set `game`-field enum — `weapon`, `mommy_mode` (+ its `mommy` companion), `view_mode`, `ssaa_mode`, `bj_phase`, `dc_sub`, `inter_stage`, `hs_source` — so the structs that carry them and the subsystems that read them share one declaration without a module cycle. |
| `video.fc` | `video` | Display geometry: fb_w-from-aspect, supersample-scale pick, `render_ctx` alloc/resize, SSAA buffer rebind, on-the-fly `apply_view_mode`/`apply_scale_factor`/`apply_ssaa_mode`, texture rebuild; `struct video_state` (window/renderer/texture handles). |
| `sfx.fc` | `sfx` (nested `id`), `audio_thread` | `struct audio_ctx`; SFX trigger helpers + 76 sound IDs + `digi_slot` / `adlib_chunk` tables; the command-ring consumer (`audio_thread.drain`) + SDL audio callback. |
| `ui.fc` | `music`, `pics` (nested `id`), `font`, `hud` | Music track IDs + per-level `songs[]`, VGAGRAPH pic blitter, font, status bar, BJ face animation. |
| `save.fc` | `paths`, `diag`, `save`, `config`, `highscore` | `struct save_menu_ctx` / `highscore_ctx` + factories; save slot I/O, config file, high-score persistence, crash-surviving diag log. `paths` is a leaf module (shared with `overlay` / `flow` / `quit_prompts`). |
| `combat.fc` | `dir`, `enemies` (nested `ai`), `projectiles`, `hitscan` | Enemy data + AI + projectiles + player hitscan. |
| `level.fc` | `difficulty`, `tilemap`, `areas`, `spawn`, `doors`, `pushwall`, `pickups`, `level` | `struct level` + geometry, spawning, doors/pushwall, pickup collection, and the type-associated lifecycle module (`level.build`/`destroy`/`reload`/`reset_counters`). |
| `cutscenes.fc` | `bj_victory`, `death_cam`, `intermission`, `episode_end`, `endart_screen`, `pg13_screen`, `high_scores_screen`, `title_screen` | Per-phase state machines + renderers. `endart_screen` parses the OG article-markup language. |
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
- **320×200 raycaster shimmer is inherent.** Even Steam/DOSBox has it. Don't chase it as a bug; the mitigations are supersampling (`rc.scale`) for ray density and 2× SSAA (`g.ssaa_mode`) for edge AA after the raycast.
- **Vertical projection scale comes from horizontal viewport width, not viewport height.** The OG's `heightnumerator` works out to a focal length of `viewwidth · facedist` (≈ 218.75 logical px at fb_w=320), so a 1-tile object at perpendicular distance 1 projects to ~218 px vertically — taller than the 160-row 3D viewport, which is why walls fill the screen up close. Both the raycaster (`line_h`) and world billboards (`spr_h`/`spr_w`) compute `focal_px = vbuf_w / (2·plane_factor)` and divide by perp distance / ty. Don't substitute `view_render_h` here — that flattens the world to ~73 % of the OG's vertical aspect (squat-and-wide doors). Weapon and death-cam sprites are HUD-style fill-viewport overlays and *do* track `view_render_h`; they aren't perspective-projected.
- **OG WL6 is GOODTIMES.** Features inside `#ifndef GOODTIMES` (e.g. the "Read This!" menu entry) are dead in our target — don't wire them as "fidelity gaps".
- **Enemies stutter-step on purpose.** The walk cycle has hold beats after poses 1 and 3 (chase 10·3·8·10·3·8 tics, patrol 20·5·15·20·5·15) during which an actor neither moves nor rolls to fire; `enemy.walk_pause` is that state. It's the original's gait and what makes the nominal speeds come out right (chase covers 6/7 of nominal, patrol 7/8). Don't smooth it out, and don't "fix" a chasing guard that pauses for 3 tics.
- **Enemy wake-up follows the OG contract exactly** (audited against the id source 2026-09): an actor in `stand`/`path` first needs its area in `area_by_player` (flooded from the player's area through *open* doors; recomputed only on door open/close). Then an AMBUSH actor (plane-0 tile 106, and every boss) wakes on line-of-sight only; anyone else wakes on LOS *or* `g.made_noise`, a per-tick flag set by any gun shot (not the knife) and by any damage landing on an enemy (so a knife hit shouts). "Sight" = within 1.5 tiles on both axes with no facing or LOS test, else the cardinal facing half-plane (diagonal/nodir headings have none) plus a tile-stepping line trace that treats doors as open past a fixed-point threshold. Detection only seeds a per-kind reaction delay (guard 1+r/4, officer 2, SS/mutant 1+r/6, dog 1+r/8, boss 1 tic); the countdown commits — losing LOS doesn't cancel it — and the actor stays unaware (double damage) until it ends. Patrollers keep walking through the detection tick and the countdown but not through the walk cycle's hold beats, which don't look at all. Bosses spawn with a fixed cardinal facing (Hans/Schabbs/Fat/Mecha south, Gretel/Gift/Fake Hitler north), so one can be blind to a player entering from behind — E3M9 is the showcase: three of its five Fake Hitlers are reached from the south and stand there until you reach their row, get within 1.5 tiles, or shoot (not a regression; `mapdump` shows the approach sides). The alert vocal plays once per actor, including when a sleeping actor is shot and survives; boss lines are unpositioned. On top of all that sits the per-actor think gate (`enemy.active`): an actor that has never been on screen and whose area isn't player-connected skips its update entirely — no countdown, no chase step, no animation — so a guard woken by a shot through a doorway freezes in place if that door shuts before he's ever been drawn, and resumes only when a door reconnects the rooms. Patrollers spawn active; standing spawns, bosses, ghosts and the morphed Real Hitler earn it on first draw (our "drawn" = the raycaster touched one of the nine tiles around the actor this frame, the OG's own test, via `tilemap.mark_visible_tiles`). Any hit also marks the target active, since the OG can only hit drawn actors.
- **More OG rules that look like bugs but are the game** (2026-09-10 pass, all pinned by tests): an actor never steps to within a tile (per axis) of the player — it marks time against you (ghosts drain 2 HP per tic while held there), and the player can't close to within a tile of a live shootable actor either (ghosts aren't shootable, so they never block); blocking decorations own their whole tile. Without a line to you the chase selector treats a full reversal as the last resort, so a woken patroller walks on down its corridor. Schabbs, Giftmacher and Fat Face kite: inside four tiles every heading re-picked at a tile centre runs away. A shot lands 12 tics after the press; pistol and knife are one attack per press, the machine gun repeats every 12 tics and the chain gun every 6 only while the key is held; ammo coming back re-arms the *chosen* weapon, gated on the attack *frame index* being 0 — idle, or a cycle's first entry, so a clip grabbed in the first 6 tics of a knife swing re-arms at once and the rest of that swing plays out on the gun's frame table, while entries 1-3 defer the swap to the cycle's last frame (gating on "an attack is running" instead holds the knife for the whole swing); a pickup only switches you to a gun that beats your best. Items are collected from the sprite pass, not your tile: an item is taken when it's roughly half a tile to a tile ahead of you within half a tile of the view axis and its tile was ray-touched — never one you stand on or have beside you. The elevator switch only answers from its east or west face (E1M1's car has switch textures on three walls; only the east one works). Doors take 64 tics to slide and hold 300; use closes an open door (refused silently while anything is in the doorway, which also holds off the auto-close), and an actor waiting on a door keeps its heading and keeps the door's hold timer reset. Secret walls slide a tile per 128 tics with both cells solid, refuse with "no way" if the first cell holds anything, and stop after one tile if the second does; vacated cells join the player's area. Death sequences: officer 11-tic frames, mutant 7, bosses 10, everyone else 15; the vocal plays when the first die frame ends; Schabbs/Gift/Fat/Hitler stand upright for 141–150 tics first, and Schabbs and Real Hitler also scream at the kill. The extra-life threshold climbs and never rewinds. The damage flash is a tic counter fed by points taken (depth count/10+1 of six eighth-steps, draining one per tic), so god mode still flashes. TAB+E on a boss floor pays the bonus-floor 15000 and lands on the secret floor. The victory averages divide by a fixed eight floors. Per-frame order is doors → push-walls → player → actors. The Fake Hitler's flame moves only when its 6-tic frame rolls, by one *frame's* worth of travel — a slow, sidesteppable puff (0.82 tiles/s at the reference frame, see the next bullet), and a fresh flame gets a one-tic first frame so it steps (and can hit) almost at once.
- **Frame-rate-dependent OG rules are evaluated at the reference frame, one tic at 70 Hz** (`og_frame_tics` / `og_frame_dt` in `main.fc`; user decision 2026-09-12). The id loop spins until at least one tic has passed and waits for retrace, so on a fast enough machine every frame is one tic — the pace all its timings are written in and what id tuned for — while a slow 386 got several tics per frame and a different game in the few places the code reads the frame length instead of elapsed time. We want the ideal-machine game, identical on a 60 Hz and a 144 Hz display. The sites: the "player is running" hitchance gate (thrust summed per frame vs. 6000 — one tic means only the run key or strafe-and-walk counts), the enemy fire roll (per-tic chance with the OG's integer division, then scaled by the real elapsed tics as a fraction and rolled with `enemies.rnd_chance`, so the rate is exact at any frame rate), the ghost's stand-off drain (two points per tic, fraction banked in `enemy.ghost_drain`), and the flame's per-frame step. Elapsed-time rules (movement, timers, countdowns) use the real `dt` as before. When you meet another rule that reads `tics` as a frame length rather than a duration, evaluate it at `og_frame_tics`, never at the real frame — and never introduce a fixed-step accumulator for it (frame pacing is settled: vsync dt-snap). Patrollers and ghosts spawn at a random point in their first walk frame (one enemy-RNG draw per timed spawn, map order), so they don't march in lockstep — and so any change to the spawn roster shifts every later roll.
- **Combat rules that look like bugs but are the game:** an unaware (stand/path) actor takes double damage; a hitscan enemy whose destination tile is the player's, or adjacent with < ¼ tile to go, attacks with certainty (chance 300) every think; the player's aim window is *angular* (±8.3°, `hitscan.aim_half_tan`), so long shots are lenient on aim and gated by the distance miss roll instead; dogs lunge and bite inside a per-axis box with no line-of-sight check; the straight-chase detour scan only tries north → northwest → west; a woken standing guard keeps its facing as its "previous" heading so a noise-wake from behind makes it step forward first, while a sight-wake dodges freely (`enemy.first_attack`). Headings and half-taken steps survive pain and shoot states. All of it is covered by the combat sections of the regression suite.

## FC Reminders (project-specific)

Anything general about FC syntax/semantics: **read `../fc-lang/spec/examples.fc` (or `fc-spec.html`) instead of guessing or relying on memory.** The points below are wolf-fc-specific patterns or compiler corners we've actually hit:

- `let main = (args: str[]) ->` — must take `str[]`.
- `i32` literals auto-widen to `i64` in slice indices, comparisons, and call args. Only use the `i64` suffix when a binding's *type* needs to be i64 from the start (e.g. `let mut x = 0i64` used in later i64 arithmetic).
- `%f` interpolation requires an explicit width: `"%8.2f{expr}"`.
- `from` is a reserved word; don't use as a variable name.
- Module-level `let`s are limited to constant expressions. `alloc(...)!` is *not* a constant expression — keep buffers/caches on context structs, allocate in their factories. Array literals at module scope require literal lengths and matching element-type suffixes (e.g. `u8[n] { 0u8, 1u8, ... }`); when in doubt use `i32[n]` with plain int literals.
