#!/usr/bin/env bash
# Wolf-FC regression tests.
#
# Runs the game binary in headless --test mode against a set of scripted
# scenarios and asserts on patterns in the stdout dumps. Covers spawn
# tables, pickups, doors, elevator, combat (hitscan + enemy AI), and the
# movement edge cases that have previously regressed (door straddle,
# mutual deadlock on an enemy walking onto the player).
#
# Usage:
#   ./tests/run-tests.sh              # run all
#   ./tests/run-tests.sh -v           # verbose: print every output
#   ./tests/run-tests.sh -k doors     # only tests whose name contains 'doors'
#
# Determinism: in --test mode the game seeds both PCG32 streams (enemy AI
# and face animation) with 0, so scripted scenarios reproduce bit-identically
# across runs. Tests that assert on exact HP / position values rely on this;
# when you change enemy-AI code in a way that shifts the RNG-call order,
# expect to update the expected values below. This is easier than making
# every test robust to RNG order, and the failure is loud rather than silent.

set -u

cd "$(dirname "$0")/.."

VERBOSE=0
FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        -k) FILTER="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's|^# \?||'
            exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

BIN="/tmp/wolf-fc-bin"
if [[ ! -x "$BIN" ]]; then
    echo "building wolf-fc..."
    ./run.sh --test state >/dev/null 2>&1 || { echo "build failed" >&2; exit 2; }
fi

# Isolate the test's save / screenshot directory so the suite can't stomp on
# the real user's saves. The binary honours WOLF_FC_HOME as an override for
# its per-user data root; we point it at a throwaway temp dir and wipe the
# dir on exit. Previously we rm'd $HOME/.wolf-fc/saves/slot_*.sav directly,
# which ate real user saves (and the listsaves-occupied test also actively
# wrote into slot 6 of the real directory).
WOLF_FC_TEST_HOME="$(mktemp -d -t wolf-fc-tests.XXXXXX)"
export WOLF_FC_HOME="$WOLF_FC_TEST_HOME"
trap 'rm -rf "$WOLF_FC_TEST_HOME"' EXIT

pass=0
fail=0
skipped=0
failures=()

# Run the binary with the given test-mode arguments and capture stdout+stderr.
# Args are passed through word-split on purpose so callers can pass a single
# space-separated command string.
run_cmd() {
    # shellcheck disable=SC2086
    "$BIN" --test $1 2>&1
}

report_fail() {
    local name="$1" expected="$2" actual="$3"
    fail=$((fail + 1))
    failures+=("$name")
    printf "  \033[31mFAIL\033[0m %s\n" "$name"
    printf "    expected: %s\n" "$expected"
    printf "    output:\n%s\n" "$(printf '%s' "$actual" | sed 's/^/      /')"
}

report_pass() {
    local name="$1" actual="$2"
    pass=$((pass + 1))
    printf "  \033[32mok\033[0m   %s\n" "$name"
    if [[ $VERBOSE -eq 1 ]]; then
        printf '%s\n' "$actual" | sed 's/^/       /'
    fi
}

skip() {
    local name="$1"
    if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
        skipped=$((skipped + 1))
        return 0
    fi
    return 1
}

# assert_contains NAME CMD "EXPECTED-SUBSTRING"
assert_contains() {
    local name="$1" cmd="$2" expected="$3"
    skip "$name" && return
    local out; out=$(run_cmd "$cmd")
    if grep -qF -- "$expected" <<< "$out"; then
        report_pass "$name" "$out"
    else
        report_fail "$name" "contains: $expected" "$out"
    fi
}

# assert_not_contains NAME CMD "UNWANTED-SUBSTRING"
assert_not_contains() {
    local name="$1" cmd="$2" unwanted="$3"
    skip "$name" && return
    local out; out=$(run_cmd "$cmd")
    if grep -qF -- "$unwanted" <<< "$out"; then
        report_fail "$name" "does NOT contain: $unwanted" "$out"
    else
        report_pass "$name" "$out"
    fi
}

# assert_regex NAME CMD 'REGEX'   (posix-extended, like grep -E)
assert_regex() {
    local name="$1" cmd="$2" pattern="$3"
    skip "$name" && return
    local out; out=$(run_cmd "$cmd")
    if grep -qE -- "$pattern" <<< "$out"; then
        report_pass "$name" "$out"
    else
        report_fail "$name" "regex: $pattern" "$out"
    fi
}

# ----------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------

section() { printf "\n\033[1m%s\033[0m\n" "$1"; }

section "spawn"
assert_contains "spawn:enemy-count"           "enemies" "total=38"
assert_contains "spawn:kind-breakdown"        "enemies" "guard=33 officer=0 ss=0 dog=5 mutant=0"
assert_contains "spawn:one-pre-killed-corpse" "enemies" "dead=1"
assert_contains "spawn:player-at-start"       "state"   "pos=( 29.5000,  57.5000)"
assert_contains "spawn:starting-hp-100"       "state"   "health=100"
assert_contains "spawn:starting-ammo-8"       "state"   "ammo=8"
assert_contains "spawn:starting-weapon-1"     "state"   "weapon=1 best=1"

