# Wolf-FC TODO

## Open work

### Distribution

- **Windows-proper redistributable build.** Today the only Windows
  path is "install MSYS2 UCRT64, build/install from inside it" — a
  double-clicked `wolf-fc.exe` from Explorer fails because (a) the
  binary dynamically links MSYS2's `libSDL2-2.0.dll` + runtime DLLs
  that aren't on Windows's PATH, and (b) the baked install data path
  is relative to MSYS2's POSIX root. Minimum viable redistributable:
  bundle `SDL2.dll` + `libgcc_s_seh-1.dll` / `libwinpthread-1.dll` /
  etc. next to the exe, switch the data-dir lookup from compile-time
  bake-in to relocatable (`GetModuleFileNameW` on Windows,
  `/proc/self/exe` on Linux) + a `<exe-dir>/data` fallback, then ship
  a portable zip. A proper Inno Setup / NSIS installer with a Start
  Menu entry + uninstaller comes after that. README's "Windows: MSYS2
  is required" subsection spells out the situation today.

### Gameplay
### UI / Menus

Configurable input was retired 2026-04-28: wolf-fc keeps the hard-coded
WASD / arrows / Ctrl-fire / Space-use scheme. The OG's CONTROL +
CUSTOMIZE CONTROLS submenus and the `vg_c_control` / `vg_c_customize`
art lumps stay unused — `menu.fc` already hides those rows rather than
greying them. The `SHOOTDOORSND` chunk (the OG keybind-confirm beep)
is retired with this decision; if you ever wire keybind editing as a
deliberate enhancement, that sound lands with it.

- [x] **Quit Y/N confirmation prompt.** Triggered from the main-menu
  QUIT row (the only exit path today). Lands on a new `menu.nav.quit`
  sub-page which renders the underlying main menu plus a centred
  `draw_window` bevelled popup — closer to the original's `Confirm`
  helper than the article-window border the TODO originally proposed
  (`h_bottominfo` has "[<-] PAGE  ESC EXITS" baked in). Tagline rolled
  via `g->rng_face` (non-gameplay, not bit-stable in test mode — and
  test mode never reaches the menu anyway), stashed on `g->quit_prompt_idx`
  so it stays stable while the modal is up. Built-in pool of 14
  invented "for X and Y..." style prompts in `module quit_prompts`
  (no OG strings, copyleft-hygiene). Override pool:
  `~/.wolf-fc/quit-prompts`, one prompt per line; blank/whitespace-only
  lines and a missing/empty file all fall back to the built-in pool.
  Y commits + plays SHOOTSND; N / Esc cancel + play ESCPRESSEDSND
  (Enter / Space deliberately not synonyms for Y, matching the OG's
  strict-Y behaviour). `setphase:quitprompt` test command added for
  screenshot coverage. The four-piece `pics.draw_help_window` was
  lifted out of `endart_screen` (formerly private) along the way —
  the quit modal didn't end up using it, but it's a natural home for
  the helper now that there's a `pics` module.
### VGAGRAPH art not yet surfaced

Constants for every chunk exist in main.fc under the `vg_*` prefix (with
`(unused)` tags on unwired ones). Items here are ordered roughly by visibility
of the gap and implementation size. Many are grouped because they share a
lump and would naturally land together.

Retired 2026-04-28:
- `vg_order` (136) — shareware order screen; wolf-fc isn't shareware.
- `vg_error` (137) — generic error pic; current `stderr + exit` on fatal
  data-load failures is fine, no need to surface a pic.
- `vg_t_demo0..3` (139..142) — binary demo recordings in the OG format.
  Bit-identical replay is impossible because wolf-fc uses PCG32 instead
  of `US_RndT` (an accepted divergence per the 2026-04-17 fidelity
  audit), so the OG demos would desync within seconds. A homegrown
  recorder is feasible but not planned.
- `vg_t_helpart` (138) + `h_*` (3..9) — Read This! help screen. Dead
  data in the GOODTIMES build wolf-fc targets. The original DOS source
  wraps both the menu entry AND the `CP_ReadThis` function itself in
  `#ifndef GOODTIMES` (`WL_MENU.C:603-617, 85-95`); GT Interactive
  dropped the feature in the 1.4 v1.4 GT/ID/Activision re-release that
  became the Steam/GOG version. Wolf4sdl defaults to `GOODTIMES` for
  the same reason. The chunks remain in our WL6 VGAGRAPH but the
  GOODTIMES executable never references them — same situation as the
  retired SELECTWPNSND / HEARTBEATSND audio chunks.

- [x] **`vg_pg13` (chunk 88) — PG-13 parental-advisory splash.** New
  `game_phase.pg13` runs first at startup; any key advances to the title
  screen, with a 6 s auto-advance fallback (`pg13_screen.auto_advance_time`).
  Music is already running at this point — `font.music_chunk_for_phase`
  routes the splash to WONDERIN_MUS, same as the menu, so the pre-title
  sequence has continuous audio.
- [x] **`vg_credits` (89) — credits screen.** Surfaced via the title
  attract cycle: TITLE → CREDITS → HIGHSCORES → loop, holds matching
  the OG (`wl_main.cpp:1590-1610`: 15 / 10 / 10 s) with a 0.5 s
  black fade between sub-phases. The OG also plays a recorded demo
  at the tail of every cycle; wolf-fc skips that (no recorder) and
  loops straight back to TITLEPIC. Any key at any sub-phase still
  drops into the main menu; phase_timer resets on phase change so
  re-entry restarts from TITLEPIC.
- [x] **`vg_highscores` (90) — high-scores screen + high-score system.**
  New `game_phase.high_scores` runs the OG `DrawHighScores` layout:
  HIGHSCORESPIC banner over a black title stripe, `c_name`/`c_level`/
  `c_score` column headers, 7 rows of name + "E?/L?" + score on a
  BORDCOLOR backdrop. Persisted at `~/.wolf-fc/highscores` (text
  format), seeded with the OG defaults (`id software-'92` etc.) on
  first launch. Insert / qualify / tie-break logic ports
  `CheckHighScore`: strictly-better score qualifies, tie on score
  needs higher `completed` to bump. The qualifying row enters an
  inline name editor (A-Z / 0-9 / Space; Enter or Esc commit).
  Reachable from three sites — death (replaces the old game-over
  placeholder), endart article exit (matches Victory()'s embedded
  CheckHighScore), and the new VIEW SCORES main-menu entry.
- [x] **`vg_t_endart1`..`vg_t_endart6` (143..148) — per-episode ending text
  pages.** New `game_phase.endart` sits between `episode_end` and the
  next-episode advance. The article-markup parser handles the OG syntax
  (^P pages, ^Cnn colors, ^Bx,y,w,h fills, ^Lyyy,xxx jumps, ^>, ^Gy,x,p
  graphics with margin reflow, ^Tx,y,p,t timed pics treated as ^G,
  ^; comments) and word-wraps the text inside the four-piece help-window
  border (h_topwindow / h_leftwindow / h_rightwindow / h_bottominfo).
  Music continues with URAHERO_MUS across episode_end → endart → next.
