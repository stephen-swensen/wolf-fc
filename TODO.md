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

### Fidelity

Survey passes happen ad-hoc, not on a schedule. The 2026-04-23 sweep
against `GunAttack` / `TakeDamage` / pickup handling / `UpdateFace` /
pacman-ghost chase closed eight divergences. When something feels off
in play, audit the relevant subsystem against id's source / wolf4sdl,
log a finding here, and fix.

## Decisions / retirements

These document deliberate "won't do" calls so they don't get
re-proposed. Wolf-fc targets the GOODTIMES build of WL6 (the 1.4
GT/ID/Activision re-release that became the Steam/GOG version);
features the GOODTIMES executable never references are dead data, not
fidelity gaps.

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