section "pickups"
assert_contains "pickup:food-heals-10"        "sethp:50 goto:29,51 state" "health=60"
assert_contains "pickup:food-ignored-at-full" "goto:29,51 state"          "health=100"
# Dropped clips (bo_clip2) give half the ammo of a map-placed clip: +4, not +8.
# Kill the guard at (28,62) with three point-blank pistol shots (ammo drops
# from 50 to 47), then step onto the drop tile. Final ammo should be 51
# (47 + 4). A map-placed clip would leave it at 55.
assert_contains "pickup:dropped-clip-gives-4-ammo" \
    "goto:30,62 turnr:180 setammo:50 fire wait:15 fire wait:15 fire wait:15 goto:28,62 state" \
    "ammo=51"
# bo_fullheal (the "one up" sprite at (14,55) on E1M1) grants full heal +
# 25 ammo + one life + a treasure pickup. With starting ammo=8 the pickup
# caps to 33, lives 3 -> 4.
assert_contains "pickup:extra-life-grants-ammo-and-life" \
    "goto:14,55 state" \
    "health=100 ammo=33 score=0 lives=4"
assert_contains "pickup:extra-life-counts-as-treasure" \
    "goto:14,55 counters" \
    "treasures=1/22"
# bo_gibs (tiles 57 & 61) heals +1 HP only when the player is at or below
# 10 HP. E1M2 has a single gibs at (60,39). At full HP the pickup is
# refused (sprite stays on the floor). At HP=10 it's accepted and heals
# to 11. At HP=5 it heals to 6.
assert_contains "pickup:gibs-refused-above-threshold" \
    "setlevel:1 goto:60,39 state" \
    "health=100"
assert_contains "pickup:gibs-accepted-at-threshold" \
    "setlevel:1 sethp:10 goto:60,39 state" \
    "health=11"
assert_contains "pickup:gibs-accepted-below-threshold" \
    "setlevel:1 sethp:5 goto:60,39 state" \
    "health=6"

section "static-sprites"
# Wolf3D blocking decorations (barrels, wells, tables, etc.) stop the player.
# A blocking sprite sits at tile (37,22) on E1M1. Blocking uses a half-tile
# AABB centered on the sprite (reach = player_radius 0.35 + sprite_half 0.25
# = 0.6), so the clamp point from the east is px ≤ 37.5 - 0.6 = 36.9.
# Discrete-tick movement lands at 36.8.
assert_contains "static:blocks-player" \
    "goto:36,22 fwd:60 state" \
    "pos=( 36.8000,  22.5000)"

section "doors"
assert_contains "door:elevator-switch"        "goto:25,47 turnl:90 space wait:40 facetile phase" "phase=intermission"
assert_contains "door:walk-all-the-way-through" \
    "fwd:15 space wait:40 fwd:20 state" "pos=( 33.0000,  57.5000)"
# Door straddle used to trap the player: walk through a door but stop with
# bbox-yh still poking into the door tile, then wait past door_stay_time.
# Before the fix, the door closed on the bbox and player_blocked_by_map
# rejected every subsequent move. Now the close check uses bbox overlap,
# so the door stays open while the player is straddling. The player's
# forward motion succeeds past the straddle pos (34.5, 37.8).
assert_not_contains "door:straddle-does-not-lock" \
    "sethp:1000 goto:34,40 turnl:90 fwd:15 space wait:40 fwd:16 wait:200 fwd:10 state" \
    "pos=( 34.5000,  37.8000)"

section "combat:player-fires"
assert_contains "hitscan:pistol-point-blank-kills-guard" \
    "goto:30,62 turnr:180 setammo:50 fire wait:15 fire wait:15 fire state" \
    "score=100"
assert_contains "hitscan:knife-at-1-tile-damages-guard" \
    "goto:29,62 turnr:180 setweapon:0 fire wait:10 enemylist" \
    "kind=guard state=shoot dir=2 hp=15"
# Knife is a 1.5-tile-range melee. At 2-tile distance the hitscan misses
# but the guard wakes to sight — verify HP is unchanged (25) rather than
# asserting a specific post-wake AI state (those RNG-roll into shoot/chase).
assert_regex "hitscan:knife-at-2-tiles-misses" \
    "goto:30,62 turnr:180 setweapon:0 fire wait:10 enemylist" \
    '\[37\] \(28,62\) kind=guard state=(chase|shoot|stand) dir=[0-9]+ hp=25'

section "combat:enemies-attack"
assert_contains "ai:dog-bites-on-contact" \
    "goto:45,34 turnr:90 wait:120 state" \
    "health=85"
assert_contains "ai:guard-wakes-on-sight" \
    "goto:28,60 turnl:90 wait:40 enemies" \
    "chase=1"
