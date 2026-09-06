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

## Open findings

The 2026-05-31 multi-agent audit's 76 confirmed findings are now all
either applied or retired; see Decisions below for the ones we
deliberately won't do. The last sweep (2026-09-05) applied every
remaining P2 / P3 / dead-code / cheap-perf item and closed the audit,
leaving **[render-fp]** — a structural, golden-busting render pass — as
the only item carried forward, plus two new findings raised by that
sweep's own review.

Earlier passes, for the record: license-hygiene / doc-comment / leak /
clean-fail-hard fixes in `38da848` + `1bf1c5c` (the silent-continue
bounds-guards from that batch were deliberately reverted — see
Decisions); **[arch-1]** (enemy `last_visible` moved out of the render
path, 2026-06-02, no golden churn, now pinned by the `vis=` column on
`enemylist`); **[level-1]** (1-UP counted in the treasure denominator,
2026-06-04, churned the three level-0 treasure assertions);
**[player-2]** + **[player-4]** (respawn key-clear and OG-faithful
number-key weapon switching, 2026-06-09).

### Carried forward

- **[render-fp] move the per-pixel texture coordinate to fixed-point —
  per-frame-critical, and structural.** The
  hot band loop keeps the texel coordinate as a `float64` accumulator and
  converts to a row index *every pixel* with `let tex_y = (int32)
  bd_tex_pos[k]` (~64k+ conversions/frame in the fast/edge bands), then
  clamps to `[0,63]`. Same shape in the
  per-column DDA setup (`(int32)(vfocal/perp_dist)`, step/tex_pos) and the
  billboard scaler. The float→int
  conversion is the expensive op: at `-O3` an isolated cast+clamp+LUT loop
  measured ~0.035s (bare cast) vs ~0.02s when the coordinate is 16.16
  fixed-point — `let tex_y = (tex[k] >> 16) & 63` is a shift+mask, emits
  **zero** float→int conversions, and the `& 63` makes the range exact so
  the `if tex_y < 0 … if tex_y > 63 …` clamp drops too (two per-pixel costs
  removed, not one). This is the classic Wolf3D/Doom software-rasterizer
  technique: step texcoords in fixed-point, extract the texel with a shift.
  Worth doing "throughout" — wall texturing, floor/ceiling, sprite scaling,
  DDA — not just the wall band. **Caveat — NOT test-safe:** fixed-point rounds
  differently from `float64`, so this *changes rendered pixels* and busts
  the bit-stable golden suite — needs a deliberate golden re-pin plus a
  precision review (16.16 has ample headroom for 64-texel textures, but
  verify no visible seams/wobble at grazing angles before re-blessing).
  Bigger than a micro-opt; sequence it as its own pass.

  > Context: the rc5 saturating-cast overhead this item used to also
  > cover is already clawed back — `unguarded` / `guarded` blocks now wrap
  > every in-range cast on the hot render path (per-pixel wall texel,
  > per-column line_h / tex_x, `shade_color`'s channel casts, the billboard
  > scaler), and the same blocks dropped the per-store bounds check that
  > once forced the raw `vbuf.ptr` / `ssaa_buf.ptr` escape.
  > Disassembly-confirmed: zero `fc_f2*` calls and zero hot-loop `fc_oob`
  > in `raycaster__render_walls` / `billboards__render`. What remains for
  > this item is the conversion itself.

### New — 2026-09-05 sweep

- **[test-1] the tally's remaining uncovered arms.** The wrong par times
  below survived because every intermission assertion ran on E1M1, whose
  par happened to be one of the three correct entries. That gap is now
  mostly closed: par on a corrected floor and on a boss floor, which
  floors feed the episode averages, the ratio percentage (including that
  it floors — 10 of 11 reads 90 %), and the 100 %-category bonus are all
  pinned, the last two via E1M1 on Can I Play Daddy, whose 11 enemies are
  few enough to clear from a script. Both new arms were mutation-checked
  (zeroing the bonus, and removing the averages' zero-divisor guard, each
  fail exactly one assertion and nothing else).

  What is still unasserted: the *secret* and *treasure* 100 % arms. They
  are the same three-line shape as the kill arm that is now covered, and
  reaching them from a script would mean triggering every push-wall or
  collecting every treasure on a floor. Left uncovered deliberately —
  worth revisiting only if that code grows a per-category difference.

