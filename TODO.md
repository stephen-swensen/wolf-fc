# Wolf-FC TODO

## Current State (2026-04-13)

Working:
- DDA raycasting with textured walls from VSWAP.WL6 data
- Per-level ceiling colors, floor color
- Doors render as full-tile walls with correct door textures (standard, locked, elevator)
- Space key opens doors (instant removal from tilemap)
- Billboard sprite rendering for static objects (tiles 23-72 from plane 1)
  - Compressed sprite format (t_compshape) decoded correctly including signed newstart offsets
  - Z-buffer occlusion against walls
  - Distance-sorted back-to-front rendering
- IMF music playback via OPL2 emulator (opl2.fc), per-level song mapping
- Basic HUD: health, ammo, score, lives (bitmap digit font on dark red bar)
- Classic Wolf3D controls: arrows move/turn, alt+arrows strafe, shift run, space open
- Display: 320x200 game → 2x upscale to 640x400 → SDL texture → SDL_RenderSetLogicalSize(640,480) for 4:3 correction
- F11 fake-fullscreen toggle (borderless window approach from face-invaders)
- `--screenshot` flag saves PPM for debugging

## Rendering

### Doors (high priority)
- [ ] Mid-tile door rendering: doors should render at tile midpoint (0.5 into tile), not as full-tile walls. Requires special-case ray intersection — when DDA enters a door tile, check if ray reaches the midpoint. See wolf4sdl `AsmRefresh` lines ~1231 and ~1386 for the `tilehit & 0x80` handling. The ray checks `doorposition[doornum]` to handle partially-open doors.
- [ ] Door-side textures: walls adjacent to doors should show door frame texture (DOORWALL+2/+3) instead of their regular texture. Wolf4sdl uses a 0x40 flag on adjacent tiles, but the raycaster checks at runtime whether the actual adjacent tile has a door (0x80). See `HitVertWall`/`HitHorizWall` in wl_draw.cpp.
- [ ] Animated door opening/closing: track door state (closed/opening/open/closing) with a `doorposition[]` array (0=closed, 0xFFFF=open). Advance position over time. See wolf4sdl `MoveDoors()` in wl_act1.cpp.

### Push-walls
- [ ] Plane 1 tile value 98 marks a pushable wall. Space key near a push-wall slides it 2 tiles in the direction the player pushes. See wolf4sdl `PushWall()` in wl_act1.cpp.

### Weapon overlay
- [ ] Draw the player's weapon sprite at the bottom center of the 3D viewport. Weapon sprites are in VGAGRAPH (not VSWAP). This requires Huffman decompression of VGAGRAPH chunks. Alternatively, use a simplified procedural weapon graphic.
- [ ] Weapon bob during movement

### HUD improvements
- [ ] BJ face with expressions (idle, hurt, grinning) — faces are in VGAGRAPH, need Huffman decoding
- [ ] Key indicators (gold/silver)
- [ ] Level number display
- [ ] Proper Wolf3D status bar layout (gray bar with sections)
- [ ] Weapon name/icon

### Rendering polish
- [ ] Distance-based shading (walls farther away are darker). Wolf4sdl uses a shade table.
- [ ] Textured floors and ceilings (optional — original Wolf3D uses flat colors)

## Gameplay

### Enemy AI (major feature)
- [ ] Spawn enemies from plane 1 data (tiles 108+). Each tile range maps to an enemy type (guard, officer, SS, dog, mutant, boss) with a facing direction.
- [ ] Enemy state machine: standing, patrolling, chasing, attacking, pain, dying, dead
- [ ] Line-of-sight detection (can the enemy see the player?)
- [ ] Pathfinding: enemies move toward player, navigate around walls
- [ ] Enemy rendering: enemies have 8 directional sprites (based on angle relative to player) plus animation frames for walking/attacking/dying. These are consecutive VSWAP sprite pages.
- [ ] Enemy combat: enemies fire at player on a timer when in line of sight

### Weapons and combat
- [ ] Weapon types: knife, pistol, machine gun, chain gun
- [ ] Firing: reduce ammo, hitscan ray from player to first enemy/wall
- [ ] Damage calculation per weapon type
- [ ] Weapon switching (1-4 keys)
- [ ] Weapon pickup upgrades (machine gun, chain gun from floor items or enemies)

