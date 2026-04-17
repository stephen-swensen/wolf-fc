# Wolf-FC TODO

## Current State (2026-04-17)

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
- Space during intermission animation skips to the final "everything shown"
  state; a second press advances to the next level. The `advance` test
  command collapses both steps into one so regression tests stay single-hop.

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
- In-game message banner: pickup names (gold key, treasures), fades out over 0.5s.
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
- [x] Bosses: Hans / Schabbs / Gretel / Giftmacher / Fat / Hitler-fake / Hitler as enemy kinds with boss HP / score / gold-key drop. Killing a boss sets next_level=true. Sprite indices counted directly from wolf4sdl `wl_def.h` (non-SPEAR build); verified visually by rendering Hans on E1M9.
- [x] Pacman ghosts: Blinky/Pinky/Clyde/Inky spawn from plane-1 tiles 224..227 (found on E3M10 = level 29), chase player, touch damage. Sprite indices 288..295 verified visually.
- [x] Mutant-specific double-shot pattern (they fire twice per shoot cycle in wolf4sdl).

### Weapons and combat
- [x] Weapon-specific hit sounds (HITENEMYSND when a shot connects).
- [x] Verify MG/chain pickups are reachable on early levels (SS spawn on E1M3+ now tested via `setlevel:2 enemies` — SS drop MG, chain gun pickup from secret rooms).

### Game state / death flow
- [x] Player death when health ≤ 0: red damage flash + collapse tint, drop a life, transition to restart.
- [x] Game-over screen when lives exhausted (press space to restart).
- [x] Level-restart on death with lives remaining.
- [x] Kill / secret / treasure counters (built at level load, increment in damage_enemy / try_push_wall / check_pickups).

### Level progression
- [x] Par-time tracking per level (par_times[] from wolf4sdl, seconds).
- [x] Intermission screen between levels (kill/secret/treasure percentages, time vs par, press space to continue).
- [x] Full episode structure (6 episodes × 10 levels) with per-episode victory screen, secret-level routing (ALTELEVATORTILE → level 9, level 9 → ElevatorBackTo), and final victory after episode 6.
- [x] Per-episode music table for episodes 4–6 — songs[] table matches wolf4sdl: Wolf3D's six episodes share the three music sets, so the "duplication" is correct.
- [x] Bonus score calculations: par-beaten bonus (500 pts per unused 10s) + 10000 pts each for 100% kills / secrets / treasures. Applied when entering intermission, reflected in score line.

## Rendering

### Polish
- [ ] Textured floors and ceilings (optional — not part of OG Wolf3D; deferred).
- [ ] Any-angle door-frame texture fixes if regressions surface after enemy rendering lands

### HUD
- [x] BJ face with health-driven expressions (7 frames from healthy to near-dead; dying-phase locks to worst face).
- [x] Full Wolf3D status bar: STATUSBARPIC, number pics for all fields, weapon icon, key indicators.
- [x] Weapon icon on status bar.

## Audio

- [x] Spatial panning for SFX based on source angle relative to player — enemy voices/gunfire/death pan per-source; player-originated sounds stay centered. Stereo output via digi per-slot pan; adlib/imf duplicated to both channels.
- [x] Music fade-out on level end / game over: 0.5s ramp via imf player volume field.
- [x] Per-kind / per-boss vocal variety — wolf4sdl's FirstSighting + A_DeathScream behaviour. Guards now pick one of 8 random death screams; officers / SS / mutants / dogs have distinct death vocals (NEINSOVASSND / LEBENSND / AHHHGSND / DOGDEATHSND). Each boss has signature sighting + death lines (Gutentag/Mutti, Schabbs-ha/Mein Gott, Tot-hund/Hitler-ha, Die/Scheist, Die/Eva, Kein/Mein, Eine/Donner, Erlauben/Rose).
- [ ] Tile-based ambient sounds (periodic fountain drip, torch crackle, etc.) — not in OG Wolf3D; would be an addition, not a port.

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
- [x] In-game text messages (pickup names, boss-key banner, fade-out timer).
- [x] Episode selection submenu (6 episodes, under NEW GAME).
- [x] Save Game / Load Game menus (10 slots, ~/.wolf-fc/saves/slot_NN.sav, text format).
- [ ] Controls remapping menu (wolf4sdl parity; optional).

## Code Quality

- [ ] Consider splitting `main.fc` (render / pickups / weapons / enemies) once enemies land and it grows further
- [x] Pre-extract sprite column headers (leftpix/rightpix/col_offsets) at load — avoids repeated bytes.u16 reads per draw_sprite_col call. Column-level run-list is still parsed at draw time; further pre-decoding to flat pixel rows is possible but not yet needed.
- [ ] Widen tilemap to uint16 if more tile states are needed for enemy blocking / secret flags

## Reference

- **wolf4sdl** at `../wolf4sdl/` — reference C implementation, consult for data format details and rendering correctness (but don't copy code to avoid GPL)
- **fc-lang** at `../fc-lang/` — FC compiler and stdlib
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
