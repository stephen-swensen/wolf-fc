# Wolf-FC TODO

The Makefile bakes a `yy.mm.dd.SS` version derived from the latest
commit (see `print-version`), and fidelity sweeps happen ad-hoc when
something feels off in play — audit the relevant subsystem against id's
source / wolf4sdl, log a finding here if it turns into more than a
one-off fix, and patch.

## Manual notes

* disabling wide screen mode (4:3 letterbox) shows more jitter/frame drops
  on Linux — but ONLY under fractional display scaling (Linux Mint @ 150%);
  at 100% it's gone. Measured: `work_ms` stays flat/slightly lower in 4:3
  (smaller texture, fewer pixels to scale), only `dbg_jitter_ms` climbs — so
  it's NOT the prep path (the original "SDL repaint / black-fill the bars
  ourselves" guess is disproven; filling bars wouldn't help). It's a
  compositor/present interaction: under fractional scaling a pillarboxed
  surface can't take the direct-scanout fast path the way a full-bleed
  widescreen surface can, forcing recomposition. Environmental, out of our
  hands → won't-fix.

## Open findings — 2026-05 audit (re-prioritized 2026-06-09 against id's source)

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
faithful to the original) — see Decisions below.

**2026-06-09 recheck.** The original audit ran *without* the OG reference
tree. It has since been restored at `../wolf3d/WOLFSRC` (id's DOS source;
wolf4sdl is currently absent, but id's source is authoritative anyway), so
every open finding was re-read against it. Two were retired as non-issues
and moved to Decisions:

- **[main-2]** — the OG's `GivePoints` (`WL_AGENT.C:523`) loops its
  next-extra counter and fires `BONUS1UPSND` *per* 40k milestone, exactly
  as our `add_score` does; the proposed "fire the cue once" would
  *diverge* from the OG, and two `SD_PlaySound` calls in one frame just
  retrigger the same cue (no glitch). Already faithful.
- **[sdl2-1]** — a cosmetic `const`-on-extern doc nit with no behavioral
  effect; the finding itself flagged it skippable.

**[player-2]** and **[player-4]** (the P1 pair) were applied 2026-06-09 —
both predicted test-safe, and indeed the 208-test suite passed with no
golden churn (it drives weapons via `setweapon:`, never the number keys,
and the respawn key-clear is inert in test mode):

- **[player-2]** — `restart_current_level` (`main.fc:1577`) now calls
  `player.clear_input_keys(g)` right after `reset_for_life`, so a movement
  key held when the death animation ends no longer walks the respawned
  player. Mirrors `advance_next_level` and id's `Died → IN_ClearKeysDown`
  (`WL_GAME.C:1199`).
- **[player-4]** — the bare `g.weapon = 0..3` number-key handler
  (`main.fc:4149`) now mirrors id's `CheckWeaponChange` (`WL_AGENT.C:117`):
  it switches only while playing, only when `g.fire_timer <= 0.0` (id's
  `T_Attack` never calls `CheckWeaponChange`, so the OG can't switch
  mid-attack — this was the real cause of the audit's "attack-frame
  desync"), only with `g.ammo > 0`, and only up to `g.best_weapon`
  (so `4` no longer selects an unowned chain gun). The `setweapon:` test
  command stays ungated on purpose.

The rest stand and are ordered below by priority rather than by category.

Tag: **[golden re-pin]** = changes RNG draw order or pinned stats, so it
must update `tests/run-tests.sh` golden values in the same commit. (The
old **[needs OG source]** tag is retired — `../wolf3d` is now present.)

### P2 — real, narrower scope or edge cases

- **[save-3] loading a save under a different view mode gives a wrong
  FOV** (`save.fc:733-738`). `from_slot` restores `plane_x/plane_y`
  verbatim, but the plane magnitude must equal the live `plane_factor`
  (view-mode/aspect-derived; `view_mode` lives in config, not the slot),
  so saving in 4:3 and loading in widescreen (or vice-versa) keeps the
  stale FOV until the next CHANGE VIEW. Fix: after restoring dir+plane,
  renormalize the plane to `|plane| == g.plane_factor` (its direction is
  already perpendicular to dir). No-op in test mode (view mode pinned) →
  test-safe.

- **[main-4] `setlevel:`/`setepisode:` test commands leave
  `next_level`/episode latches stale** (`main.fc:2325`, `:2340`). A script
  doing `endepisode` then `setlevel:N` bounces straight into intermission
  on the new level. Fix: in both branches clear `next_level=false;
  next_level_delay=0.0; went_secret=false; ep_recorded_current=false`
  (mirrors `advance_next_level`). Test-only; existing golden scripts don't
  pre-set these → test-safe.

- **[opl2-1] additive-connection channel drops the modulator when the
  carrier env hits 'off'** (`opl2.fc:599`). The whole-channel early-out
  keys only on the carrier; in an additive (connection-bit) channel a
  still-audible modulator is cut when the carrier finishes release. Fix:
  gate the early-out on connection mode and, in the additive branch, emit
  the modulator alone when the carrier is off. FM mode unchanged.
  **Latent — confirm reach before investing:** check whether any WL6 SFX
  instrument or music track ever writes a `0xC0+ch` register with bit 0
  set; if none do, this is emulator-correctness only with no audible
  effect on our data.

### P3 — cosmetic / well-definedness / very-low-reach

- **[cutscenes-4] endart `^L` desyncs `st.py` from `st.rowon` for an
  out-of-range row** (`cutscenes.fc:1248-1253`). `st.rowon` is clamped
  (`:1250-1252`) but `st.py = snap_y` is derived from the *unclamped*
  `new_row` (`:1249`) → drawn baseline drifts
  (cosmetic; `font.draw_char` clips, no OOB). The OG's `^L`
  (`WL_TEXT.C:231`) keeps them consistent precisely because it derives
  *both* from one value and clamps *neither* (`rowon = (py-TOPMARGIN)/
  FONTHEIGHT; py = TOPMARGIN + rowon*FONTHEIGHT`). Simplest faithful fix:
  mirror the OG — compute `new_row` once, derive both fields from it. The
  clamp only matters on malformed markup the real `endart` chunk never
  emits, so this never triggers on shipped data. Endart-only, test-safe.

- **[main-5] `--level` launch doesn't pin `oldscore`**
  (`main.fc:3170-3179`), unlike `setlevel:` (`:2331`/`:2348`). No-op today
  (score is 0 and `oldscore` inits to 0) but makes the death-rewind
  baseline well-defined. Fix: add `g.oldscore = g.score` in the
  `some(lvl)` branch. Test-safe.

### Dead code — each needs a keep-or-delete call

- **[main-1] redundant 2nd `update_phase_transitions()` in the
  interactive loop** (`main.fc:4234`; `tick()` already calls it at
  `:1786`, discarding the returned `level_changed`). A no-op today
  (idempotent when no transition is pending) but a maintenance trap — a
  future non-phase-changing transition would run twice interactively, once
  per test tick. Fix: delete `:4234`; if the loop's music refresh ever
  needs `level_changed`, read it from `tick()`'s already-returned bool at
  the single site. Interactive-only, test-safe.

- **[cla-dead-1] unused enemy fields** `move_remaining` / `dist_flat` /
  `dist_to_player` (`combat.fc:118-120`). Never read for behavior. Fix:
  drop `dist_flat`/`dist_to_player` + their `level.fc:1034-1035` inits
  (zero other refs). `move_remaining` is also serialized
  (`save.fc:611`/`:813`) — removing it changes the save format (renumber
  later token indices), so version-bump the save or leave that one field.

- **[ui-3] unused HUD number-drawer / mini-font cluster**
  (`ui.fc:660-673` `draw_digit`/`digit_glyph`/`draw_number`,
  `ui.fc:712` private `fill_rect`). `hud.draw_number` has no callers.
  Confirmed 2026-06-09: the 3×5-font path is *also* dead — `hud.draw_text`
  (`ui.fc:694`) is reached only by `overlay.draw_centered_text`
  (`render.fc:813`), which itself has no callers. Fix: delete the whole
  cluster (`draw_number`/`draw_digit`/`digit_glyph` + `char_glyph`/3×5
  `draw_text` + `draw_centered_text` + the private `fill_rect`). Keep the
  real font path `font.draw_text` (`ui.fc:545`) — it's live.

- **[ui-2] `pics.extend_pic_horizontally` is never called**
  (`ui.fc:444`), with a latent OOB (no upper `pic_x` clamp) if wired.
  Fix: delete; or if kept for future widescreen banners, add the upper
  clamp + a TODO that it's unwired.

- **[menu-6] `render_quit_modal` has an unused `ac` param**
  (`menu.fc:722`; call site `:771`). Confirmed `ac` is referenced only in
  the signature. Fix: drop the param + arg (leave `render_main`'s `ac` —
  still used by `render_sound_list`). Only if no quit-modal SFX is
  planned.

### Performance — optional micro-opts (none per-frame-critical)

- **[render-fp] move the per-pixel texture coordinate to fixed-point —
  the one per-frame-critical item in this section, and structural.** The
  hot band loop keeps the texel coordinate as a `float64` accumulator and
  converts to a row index *every pixel* with `let tex_y = (int32)
  bd_tex_pos[k]` (`render.fc:465`, `:478`, `:493`; ~64k+ conversions/frame
  in the fast/edge bands), then clamps to `[0,63]`. Same shape in the
  per-column DDA setup (`:326` `(int32)(vfocal/perp_dist)`, `:385-386`
  step/tex_pos) and the billboard scaler (`:688-690`, `:698`). The float→int
  conversion is the expensive op: at `-O3` an isolated cast+clamp+LUT loop
  measured ~0.035s (bare cast) vs ~0.02s when the coordinate is 16.16
  fixed-point — `let tex_y = (tex[k] >> 16) & 63` is a shift+mask, emits
  **zero** float→int conversions, and the `& 63` makes the range exact so
  the `if tex_y < 0 … if tex_y > 63 …` clamp drops too (two per-pixel costs
  removed, not one). This is the classic Wolf3D/Doom software-rasterizer
  technique: step texcoords in fixed-point, extract the texel with a shift.
  Worth doing "throughout" — wall texturing, floor/ceiling, sprite scaling,
  DDA — not just the wall band. Also sidesteps the rc5 saturating-cast cost
  entirely (see below). **Caveat — NOT test-safe:** fixed-point rounds
  differently from `float64`, so this *changes rendered pixels* and busts
  the bit-stable golden suite — needs a deliberate golden re-pin plus a
  precision review (16.16 has ample headroom for 64-texel textures, but
  verify no visible seams/wobble at grazing angles before re-blessing).
  Bigger than a micro-opt; sequence it as its own pass.

  > Context: rc5's `(int32)float` emits a saturating helper (`fc_f2i32`:
  > NaN-check + two range branches) instead of rc4's bare `cvttsd2si`,
  > making each per-pixel conversion ~2.5× costlier. That compiler-side
  > question resolved upstream as `unguarded`/`guarded` blocks (which
  > superseded the interim `(T!)` cast), now wrapping every in-range cast
  > on the hot render path — the per-pixel wall texel (`render.fc` band
  > loops), per-column line_h / tex_x, `shade_color`'s channel casts, and
  > the billboard scaler all emit a bare `cvttsd2si` again. The same blocks
  > also drop the per-store bounds check that previously forced the raw
  > `vbuf.ptr` / `ssaa_buf.ptr` escape (flat fill, band stores, sprite-col
  > blend, SSAA downsample now index the slice directly under `unguarded`),
  > and the per-stripe `… / spr_w` billboard divide skips its divide-by-zero
  > guard. Disassembly-confirmed: zero `fc_f2*` calls and zero hot-loop
  > `fc_oob` in `raycaster__render_walls` / `billboards__render`; the
  > `unguarded` slice form is byte-identical to the old raw pointer; golden
  > suite unchanged since `unguarded` is bit-identical for in-range inputs.
  > So the saturation + bounds-check overhead is *already* clawed back; what
  > remains for this item is the conversion itself — fixed-point removes the
  > per-pixel float→int op (and its `[0,63]` clamp) outright, a further win.

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

### 1-UP cue fires per 40k milestone — already faithful ([main-2], retired 2026-06-09)

The 2026-05 audit flagged `add_score` (`main.fc:1013`) for firing the
`bonus1up` cue once per 40k milestone when a single add crosses more than
one (e.g. a near-boundary intermission bonus), and proposed firing it
once. We will NOT do this — it's already faithful. id's `GivePoints`
(`WL_AGENT.C:523`) is a `while (score >= nextextra) { nextextra +=
EXTRAPOINTS; GiveExtraMan(); }` loop, and `GiveExtraMan` calls
`SD_PlaySound(BONUS1UPSND)` (`:497`) every iteration — so the OG fires the
cue per milestone exactly as we do. Collapsing to one cue would be a
*divergence*. (Two `SD_PlaySound` calls in one frame just retrigger the
same sample — no audible stutter — so there's nothing cosmetic to fix
either.)

### `const`-on-extern doc nit — not tracked ([sdl2-1], retired 2026-06-09)

The `SDL_OpenAudioDevice` extern dropped `const` on a couple of pointer
params relative to the C header. This is a pure documentation-accuracy
nit with zero behavioral or codegen effect; the finding itself flagged it
"skip if it risks churn." Not worth a tracked item — fold it into any
unrelated `sdl2.fc` edit if convenient.

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

- **wolf3d** at `../wolf3d/WOLFSRC/` — id's original DOS source (GPLv2);
  authoritative for OG behavior. Consult for behavior, don't transcribe
  (see CLAUDE.md copyleft hygiene). Key files: `WL_AGENT.C` (player /
  weapon firing / `GivePoints` / `CheckWeaponChange`), `WL_GAME.C`
  (`Died`, level setup), `WL_PLAY.C` (game loop, `songs[]`), `WL_ACT1.C`
  (doors, pushwall), `WL_ACT2.C` (enemy AI), `WL_DRAW.C` (raycaster),
  `WL_STATE.C` (`CheckLine` sight), `WL_TEXT.C` (endart markup),
  `ID_SD.C` (audio), `ID_CA.C` (Carmack/RLEW/Huffman), `ID_PM.C` (VSWAP),
  `WL_DEF.H` (constants/structs), `AUDIOWL6.H` (sound/music enums).
- **wolf4sdl** — reference C port, normally at `../wolf4sdl/`. **Currently
  absent** from this checkout; restore it if a format detail is clearer
  in the SDL port. id's DOS source wins when they disagree.
- **fc-lang** at `../fc-lang/` — FC compiler source and stdlib
  (installed system-wide as `fcc` via `make install`; see README.md).
