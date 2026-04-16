# Wolf-FC TODO

## Current State (2026-04-15)

Working:
- DDA raycasting with textured walls from VSWAP.WL6, distance-based shading
- Per-level ceiling colors, flat floor color
- Doors: mid-tile rendering, animated open/close, door-frame (DOORWALL+2/+3) on adjacent walls, standard/locked/elevator textures, space-to-open
- Push-walls: plane-1 tile 98 detected at level build, space slides the wall 2 tiles in the push direction
- Billboard sprite rendering for static objects (tiles 23–72)
  - Compressed t_compshape decoded including signed `newstart`
  - Z-buffer occlusion against walls, distance-sorted back-to-front
- Item pickups (walk-over): health (dog food/food/first-aid/extra life), ammo (clip/MG/chain), treasure (cross/chalice/bible/crown), gold/silver keys. Score tracked, extra life at 40 000.
- Elevator tile (21) loads the next level; level state rebuilt, music switched, player re-spawned at new start.
- IMF music via OPL2 emulator, per-level song table for episodes 1–3, M toggles music
- AdLib SFX + digitized PCM SFX (VSWAP sound pages, 7042 Hz → 44100 Hz nearest) mixing additively. Sound triggers for door/weapon/pickup/pain.
- Weapons: 4 slots (knife/pistol/MG/chain), fire rates per weapon, 1–4 key-select, procedural on-screen sprite with bob, Ctrl fires and decrements ammo
- HUD: health/ammo/score/lives/floor-number digits, gold/silver key indicators
- Display: 320×200 → 2× upscale → 640×400 texture → `SDL_RenderSetLogicalSize(640,480)` for 4:3
- F11 fake-fullscreen toggle
- Player collision radius (prevents see-through-walls glitch)
- PNG screenshots via `s` key (→ `~/.wolf-fc/screenshots/ss_NNN.png`), with full game-state metadata in a `tEXt` chunk
- Headless test mode (`--test`) with scripted commands for regression testing (see README.md)

## Gameplay

### Enemies (biggest missing feature)
- [ ] Spawn enemies from plane 1 (tiles 108+). Tile ranges encode type (guard/officer/SS/dog/mutant/boss) and facing (N/E/S/W).
- [ ] State machine: stand, patrol, chase, attack, pain, die, dead
- [ ] Line-of-sight detection against the tilemap (ray from enemy tile to player tile, stopping at walls/closed doors)
- [ ] Pathfinding / tile-based movement toward the player, avoiding walls and other enemies
- [ ] 8-directional billboard rendering based on enemy angle relative to player, with animation frames for walk/attack/pain/die. Sprites are consecutive VSWAP pages per enemy type.
- [ ] Enemies fire at the player on a per-type timer when in LOS; player takes damage
- [ ] Corpses remain as a flat sprite, optionally dropping a pickup (MG/chain guns from officers/SS)

### Weapons and combat
- [ ] Hitscan fire: ray from player along facing, find first enemy or wall intersection, apply damage. Currently `Ctrl` only plays the fire animation and sound — no hits.
- [ ] Weapon-specific hit sounds and pain feedback on enemies
- [ ] Verify MG/chain pickups are reachable on early levels (they're implemented as pickup item types but most early-episode maps only surface them behind push-walls or from enemy drops, neither of which currently yield them)

### Game state / death flow
- [ ] Player death when health ≤ 0: red flash, collapse animation, drop a life
- [ ] Game-over screen when lives exhausted
- [ ] Level-restart on death with lives remaining
- [ ] Secret counter (push-walls found), kill counter, treasure counter

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