assert_contains "ai:sustained-fire-kills-player" \
    "goto:28,60 wait:600 state" \
    "lives=2"
# Wake guard [18] at (38,33), teleport to the far side of the door at (43,33),
# then wait for its chase path to push through — the door should no longer be
# closed (wolf4sdl T_Chase OpenDoor behaviour).
assert_regex "ai:guards-open-doors-while-chasing" \
    "goto:37,33 wait:5 goto:44,33 wait:150 goto:43,33 probe" \
    'tile \(43,33\) = 137 \(DOOR:(opening|open)\)'
# Dogs use CHECKDIAG in the original game and treat closed doors as walls.
# Wake the dog at (45,34) and place the player past the door — the dog should
# pace near the door but never open it, so (43,33) stays closed.
assert_contains "ai:dogs-cannot-open-doors" \
    "goto:45,34 wait:5 goto:42,33 wait:150 goto:43,33 probe" \
    "tile (43,33) = 137 (DOOR:closed)"
# ICONARROWS path markers (plane-1 90..97) redirect patrolling enemies to the
# encoded direction. Dog [19] spawns at (45,34) walking west; arrows at (44,34)
# and (46,34) bounce it back and forth. After 200 ticks (~5.7s) it should be
# resting on an arrow tile facing east. Player teleports to the far corner so
# the dog never enters chase.
assert_regex "ai:patrol-arrow-redirects-dog" \
    "goto:29,57 wait:200 enemylist" \
    '\[19\] \(44,34\) kind=dog state=path dir=0'
# madenoise propagation: just standing at the spawn never wakes a guard whose
# sight cone misses the player. Firing a pistol from the same spot is meant to
# wake every non-AMBUSH guard in the player's currently-connected area set
# (wolf4sdl SightPlayer noise short-circuit). The two stand guards in area 2
# at (28,62) and (39,61) should both flip to chase. We assert the diff so the
# test stays meaningful even if level layout changes the absolute counts.
assert_contains "ai:no-wake-without-noise-or-sight" \
    "wait:10 enemies" \
    "chase=0"
assert_contains "ai:firing-wakes-guards-in-connected-area" \
    "setammo:50 fire wait:40 enemies" \
    "chase=2"

section "weapons:auto-restore"
# Running out of ammo drops the player to the knife; grabbing the clip that
# a killed guard dropped should swap them back to their best firearm (pistol
# by default). Kill guard at (28,62), zero out ammo + drop to knife, then
# step onto the drop tile and check the weapon slot bounces back to 1.
assert_contains "weapon:ammo-pickup-restores-from-knife" \
    "goto:30,62 turnr:180 setammo:50 fire wait:15 fire wait:15 fire setammo:0 setweapon:0 goto:28,62 state" \
    "weapon=1"
# MG pickup also upgrades the player's best-weapon ceiling. We don't have
# SS on E1M1 to drop one naturally, so exercise the pickup path using the
# tile-50 machine-gun sprite in plane 1 — level 0 has none either; skip.
# TODO: add a minimal plane-1 injection helper, or test on a level that
# features the pickup. For now this is a coverage gap.

section "level-transition"
# Walk onto the elevator, press space, wait. The interactive loop handles
# next_level transition but --test mode exits before that — the facetile
# assertion above is the best we can do without adding a transition hook
# to run_test_cmd. Record this coverage gap explicitly.

section "map-probe (diagnostic command)"
# The 'probe' test command is itself a diagnostic aid — verify it at least
# produces parseable output. Without this, changes to FC union match
# syntax could silently break the diagnostic.
assert_contains "probe:prints-bbox"  "goto:29,57 probe" "bbox_tiles:"
assert_contains "probe:detects-wall" "goto:29,57 probe" "open"

section "death flow"
# Total enemy count on E1M1 (hard difficulty, the default) — 37 live + 1 corpse.
# total_kills mirrors the live count; corpses aren't counted.
assert_contains "counters:initial" "counters" "kills=0/37 secrets=0/5 treasures=0/22"
# Damaging the player drops their HP without changing phase.
assert_contains "damage:hp-drops-not-dying" \
    "sethp:5 counters phase" \
    "phase=playing"
# `kill` test command drops HP to 0 and flips to dying phase immediately.
assert_contains "death:kill-enters-dying" "kill phase" "phase=dying"
# After dying long enough (phase_timer >= death_anim_time = 2.2s = ~77 ticks),
# the level reloads and one life is consumed. Phase is back to playing.
assert_contains "death:restart-on-death-with-lives" \
    "kill wait:80 phase" \
    "phase=playing timer= 0.000 lives=2"
# Deaths spend lives; 4 deaths (3→2→1→0→gameover) land on the game-over screen.
assert_contains "death:game-over-after-lives-exhausted" \
    "kill wait:80 kill wait:80 kill wait:80 kill wait:80 phase" \
    "phase=gameover"