### Applied — 2026-09-05

Every item below was applied with the 214-test suite green; the ones
touching rendered pixels or written files were additionally verified
byte-identical against the pre-change binary.

- **[save-3]** loading a save no longer keeps a stale FOV. `from_slot`
  now rebuilds the camera plane from the restored heading
  (`plane = dir rotated 90° CW, scaled by plane_factor`) instead of
  trusting the slot's copy, so a game saved in 4:3 and loaded in
  widescreen picks up the live FOV. Also undoes the perpendicularity
  drift the slot's 6-decimal formatting introduces. Verified: a
  save/load round-trip in test mode is pixel-identical.

- **[save-4] (new)** a loaded game is now marked `has_active_game`.
  It starts false on a fresh launch and is cleared on game over, and
  `from_slot` never set it — so LOAD GAME from either state resumed a
  running game whose main menu still read "BACK TO DEMO", greyed out
  SAVE GAME, and dumped the player on the title screen (discarding the
  loaded game) on the next Esc. Regression:
  `save:load-marks-game-active`.

- **[save-5] (new)** the per-episode running totals are now saved.
  The original persists its `LevelRatios[]` table
  (`WL_MAIN.C:371-375`); ours lived only in memory, so a game resumed
  mid-episode reported episode-end averages over just the levels played
  since the load — and inherited whatever the live session (possibly a
  different episode) had accumulated. Written as a new `episode` line,
  so WLFC 2 files stay loadable; the loader zeroes the totals first, so
  a slot without the line loads a clean baseline. New `epstats` test
  command; regression: `save:episode-totals-round-trip`.

- **[inter-2] (new)** the par-time table was wrong for 47 of 60 levels.
  Only E1M1-M3 matched the original; episodes 4-6 were verbatim copies
  of episodes 1-3, and boss floors carried a bogus 7-minute par where
  the original has none. Both the tally screen's `PAR` line and the
  +500/sec time bonus read this table, so scoring was off on nearly
  every level (E1M4: 150 s vs the correct 210 s = 30 000 points). Now
  id's `parTimes[]` (`WL_INTER.C:443`) converted from minutes to whole
  seconds, with 0 for boss / secret floors → "??:??" and no time bonus.
  Cross-checked the sibling reproduced tables at the same time:
  `ceil_table`, `episode.back_to`, enemy `hp_for_kind` (incl. the real
  Hitler morph tiers) and `score_for_kind` all match id exactly.

- **[inter-1] / [inter-3]** the episode-end averages now cover the eight
  ordinary floors of an episode, as the original's do. Two floors were
  wrongly feeding them: the floor an episode ends on (which also earned a
  level-completion bonus it should never have had — it skips the tally
  screen entirely and cuts to the victory screen), and bonus floors
  (which are paid a flat sum *instead of* a tally, so the original works
  out no ratios for them at all). The boss case was a deliberate
  divergence, retired on review — the original's exclusion is clearly
  intentional, not an oversight (see Decisions). The bonus-floor case was
  an ordering accident: the per-episode snapshot sat above the flat-bonus
  early-out rather than below it. Four entry points had to agree — the BJ
  run, the death-cam route, the debug level-skip, and the test-mode
  advance. Side effect worth noting: with both floors excluded, our
  "divide by floors actually played" divisor now reaches the original's
  fixed eight on a full run, so the two only differ on a mid-episode
  start. Regressions: `intermission:boss-floor-earns-no-completion-bonus`,
  `…boss-floor-not-in-episode-averages`,
  `…secret-floor-not-in-episode-averages`,
  `…ordinary-floor-recorded-in-averages`.