- [x] **Menu art lump (10..42) — replace text menus with original graphics.**
  `menu.fc` now blits the OG cursor (`c_cursor1`/`2`, blinking at 3.5 Hz),
  the difficulty face cards (`c_baby`/`c_easy`/`c_normal`/`c_hard`), the
  episode cards (`c_episode1..6`), the load/save header pics
  (`c_loadgame`/`c_savegame`), and the SOUND submenu's section headers
  (`c_fx_title`/`c_music_title`). Submenus the port doesn't support
  (Control / Customize / Read This!) are hidden rather than greyed;
  the per-row selected / not-selected backdrops
  (`c_selected`/`c_notselected`) aren't used since the framed box plus
  cursor reads cleanly without them. CHANGE VIEW + VIEW SCORES are
  wired as their own submenus.
### Sound effects not yet triggered

Wolf3D enum IDs (0..86 per `audiowl6.h`) that the original triggered but
wolf-fc still doesn't. To wire one up, add an `id.*` entry in `sfx.fc`,
bump `count`, extend the `digi_slot` / `adlib_chunk` tables, and call
`sfx.trigger`.

Audited 2026-04-25 against wolf4sdl + id's original DOS source. AUDIOT
contains roughly a dozen additional chunks that look like fidelity gaps
(SELECTWPNSND, HEARTBEATSND, GAMEOVERSND, WALK1/2SND, etc.) but are dead
data — never called from any original-game source path. They've been
retired from this list; if you ever want to wire one as a deliberate
enhancement, add it back and flag it as a divergence.

- [x] **`MOVEGUN2SND` (4) — SOUND-submenu commit beep.** Wired as
  `sfx.id.move_gun2` (chunk 4, AdLib only). Plays on Enter inside the
  SOUND submenu when the player toggles a row. Other menus drilling
  into a submenu still fire SHOOTSND.
- [x] **`PLAYERDEATHSND` (9) — BJ death scream.** Wired as
  `sfx.id.player_death`, fired from `damage_player` on the lethal
  hit (`combat.fc`). AdLib-only — PLAYERDEATHSND has no entry in
  the WL6 `wolfdigimap[]`. Replaces the previous `death_1` (guard
  scream) trigger that BJ was sharing.
- [x] **`SHOOTDOORSND` (28) — keybind-rebind confirm.** Retired
  with the configurable-input decision (see UI / Menus section
  header). Despite the name, the OG plays it only at four sites
  inside `EnterCtrlData` (`wl_menu.cpp:2280, 2310, 2342, 2373`)
  in the keybind menu — wolf-fc has no keybind menu, so the chunk
  stays unused.

### Music tracks not yet surfaced

The per-level `songs[]` table uses 18 of the 27 available tracks. Audited
2026-04-25: only two more tracks are actually called from the original
Wolf3D source. The rest (HITLWLTZ, SALUTE, VICTORS, FUNKYOU) are dead
data despite their suggestive names — retired from this list.

- [x] **`music_nazi_nor` (7) — title-screen / intro music.** Split the
  `music_chunk_for_phase` arm: `title` plays NAZI_NOR (INTROSONG),
  `pg13` and `main_menu` keep WONDERIN. Demo / attract loop is the
  remaining unwired site, but that depends on a demo recorder which
  isn't planned.
- [x] **`music_roster` (23) — high-scores roll.** Wired via
  `font.music_chunk_for_phase`'s `high_scores` arm; the OG plays
  ROSTER_MUS at both CheckHighScore (post-death / post-victory) and
  CP_ViewScores (View Scores menu entry), all of which share the
  single `game_phase.high_scores` in wolf-fc.

### Fidelity

Survey passes happen ad-hoc, not on a schedule. The 2026-04-23 sweep
against `GunAttack` / `TakeDamage` / pickup handling / `UpdateFace` /
pacman-ghost chase closed eight divergences (see 2026-04-23 notes
below). When something feels off in play, audit the relevant subsystem
against id's source / wolf4sdl, log a finding here, and fix.

## Current State (2026-04-25)

