extends Resource
class_name GameBalance_EconomySanctum
## GameBalance_EconomySanctum
## Centralized economy + sanctum balance for MVP.
## All Ase/Ekwan flow, basic summon costs, and sanctum base values
## should be defined here so we don’t hardcode them across multiple services.
## Canon: mirrors “Legacy Never Dies” §8 (Economy & Progression – The Flow of Ase)
## and §7 (The Obosom Sanctum).

# ---------------------------------------------------------
# ASE GENERATION
# This should match what we see in the logs: +0.08 effective per tick
# and +1 banked roughly every ~13 ticks.
# If we change tick pacing later, we do it here.
# ---------------------------------------------------------
const ASE_TICK_BASE: float = 0.08
const ASE_BANK_PULSE: int = 1

# Minimum and maximum safety rails for Ase so we don’t go negative
# or explode during debug.
const ASE_MIN: int = 0
const ASE_MAX: int = 999_999

# ---------------------------------------------------------
# SUMMONING COSTS (Echoes from the Flame)
# Canon §8: Ase → action → legacy, no hard stalls.
# MVP rule: 1 summon action should be reachable within a few minutes of idle Ase.
# We keep a flat cost for now, but expose hooks for batch and discounts.
# ---------------------------------------------------------
const SUMMON_BASE_COST_ASE: int = 60    # MVP: 1 Echo = 60 Ase
const SUMMON_COST_BASE: int = SUMMON_BASE_COST_ASE  # alias for debug console / legacy
const SUMMON_BATCH_SIZE: int = 1        # MVP: we summon 1 at a time
const SUMMON_MAX_PER_ACTION: int = 5    # safety rail in case of future batching
const SUMMON_COST_PER_EXTRA: int = 0    # future: +X Ase per extra Echo in the same action
const SUMMON_DISCOUNT_FACTOR: float = 1.0  # 1.0 = no discount; 0.9 = 10% off

# ---------------------------------------------------------
# ASE ↔ EKWAN EXCHANGE (Economy epic, early)
# We don’t have Ekwan fully yet, but we already know we want
# the player to be able to trade “fluid” (Ase) for “hard” (Ekwan).
# These are placeholders and should be surfaced in the UI later.
# ---------------------------------------------------------
const EXCHANGE_ASE_TO_EKWAN_RATE: float = 0.5  # 1 Ase → 0.5 Ekwan
const EXCHANGE_EKWAN_TO_ASE_RATE: float = 2.0  # 1 Ekwan → 2 Ase

# ---------------------------------------------------------
# DEBUG ECONOMY (for console commands and tests)
# We centralize this so /give_ase and /summon in debug don’t drift.
# ---------------------------------------------------------
const DEBUG_ASE_GRANT: int = 500
const DEBUG_SUMMON_COST_OVERRIDE: int = -1  # -1 = use normal cost

# ---------------------------------------------------------
# SANCTUM / OBSOM TRIANGLE (Faith ↔ Harmony ↔ Favor)
# These are starting baselines. Real bonuses will scale off these.
# ---------------------------------------------------------
const SANCTUM_FAITH_BASE: int = 10
const SANCTUM_HARMONY_BASE: int = 10
const SANCTUM_FAVOR_BASE: int = 5

# Future: upkeep, capacity, hero-duty multipliers go here.

static func has(key: String) -> bool:
	if key == "ASE_TICK_BASE" or key == "ASE_BANK_PULSE" or key == "ASE_MIN" or key == "ASE_MAX":
		return true
	elif key == "SUMMON_BASE_COST_ASE" or key == "SUMMON_COST_BASE" or key == "SUMMON_BATCH_SIZE" or key == "SUMMON_MAX_PER_ACTION":
		return true
	elif key == "SUMMON_COST_PER_EXTRA" or key == "SUMMON_DISCOUNT_FACTOR":
		return true
	elif key == "EXCHANGE_ASE_TO_EKWAN_RATE" or key == "EXCHANGE_EKWAN_TO_ASE_RATE":
		return true
	elif key == "DEBUG_ASE_GRANT" or key == "DEBUG_SUMMON_COST_OVERRIDE":
		return true
	elif key == "SANCTUM_FAITH_BASE" or key == "SANCTUM_HARMONY_BASE" or key == "SANCTUM_FAVOR_BASE":
		return true
	return false
