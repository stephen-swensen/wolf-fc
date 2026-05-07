# Render dirty-frame plan

Working note for the next round of render-pipeline cleanup. Scratchpad for
side convos before any code lands.

## Context

`#1 + #2 + #5` (commit `2b8fd35`) eliminated three categories of waste in the
3D-phase render path: per-frame floor/ceiling pre-fill, the always-on view
sentinel clear + composite, and the redundant SDL backbuffer clear when no
letterbox is present. Combined with the D3D11 swap-chain switch, fullscreen
4K is much smoother.

**What's still wasted, every frame, regardless of whether anything changed:**

1. Static phases (title, main_menu, intermission, episode_end, endart,
   pg13, high_scores) re-rasterize the entire dbuf via `upscale_nx` even
   when fb is byte-identical to the previous frame. At scale=6 / fb_w=426
   that's ~12 MB of writes per frame.
2. Every frame, the full dbuf gets uploaded to the streaming texture via
   `update_texture` — same ~12 MB CPU→GPU transfer.
3. During gameplay, the HUD region is re-blitted into fb and composited
   into dbuf every frame, even though score / health / ammo / face usually
   don't change frame-to-frame.

All three are forms of the same bug: we don't know "nothing changed this
frame" and so we redo all the work.

This plan is the staged path to fixing that. Step 1 is the foundation; the
others build on it.

## Step 1 — Establish a "dirty?" signal (was "#4" in the audit)

**Goal.** Render dispatcher can answer "is the current fb byte-identical to
the version we drew last frame?" If yes, skip `upscale_nx`.

**Two strategies, pick one:**

- **(a) Frame-throttle approach.** For non-3D phases, render at ~15 fps
  regardless of input. Skip whole frames when the phase has no animation.
  Coarse but bulletproof — no per-writer bookkeeping. Captures most of the
  static-phase win.
- **(b) Dirty-flag approach.** Add `rc->fb_dirty: bool`, every fb writer
  sets it true, dispatcher checks-and-clears. Precise, but every writer
  must participate. Missed invalidation = stale frame.

**Tradeoff to discuss.** (a) is one change to the main loop; (b) is dozens
of writer touchpoints. (b) gives us per-region flags later (Step 4); (a)
doesn't generalize as cleanly.

**Open questions.**
- Cursor blink animates at ~3.5 Hz on the title / menu screens. How does
  it interact with a 15 fps throttle? (Likely fine — 15 fps > 3.5 Hz × 2.)
- Intermission has count-up animations; episode_end and bj_victory have
  walking-BJ frames. Are they all comfortable at 15 fps, or does the
  count-up "zip" feel laggy? Have to test.
- Some "static" phases have continuous timers (e.g. fade-ins) that look
  better at 60 fps. Maybe a per-phase `target_fps` is the right knob.

**What this saves on its own.** ~12 MB/frame of dbuf writes during
non-3D phases. CPU drops to near zero in menus.

## Step 2 — Skip `update_texture` on clean frames

**Depends on:** Step 1.

**Goal.** When the dispatcher decides "fb is clean," also skip the
`sdl2.update_texture` call. The streaming texture's contents persist across
frames; `render_copy` + `present` happen as usual and re-display the
existing texture.

**What this saves.** Another ~12 MB CPU→GPU transfer per clean frame, plus
D3D11's per-call overhead. Combined with Step 1, a static menu frame does
nothing but `present` (which blocks on vsync).

**Risk.** Low. Texture content is untouched by FLIP_DISCARD's backbuffer
invalidation. Need to mark "dirty" on resize / view-mode change so the
next frame uploads fresh.

## Step 3 — Dirty-rect texture upload (audit's "#10")

**Depends on:** Step 1 (or works standalone with finer granularity).

**Goal.** When only part of fb changed, upload only the changed sub-rect.
SDL's `update_texture` accepts an `SDL_Rect` for the destination region.

**What this enables.**
- Cursor blink: ~16×16 upload instead of 12 MB.
- Intermission counter ticks: digit-strip rect.
- Score / ammo / health updates during play: digit-rect upload.

**Risk.** Per-call overhead on `update_texture` may dwarf the byte savings
for tiny rects on some drivers. Need to measure. Coalescing overlapping
dirty rects adds complexity.

**Likely worth it for static phases (cursor blink), questionable during
play.**

## Step 4 — HUD-region dirty during play (audit's "#9")

**Depends on:** Step 1 (specifically the per-region dirty-flag variant).

**Goal.** Track HUD-region dirty separately from view-region dirty during
3D phases. HUD writers (`add_score`, damage application, weapon change,
key pickup, `update_face` frame tick) set `hud_dirty = true`. Skip
`hud.render` (fb writes) and `composite_hud` (dbuf scale² blit) when
clean.

**What this saves.** ~1.6 MB dbuf writes per clean-HUD frame at scale=6 /
fb_w=426. Most gameplay frames have an unchanged HUD; the savings
compound precisely during heavy action where scale=6 currently stutters.

**Bookkeeping touchpoints.**
- `add_score` (wallet ticks, kill bonus, pickup bonus, intermission tally)
- damage taken (health drops + face-of-pain swap)
- ammo spent (firing) / gained (clip pickup)
- weapon switch (key 1-4)
- keys picked up (gold/silver)
- BJ face animation timer (~0.5–1 s frame flips)
- god-mode toggle (face swap)

**Risk.** A miss = HUD frozen at stale value, which is visible. Test by
playing through a level and spot-checking each HUD element.

## Suggested ordering

1. **Step 1 with strategy (a) — frame throttle.** Lowest risk, biggest
   single visible improvement (calm menus). Land standalone; test all
   non-3D phases for animation feel.
2. **Step 2.** Almost free given the throttle infra; just gate the
   `update_texture` call too.
3. **Step 4.** The remaining gameplay-side win. Whether to do this with
   strategy (b) for Step 1 retrofitted, or as a localized HUD-only
   dirty-flag layered on top of (a), is a separate design call.
4. **Step 3.** Only worth pursuing once cursor-blink upload becomes the
   measured bottleneck on static phases — which it probably never will,
   given Step 1 already drops menu frames to ~15 fps.

## Cross-cutting questions

- **Should `tick` continue running during throttled static-phase frames?**
  In test mode every command advances time at fixed `dt`, but in
  interactive mode the loop's `dt` accumulator should still cover the
  skipped frames so animations don't drift. (Probably trivial — `tick`
  takes `dt`; skipping a render frame just means a larger `dt` on the
  next render. But cursor-blink phase is computed from time, so it's
  fine either way.)
- **Headless test mode.** `--test` already pins `scale = 2` and renders
  bit-deterministically. Throttling the interactive loop shouldn't
  affect test mode (no SDL window, no upscale/upload). Verify regression
  tests still pass.
- **Vsync interaction.** With vsync, the throttled-15-fps loop will
  `present` once per render and `delay` between renders, vs the current
  60 fps `present`-blocks-on-vblank model. The change in present cadence
  shouldn't matter for D3D11 flip-model.
- **Single dirty bool vs per-region flags.** Step 4 needs at least
  `view_dirty` and `hud_dirty`. If we go with throttle for Step 1, we
  can defer the per-region split until Step 4 actually lands and add it
  there. If we go with dirty-flag for Step 1, design the per-region
  split up front.