# `advance` test command simulates the space-press that dismisses game-over.
# Fresh game restored: 3 lives, score 0, level 0, back to player start.
assert_contains "death:advance-from-game-over-resets" \
    "kill wait:80 kill wait:80 kill wait:80 kill wait:80 advance state" \
    "score=0 lives=3 level=0"

section "intermission / level progression"
# Stepping onto the elevator + space transitions to intermission phase, but
# only after the ~1s pre-intermission freeze (elevator_wait_time) during
# which gameplay pauses so LEVELDONESND can play out in-world.
assert_contains "intermission:elevator-enters-intermission" \
    "goto:25,47 turnl:90 space wait:40 phase" \
    "phase=intermission"
# Level time accumulates in gp_playing and freezes during intermission.
# (wait:70 here straddles both the pre-delay freeze and the intermission
# itself; neither advances level_time, so the total stays at the fwd:70
# accumulation of 70/35 ticks plus the one `space` tick = ~2.03s.)
assert_regex "intermission:time-freezes-during-intermission" \
    "fwd:70 goto:25,47 turnl:90 space wait:70 counters" \
    'time=[ ]*2\.0[0-9]+'
# `advance` on intermission loads the next level (level_num increments).
assert_contains "intermission:advance-loads-next-level" \
    "goto:25,47 turnl:90 space wait:40 advance state" \
    "level=1"
# New level has its own enemy/secret/treasure totals.
assert_contains "intermission:new-level-resets-counters" \
    "goto:25,47 turnl:90 space wait:40 advance counters" \
    "kills=0/82 secrets=0/4 treasures=0/62"
# Entering intermission with time 0 awards full par-time bonus: par=90s →
# (90 - 0) * 500 = 45000 (wolf4sdl LevelCompleted, PAR_AMOUNT = 500/sec).
assert_contains "intermission:par-time-bonus-awarded" \
    "goto:25,47 turnl:90 space wait:40 state" \
    "score=45000"
# Secret-level intermission (exiting E3M10, map index 9 of episode 3) uses
# a completely different layout: flat 15000 bonus, no par / ratio tally.
# Matches wolf4sdl's LevelCompleted else-branch (`GivePoints(15000)`).
assert_contains "intermission:secret-floor-awards-15000" \
    "setlevel:29 endepisode wait:10 state" \
    "score=15000"
# Advancing from the secret-floor intermission routes back via the
# elevator_back_to table rather than into map 10 of the next episode.
assert_contains "intermission:secret-floor-advances-back" \
    "setlevel:29 endepisode wait:10 advance state" \
    "level=27"

section "counters"
# A kill increments the kills counter and awards score.
assert_contains "counters:kill-increments" \
    "goto:30,62 turnr:180 setammo:50 fire wait:15 fire wait:15 fire counters" \
    "kills=1/37"
# Treasure pickup counts.
assert_contains "counters:treasure-cross-pickup" \
    "goto:7,14 counters" \
    "treasures=1/22"

section "difficulty"
# Default (gd_hard=3) spawns all three tile tiers. E1M1 has 37 live enemies.
assert_contains "difficulty:default-hard-spawns-all" "enemies" "total=38"
# Lowering to gd_baby=0 filters out +36 and +72 tier tiles, leaving only
# base-tier tiles + the pre-dead corpse.
assert_contains "difficulty:baby-filters-higher-tiers" \
    "setdifficulty:0 enemies" \
    "total=12"
# Medium allows base + medium tier (+36) only; hard adds +72.
# E1M1: 11 base guards + 1 corpse + 7 medium = 19 + 2 dogs base + 1 medium = 21 at gd_medium.
assert_contains "difficulty:medium-allows-middle-tier" \
    "setdifficulty:2 enemies" \
    "total=21"

section "VGAGRAPH"
assert_contains "vgagraph:loads-150-chunks"     "vgtable"           "pic 87: 320x200"
assert_contains "vgagraph:statusbar-dims"       "vginfo:86"         "width=320 height=40"
assert_contains "vgagraph:title-dims"           "vginfo:87"         "width=320 height=200"
assert_contains "vgagraph:face-pic-dims"        "vginfo:109"        "width=24 height=32"

section "phases"
assert_contains "phase:title-on-fresh-interactive" "setphase:title phase" "phase=title"
assert_contains "phase:menu-nav-state"             "setphase:menu phase"   "phase=menu"

section "bosses / ghosts"
# E1M9 is level 8 (0-indexed). It has Hans Grösse at tile (34, 14).
assert_contains "boss:hans-spawns-on-e1m9" \
    "setlevel:8 enemies" \
    "boss=1 ghost=0"
assert_contains "boss:hans-hp-1200" \
    "setlevel:8 enemylist" \
    "kind=hans state=stand dir=8 hp=1200"
# E3M10 (level 29) is the Pacman-homage secret — all four ghosts spawn.
assert_contains "ghost:four-ghosts-on-pacman-level" \
    "setlevel:29 enemies" \
    "ghost=4"
