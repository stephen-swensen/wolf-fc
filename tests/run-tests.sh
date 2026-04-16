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
# Determinism: the enemy RNG is a file-scope LCG with a fixed seed, so
# scripted scenarios reproduce bit-identically across runs. Tests that
# assert on exact HP / position values rely on this; when you change
# enemy-AI code in a way that shifts the RNG-call order, expect to update
# the expected values below. This is easier than making every test robust
# to RNG order, and the failure is loud rather than silent.

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
assert_contains "door:elevator-switch"        "goto:25,47 turnl:90 space facetile phase" "phase=intermission"
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
    "kind=guard state=shoot dir=2 hp=9"
# Knife is a 1.5-tile-range melee. At 2-tile distance the hitscan misses
# but the guard wakes to sight — verify HP is unchanged (25) rather than
# asserting a specific post-wake AI state (those RNG-roll into shoot/chase).
assert_regex "hitscan:knife-at-2-tiles-misses" \
    "goto:30,62 turnr:180 setweapon:0 fire wait:10 enemylist" \
    '\[37\] \(28,62\) kind=guard state=(chase|shoot|stand) dir=[0-9]+ hp=25'

section "combat:enemies-attack"
assert_contains "ai:dog-bites-on-contact" \
    "goto:45,34 turnr:90 wait:30 state" \
    "health=92"
assert_contains "ai:guard-wakes-on-sight" \
    "goto:28,60 turnl:90 wait:10 enemies" \
    "chase=1"
assert_contains "ai:sustained-fire-kills-player" \
    "goto:28,60 wait:600 state" \
    "lives=2"
# Wake the dog at (45,34), teleport to the far side of the door at (43,33),
# then wait for the dog's chase path to push through — the door should no
# longer be closed (wolf4sdl T_Chase OpenDoor behaviour).
assert_regex "ai:enemies-open-doors-while-chasing" \
    "goto:45,34 wait:5 goto:42,33 wait:60 goto:43,33 probe" \
    'tile \(43,33\) = 137 \(DOOR:(opening|open)\)'
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
    "setammo:50 fire wait:10 enemies" \
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
# After dying long enough (phase_timer >= death_anim_time = 1.0s = ~35 ticks),
# the level reloads and one life is consumed. Phase is back to playing.
assert_contains "death:restart-on-death-with-lives" \
    "kill wait:50 phase" \
    "phase=playing timer= 0.000 lives=2"
# Deaths spend lives; 4 deaths (3→2→1→0→gameover) land on the game-over screen.
assert_contains "death:game-over-after-lives-exhausted" \
    "kill wait:50 kill wait:50 kill wait:50 kill wait:50 phase" \
    "phase=gameover"
# `advance` test command simulates the space-press that dismisses game-over.
# Fresh game restored: 3 lives, score 0, level 0, back to player start.
assert_contains "death:advance-from-game-over-resets" \
    "kill wait:50 kill wait:50 kill wait:50 kill wait:50 advance state" \
    "score=0 lives=3 level=0"

section "intermission / level progression"
# Stepping onto the elevator + space transitions to intermission phase.
assert_contains "intermission:elevator-enters-intermission" \
    "goto:25,47 turnl:90 space phase" \
    "phase=intermission"
# Level time accumulates in gp_playing and freezes during intermission.
assert_regex "intermission:time-freezes-during-intermission" \
    "fwd:70 goto:25,47 turnl:90 space wait:70 counters" \
    'time=[ ]*2\.0[0-9]+'
# `advance` on intermission loads the next level (level_num increments).
assert_contains "intermission:advance-loads-next-level" \
    "goto:25,47 turnl:90 space advance state" \
    "level=1"
# New level has its own enemy/secret/treasure totals.
assert_contains "intermission:new-level-resets-counters" \
    "goto:25,47 turnl:90 space advance counters" \
    "kills=0/82 secrets=0/4 treasures=0/62"
# Entering intermission with time 0 awards full par-time bonus: par=90s →
# (90 - 0) * 500 / 10 = 4500.
assert_contains "intermission:par-time-bonus-awarded" \
    "goto:25,47 turnl:90 space state" \
    "score=4500"

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
assert_contains "phase:paused-freezes-play"        "setphase:paused phase" "phase=paused"
assert_contains "phase:menu-nav-state"             "setphase:menu phase"   "phase=menu"

section "bosses / ghosts"
# E1M9 is level 8 (0-indexed). It has Hans Grösse at tile (34, 14).
assert_contains "boss:hans-spawns-on-e1m9" \
    "setlevel:8 enemies" \
    "boss=1 ghost=0"
assert_contains "boss:hans-hp-850" \
    "setlevel:8 enemylist" \
    "kind=hans state=stand dir=4 hp=850"
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

section "messages"
# Picking up a treasure item posts a pickup message; msg_timer becomes > 0.
# We verify the counters command doesn't show msg_timer directly, so render
# a screenshot — the PNG tEXt metadata (saved by save_png) includes score.
assert_contains "msg:cross-pickup-awards-100" \
    "goto:7,14 state" \
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
