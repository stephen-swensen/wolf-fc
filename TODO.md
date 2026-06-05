# Wolf-FC TODO

The Makefile bakes a `yy.mm.dd.SS` version derived from the latest
commit (see `print-version`), and fidelity sweeps happen ad-hoc when
something feels off in play — audit the relevant subsystem against id's
source / wolf4sdl, log a finding here if it turns into more than a
one-off fix, and patch.

## Open findings — 2026-05 audit

A multi-agent audit (2026-05-31) over the whole engine produced 76
confirmed findings. The license-hygiene, doc-comment, leak, and
clean-fail-hard fixes were applied (commits `38da848`, `1bf1c5c`); the
silent-continue bounds-guards were deliberately reverted (see Decisions
below). **[arch-1]** (enemy `last_visible` moved from the render path into
`ai.update_enemies`) was applied 2026-06-02 — despite its `[golden re-pin]`
tag it needed *no* golden churn: the regression scripts never land a
`rnd_byte` roll in the narrow hitchance gap (≤ dist·8 wide) the flag
opens, so no hit/miss outcome flipped. The flag is now exercised directly
via a new `vis=` column on `enemylist` and two `combat:enemy-sight`
assertions, so the behavior can't silently regress. **[level-1]** (count
the 1-UP in the treasure denominator, matching the original) was applied
2026-06-04 with its golden re-pin — only the three level-0 treasure
assertions churned (`x/22 → x/23`); the predicted churn on other levels
never materialized because those maps carry no 1-UP. **[cla-door-1]** was
investigated and retired as a non-bug (the door-LOS code is already
faithful to the original) — see Decisions below. What remains is open
work — each item is self-contained for a solo session, with the audit ID
in brackets for traceability. Tags:
**[golden re-pin]** = changes RNG draw order or pinned stats, so it must
update `tests/run-tests.sh` golden values in the same commit;
**[needs OG source]** = can't be settled as faithful-vs-divergent
without restoring the `../wolf3d` / `../wolf4sdl` reference trees.

### Fidelity / behavior

- **[player-2] respawn doesn't clear held input keys**
  (`main.fc:1442-1459`). `restart_current_level` calls `reset_for_life`
  but not `clear_input_keys` (unlike `advance_next_level:1419`), so a
  movement key held when the death animation ends walks the respawned
  player. Fix: add `player.clear_input_keys(g)` after `reset_for_life`.
  Test-safe.

- **[save-3] loading a save under a different view mode gives a wrong
  FOV** (`save.fc:727-732`). `from_slot` restores `plane_x/plane_y`
  verbatim, but the plane magnitude must equal the live `plane_factor`
  (view-mode/aspect-derived; `view_mode` is in config, not the slot).
  Fix: after restoring dir+plane, renormalize the plane to
  `|plane| == g->plane_factor`. No-op in test mode → test-safe.

- **[cutscenes-4] endart `^L` desyncs `st.py` from `st.rowon` for an
  out-of-range row** (`cutscenes.fc:1245-1250`). `st.rowon` is clamped
  but `st.py` is derived from the unclamped row → drawn baseline drifts
  (cosmetic; `font.draw_char` clips, no OOB). Fix: clamp `new_row` once,
  derive both fields from it. Endart-only, test-safe.

- **[opl2-1] additive-connection channel drops the modulator when the
  carrier env hits 'off'** (`opl2.fc:599`). The whole-channel early-out
  keys only on the carrier; in an additive channel a still-audible
  modulator is cut when the carrier finishes release. Fix: gate the
  early-out on connection mode and, in the additive branch, emit the
  modulator alone when the carrier is off. FM mode unchanged; audible
  only on rare additive instruments.

- **[cutscenes-3] zero-total ratio defaults disagree**
  (`cutscenes.fc:554-561` vs `main.fc:1369-1371`). A category with total
  0 shows 0% in the per-level intermission but contributes 100 to the
  episode-end average. Fix: pick one convention, apply in both
  `compute_ratio` and `record_level_for_episode`. **[needs OG source]**
  to confirm 0-vs-100. Test-safe (no pinned goldens).