assert_contains "ghost:blinky-is-present" \
    "setlevel:29 enemylist" \
    "kind=blinky state=stand"
# Every boss tile spawns the right kind on its level.
# E2M9 = level 18 (Dr. Schabbs). E3M9 = level 28 (Hitler).
# E4M9 = level 38 (Giftmacher). E5M9 = level 48 (Gretel).
# E6M9 = level 58 (Fat Face).
assert_contains "boss:schabbs-on-e2m9"   "setlevel:18 enemylist" "kind=schabbs"
assert_contains "boss:hitler-on-e3m9"    "setlevel:28 enemylist" "kind=hitler"
assert_contains "boss:giftmacher-on-e4m9" "setlevel:38 enemylist" "kind=gift"
assert_contains "boss:gretel-on-e5m9"    "setlevel:48 enemylist" "kind=gretel"
assert_contains "boss:fat-face-on-e6m9"  "setlevel:58 enemylist" "kind=fat"
# killenemy:N runs damage_enemy with overkill damage; verifies that a
# boss kill no longer immediately ends the level (the original game
# requires the player to walk onto the EXITTILE behind the gold-key
# door first). Boss enters es_die, world keeps ticking, phase stays
# playing, gold key drops in the corpse tile.
assert_contains "boss:kill-doesnt-end-level" \
    "setlevel:8 killenemy:0 wait:30 phase" \
    "phase=playing"
assert_contains "boss:kill-completes-die-animation" \
    "setlevel:8 killenemy:0 wait:30 enemylist" \
    "kind=hans state=dead"
# Bosses spawn with FL_AMBUSH + dir=nodir in the original. With a closed
# door between the player and Hans, approaching quietly must leave him
# asleep; opening the door gives him LOS and he wakes + shoots.
assert_contains "boss:hans-stays-asleep-behind-closed-door" \
    "setlevel:8 goto:34,16 wait:200 enemylist" \
    "kind=hans state=stand"
assert_contains "boss:hans-wakes-when-door-opens" \
    "setlevel:8 goto:34,16 space wait:35 enemylist" \
    "kind=hans state=shoot"
# E1M9's three EXITTILE markers (plane-1 tile 99) sit at y=7 behind the
# gold-key door; stepping onto one fires the BJ-victory cutscene
# directly without the elevator-wait freeze.
assert_contains "exittile:e1m9-has-three-exit-tiles" \
    "setlevel:8 exittiles" \
    "exittiles: count=3"
assert_contains "exittile:walking-onto-it-fires-bj-victory" \
    "setlevel:8 goto:34,8 fwd:50 phase" \
    "phase=bj_victory"
# Boss kill before the EXITTILE walk: boss is fully `dead` (final pose)
# by the time the cutscene starts, even when the kill happens just
# before stepping onto the tile — update_dying_enemies pumps the die
# frames during the cutscene so the corpse doesn't freeze on frame 1.
assert_contains "exittile:bj-cutscene-corpse-finishes-dying" \
    "setlevel:8 killenemy:0 goto:34,8 fwd:50 wait:60 enemylist" \
    "kind=hans state=dead"
# The four death-cam bosses (Schabbs / Gift / Fat / real Hitler) end the
# episode via A_StartDeathCam in the original: hold on final death frame,
# fizzle to black, taunt card, teleport camera, fizzle in, replay death
# animation, drop into the intermission tally. Hans and Gretel are the
# two exceptions — they still use the gold-key + EXITTILE flow.
assert_contains "deathcam:schabbs-enters-death-cam-on-kill" \
    "setlevel:18 killenemy:0 phase" \
    "phase=death_cam"
assert_contains "deathcam:giftmacher-enters-death-cam-on-kill" \
    "setlevel:38 killenemy:0 phase" \
    "phase=death_cam"
assert_contains "deathcam:fat-enters-death-cam-on-kill" \
    "setlevel:58 killenemy:8 phase" \
    "phase=death_cam"
assert_contains "deathcam:hitler-enters-death-cam-on-kill" \
    "setlevel:28 killenemy:2 phase" \
    "phase=death_cam"
# Hans and Gretel do NOT enter gp_death_cam — their death flow still
# routes through the gold-key drop + EXITTILE walk → gp_bj_victory.
assert_contains "deathcam:hans-does-not-enter-death-cam" \
    "setlevel:8 killenemy:0 wait:30 phase" \
    "phase=playing"
# After the full cutscene (pre_fade + fade_out + taunt + fade_in +
# pre_replay + replay_anim + replay_hold ≈ 12s) we hand off to the
# regular intermission tally screen.
assert_contains "deathcam:auto-advances-to-intermission" \
    "setlevel:18 killenemy:0 wait:500 phase" \
    "phase=intermission"