### Build system migrated to GNU Makefile (2026-05-02)
Mirrors `fc-lang`'s Makefile shape: `make` (default `-O2` build), `make
dev` (clean rebuild at `-O0`), `make clean`, `make install` /
`make uninstall` with `PREFIX` / `DESTDIR` / `OPT` / `CC` overrides, and
`make check` (depends on the binary in the dep graph, so it always runs
against an up-to-date build — no manual cache-busting). Build artifacts
land in `./build/` (gitignored). `run.sh` shrank to a 5-line wrapper
around `make -s && exec ./build/wolf-fc`. WL6 data files now live in any
of three locations (env override > `./data/` > compile-time install
location at `$(PREFIX)/share/wolf-fc/data/`); the chosen path is baked
into the binary at build time via a generated `build/install_path.fc`,
and `make install` ships `./data/*.WL6` along with the binary when
present. `tests/run-tests.sh` lost its `/tmp/wolf-fc-bin` cache and now
shells out to `make -s` so stale-binary scenarios are handled by Make's
dep graph.

### Hor+ widescreen + Change View submenu (2026-04-25, part 2)
Replaced the locked 4:3 pipeline with a runtime-detected Hor+ widescreen
path. The 3D viewport now expands horizontally to match the display
aspect (same vertical FOV, more peripheral world); UI elements stay in a
320-wide region centered inside the wider framebuffer.
- **Framebuffer width is dynamic.** New `render_ctx.fb_w` / `fb_h` /
  `screen_w` / `ui_offset_x` fields replace the file-scope `game_w` /
  `screen_w` constants in the render path. `game_w` stays as the
  reference 320 so UI layout math (HUD, menus, font centring, save
  slots) keeps reading from a stable origin; everything offsets by
  `rc->ui_offset_x = (fb_w - 320) / 2`. The 2× upscaler, framebuffer
  alloc, and `zbuf` all scale to `fb_w`. Test mode forces `fb_w = 320`
  so the regression suite stays bit-stable.
- **FOV widens with the framebuffer.** New `game.plane_factor` replaces
  the `fov_factor` constant in the player / hitscan / spawn paths. At
  startup it's `0.66 * fb_w / 320` — 0.66 at 4:3 (OG), 0.792 at 16:10,
  0.88 at 16:9. Proportional widening keeps wall verticals
  perspective-correct. Death-cam camera teleport also uses
  `g->plane_factor` (was hardcoded 0.66 — would zoom 4× when the user
  switched back to 4:3 mid-session).
- **CHANGE VIEW main-menu submenu** (slot 3). Four rows: AUTO / ORIGINAL
  4:3 / WIDESCREEN 16:10 / WIDESCREEN 16:9. Selection persists in
  `~/.wolf-fc/config` as `view_mode 0..3`. Active mode is marked with
  an asterisk to the right of the label (left of the gun cursor would
  collide). Applies dynamically via `apply_view_mode`: frees and
  reallocs `fb` / `dbuf` / `zbuf` / `title_bg`, recreates the SDL
  texture at the new size, and rescales the live `plane_x` / `plane_y`
  vector so the player's heading is preserved across the resize.
- **OPTIONS main-menu submenu** (slot 2). NO DOGS toggle (mirrors
  `--no-dogs` CLI), SHADOW DEPTH slider (0=off, 1..5 cosmetic depth
  bands for distance shading; 0 is OG-faithful, ≥1 is an opt-in
  improvement), BJ SPEED + ENEMY SPEED sliders (20..200% in ±5%
  steps; BJ SPEED scales player movement only, ENEMY SPEED scales
  every enemy's patrol/chase speed *and* their firing rate — so
  the slider is a single linear-ish difficulty knob; 100% =
  OG-faithful), and a RESET row that restores all six toggles
  (No Dogs, Shadow Depth, BJ Speed, Enemy Speed — plus the SOUND
  submenu's Music + SFX) and the Change View selection to defaults.
  All persist through `config.snapshot` / `config.load`.
- **Per-episode ending text** (`game_phase.endart`) sits between
  episode_end and the main-menu return. Loads VGAGRAPH chunks
  143..148 (`vg_t_endart1..6`) and parses the OG article-markup
  syntax: `^P` page break, `^E` end-of-article, `^Cnn` color, `^Bx,y,w,h`
  fill, `^Lyyy,xxx` cursor jump, `^>` tab, `^Gy,x,p` graphic with
  margin reflow, `^Tx,y,p,t` timed pic (treated as `^G`), `^;` comment
  line. Word-wraps text inside the four-piece help-window border
  (`h_topwindow` / `h_leftwindow` / `h_rightwindow` /
  `h_bottominfo` — the top and bottom strips are stretched
  horizontally to span the wider viewport). Page nav: any forward key
  → next page (or exit-to-menu on the last page); Left / Up / PageUp →
  back; Esc → exit-to-menu (the OG-faithful "skip rest"). Music
  continues from episode_end (URAHERO_MUS) without a swap.
- **Title pic letterbox** is solid black (was an early "stretch with
  fizzle bands" experiment). The pic centers in the wider FB without
  distortion; menus draw on top inside the bevel-framed window.
- **Boss-floor TAB+E** routes through `episode_end.enter` directly
  instead of `bj_victory.enter`. The bj_victory cutscene needs the
  level's path-arrow tiles to walk BJ along; on TAB+E we don't have
  a fresh arrows scan and the dir defaults to `dir.nodir`, which
  used to stall the cutscene. The skip is debug-only and matches
  the test-mode `advance` shortcut.
- **All cutscene renderers centred** to the wider FB by adding
  `rc->ui_offset_x` to their pic/font draw coords (intermission,
  episode_end, death_cam taunt, bj_victory, endart, high_scores,
  pg13). HUD side panels fill `VIEWCOLOR` (palette 0x7f) outside
  the 320-wide HUD pic — was bright red (0x29 BORDCOLOR) before.
- **Inline save-name editor.** Save-slot rows on the SAVE GAME menu
  enter a name-edit mode on Enter (cursor blinks, text typing edits
  the slot label). Commit on Enter writes the slot with the typed
  name; Esc cancels back to the slot list without overwriting. Slot
  edit state (`save_menu_ctx.edit_buf` / `edit_len`) is scratch on
  the menu context.
- **Hidden floor-jump on episode picker.** Pressing 1..9 starts the
  selected episode at floor 1..9; 0 jumps to the bonus floor (level
  9 of the episode). Plays the same SHOOTSND as Enter so the press
  is acknowledged audibly. Debug helper for CLI parity with
  `--level=N`.
- **Removed final-victory screen.** OG WL6 has no all-six-cleared
  cutscene; episode 6 ends on its own endart text and returns to the
  main menu. `game_phase.victory` and `victory_screen` module
  removed; the `victory` test-phase alias points at `main_menu`.
- **27 new regression tests** (137 → 164). Coverage: pg13 splash,
  config round-trip (music/sfx/no-dogs/shadow/view-mode/bj-speed/enemy-speed persistence),
  endart per-page markup parsing, save-name editor, options-menu
  toggles, view-mode label rendering, plane-factor scaling at all
  four modes, post-resize plane-vector preservation.

### Intro / menu / episode-select sweep (2026-04-25)
Reworked the pre-game flow against the original Wolf3D layout. Constraints
that aren't supported (driver-selection radios, screen-size chooser,
keybind editor) are dropped rather than greyed; everything else lands on
OG art.
- **Signon screen skipped.** The OG had a `SIGNON.BIN` banner image
  linked into the EXE before the PG-13 splash (memory-check ritual,
  hardware probe). The asset isn't in WL6 data files — only in id's
  source release as `WOLFSRC/OBJ/SIGNON.OBJ` — so we don't have it on
  a typical Wolf-FC install. Recreating it from primitives looked
  amateur next to the painted original; we'd rather start at PG-13
  than fake the splash badly. Could be revisited if we add a loader
  for a user-supplied `SIGNON.BIN`.
- **PG-13 splash** (`game_phase.pg13`) is the first screen now. Fills
  the full 320x200 with palette index 0x82 (the warning-card cyan)
  and stamps `vg_pg13` at native size at (116, 68) so the pic's outer
  pixels blend into the fill — visually fills the screen. Matches
  wolf4sdl's PG13() exactly. Auto-advance after 6 s
  (`pg13_screen.auto_advance_time`) or skip on any keypress.
- **Music continuity**: NAZI_NOR_MUS (INTROSONG) plays through the
  PG-13 splash and the title screen — both phases share the same
  chunk so the swap logic no-ops on the transition and the music
  plays unbroken. `main_menu` switches to WONDERIN_MUS (MENUSONG).
- **Menu rendering rebuilt** in `menu.fc` with WL6 art: blinking
  `c_cursor1`/`2` gun cursor at 3.5 Hz on the selected row,
  `c_baby`/`c_easy`/`c_normal`/`c_hard` face cards on the difficulty
  picker, `c_episode1..6` cards on the episode picker, `c_loadgame`/
  `c_savegame` header pics on the save/load slot screens, and
  `c_fx_title`/`c_music_title` row-label pics on the SOUND submenu.
  All menus draw inside a 1-pixel framed box (palette-style border +
  fill) over the dimmed title art so rows stay readable.
- **Main menu reordered to OG layout** (NEW GAME / SOUND / LOAD GAME /
  SAVE GAME / BACK TO GAME / QUIT). RESUME GAME → BACK TO GAME (matches
  the original's "BACK TO DEMO/GAME" wording). SAVE GAME and BACK TO
  GAME are locked when there's no active game; up/down nav skips
  locked rows. Esc from playing now lands on BACK TO GAME (was 0/RESUME).
- **SOUND submenu** with two ON/OFF toggles: SOUND EFFECTS (gates
  `sfx.trigger_panned_gain` via the new `audio_ctx.sfx_on`) and MUSIC
  (existing `g->music_on`). The original's three driver dropdowns
  (PC speaker / AdLib / SoundBlaster radios) are folded into single
  toggles since wolf-fc always mixes AdLib + digi through one path.
- **Floor (map) picker dropped** from the menu. Was an early debug
  helper; the underlying support stays (`--level=N`, `--near-boss`
  CLI flags, `setlevel:N` test command) so test scripts and CLI flags
  are unaffected.
- **MOVEGUN2SND wired** as `sfx.id.move_gun2`. Fires on Enter inside
  the SOUND submenu (commit-a-setting beep). Other menu confirms still
  use SHOOTSND (drilling into a submenu).
- **Sound effects mute toggle** routes through `audio_ctx.sfx_on`,
  checked at the top of `trigger_panned_gain`. Both spatial and
  centered triggers honor it.
- New regression tests: `cli:setphase-pg13`, `cli:setphase-soundmenu`,
  `cli:pg13-auto-advances-to-title`, plus updated music routing tests
  (`music:title-plays-nazi-nor`, `music:pg13-plays-wonderin`). Test
  count: 138 → 140.

## Current State (2026-04-23)

### Fidelity sweep vs original GunAttack / TakeDamage / GetBonus / UpdateFace / T_Ghosts (2026-04-23)
- **Knife damage 0-15** (was 10-41): `hitscan.weapon_damage_roll` now
  rolls `rnd_byte >> 4` for the knife, matching the original's
  `US_RndT() >> 4`.
- **Gun damage formula rebuilt**: tile-Chebyshev distance (max of the
  per-axis tile deltas), three bands (<2 tiles: rnd/4; <4 tiles: rnd/6;
  else: miss roll `rnd/12 < dist` then rnd/6). Replaces the earlier
  four-band Euclidean-+-flat-floor formula that couldn't miss at long
  range and couldn't graze for 0 at close range.
- **"Can I Play Daddy" damage scaling**: `ai.damage_player` now does
  `dmg >> 2` when difficulty is baby, matching TakeDamage's
  `points >>= 2`. Sub-4 hits round to 0 and are silently dropped.
- **Enemy-dropped clip split off** as `pickups.item_kind.clip_small`
  (+4 ammo, the original's `bo_clip2`). Map-placed clips still give
  +8 via `pickups.item_kind.clip`. `drop_for_kind` returns `clip_small`
  for guard / officer / mutant; SS still drops the MG.
- **Extra-life (`bo_fullheal`) now gives +25 ammo + counts as a
  treasure pickup** in addition to the full heal and extra man. Missing
  treasure bump was lowering achievable %treasure on maps with 1-ups.
- **Gibs pickup wired up** (`pickups.item_kind.gibs`): plane-1 tiles 57
  and 61 (statinfo[34] / statinfo[38]) grant +1 HP only when the
  player is at ≤10 HP, refused otherwise. Plays the new SLURPIESND
  (`sfx.id.slurpie`, AdLib-only chunk 61). Also clears the
  `src_slurpie` sound TODO item.
- **Dead-face pic fixed**: health=0 now renders `FACE8APIC` (single
  dead-face, no A/B/C variants) instead of the old FACE7A "almost
  dead" frame. When the killing blow was a Schabbs needle, the face
  swaps to `MUTANTBJPIC` (original's `LastAttacker->obclass ==
  needleobj` branch). Uses a new `g->last_hit_needle` latch,
  reset on respawn / new game and cleared by any non-needle damage.
- **Pacman-ghost contact tightened**: the touch box is now per-axis
  MINACTORDIST (±0.25 tile) instead of ±1.0 tile, and a
  `touch_cooldown` refractory window (0.25 s) stands in for the
  original's "back up after bite" ClipMove step. Bite damage uses a
  single `rnd_byte >> 4` roll (0-15) per approach cycle. Net DPS is
  a lot closer to the original's feel. `touch_cooldown` saves and
  loads (back-compat default 0 on old slots).
- **Two new regression tests**: `pickup:dropped-clip-gives-4-ammo`
  and `proj:baby-difficulty-quarters-rocket-damage`. Updated
  `hitscan:knife-at-1-tile-damages-guard` expectation to hp=15
  (guard survives a single 0-15 roll at 25 HP).

### Recent additions (this session, part 7)
- Secret cheat chords (M+L+I and B+A+T) wired to the interactive loop.
  MLI refills health/ammo/keys/chaingun and zeros score; BAT shows a
  flavor message only. Both use the full original-game text (multi-line
  Commander Keen plug for BAT, the 100%-health/"eliminated your high
  score" lecture for MLI); `render_message` now wraps on '\n' and the
  banner buffer grew to 256 bytes. Cheat banners hold 6 s before the
  fade. No sound — matches the original. Latched so holding the chord
  fires the effect once. Test-mode commands `mli` / `bat` invoke the
  effects directly (no keyboard in headless mode). Music-toggle on M is
  suppressed when L+I are already held so finishing the MLI chord
  doesn't kill audio.
- Enemy projectiles: Schabbs (needle), Giftmacher / Fat (rocket), and
  fake Hitler (flame) now fire visible, dodgeable projectiles instead of
  hitscanning. Ports wolf4sdl's `T_SchabbThrow` / `T_GiftThrow` / `T_Launch`
  / `T_FakeFire` spawn paths + the `T_Projectile` tic step. Rockets
  explode with a short 3-frame boom anim (+MISSILEHITSND) on wall hit;
  flames dissipate silently. Damage rolls match `T_Projectile`: needle
  `20+(rnd>>3)`, rocket `30+(rnd>>3)`, flame `rnd>>3`. New `projectiles`
  test command dumps slot/kind/pos/angle for debugging. 5 new regression
  tests cover in-flight + damage for each kind.
- `--level=N` / `--difficulty=N` CLI flags drop the player straight into
  map N in playing phase, optionally at a non-default difficulty. Handy
  for boss-fight testing (E1 Hans=8, E2 Schabbs=18, E3 Hitler=28,
  E4 Giftmacher=38, E5 Gretel=48, E6 Fat=58). Also respected in `--test`
  mode so regression scripts can skip the `setlevel:` prefix.
- `--near-boss` CLI flag and in-game BOSS FIGHT menu entry teleport the
  player onto an open tile adjacent to the first boss on the map, facing
  it. Tries 2-tile offsets first (south/north/east/west priority) so
  projectile bosses still have room to spawn a visible projectile. No-op
  on maps without a boss. `teleport_near_boss` in main.fc runs during
  `start_new_game_here` (consumes `g->want_near_boss`) and on the CLI
  startup path after the level loads. New `menu_map` submenu shows
  MAP 1..10 plus BOSS FIGHT, sitting between the episode picker and the
  difficulty picker.
- Secret-floor intermission: exiting E?M10 (`level_num % 10 == 9`) now
  draws a "SECRET FLOOR / COMPLETED!" caption with a flat 15000-point
  bonus instead of the normal time/par/ratio tally. Matches wolf4sdl's
  `LevelCompleted` else-branch. The ticker is parked at stage 4 and the
  score is bumped inside `enter_intermission` so the advance / next-level
  wiring stays unchanged.
- BJ victory cutscene: stepping onto an EXITTILE (plane-1 tile 99,
  marked into `lv->exit_tiles` at level build) on a boss map enters
  a new `gp_bj_victory` phase where BJ spawns at the player and follows
  the level's path-arrow tiles for 6 tiles via a port of wolf4sdl's
  `SelectPathDir`, then jumps 4 frames, yells YEAHSND on frame 2, and
  auto-advances to the episode-end screen. Boss kill itself is now a
  regular enemy death (drops a gold key, plays the death animation,
  no level transition); the player has to grab the key and walk past
  the gold-key door to reach the EXITTILE — same flow as the original
  game. `update_dying_enemies` keeps the boss corpse animating during
  the cutscene's freeze so it lands on its `dead` pose instead of
  freeze-framing on the first die frame. Sprites from `SPR_BJ_W1..W4
  / JUMP1..4` (sprite_start + 408..415). Music routes to URAHERO_MUS
  for the cutscene and the following episode-end screen. `advance`
  test command skips the cutscene directly to episode_end for
  scripted tests; `endepisode` synthesizes the BJ trigger on a boss
  map by setting `next_level=true` (routed by update_phase_transitions).

### Recent additions (this session, part 6)
- Pre-intermission wait: pulling the elevator switch now
  freezes gameplay for `elevator_wait_time` (1.0s) while LEVELDONESND plays
  out in the world before the tally screen pops. `g->next_level_delay` ticks
  down in the gp_playing branch of `tick` and `update_phase_transitions` only
  enters intermission once it hits 0. `inter_lead_in` trimmed from 0.7s →
  0.25s since the ding already had a full second to breathe.
- Intermission advance is now any-key (IN_Ack), not just space. New
  `g->key_ack` / `g->key_ack_handled` pair is set on any KEYDOWN while in
  `gp_intermission`; the advance check at end of the main loop uses that
  latch instead of `key_space`. The `advance` test command is unchanged.
- Fixed: `enter_intermission` no longer pre-sets `key_ack_handled = true`.
  That was a carry-over of the old `key_space_handled` pattern, but with the
  new 1s pre-intermission freeze already absorbing any held elevator press,
  the pre-handled guard only served to swallow the player's first legitimate
  "advance" keypress. (Symptom: speed-through / advance felt like it needed
  two presses — the first was silently eaten.)
- Fixed: same anti-pattern removed from `enter_intermission` (`key_space_
  handled`), `enter_episode_end`, `enter_final_victory`, and `load_game_
  from_slot`. All four were defensively pre-setting `key_space_handled =
  true` on phase entry, which swallowed the first real space press after
  each transition. Symptom surfaced as "first space press after loading a
  save does nothing" (elevator switch, or re-opening a door). The held-key
  guard that old intermission code relied on is no longer needed: keydown
  events themselves latch the handled flag on the first usage.
- Pre-intermission fade-to-black: during the `elevator_wait_time` freeze
  (set when the elevator switch is pulled), `render_frame` now applies
  `viewport_tint_full` with `alpha = 1 - next_level_delay / elevator_wait_
  time`, so the screen darkens linearly toward black over the second before
  the tally screen appears. Gives immediate visual feedback that the press
  registered — without it the 1s freeze read like "nothing happened".
- Intermission cash-register feel, tightened to match the original:
  - HUD stays visible during the tally. `render_intermission` now only
    fills the 3D viewport (y < 160) with VIEWCOLOR and calls `render_hud`
    at the end, matching wolf4sdl's split-screen status bar.
  - Counters zip to target: `inter_time_rate` bumped to 400 units/s and
    `inter_ratio_rate` to 140 units/s so a 90s time bonus settles in
    ~0.23s and a 100% ratio in ~0.7s.
  - Tick sound cadence matches wolf4sdl: ENDBONUS1SND every 50 units for
    the time bonus (PAR_AMOUNT/10), every 10 units for the ratio rounds.
  - New `inter_pause_timer` + `inter_stage_gap = 0.35s` inserts a short
    hold after each end-of-stage sound before the next counter starts,
    so the just-finished value stays readable — analogue of wolf4sdl's
    `VW_WaitVBL(VBLWAIT) + while (SD_SoundPlaying) BJ_Breathe()` gap.
  - `finish_intermission_anim` also clears the pause timer on skip.
  - Fixed: the final ENDBONUS1SND tick and the end-of-stage ring sound no
    longer overlap. When the counter hits target we now freeze it, queue
    the ring sound behind a short `inter_end_sound_wait = 0.18s` delay,
    then let `inter_pause_timer` hold for the remainder of the gap before
    advancing. Also suppresses the tick that would land exactly on target
    (e.g. the 100 tick at 100% ratio), which otherwise dogpiled onto the
    ring. wolf4sdl got this implicitly from its `while (SD_SoundPlaying)`
    wait; we do it explicitly with the two timers.
  - Fixed: when the player doesn't beat par (`inter_target_timeleft == 0`),
    skip the time-bonus stage silently instead of firing an ENDBONUS2SND
    for a zero bonus. Matches wolf4sdl's `if (bonus)` guard around the
    whole time-bonus block. Before: 4 dings (1 bogus time + 3 ratios).
    After: 3 dings (ratio ends only).

### Recent additions (this session, part 5)
- Elevator switch now plays the classic LEVELDONESND (digi 30 / AdLib 40) when
  the player uses it — added `snd_level_done` + `snd_end_bonus1` / `_bonus2` /
  `snd_percent100` / `snd_no_bonus` entries to the sound tables.
- Classic Wolf3D intermission screen: L_GUYPIC/L_GUY2PIC breathing BJ portrait,
  L_APIC..L_ZPIC big-letter font and L_NUM0..9/L_COLON/L_PERCENT digits/punct
  from the LEVELEND lump, VIEWCOLOR (0x7F) background, "floor N completed"
  caption, BONUS / TIME / PAR lines, KILL/SECRET/TREASURE RATIO rows. New
  `write_lpic_text` + `write_lpic_number` helpers.
- Intermission count-up animation via `tick_intermission`: stage machine
  (time → kill % → secret % → treasure %), ticks ENDBONUS1SND every 10 units,
  plays PERCENT100SND / ENDBONUS2SND / NOBONUSSND at each stage end, updates
  live BONUS running total.
- `compute_level_bonus` now uses wolf4sdl's full 500/sec par bonus (previously
  divided by 10). Test `intermission:par-time-bonus-awarded` updated from
  score=4500 to score=45000 to match.
- First keypress during intermission animation skips to the final "everything
  shown" state; a second press advances to the next level. (Originally space-
  only; part 6 widened this to any key.) The `advance` test command collapses
  both steps into one so regression tests stay single-hop.

### Recent additions (this session, part 4)
- Esc from `gp_playing` now jumps straight to the main menu (no separate
  pause overlay); RESUME GAME is added as menu item 0 and is the default
  selection on entry. Up/down navigation skips locked rows so RESUME and
  SAVE GAME stay out of the way when no game is active.
- Phase-aware music: `music_chunk_for_phase` picks WONDERIN_MUS for
  title/menu, ENDLEVEL_MUS for intermission, URAHERO_MUS for per-episode
  victory, VICMARCH_MUS for final victory, and the per-level `songs[]`
  table for gameplay. Main loop tracks `current_music_chunk` and only
  reloads the IMF player on actual chunk changes.
- `music` test command prints the chunk for the current phase; 6 new
  regression tests assert routing on title / menu / gameplay /
  intermission / episode-end / final-victory.
- Removed `gp_paused` phase, `render_paused`, and `setphase:paused`.

### Recent additions (this session, part 3)
- Episode structure: 6 episodes × 10 levels. Elevator on level 8 triggers the
  per-episode victory screen; level 9 (secret) routes back via wolf4sdl's
  `ElevatorBackTo`; ALTELEVATORTILE (plane-0 area-0 tile under player's feet
  while pressing space at an elevator-21) sets the `went_secret` latch and
  jumps to the secret level.
- New phases `gp_episode_end` and `gp_victory`. Episode-end screen shows
  episode title + final score; final victory shown after episode 6.
- Episode picker menu (under NEW GAME) lets the user start at any of the six
  episodes; difficulty picker follows.
- Save/load system: 10 slots at `~/.wolf-fc/saves/slot_NN.sav`, text format.
  Persists level_num, difficulty, player state, doors, push-wall, sprite
  alive flags, and full enemy roster (pos/state/hp/dir/animation).
- Main menu gains LOAD GAME and SAVE GAME entries (SAVE GAME greyed without
  an active game). Save/load list screens show slot label + level code +
  score per slot.
- Test commands: `setepisode:N`, `save:N`, `load:N`, `listsaves`,
  `endepisode`, `setphase:{epmenu,savemenu,loadmenu}`. 14 new regression
  tests cover episode boundaries and save/load round-trips.

### Recent additions (this session, part 2)
- VGAGRAPH Huffman decoder: loads VGADICT/VGAHEAD/VGAGRAPH.WL6, decodes pictures and the picture-table (STRUCTPIC). Unplanar conversion for 4-plane VGA format.
- Wolf3D bitmap font rendering (variable-width, row-major glyph bitmaps).
- Real Wolf3D status bar: draws STATUSBARPIC with BJ face (health-driven), N_*PIC digits (score/level/lives/health/ammo), weapon icons, gold/silver key indicators.
- Title screen (TITLEPIC + blinking prompt).
- Main menu with keyboard nav: New Game, Sound toggle, Quit; difficulty sub-menu (Can I Play Daddy / Don't Hurt Me / Bring 'Em On / I Am Death Incarnate).
- Pause screen (Esc during play): dims the game frame + overlays "PAUSED".
- In-game message banner: used by cheat chords (IDDQD / IDKFA / MLI / BAT / noclip / free-items toggles), multi-line with fade-out. No pickup banner — the original game was silent on pickup aside from the SFX and score bump.
- Boss enemy kinds: Hans, Schabbs, Gretel, Giftmacher, Hitler (fake/real). Non-rotating sprites, boss HP (850 / 200 / 800), killing ends the level, drops gold key.
- Pacman ghosts (Blinky/Pinky/Clyde/Inky): non-rotating, chase-only, damages player on contact.
- Music fade-out on intermission / game-over via imf volume field routed through opl2.fill_ticked_vol.
- setdifficulty:N / setlevel:N / setphase:X test commands for scripted coverage.

### Recent additions (this session)
- Player death flow: red damage-flash overlay, dying-collapse tint, transition to restart-level (lives remaining) or game-over (lives exhausted).
- Game-over screen: black fullscreen, "GAME OVER" + final score + "PRESS SPACE" prompt. Space resets to level 0 with 3 lives.
- Level-restart on death: reloads current level from disk, resets health/ammo/weapon, preserves score + inventory.
- Intermission screen between levels: "FLOOR N COMPLETE", kill/secret/treasure percentages, time vs par, press-space prompt.
- Kill / secret / treasure counters: totals computed at build_level (live enemies, pushwall tiles, treasure pickups); current values mirrored on game.
- Par-time tracking: per-level seconds from wolf4sdl ParTimes table; level_time accumulates during gp_playing.
- Difficulty filter: `gd_baby..gd_hard` gate enemy tile tiers. Default is `gd_hard` (all enemies spawn; matches pre-change behavior).
- Spatial SFX panning: audio now stereo (2-channel). Enemy voices, gunfire, and death screams pan by source position relative to player facing. Player-originated sounds (gun, doors, pickups) stay centered.
- Pre-extracted sprite headers: VSWAP load pre-parses leftpix/rightpix/col_offsets for every sprite page, eliminating per-column bytes.u16 overhead in draw_sprite_col.

Working:
- DDA raycasting with textured walls from VSWAP.WL6, distance-based shading
- Per-level ceiling colors, flat floor color
- Doors: mid-tile rendering, animated open/close, door-frame (DOORWALL+2/+3) on adjacent walls, standard/locked/elevator textures, space-to-open
- Push-walls: plane-1 tile 98 detected at level build, space slides the wall 2 tiles in the push direction
- Billboard sprite rendering for static objects (tiles 23–72) and enemies, merged into one back-to-front draw list
  - Compressed t_compshape decoded including signed `newstart`
  - Z-buffer occlusion against walls
- Item pickups (walk-over): health (dog food/food/first-aid/extra life), ammo (clip/MG/chain), treasure (cross/chalice/bible/crown), gold/silver keys. Score tracked, extra life at 40 000.
- Elevator tile (21) loads the next level; level state rebuilt, music switched, player re-spawned at new start.
- IMF music via OPL2 emulator, per-level song table for episodes 1–3, M toggles music
- AdLib SFX + digitized PCM SFX (VSWAP sound pages, 7042 Hz → 44100 Hz nearest) mixing additively. Sound triggers for door/weapon/pickup/pain/alert/fire/death.
- Weapons: 4 slots (knife/pistol/MG/chain), fire rates per weapon, 1–4 key-select, procedural on-screen sprite with bob, Ctrl fires and decrements ammo
- Auto-weapon-restore: running out of ammo drops the player to the knife; picking up a clip / MG / chain swaps them back to their best firearm (wolf4sdl's `GiveAmmo` / `chosenweapon` behaviour)
- Player hitscan: ray from facing through FOV cone hits nearest enemy clear of walls; per-weapon damage roll, knife limited to 1.5-tile melee range. Scores kill on HP ≤ 0.
- Enemies (guard / officer / SS / dog / mutant) spawned from plane-1 tiles 108+, with difficulty tiers recognized
  - State machine: stand → chase on sight, path/patrol, shoot (burst), pain, die, dead (corpse sprite)
  - 8-directional billboard rendering with per-state frames (walk cycle, pain, shoot, die, dead)
  - Line-of-sight against tilemap (walls + not-fully-open doors block); 90° forward cone
  - Tile-center grid movement with chase / dodge selection (prefers axis toward player, random fallback, turnaround)
  - Enemy-fire distance-based hit chance / damage roll (SS are more accurate); dogs melee bite
  - Drops pickup on kill (guard/officer → clip, SS → machine gun, dog/mutant → nothing)
  - Live enemies block player movement with a "can always move away" exception (no mutual-deadlock when an enemy walks onto the player); corpses don't block
  - Mutants double-shot per shoot cycle (T_Shoot fires on frames 0 and 2); other enemies fire once mid-windup
  - Enemies open closed doors during chase/patrol — pause at the door tile, kick it open, then walk through (wolf4sdl T_Chase OpenDoor)
- Player firearm hits trigger HITENEMYSND on impact
- Static decorations block player and enemy movement per wolf4sdl `statinfo[].block` (barrels, tables, wells, lamps, columns, etc.); pickups, lights, gibs, and skeletons stay walk-through
- HUD: health/ammo/score/lives/floor-number digits, gold/silver key indicators
- Display: 320×200 → 2× upscale → 640×400 texture → `SDL_RenderSetLogicalSize(640,480)` for 4:3
- F11 fake-fullscreen toggle
- Player collision radius (prevents see-through-walls glitch)
- PNG screenshots via `s` key (→ `~/.wolf-fc/screenshots/ss_NNN.png`), with full game-state metadata in a `tEXt` chunk
- Doors stay open while the player's bbox overlaps the door tile (prevents a closing door from trapping a player straddling its edge) and reopen if the player re-enters mid-close
- Headless test mode (`--test`) with scripted commands for regression testing (see README.md). Includes `enemies`, `enemylist`, `arrows`, and `probe` (bbox tile diagnostics) dumps.
- Regression test suite at `tests/run-tests.sh` — 26 scripted scenarios covering spawn, pickups, doors (including straddle lockout and enemy-opened doors), static-sprite blocking, hitscan combat, enemy AI (ICONARROWS patrol redirection, areas+madenoise noise propagation), weapon auto-restore, and the probe command. Supports `-k NAME` filter and `-v` verbose.

## Gameplay

### Enemy polish
- [x] Difficulty-filtered spawning: gd_baby/gd_easy/gd_medium/gd_hard control which tile tiers spawn. Default gd_hard. No menu UI yet — settable via `--test setdifficulty:N` for scripted play.
- [x] Patrol path markers (plane-1 tiles 90..97 "ICONARROWS" that redirect T_Path).
- [x] FL_AMBUSH tile (106) handling — enemies on that tile ignore noise and only wake on direct LOS.
- [x] Enemies opening doors as they walk into them (wolf4sdl's OpenDoor-from-T_Chase path).
- [x] Areas + madenoise: firing a gun (or landing a knife hit) wakes every non-AMBUSH enemy in the player's currently-connected area set (open-door reachable). Knife stealth preserved.
- [x] Bosses: Hans / Schabbs / Gretel / Giftmacher / Fat / Hitler-fake / Hitler as enemy kinds with boss HP / score + per-boss drops. Hans and Gretel drop a gold key for the EXITTILE-gated BJ-runs cutscene (gp_bj_victory); Schabbs / Gift / Fat / real Hitler end the episode via the death-cam cutscene (gp_death_cam). Sprite indices counted directly from wolf4sdl `wl_def.h` (non-SPEAR build); verified visually.
- [x] Boss spawn flags: FL_AMBUSH + dir=nodir for all seven bosses, matching wolf4sdl's SpawnBoss / SpawnSchabbs / etc. Stops a boss from auto-waking on area noise while his door is closed, and lets forward-cone LOS see the player in the doorway.
- [x] **Death-cam cutscene** for Schabbs / Giftmacher / Fat / real Hitler — the four bosses that end the episode on kill rather than via the EXITTILE flow. New `gp_death_cam` phase with six sub-phases: hold on final death frame (1.43s), dissolve viewport to black over 1.0s (reuses `dissolve_stipple`'s spatial-hash pattern, driven by a 0..1 `dc_fade`), "Let's see you in hell!" taunt card, wait for space or 4.3s, camera teleport to frame the corpse at ≥1.25 tiles along the kill-direction ray (with wall-clip back-off), dissolve back in, replay death animation, hand off to intermission. HUD stays visible throughout.
- [x] Pacman ghosts: Blinky/Pinky/Clyde/Inky spawn from plane-1 tiles 224..227 (found on E3M10 = level 29), chase player, touch damage. Sprite indices 288..295 verified visually.
- [x] Mutant-specific double-shot pattern (they fire twice per shoot cycle in wolf4sdl).
- [x] Enemy projectile attacks: Schabbs syringe (`pk_needle`), Giftmacher / Fat rocket (`pk_rocket`, with boom on wall hit), fake Hitler flame (`pk_fire`). Ported from wolf4sdl's T_SchabbThrow / T_GiftThrow / T_Launch / T_FakeFire + T_Projectile. Damage rolls match the original (20-51 / 30-61 / 0-31). Rockets fire MISSILEHITSND on wall impact; flames dissipate silently.
- [x] Mecha Hitler: the armored mech-suit stage of the E3M9 boss. Spawns from plane-1 tile 178 with 800-1200 HP, 3-bullet BOSSFIRESND bursts, MECHSTEPSND on walk frames 0 / 2. When his HP hits zero he plays a 3-frame die-anim (SCHEISTSND) and morphs the actor slot in place into `hitler` (sprite base 345) with the 500-900 HP tier from A_HitlerMorph; real Hitler's kill then routes through the regular death-cam cutscene. `--near-boss` excludes hitler_fake decoys so the teleport lands at the mech.

### Weapons and combat
- [x] Weapon-specific hit sounds (HITENEMYSND when a shot connects).
- [x] Verify MG/chain pickups are reachable on early levels (SS spawn on E1M3+ now tested via `setlevel:2 enemies` — SS drop MG, chain gun pickup from secret rooms).

### Game state / death flow
- [x] Player death when health ≤ 0: red damage flash + collapse tint, drop a life, transition to restart.
- [x] Game-over screen when lives exhausted (press space to restart).
- [x] Level-restart on death with lives remaining.
- [x] Kill / secret / treasure counters (built at level load, increment in damage_enemy / try_push_wall / check_pickups).
- [x] Death-cam swing: the dying-phase camera rotates the player's heading toward the killer's world position, as in the original. damage_player latches the attacker's (x, y) on the lethal hit; player.update_death_swing rotates dir/plane at 140 deg/s (shortest signed arc) until aligned, then idles for the rest of the dying hold. Projectile hits aim the swing at the projectile's position rather than the launcher, matching the original's behavior.

### Level progression
- [x] Par-time tracking per level (par_times[] from wolf4sdl, seconds).
- [x] Intermission screen between levels (kill/secret/treasure percentages, time vs par, press space to continue).
- [x] Full episode structure (6 episodes × 10 levels) with per-episode victory screen, secret-level routing (ALTELEVATORTILE → level 9, level 9 → ElevatorBackTo), and final victory after episode 6.
- [x] Per-episode music table for episodes 4–6 — songs[] table matches wolf4sdl: Wolf3D's six episodes share the three music sets, so the "duplication" is correct.
- [x] Bonus score calculations: par-beaten bonus (500 pts per unused 10s) + 10000 pts each for 100% kills / secrets / treasures. Applied when entering intermission, reflected in score line.

### Fidelity audit findings (2026-04-17)
Cross-referenced against wolf4sdl. See the 2026-04-17 chat session for details.
- [x] Gate `advance_enemy_move` door-opening on kind — dogs / fake-Hitlers / pacman ghosts used CHECKDIAG in the original and treat doors as walls.
- [x] **HP scaling by difficulty** — `hp_for_kind` now takes difficulty; mutant/fake-Hitler/all bosses/mecha Hitler scale per wolf4sdl's `starthitpoints[4][NUMENEMIES]`. Grunts and dogs stay constant as in the original.
- [x] **Dog bite damage off-by-one** — dropped the `+1` in `enemy_bite_player`, roll is now `rnd_byte() >> 4` (0-15), matching wolf4sdl's `T_Bite`.
- [x] **Weapon fire rates** — `fire_rate` now 0.343 / 0.343 / 0.171 / 0.086 s, derived from `attackinfo[4][14]` (6 tics per frame at 70Hz, with per-weapon loop structure).
- [x] **Melee/contact ranges use per-axis boxes** — replaced the euclidean `enemy_melee_range` constant with wolf4sdl's per-axis checks: `enemy_bite_player` uses `|dx| ≤ 2 && |dy| ≤ 2` (T_Bite, wl_act2.cpp:2361-2372); the dog chase→jump transition uses `|dx| ≤ 1+step && |dy| ≤ 1+step` where `step = dog_chase_speed * dt` (T_DogChase, wl_act2.cpp:2097-2117); pacman ghost contact damage uses `|dx| ≤ 1 && |dy| ≤ 1` (ClipMove ghost branch, wl_state.cpp:730-746).
- [x] **RNG divergence accepted** — we use PCG32 (`random.pcg_random`, two channels off one seed) rather than the original's 256-byte `US_RndT` table. Distributions differ, so damage streaks / hit-miss patterns won't match the original frame-for-frame. Intentional: the PCG+channels setup is also an FC stdlib demo, and sequence-level fidelity here isn't worth the porting cost.
- [x] **Noise/area wake semantics verified** against `SightPlayer` (wl_state.cpp:1467) + `ConnectAreas` (wl_act1.cpp:319) + `DamageActor` (wl_state.cpp:1004) + `GunAttack`/`KnifeAttack` (wl_agent.cpp:1198/1232). All paths match: iterative fixed-point `connect_areas` computes the same transitive closure as `RecursiveConnect`; `area_connect[][]` ref-counting is bumped once on the opened→opening transition and decremented once on closing→closed (closing→opening re-entry correctly skips both, since the close never completed); `made_noise` resets at the top of tick before `update_enemies`, so intra-tick propagation (enemy-i pain raising noise → enemy-j wakes) matches wolf4sdl's sequential `DoActor` chain; knife stealth preserved (only firearms raise noise on fire, knife hits raise via `damage_enemy`'s unconditional set). AMBUSH tiles honor LOS-only wake correctly.
- [x] **T_Shoot hitchance / damage match the original** — `enemy_fire_at_player` now picks one of four base hitchances per wolf4sdl `T_Shoot` (wl_act2.cpp:2268): `256-dist*8` (still + hidden), `256-dist*16` (still + visible), `160-dist*8` (running + hidden), `160-dist*16` (running + visible). The discount-for-SS-and-Hans (`dist*2/3`) still applies. Added `g->player_running` (set in `update_player` from `key_shift + motion`) and `e->last_visible` (set in `build_billboards` via a forward-cone projection; mirrors FL_VISABLE from DrawScaleds). Damage roll drops the old `+1` bias so grazes can now land for 0, and the 20/256 hit-chance floor is removed.
- [x] **Reaction delay (`temp2`) added** — `enemy.reaction_timer` plus `reaction_delay_for_kind` give first-detection a per-kind countdown before the transition to chase fires (guards `1+rnd/4` tics, officers 2, mutants/SS `1+rnd/6`, dogs `1+rnd/8`, bosses/ghosts 1). Split the old wake into "detect → seed timer" (stand/path stays patrolling) and "timer expires → `wake_enemy`", so LOS lost mid-countdown still commits to the wake as in the original. `reaction_timer` round-trips through save slots (backward-compatible: missing token defaults to 0).

## Rendering

### HUD
- [x] BJ face with health-driven expressions (7 frames from healthy to near-dead; dying-phase locks to worst face).
- [x] Full Wolf3D status bar: STATUSBARPIC, number pics for all fields, weapon icon, key indicators.
- [x] Weapon icon on status bar.
- [x] BJ face idle animation: rolls A/B/C variant per wolf4sdl UpdateFace (`facecount += tics`, threshold from US_RndT(), faceframe = `US_RndT()>>6` clamped so 3→1, giving 0=25%/1=50%/2=25%). Drawn from `rng_face` (its own pcg channel) so HUD rendering doesn't disturb the enemy AI stream. Reset on damage so the new health row shows immediately.

## Audio

- [x] Spatial panning for SFX based on source angle relative to player — enemy voices/gunfire/death pan per-source; player-originated sounds stay centered. Stereo output via digi per-slot pan; adlib/imf duplicated to both channels.
- [x] Music fade-out on level end / game over: 0.5s ramp via imf player volume field.
- [x] Per-kind / per-boss vocal variety — wolf4sdl's FirstSighting + A_DeathScream behaviour. Guards now pick one of 8 random death screams; officers / SS / mutants / dogs have distinct death vocals (NEINSOVASSND / LEBENSND / AHHHGSND / DOGDEATHSND). Each boss has signature sighting + death lines (Gutentag/Mutti, Schabbs-ha/Mein Gott, Tot-hund/Hitler-ha, Die/Scheist, Die/Eva, Kein/Mein, Eine/Donner, Erlauben/Rose).

## Data Loading

### VGAGRAPH (unblocks face, menus, messages)
- [x] Huffman decoder for VGAGRAPH (VGADICT.WL6 + VGAHEAD.WL6 + VGAGRAPH.WL6).
- [x] Picture table (width/height per graphic): STRUCTPIC (chunk 0) decoded at load.
- [x] Asset extractors for: status-bar, BJ face frames, font, title / credits pics, digit pics, weapon icons.

## UI / Menus

- [x] Title screen (TITLEPIC + blinking "PRESS ANY KEY").
- [x] Main menu (new game / sound toggle / quit).
- [x] Difficulty selection submenu (Can I Play Daddy / Don't Hurt Me / Bring 'em On / I Am Death Incarnate).
- [x] Pause screen (Esc freezes + "PAUSED" overlay; Esc again returns to main menu).
- [x] In-game text messages: cheat-chord feedback (IDDQD / IDKFA / MLI / BAT / god / noclip / free-items). Fade-out timer, multi-line. Pickup banners were briefly wired in for debug / name-learning and removed for fidelity — the original game is silent on pickup aside from SFX.
- [x] Episode selection submenu (6 episodes, under NEW GAME).
- [x] Save Game / Load Game menus (10 slots, ~/.wolf-fc/saves/slot_NN.sav, text format).

## Code Quality

- [x] Pre-extract sprite column headers (leftpix/rightpix/col_offsets) at load — avoids repeated bytes.u16 reads per draw_sprite_col call. Column-level run-list is still parsed at draw time; further pre-decoding to flat pixel rows is possible but not yet needed.

## Reference

- **wolf4sdl** at `../wolf4sdl/` — reference C implementation, consult for data format details and rendering correctness (but don't copy code to avoid GPL)
- **fc-lang** at `../fc-lang/` — FC compiler source and stdlib (installed system-wide as `fcc` via `make install`; see README.md)
- Key wolf4sdl files:
  - `wl_draw.cpp` — raycaster (AsmRefresh, HitVertWall/Door, ScaleShape, DrawScaleds)
  - `wl_act1.cpp` — doors (MoveDoors, OpenDoor), PushWall
  - `wl_act2.cpp` — enemy AI state machines (SpawnStand/SpawnPatrol, T_Chase, T_Shoot)
  - `wl_game.cpp` — level setup (SetupGameLevel, ScanInfoPlane)
  - `wl_agent.cpp` — player actions (weapon firing, damage)
  - `wl_play.cpp` — game loop, songs[] table
  - `id_ca.cpp` — asset loading (Carmack/RLEW/Huffman)
  - `id_sd.cpp` — audio (IMF playback, SFX)
  - `id_pm.cpp` — VSWAP page manager
  - `id_vl.cpp` — display setup
  - `audiowl6.h` — sound/music chunk enums (LASTSOUND=87, STARTMUSIC=261)
  - `wl_def.h` — all game constants and structs