- **[main-2] `add_score` can stack multiple 1-UP cues in one frame**
  (`main.fc:929-939`). Crossing >1 40k milestone in one add fires
  `bonus1up` per milestone (lives are correctly clamped). Cosmetic. Fix:
  grant silently in the loop, fire the cue once after if any granted.
  Test-safe (audio off in test mode).

- **[sdl2-1] `SDL_OpenAudioDevice` extern drops `const` on pointer
  params** (`sdl2.fc`). Harmless. Fix: optional doc-accuracy — `const
  any*`; verify the spec accepts `const any*` in an extern sig first.
  Skip if it risks churn. (The `SDL_QueueAudio` binding was removed when
  audio moved to a callback device.)

### Minor bugs

- **[main-5] `--level` launch doesn't pin `oldscore`**
  (`main.fc:2989-3000`), unlike `setlevel:` (`:2190`). No-op today (score
  is 0 at launch) but makes the death-rewind baseline well-defined. Fix:
  add `g->oldscore = g->score` in the `start_level` branch. Test-safe.

- **[main-4] `setlevel:`/`setepisode:` test commands leave
  `next_level`/episode latches stale** (`main.fc:2184-2215`). A script
  doing `endepisode` then `setlevel:N` bounces straight into intermission
  on the new level. Fix: in both branches clear `next_level=false;
  next_level_delay=0.0; went_secret=false; ep_recorded_current=false`
  (mirrors `advance_next_level`). Test-only; existing golden scripts
  don't pre-set these → test-safe.

- **[player-4] mid-attack weapon switch desyncs the attack-frame
  denominator** (`player.fc:619-625`). `fire_timer` is set from the
  firing weapon's `fire_rate`, but the per-frame
  `progress = 1 - fire_timer/fire_rate[g->weapon]` uses the *current*
  weapon, and the number keys (`main.fc:3895-3898`) switch with no timer
  gate → the animation freezes on a frame or jumps. Fix: snapshot the
  firing weapon's rate at fire time and use it as the denominator (covers
  the `setweapon` test path), or gate the keydown switch on
  `fire_timer <= 0.0`. Test-safe.

### Dead code — each needs a keep-or-delete call

- **[main-1] redundant 2nd `update_phase_transitions()` in the
  interactive loop** (`main.fc:3979`; `tick()` already calls it at
  `:1651`). A no-op today but a maintenance trap (a future
  non-phase-changing transition would run twice interactively, once per
  test tick). Fix: delete `:3979`; if the loop's music-refresh needs the
  `level_changed` bool, return it from `tick()` and read it at the single
  site. Interactive-only, test-safe.

- **[cla-dead-1] unused enemy fields** `move_remaining` / `dist_flat` /
  `dist_to_player` (`combat.fc:118-120`). Never read for behavior. Fix:
  drop `dist_flat`/`dist_to_player` + their `level.fc:1032-1033` inits
  (zero other refs). `move_remaining` is also serialized
  (`save.fc:606/807`) — removing it changes the save format (renumber
  later token indices), so version-bump the save or leave that one field.

- **[ui-3] unused HUD number-drawer cluster** `hud.draw_number` /
  `draw_digit` / `digit_glyph` + private `fill_rect`
  (`ui.fc:666-699, 720-724`). No callers. Fix: delete. Note the 3×5-font
  path (`char_glyph`/`draw_text` → `overlay.draw_centered_text`) is *also*
  currently unreachable — decide whether to keep it.

- **[ui-2] `pics.extend_pic_horizontally` is never called**
  (`ui.fc:452-474`), with a latent OOB (no upper `pic_x` clamp) if wired.
  Fix: delete; or if kept for future widescreen banners, add the upper
  clamp + a TODO that it's unwired.