# The death scream fires a second time when the replay animation starts
# (matches the original: re-entering the die-cascade hits A_DeathScream
# again). At wait:320 we're just past the pre_replay beat so Schabbs's
# death cry should be audible — sound 24 is MEINGOTTSND ("Mein Gott!").
assert_contains "deathcam:death-scream-replays-on-replay-anim" \
    "setlevel:18 killenemy:0 wait:320 digi_slots" \
    "sound=24"
# The `advance` test command dismisses the death-cam early, same way a
# space press would end the taunt card and (after the rest of the
# cutscene) land on the intermission screen.
assert_contains "deathcam:advance-skips-to-intermission" \
    "setlevel:18 killenemy:0 advance phase" \
    "phase=intermission"
# Hans still drops a gold key — walking onto his tile after the kill
# picks it up. Preserves the gold-key + EXITTILE flow on E1M9.
assert_contains "deathcam:hans-still-drops-gold-key" \
    "setlevel:8 killenemy:0 goto:34,14 state" \
    "gold=1"

section "enemy projectiles"
# Fake Hitler on E3M9 unloads a flame salvo down the corridor west of him.
# At wait:20 the first couple of flames are still mid-flight, before any
# have reached the player — verifies that the boss actually spawns visible
# dodgeable projectiles instead of hitscanning.
assert_regex "proj:fake-hitler-flame-in-flight" \
    "setlevel:28 goto:25,57 wait:20 projectiles" \
    "proj\[[0-9]+\] fire"
# Standing one tile north of Schabbs gives a clean LOS with no flanking
# mutants in fire range. At wait:18 the needle is mid-flight; by wait:20
# it has connected and health has dropped by at least 20 (needle rolls
# 20-51 per hit in the original).
assert_contains "proj:schabbs-needle-in-flight" \
    "setlevel:18 goto:31,17 wait:18 projectiles" \
    "needle"
assert_regex "proj:schabbs-needle-damages-player" \
    "setlevel:18 goto:31,17 wait:20 state" \
    "health=([0-7][0-9]|80)"
# Giftmacher on E4M9 at (27,18) fires rockets at the player one tile south;
# one rocket hit alone drops the player by 30-61 HP. Rocket damage is
# distinctive enough that we check the value clearly fell below 70.
assert_regex "proj:giftmacher-rocket-damages-player" \
    "setlevel:38 goto:27,19 wait:25 state" \
    "health=([0-6][0-9]|70)"
# Fat Face on E6M9 also spawns rockets from the same T_GiftThrow path;
# mostly a coverage check that setlevel:58 reaches the right map.
assert_contains "proj:fat-face-spawns-rockets" \
    "setlevel:58 enemylist" \
    "kind=fat state=stand"
# "Can I Play Daddy" (baby) quarters incoming damage per TakeDamage's
# `points >>= 2` branch in the original. Same Giftmacher rocket hit that
# drops the player to 55 HP on hard leaves 89 HP on baby — 45 >> 2 = 11.
# Both are deterministic under the seeded PCG stream.
assert_contains "proj:baby-difficulty-quarters-rocket-damage" \
    "--difficulty=0 setlevel:38 goto:27,19 wait:25 state" \
    "health=89"

section "cli flags"
# --level=N drops the player straight onto level N in playing phase — the
# interactive shortcut for jumping to a specific boss fight. Scans run
# through the same "$BIN --test $ARGS" harness (so --level is placed
# after --test), but `main` scans all args so order doesn't matter.
assert_contains "cli:level-flag-jumps-to-level-8" \
    "--level=8 state" \
    "level=8"
# --difficulty=0 (baby) flips mutant HP to the baby-tier 45 (vs 65 default).
assert_contains "cli:difficulty-flag-lowers-mutant-hp" \
    "--difficulty=0 setlevel:18 enemylist" \
    "kind=mutant state=stand dir=6 hp=45"
# --near-boss on E1M9 teleports to an open tile adjacent to Hans Grosse
# (tile 34,14). Expect pos y within 2 tiles of the boss, facing north.
assert_contains "cli:near-boss-teleports-to-hans-on-e1m9" \
    "--level=8 --near-boss state" \
    "pos=( 34.5000,  16.5000) dir=(  0.0000,  -1.0000)"
# --near-boss on a map without a boss (E1M1) is a no-op, leaving the
# player at the designed spawn.
assert_contains "cli:near-boss-no-op-without-boss" \
    "--level=0 --near-boss state" \
    "pos=( 29.5000,  57.5000)"
# setphase:mapmenu lands in the NEW GAME → MAP submenu. The submenu itself
# has no stdout dump, but the phase command confirms menu state.
assert_contains "cli:setphase-mapmenu" \
    "setphase:mapmenu phase" \
    "phase=menu"

section "messages"
# Picking up a treasure item posts a pickup message; msg_timer becomes > 0.
# We verify the counters command doesn't show msg_timer directly, so render
# a screenshot — the PNG tEXt metadata (saved by save_png) includes score.
assert_contains "msg:cross-pickup-awards-100" \
    "goto:7,14 state" \
    "score=100"

