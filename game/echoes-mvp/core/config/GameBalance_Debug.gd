extends Resource
class_name GameBalance_Debug
## GameBalance_Debug
## Debug / tooling balance values — ONLY for console commands, test harnesses,
## and quick in-editor play sessions. These must not affect shipped economy or
## combat pacing.
##
## If you need to give yourself Ase or summon multiple Echoes during MVP testing,
## read from here instead of hardcoding in debug_console.gd.

# ---------------------------------------------------------
# Debug economy helpers
# ---------------------------------------------------------
const DEBUG_GIVE_ASE_AMOUNT: int = 500   # what we kept using in /give_ase
const DEBUG_SUMMON_BATCH: int = 5        # /summon 5 → matches your workflow

# ---------------------------------------------------------
# Debug combat helpers
# ---------------------------------------------------------
const DEBUG_FIGHT_ROUNDS: int = 6        # matches current /fight_demo tests
const DEBUG_PARTY_SIZE: int = 3          # current MVP party selection

# ---------------------------------------------------------
# Debug enemy / realm test helpers
# Used by CombatEngine when spawning training enemies from the console.
# ---------------------------------------------------------
const DEBUG_ENEMY_COUNT: int = 3          # how many test enemies to spawn
const DEBUG_ENEMY_TIER: int = 1           # use realm tier 1 by default
const DEBUG_ENEMY_HP_OVERRIDE: int = -1   # -1 = use factory value
const DEBUG_ENEMY_ATK_OVERRIDE: int = -1  # -1 = use factory value

# ---------------------------------------------------------
# Safety rails (avoid flooding logs / creating 100 heroes by accident)
# ---------------------------------------------------------
const DEBUG_MAX_SUMMON_BATCH: int = 10   # hard upper limit for one debug call
const DEBUG_MAX_GIVE_ASE: int = 10_000   # prevent accidental zero-to-riches in tests

# ---------------------------------------------------------
# Logging / verbosity
# ---------------------------------------------------------
const LOG_COMBAT_STEPS: bool = true
const LOG_MORALE_TICKS: bool = true
const LOG_ECONOMY_TICKS: bool = true