- **[menu-6] `render_quit_modal` has an unused `ac` param**
  (`menu.fc:720`; call site `:769`). Fix: drop the param + arg (leave
  `render_main`'s `ac` — still used by `render_sound_list`). Only if no
  quit-modal SFX is planned.

### Performance — optional micro-opts (none per-frame-critical)

- **[png-1] CRC-32 is bit-by-bit, run ~3× over multi-MB IDAT per
  screenshot** (`png.fc:11-18`). One-frame hitch on the `s` key / `ss:`
  only, never per-frame. Fix: 256-entry CRC table (embed as a literal
  `uint32[256]` at module scope, or build into a context-struct factory
  — module lets can't compute it). Bit-identical output.

- **[render-4] per-frame `pal_dim` LUT (256 `shade_color` calls) built
  even when unused** (`render.fc:72-74`). When `shadow_depth>0` the
  `shade==0.75` branch is never taken, so the LUT is built-but-unread.
  Fix: keep the zeroed `let pal_dim` declaration (scope) but guard only
  the fill loop with `if shadow_floor == 1.0`. Default path unchanged,
  test-safe.

- **[player-5] `blocked_by_map` / `move_blocked_by_enemy` scan all
  entries after a hit** (`player.fc:156-165, 177-190`). Fix: `break`
  after `hit = true`. Identical result, test-safe.

- **[level-2] `near_boss`/`near_goldkey`/`near_silverkey`/`near_gibs`
  scan the full array after the first match** (`level.fc:790-851`).
  Debug-only entry points (CLI flags / BOSS FIGHT menu). Fix: `break`
  after capturing the tile, or leave as-is.

## Decisions / retirements

These document deliberate "won't do" calls so they don't get
re-proposed. Wolf-fc targets the GOODTIMES build of WL6 (the 1.4
GT/ID/Activision re-release that became the Steam/GOG version);
features the GOODTIMES executable never references are dead data, not
fidelity gaps.

### Door-LOS tile-coord transparency quirk is faithful ([cla-door-1], retired 2026-06-04)

The 2026-05 audit flagged the enemy line-of-sight door check
(`enemies.ai.check_line_clear`, `combat.fc`) as buggy: it compares an
*absolute* intercept (tile index in the integer part) against
`door_pos * 256.0`, whereas the raycaster (`render.fc`) compares only the
within-tile fraction. The proposed "fix" was to make the LOS check mirror
the renderer. We will NOT do this — the current code is already faithful,
and the renderer-vs-LOS mismatch is reproduced straight from the original.

The original ships **two different** door-occlusion routines with
**different** comparisons, and wolf-fc mirrors each:

- Raycaster (id `wl_draw.cpp`): `(word)yintbuf < doorposition[...]`. The
  `(word)` cast keeps only the low 16 bits — the within-tile fraction. →
  our renderer's `fr = wm − floor(wm); fr >= door_pos`.
- Sight check (id `CheckLine`, `wl_state.cpp`):
  `intercept = xfrac − xstep/2; if (intercept > doorposition[value])`.
  Here `intercept` is **not** masked to a word, so the tile coordinate
  leaks into the comparison (1/256-tile encoding puts `tile·256` inside
  `doorposition`'s 0..0xFFFF range). → our `intercept > door_pos * 256.0`.

The scaling is exact: id's `intercept₂₅₆ > doorposition₁₆` with
`intercept₂₅₆ = tile_units·256` and `doorposition₁₆ = door_pos·65536`
reduces to `tile_units > door_pos·256`, which is what the code computes;
the midline term (`yfrac` taken after the increment, minus `ystep/2`)
matches `CheckLine` as well. The visible consequence — low-tile-coord
doors become see-through at ~4% open while tile-63 doors stay opaque to
~25% — is a real quirk of id's `CheckLine`, not ours. The
`combat.fc` comment that documents it as "the original's quirk, not a
bug" is accurate and stays. Making the LOS check fractional would be a
*divergence* from the original, not a fix.

### Defensive bounds-guards on well-formed data (retired 2026-06-01)

We deliberately do NOT add guards that catch a bad index/length and then
silently `break` / `continue` / `clamp`. FC bounds-checks every slice
access and aborts loudly on OOB, so an out-of-bounds read on corrupt data
is *already* fail-hard with a `file:line` diagnostic — which is what we
want: a crash is a bug to fix in development; a swallowed one ships a
garbled sprite / wrong note / partial map silently. We have never
encountered a corrupt WL6 file. The 2026-05 audit's memory-safety guards
across the Carmack/RLEW/Huffman decoders, the digi page-walk and
sound-index, the sprite-column decode, IMF parsing, the elevator
stand-tile, the save enemy-count, and the get-psyched bar were applied
then reverted on this basis (commit `1bf1c5c`). Exceptions that DO
warrant a guard, because "no guard" is worse than a clean abort: a
`(cstr)`/alloca on an untrusted length (stack-overflow UB — guard with a
loud abort; see `save.fc` `check_num_field`), a NULL C-interop return
(segfault — guard with a clean error + exit; see the SDL `create_*`
checks), and a short read (silent zero-fill corruption — currently
unguarded; we trust well-formed local data).

### Configurable input (retired 2026-04-28)

Wolf-fc keeps the hard-coded WASD / arrows / Ctrl-fire / Space-use
scheme. The OG's CONTROL + CUSTOMIZE CONTROLS submenus and the
`vg_c_control` / `vg_c_customize` art lumps stay unused — `menu.fc`
hides those rows rather than greying them. The `SHOOTDOORSND` chunk
(the OG keybind-confirm beep) is retired with this decision; despite
the name, the OG plays it only at four sites inside `EnterCtrlData`
(`wl_menu.cpp:2280, 2310, 2342, 2373`) in the keybind menu — wolf-fc
has no keybind menu, so the chunk stays unused. If keybind editing is
ever wired as a deliberate enhancement, that sound lands with it.

### VGAGRAPH chunks (retired 2026-04-28)

- `vg_order` (136) — shareware order screen; wolf-fc isn't shareware.
- `vg_error` (137) — generic error pic; current `stderr + exit` on
  fatal data-load failures is fine, no need to surface a pic.
- `vg_t_demo0..3` (139..142) — binary demo recordings in the OG
  format. Bit-identical replay is impossible because wolf-fc uses
  PCG32 instead of `US_RndT` (an accepted divergence per the
  2026-04-17 fidelity audit), so the OG demos would desync within
  seconds. A homegrown recorder is feasible but not planned.
- `vg_t_helpart` (138) + `h_*` (3..9) — Read This! help screen. Dead
  data in the GOODTIMES build. The original DOS source wraps both the
  menu entry AND the `CP_ReadThis` function itself in `#ifndef
  GOODTIMES` (`WL_MENU.C:603-617, 85-95`).

### Sound effects (audited 2026-04-25)

AUDIOT contains roughly a dozen chunks that look like fidelity gaps
(SELECTWPNSND, HEARTBEATSND, GAMEOVERSND, WALK1/2SND, etc.) but are
dead data — never called from any original-game source path. If you
ever want to wire one as a deliberate enhancement, add it back and
flag it as a divergence.

### Music tracks (audited 2026-04-25)

The per-level `songs[]` table uses 18 of the 27 available tracks. Two
more (NAZI_NOR for title, ROSTER for high scores) are wired to their
correct phases. The remaining four (HITLWLTZ, SALUTE, VICTORS,
FUNKYOU) are dead data despite their suggestive names — never
referenced by any original Wolf3D code path.

## Reference

- **wolf4sdl** at `../wolf4sdl/` — reference C implementation, consult
  for data format details and rendering correctness (but don't copy
  code to avoid GPL).
- **wolf3d** at `../wolf3d/` — id's original DOS source (also GPL);
  authoritative for OG behavior over wolf4sdl when they disagree.
- **fc-lang** at `../fc-lang/` — FC compiler source and stdlib
  (installed system-wide as `fcc` via `make install`; see README.md).
- Key wolf4sdl files:
  - `wl_draw.cpp` — raycaster (AsmRefresh, HitVertWall/Door,
    ScaleShape, DrawScaleds)
  - `wl_act1.cpp` — doors (MoveDoors, OpenDoor), PushWall
  - `wl_act2.cpp` — enemy AI state machines (SpawnStand/SpawnPatrol,
    T_Chase, T_Shoot)
  - `wl_game.cpp` — level setup (SetupGameLevel, ScanInfoPlane)
  - `wl_agent.cpp` — player actions (weapon firing, damage)
  - `wl_play.cpp` — game loop, songs[] table
  - `id_ca.cpp` — asset loading (Carmack/RLEW/Huffman)
  - `id_sd.cpp` — audio (IMF playback, SFX)
  - `id_pm.cpp` — VSWAP page manager
  - `id_vl.cpp` — display setup
  - `audiowl6.h` — sound/music chunk enums (LASTSOUND=87,
    STARTMUSIC=261)
  - `wl_def.h` — all game constants and structs