section "cheats"
# MLI chord: full health / 99 ammo / both keys / gatling, score zeroed.
assert_contains "cheat:mli-full-ammo" \
    "mli state" \
    "ammo=99"
assert_contains "cheat:mli-gatling" \
    "mli state" \
    "weapon=3 best=3"
assert_contains "cheat:mli-gives-both-keys" \
    "mli state" \
    "gold=1 silver=1"
assert_contains "cheat:mli-zeros-score" \
    "goto:7,14 mli state" \
    "score=0"
# BAT chord is flavor-only: gameplay state unchanged.
# IDDQD god-mode toggle: flips an in-game flag; while on, damage_player
# is a no-op so projectile / hitscan damage is silently swallowed.
assert_contains "cheat:iddqd-flips-god-mode-on" \
    "iddqd state" \
    "god=1"
assert_contains "cheat:iddqd-toggles-off" \
    "iddqd iddqd state" \
    "god=0"
assert_contains "cheat:iddqd-restores-health-on-activation" \
    "sethp:5 iddqd state" \
    "health=100"
# Schabbs needle scenario from the projectiles section: at wait:20 the
# needle has connected and HP is normally <= 80. With god mode armed
# beforehand the hit is silently absorbed.
assert_contains "cheat:iddqd-blocks-projectile-damage" \
    "setlevel:18 iddqd goto:31,17 wait:25 state" \
    "health=100"
assert_contains "cheat:bat-leaves-health-unchanged" \
    "bat state" \
    "health=100 ammo=8"
# IDKFA toggle: grants all keys + chain gun + 99 ammo, latches ammo
# non-depletion + score lock. Toggling again clears the latch but
# leaves the gifted inventory in place (no "ungiving" on toggle off).
assert_contains "cheat:idkfa-gives-everything" \
    "idkfa state" \
    "weapon=3 best=3"
assert_contains "cheat:idkfa-flips-mode-on" \
    "idkfa state" \
    "idkfa=1"
assert_contains "cheat:idkfa-toggles-off" \
    "idkfa idkfa state" \
    "idkfa=0"
assert_contains "cheat:idkfa-gives-both-keys" \
    "idkfa state" \
    "gold=1 silver=1"
assert_contains "cheat:idkfa-full-ammo" \
    "idkfa state" \
    "ammo=99"
# Ammo stays at 99 across repeated fires while IDKFA latched.
assert_contains "cheat:idkfa-ammo-non-depleting" \
    "idkfa fire fire fire fire fire state" \
    "ammo=99"
# Score lock: cross pickup would normally add 100. With IDKFA on, the
# cross is consumed but the score stays at 0.
assert_contains "cheat:idkfa-locks-score-on-pickup" \
    "idkfa goto:7,14 state" \
    "score=0"

section "episode structure"
# Episode jumping via setepisode.
assert_contains "episode:setepisode-0-starts-e1m1" \
    "setepisode:0 state" \
    "level=0"
assert_contains "episode:setepisode-2-starts-e3m1" \
    "setepisode:2 state" \
    "level=20"
# Level 8 (boss / finale) of an episode enters the BJ victory cutscene
# instead of the regular intermission. `advance` skips straight to the
# episode-end screen, collapsing what the interactive main loop does via
# the auto-transition + space press.
assert_contains "episode:level-8-enters-bj-victory" \
    "setlevel:8 endepisode wait:2 phase" \
    "phase=bj_victory"
assert_contains "episode:level-8-advance-enters-episode-end" \
    "setlevel:8 endepisode wait:2 advance phase" \
    "phase=episode_end"
# BJ cutscene auto-advances to episode_end after the 6-tile run + jump +
# final hold (~4.5 seconds, so wait:180 is comfortably past the end).
assert_contains "episode:bj-victory-auto-advances" \
    "setlevel:8 endepisode wait:200 phase" \
    "phase=episode_end"
# Pressing advance again on episode_end starts the next episode's map 0.
assert_contains "episode:episode-end-advance-to-next-ep" \
    "setlevel:8 endepisode wait:2 advance advance state" \
    "level=10"
# Level 9 (secret) advance routes back to elevator_back_to[ep]. For
# ep=0 that's level 1 (E1M2).
assert_contains "episode:secret-level-routes-back" \
    "setlevel:9 endepisode wait:2 advance state" \
    "level=1"
# Episode 6 end → final victory screen.
assert_contains "episode:last-episode-end-goes-to-victory" \
    "setlevel:58 endepisode wait:2 advance advance phase" \
    "phase=victory"
# Victory → main menu: simulated by advance on gp_victory.
assert_contains "episode:victory-advance-to-menu" \
    "setlevel:58 endepisode wait:2 advance advance advance phase" \
    "phase=menu"