- **[main-4] / [main-5]** `setlevel:` / `setepisode:` / `--level` now
  share one path, `flow.jump_to_level`, which clears the
  level-transition latches (`next_level`, `next_level_delay`,
  `went_secret`, `ep_recorded_current`) and pins `oldscore`. A script
  doing `endepisode` then `setlevel:N` used to bounce straight into the
  intermission on the new map. Regression:
  `episode:setlevel-clears-pending-transition`.

- **[cutscenes-4]** endart `^L` derives row and baseline from one
  unclamped value, like the original (`WL_TEXT.C:231`), so a jump can no
  longer draw text on one line while wrapping it against another's
  margins. Verified: all 6 episodes × 8 pages render byte-identically,
  so shipped markup never reaches the case.

- **[opl2-1]** an additive-connection channel no longer drops an
  audible modulator when the carrier's envelope finishes. Confirmed
  zero reach on our data first — no WL6 music chunk ever writes
  `0xC0+ch` with bit 0 set, and the AdLib SFX driver forces
  feedback/connection to 0 — so this is emulator correctness only.

- **[main-1]** dropped the interactive loop's second
  `update_phase_transitions` (`flow.tick` already ends in it).

- **[ui-2] / [ui-3] / [menu-6] / [cla-dead-1]** dead code removed:
  `pics.extend_pic_horizontally`; the whole 3×5 mini-font cluster
  (`hud.draw_number` / `draw_digit` / `digit_glyph` / `char_glyph` /
  `hud.draw_text` / `hud`'s private `fill_rect` /
  `overlay.draw_centered_text`); `render_quit_modal`'s unused `ac`
  param; the enemy struct's `dist_to_player` / `dist_flat`; and
  `player.blocked` (an unused back-compat shim found alongside).
  `move_remaining` was removed from the struct *without* a save-format
  break — field 12 of the `enemy` line is written as 0 and ignored on
  load, so WLFC 2 files keep loading and every later field keeps its
  position.

- **[png-1]** screenshot CRC-32 is table-driven (table built once per
  `write` on the stack — a module `let` can't compute one), and Adler-32
  defers its modulo to the standard 5552-byte NMAX blocks. Verified:
  PNG output is byte-identical and all chunk CRCs validate.

- **[render-4]** the per-frame `pal_dim` pre-shade is skipped when
  distance shading is on — but gated on the *same* flag as its reader,
  not just the fill. **The fix as originally written was unsafe:** Shadow
  Depth 25 % makes `shadow_floor` exactly 0.75, so distant X-side walls
  hit the `shade == 0.75` branch with the LUT unfilled and would have
  rendered black. Verified: a shadow-depth-25 frame is byte-identical
  before and after.

- **[player-5] / [level-2]** the collision and debug-teleport scans
  `break` on their first hit instead of running to the end of the array.

## Decisions / retirements

### Boss + bonus floors stay out of the episode averages ([inter-1], decided 2026-09-05)

The 2026-09-05 sweep flagged our awarding a level-completion bonus on the
floor an episode ends on, and folding both that floor and bonus floors
into the end-of-episode averages, as a divergence — and asked whether to
keep it (ours is arguably the more intuitive reading: the floor you just
fought through counts) or match the original. We matched the original.

The original's exclusion is deliberate, not an oversight, and several
independent details agree on it: the table holding the per-floor figures
is sized for exactly the eight ordinary floors, so recording a ninth
would run off the end of it; the write happens only on the tally path,
which bonus floors never take; the floor an episode ends on never reaches
that path at all, because winning cuts straight from the kill to the
victory screen; and the averaging sums those eight entries over a fixed
divisor of eight. A forgotten floor would look like a table with room for
it and a wrong loop bound — not four details lining up.

It also falls out of a presentation decision we already mirror: neither
floor has a tally screen on which ratios could be shown, so there is no
moment at which they would be computed. The averages are "the eight
ordinary floors", and that is a coherent definition rather than an
accident. Reproducing it costs us nothing and removes two divergences.

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
