# Wolf-FC TODO

## Current State (2026-04-16)

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
- [ ] Difficulty selection — currently spawns all tiers regardless of skill. Add a difficulty setting that filters tiles 144+ / 180+ at build time.
- [x] Patrol path markers (plane-1 tiles 90..97 "ICONARROWS" that redirect T_Path).
- [x] FL_AMBUSH tile (106) handling — enemies on that tile ignore noise and only wake on direct LOS.
- [x] Enemies opening doors as they walk into them (wolf4sdl's OpenDoor-from-T_Chase path).
- [x] Areas + madenoise: firing a gun (or landing a knife hit) wakes every non-AMBUSH enemy in the player's currently-connected area set (open-door reachable). Knife stealth preserved.
- [ ] Bosses (Hans, Gretel, Schabbs, Fat, Gift, Hitler variants) — currently ignored.
- [ ] Ghosts (Blinky/Clyde/Pinky/Inky on secret Pacman-homage level).
- [x] Mutant-specific double-shot pattern (they fire twice per shoot cycle in wolf4sdl).

### Weapons and combat
- [x] Weapon-specific hit sounds (HITENEMYSND when a shot connects).
- [ ] Verify MG/chain pickups are reachable on early levels (now that SS drop MG on death, this should be automatic once SS enemies appear on a level — confirm on E1M3).

### Game state / death flow
- [ ] Player death when health ≤ 0: red flash, collapse animation, drop a life. Currently health can reach 0 but the player keeps playing with a visual glitch; there's no death transition.
- [ ] Game-over screen when lives exhausted
- [ ] Level-restart on death with lives remaining
- [ ] Kill counter / secret counter / treasure counter (spawn_enemies knows the total; wire to `gamestate.killtotal` equivalent)

### Level progression
- [ ] Par-time tracking per level
- [ ] Intermission screen between levels (kills / secrets / treasure percentages, bonus points)
- [ ] Full episode structure (6 episodes × 10 levels) with per-episode intermissions
- [ ] Per-episode music table for episodes 4–6 (currently duplicates episodes 1–3)

## Rendering

### Polish
- [ ] Textured floors and ceilings (optional — original Wolf3D ships flat colors)
- [ ] Any-angle door-frame texture fixes if regressions surface after enemy rendering lands

### HUD
- [ ] BJ face with expressions (idle / hurt / grinning / dying) — requires VGAGRAPH
- [ ] Proper Wolf3D gray status bar layout and graphics — requires VGAGRAPH
- [ ] Weapon icon on status bar

## Audio

- [ ] Spatial panning for SFX based on source angle relative to player (enemies will need this)
- [ ] Music fade-out on level end / game over
- [ ] Ambient sounds on specific tiles where applicable

## Data Loading

### VGAGRAPH (unblocks face, menus, messages)
- [ ] Huffman decoder for VGAGRAPH (VGADICT.WL6 + VGAHEAD.WL6 + VGAGRAPH.WL6)
- [ ] Picture table (width/height per graphic)
- [ ] Asset extractors for: status-bar pieces, BJ face frames, font, menu graphics

## UI / Menus

- [ ] Title screen
- [ ] Main menu (new game / sound / controls / quit)
- [ ] Difficulty selection (Can I play Daddy? / Don't hurt me / Bring 'em on / I am Death incarnate)
- [ ] Pause screen
- [ ] In-game text messages (floor name, pickup notifications)

## Code Quality

- [ ] Consider splitting `main.fc` (render / pickups / weapons / enemies) once enemies land and it grows further
- [ ] Pre-extract sprite columns at load time — currently sprite rendering re-parses raw VSWAP bytes per frame
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