### Item pickups
- [ ] Walk-over pickup detection (player position overlaps item tile)
- [ ] Health items: dog food (+4), food (+10), first aid (+25), extra life (full heal)
- [ ] Ammo: clip (+8), machine gun (+6 + weapon), chain gun (+6 + weapon)
- [ ] Treasure: cross (100), chalice (500), bible (1000), crown (5000)
- [ ] Keys: gold key, silver key (track in game state, check when opening locked doors)
- [ ] Score tracking and extra life at 40,000 points

### Level progression
- [ ] Elevator tile (tile 21 in plane 0) triggers level end
- [ ] Load next level on elevator use
- [ ] Par time tracking
- [ ] Intermission screen (kills/secrets/treasure percentages)
- [ ] Episode structure (6 episodes x 10 levels)

### Game state
- [ ] Lives system (start with 3, death respawns or game over)
- [ ] Health damage from enemies
- [ ] Death sequence (red flash, collapse)
- [ ] Game over screen
- [ ] Secret counting (push-walls found)

## Audio

### Sound effects
- [ ] Digitized sound playback from VSWAP sound pages (8-bit unsigned PCM @ 7042 Hz, resample to 44100 Hz)
- [ ] Sound triggers: door open, weapon fire, enemy alert/attack/pain/death, item pickup, player pain
- [ ] Spatial audio (left/right panning based on sound source angle to player)

### Music improvements
- [ ] Music toggle (M key)
- [ ] Fade out music on level end
- [ ] Per-episode music mapping for episodes 4-6 (currently hardcoded for eps 1-3 repeated)

## Data Loading

### VGAGRAPH (needed for full HUD and menus)
- [ ] Huffman decompression of VGAGRAPH chunks (VGADICT.WL6 + VGAHEAD.WL6 + VGAGRAPH.WL6)
- [ ] Picture table loading (width/height metadata per graphic)
- [ ] Status bar graphics, weapon sprites, font, BJ face sprites, menu graphics

## UI / Menus

- [ ] Title screen
- [ ] Main menu (new game, sound, controls, quit)
- [ ] Difficulty selection (can I play daddy? / don't hurt me / bring 'em on / I am death incarnate)
- [ ] Pause screen
- [ ] In-game text messages

## Code Quality

- [ ] Consider breaking main.fc into multiple files as it grows (e.g., separate render.fc, enemies.fc)
- [ ] The sprite rendering could be more efficient — currently re-reads column data from raw VSWAP bytes each frame. Could pre-extract sprite columns at load time.
- [ ] The tilemap could use uint16 instead of uint8 to support more tile states (doors with position, push-wall state, etc.)

## Reference

- **wolf4sdl** at `../wolf4sdl/` — reference C implementation, consult for data format details and rendering correctness (but don't copy code to avoid GPL)
- **fc-lang** at `../fc-lang/` — FC compiler and stdlib
- Key wolf4sdl files:
  - `wl_draw.cpp` — raycaster (AsmRefresh, HitVertWall, HitHorizWall, HitVertDoor, HitHorizDoor, ScaleShape, DrawScaleds)
  - `wl_act1.cpp` — doors (SpawnDoor, MoveDoors, OpenDoor, PushWall)
  - `wl_act2.cpp` — enemy AI (enemy state machines, SpawnStand/SpawnPatrol)
  - `wl_game.cpp` — level setup (SetupGameLevel, ScanInfoPlane)
  - `wl_agent.cpp` — player actions (weapon firing, movement, damage)
  - `wl_play.cpp` — game loop, songs[] table
  - `id_ca.cpp` — asset loading (Carmack/RLEW/Huffman decompression)
  - `id_sd.cpp` — audio (IMF playback, sound effects)
  - `id_pm.cpp` — VSWAP page manager
  - `id_vl.cpp` — display setup (640x400 render, 640x480 logical, nearest scaling)
  - `audiowl6.h` — sound/music chunk enums (LASTSOUND=87, STARTMUSIC=261)
  - `wl_def.h` — all game constants and structs