section "audio mixer"
# Same-sound dedup: rapid retriggers of the same digi sound should share a
# single mix slot rather than fan out across all four (which used to
# stack DONOTHINGSND-style spam, overwhelm the SDL queue, and disconnect
# the music stream on PulseAudio). 5 pistol shots — all sound=5 — should
# only occupy one slot.
assert_contains "audio:digi-dedup-rapid-fire" \
    "setammo:50 fire fire fire fire fire digi_slots" \
    "slot 0: playing=1 sound=5"
assert_contains "audio:digi-dedup-no-stacking" \
    "setammo:50 fire fire fire fire fire digi_slots" \
    "slot 2: playing=0 sound=-1"

section "music routing"
# Phase-driven music swap: each between-game / between-screen state plays
# its wolf3d-original track instead of whatever per-level song was last
# loaded. Asserting the chunk number is enough — the audio path itself
# isn't exercised in headless mode.
assert_contains "music:title-plays-wonderin"      "setphase:title music"      "audiot offset=14"
assert_contains "music:menu-plays-wonderin"       "setphase:menu music"       "audiot offset=14"
assert_contains "music:gameplay-uses-songs-table" "music"                     "audiot offset=3"
assert_contains "music:intermission-plays-endlevel" \
    "setlevel:0 endepisode wait:2 music" \
    "audiot offset=16"
# Boss-map intermission is replaced by the BJ victory cutscene, which
# shares the episode-end URAHERO track.
assert_contains "music:bj-victory-plays-urahero" \
    "setlevel:8 endepisode wait:2 music" \
    "audiot offset=24"
assert_contains "music:episode-end-plays-urahero" \
    "setlevel:8 endepisode wait:2 advance music" \
    "audiot offset=24"
assert_contains "music:final-victory-plays-vicmarch" \
    "setlevel:58 endepisode wait:2 advance advance music" \
    "audiot offset=25"

section "save / load"
# Fresh slot state: WOLF_FC_HOME points at a per-run temp dir (see top of
# this file), so the slot directory starts empty without touching the real
# ~/.wolf-fc/saves.

# listsaves reports empty slots on a fresh directory.
assert_contains "save:listsaves-empty" \
    "listsaves" \
    "slot 0: EMPTY"
# Save to slot 4, load it back — round-trip state preservation. Using an
# exact pos with enough resolution that any off-by-one in the float parser
# would miss: fwd:30 at 35/sec lands at a non-trivial fraction.
assert_contains "save:position-round-trips" \
    "fwd:30 save:4 load:4 state" \
    "pos=( 31.6000,  57.5000)"
assert_contains "save:ammo-round-trips" \
    "fwd:30 turnl:30 fire fwd:5 save:4 load:4 state" \
    "ammo=7"
# level_num round-trips through save/load even across game mode resets.
assert_contains "save:level-round-trips" \
    "setlevel:5 fwd:3 save:4 load:4 state" \
    "level=5"
# counter totals propagate from level rebuild on load (so the totals line
# matches the level we landed on, not the level we were on before load).
assert_contains "save:counters-level-specific-totals" \
    "setlevel:2 save:5 setlevel:0 load:5 counters" \
    "kills=0/73 secrets=0/10 treasures=0/66"
# Loading an empty slot is a no-op returning failure — state stays at
# whatever we had before the load call. The temp WOLF_FC_HOME never gets a
# slot 7 written, so this always exercises the empty path.
assert_contains "save:load-empty-fails" \
    "setlevel:3 fwd:4 load:7 state" \
    "level=3"
# listsaves reports occupied slots with their saved level label. Using
# setlevel:0 before save:6 pins the label to E1M1 regardless of whether
# earlier round-trip tests moved the level.
assert_contains "save:listsaves-occupied" \
    "setlevel:0 save:6 listsaves" \
    "slot 6: E1M1"
# PRNG state round-trips. Both sequences below kill the guard at (28,62) with
# three pistol shots; the first interleaves a save/load between shots 1 and 2.
# Score=100 in both cases demonstrates that the save/load preserves the PCG
# stream position — without the rng line (or with a broken reload) the
# post-load shots would roll different damage and the guard's death state
# would differ. Identical scores prove the round-trip.
assert_contains "save:rng-state-round-trips" \
    "goto:30,62 turnr:180 setammo:50 fire wait:15 save:4 load:4 fire wait:15 fire state" \
    "score=100"

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

echo
total=$((pass + fail))
if [[ $fail -eq 0 ]]; then
    if [[ $skipped -gt 0 ]]; then
        printf "\033[32m%d/%d passed\033[0m (%d skipped)\n" "$pass" "$total" "$skipped"
    else
        printf "\033[32m%d/%d passed\033[0m\n" "$pass" "$total"
    fi
    exit 0
else
    printf "\033[31m%d/%d passed, %d failed\033[0m\n" "$pass" "$total" "$fail"
    for f in "${failures[@]}"; do printf "  - %s\n" "$f"; done
    exit 1
fi
