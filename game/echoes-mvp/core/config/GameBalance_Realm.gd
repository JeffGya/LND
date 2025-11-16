extends Resource
class_name GameBalance_Realm
## GameBalance_Realm
## Realm-level balance settings: realm catalog, stage structure, difficulty tiers,
## objective weights and reward baselines derived from the canon (§6 World / Realm Structure,
## §8 Economy & Progression, §12 Balance Curves).
##
## MVP NOTE:
##  - Realm stage count is FIXED to 5 per run (Realm = 5 stages).
##  - Post-MVP we can move to per-realm min/max and randomization.
##    Callers should always ask this file for stage count / ranges instead
##    of hardcoding "5" so the change is localized here.

# ---------------------------------------------------------
# REALM CATALOG & STAGE STRUCTURE (MVP + future-proof)
# ---------------------------------------------------------

# Fixed stage count for MVP. Generators should call get_stage_count()
# instead of using this directly, so we can change behavior later.
const REALM_STAGE_COUNT_MVP: int = 5

# Realm registry. Keys are stable ids that other systems will use.
# Virtue is a lowercase token to keep comparisons simple.
const REALM_LIST := {
	"vale_of_dust": {
		"name": "Vale of Dust",
		"virtue": "courage",
		"default_tier": 1,
	},
	"shrouded_grove": {
		"name": "Shrouded Grove",
		"virtue": "wisdom",
		"default_tier": 1,
	},
}

# Stage configuration per realm. MVP keeps min==max==5 (fixed),
# but the structure lets us add ranges per realm post-MVP.
const REALM_STAGE_CONFIG := {
	"default": {
		"min": REALM_STAGE_COUNT_MVP,
		"max": REALM_STAGE_COUNT_MVP,
	},
}

static func get_realm_ids() -> Array[String]:
	## Returns all known realm ids (e.g., ["vale_of_dust", "shrouded_grove"]).
	## REALM_LIST.keys() returns an untyped Array, so we copy into an Array[String].
	var ids: Array[String] = []
	for k in REALM_LIST.keys():
		ids.append(String(k))
	return ids

static func get_realm_meta(realm_id: String) -> Dictionary:
	## Returns metadata for a realm or {} if unknown.
	return REALM_LIST.get(realm_id, {})

static func get_stage_range(realm_id: String = "") -> Dictionary:
	## Returns {min, max} stage count for the given realm.
	## MVP: both are 5; post-MVP we can widen per realm.
	var cfg: Dictionary = REALM_STAGE_CONFIG.get(realm_id, REALM_STAGE_CONFIG["default"])
	var min_count: int = int(cfg.get("min", REALM_STAGE_COUNT_MVP))
	var max_count: int = int(cfg.get("max", REALM_STAGE_COUNT_MVP))
	return {
		"min": min_count,
		"max": max_count,
	}

static func get_stage_count(realm_id: String = "") -> int:
	## MVP helper: returns the fixed stage count for a realm.
	## Post-MVP, generators can choose a random int in [min, max]
	## from get_stage_range(). For now we always return max.
	var range := get_stage_range(realm_id)
	if range["min"] == range["max"]:
		return range["min"]
	return range["max"]

# ---------------------------------------------------------
# ENCOUNTER PACING (within a realm run)
# MVP realms should be short. This controls encounter count
# per stage or per run depending on how generators use it.
# ---------------------------------------------------------
const REALM_MIN_ENCOUNTERS: int = 2
const REALM_MAX_ENCOUNTERS: int = 5
const REALM_DEFAULT_ENCOUNTERS: int = 3

static func get_encounter_pacing() -> Dictionary:
	## Returns pacing hints for how many encounters to schedule.
	return {
		"min": REALM_MIN_ENCOUNTERS,
		"max": REALM_MAX_ENCOUNTERS,
		"default": REALM_DEFAULT_ENCOUNTERS,
	}

# ---------------------------------------------------------
# OBJECTIVE WEIGHTS (per realm)
# MVP uses two templates:
#  - "combat_trial"
#  - "purify_shrine"
# Generators will roll against these weights with a realm/seeded RNG.
# ---------------------------------------------------------
const REALM_OBJECTIVE_WEIGHTS := {
	"vale_of_dust": {
		"combat_trial": 70,
		"purify_shrine": 30,
	},
	"shrouded_grove": {
		"combat_trial": 55,
		"purify_shrine": 45,
	},
}

static func get_objective_weights(realm_id: String) -> Dictionary:
	## Returns objective weights for a realm.
	## Falls back to Vale of Dust as a safe default for unknown realms.
	if REALM_OBJECTIVE_WEIGHTS.has(realm_id):
		return REALM_OBJECTIVE_WEIGHTS[realm_id]
	return REALM_OBJECTIVE_WEIGHTS.get("vale_of_dust", {})

# ---------------------------------------------------------
# PURIFY SHRINE (objective-specific tuning)
# Canon: Purify Shrine is a two-wave survival trial with a
# corrupt, draining shrine plus shrine-specific morale drain
# and reward multipliers.
# All shrine implementations should read from this block
# instead of hard-coding numbers.
# ---------------------------------------------------------
const PURIFY_SHRINE := {
	# Number of waves for the shrine objective in MVP.
	"waves": 2,

	# Baseline enemy pack size per wave for shrines. This is
	# intentionally a little lighter than a standard combat_trial
	# at the same tier, since the party must fight two waves.
	"base_pack_size": 2,

	# Optional per-wave overrides for shrine pack sizes. Keys are
	# zero-based wave indices used by ObjectiveRunner (0, 1, ...).
	# MVP keeps both waves at the same size, but this allows us to
	# bump later waves slightly in future tiers without touching
	# EnemyFactory directly.
	"wave_pack_sizes": {
		0: 2, # Wave 0 (first wave)
		1: 2, # Wave 1 (second wave)
	},

	# Shrine HP and passive drain per wave. MVP approximates the
	# shrine "timer" as a per-wave drain; per-round drain and an
	# explicit shrine entity will be added in the combat epic.
	"shrine_hp_by_tier": {
		1: 100,
		2: 135,
		3: 170,
	},

	"shrine_passive_drain_per_wave": {
		1: 10,
		2: 15,
		3: 20,
	},

	# Morale loss applied to each participating hero after each
	# successful wave. Uses the same 0–100 morale scale as the
	# combat system. Values are tier-scaled for MVP.
	"morale_drain_per_wave": {
		1: 3, # Tier 1 shrine: gentle pressure
		2: 4, # Tier 2 shrine: noticeable tax
		3: 5, # Tier 3 shrine: spiritually exhausting
	},

	# Reward multipliers applied on top of the standard stage
	# reward calculation for shrines. These make shrines slightly
	# more rewarding than a regular combat_trial at the same tier.
	"reward_multiplier": {
		1: 1.1,
		2: 1.2,
		3: 1.3,
	},
}

static func get_purify_waves() -> int:
	## Returns the configured number of waves for shrine objectives.
	var cfg: Dictionary = PURIFY_SHRINE
	return int(cfg.get("waves", 2))

static func get_purify_base_pack_size() -> int:
	## Returns the baseline pack size for shrine waves.
	var cfg: Dictionary = PURIFY_SHRINE
	return int(cfg.get("base_pack_size", 2))

static func get_purify_pack_size(tier: int, wave_index: int) -> int:
	## Returns the configured pack size for a shrine wave.
	## MVP behavior:
	##  - Uses PURIFY_SHRINE.wave_pack_sizes[wave_index] when present.
	##  - Falls back to base_pack_size otherwise.
	##  - Ignores tier for now, but the signature includes it so
	##    we can introduce tier-based sizing later without touching
	##    callers.
	var cfg: Dictionary = PURIFY_SHRINE
	var base_size: int = int(cfg.get("base_pack_size", 2))
	if base_size < 1:
		base_size = 1

	var wave_sizes: Dictionary = cfg.get("wave_pack_sizes", {})
	if wave_sizes.has(wave_index):
		var override_size: int = int(wave_sizes.get(wave_index, base_size))
		if override_size >= 1:
			return override_size

	return base_size

static func get_purify_morale_drain(tier: int) -> int:
	## Returns the morale drain applied per wave for a given tier.
	## If the tier is not explicitly configured, falls back to tier 1.
	var drains: Dictionary = PURIFY_SHRINE.get("morale_drain_per_wave", {})
	if not drains.has(tier):
		tier = 1
	var amount: int = int(drains.get(tier, 3))
	return amount

static func get_purify_reward_mult(tier: int) -> float:
	## Returns the shrine reward multiplier for a given tier.
	## If the tier is not explicitly configured, falls back to tier 1.
	var mults: Dictionary = PURIFY_SHRINE.get("reward_multiplier", {})
	if not mults.has(tier):
		tier = 1
	var mul: float = float(mults.get(tier, 1.1))
	return mul


static func get_purify_shrine_hp(tier: int) -> int:
	## Returns the max HP for shrine objectives at a given tier.
	## Defaults to the tier 1 value if the tier is unknown.
	var hp_by_tier: Dictionary = PURIFY_SHRINE.get("shrine_hp_by_tier", {})
	if not hp_by_tier.has(tier):
		tier = 1
	var hp: int = int(hp_by_tier.get(tier, 100))
	return hp

static func get_purify_shrine_passive_drain_per_wave(tier: int) -> int:
	## Returns the passive shrine HP drain applied per wave for a given tier.
	## This approximates the shrine "timer" at the stage level; per-round
	## drain will be introduced when the combat layer gains a shrine entity.
	var drains: Dictionary = PURIFY_SHRINE.get("shrine_passive_drain_per_wave", {})
	if not drains.has(tier):
		tier = 1
	var amount: int = int(drains.get(tier, 10))
	return amount

# ---------------------------------------------------------
# DIFFICULTY TIERS (multipliers)
# These are multipliers applied on top of hero/enemy baselines.
# They also carry economy knobs (Ase/Ekwan reward) and fear pressure.
# Example: tier 2 enemy HP = base_hp * enemy_power.hp_mul
# ---------------------------------------------------------

# Legacy aliases kept for backwards compatibility.
# Values mirror the enemy_power block in TIER_SCALARS below.
const TIER1_HP_MUL: float = 1.0
const TIER1_ATK_MUL: float = 1.0
const TIER1_AGI_MUL: float = 1.0

const TIER2_HP_MUL: float = 1.25
const TIER2_ATK_MUL: float = 1.15
const TIER2_AGI_MUL: float = 1.05

const TIER3_HP_MUL: float = 1.5
const TIER3_ATK_MUL: float = 1.3
const TIER3_AGI_MUL: float = 1.1

# Canon-aligned tier scalars for enemy power, fear pressure and rewards.
# Tiers 1–3 are MVP; 4–5 are reserved for future difficulties.
const TIER_SCALARS := {
	1: {
		"enemy_power": { "hp_mul": 1.0,  "atk_mul": 1.0,  "agi_mul": 1.0 },
		"fear_pressure_add": 5,
		"ekwan_drop_mul": 1.0,
		"ase_reward_mul": 1.0,
	},
	2: {
		"enemy_power": { "hp_mul": 1.25, "atk_mul": 1.15, "agi_mul": 1.05 },
		"fear_pressure_add": 6,
		"ekwan_drop_mul": 1.2,
		"ase_reward_mul": 1.05,
	},
	3: {
		"enemy_power": { "hp_mul": 1.5,  "atk_mul": 1.3,  "agi_mul": 1.1 },
		"fear_pressure_add": 7,
		"ekwan_drop_mul": 1.4,
		"ase_reward_mul": 1.1,
	},
	4: {
		"enemy_power": { "hp_mul": 1.75, "atk_mul": 1.45, "agi_mul": 1.15 },
		"fear_pressure_add": 8,
		"ekwan_drop_mul": 1.6,
		"ase_reward_mul": 1.18,
	},
	5: {
		"enemy_power": { "hp_mul": 2.0,  "atk_mul": 1.6,  "agi_mul": 1.2 },
		"fear_pressure_add": 9,
		"ekwan_drop_mul": 1.8,
		"ase_reward_mul": 1.25,
	},
}

static func get_tier_scalars(tier: int) -> Dictionary:
	## Returns the scalar block for a tier. Defaults to tier 1 if unknown.
	if not TIER_SCALARS.has(tier):
		tier = 1
	return TIER_SCALARS[tier]

static func get_enemy_multipliers_for_tier(tier: int) -> Dictionary:
	## Backwards-compatible helper used by combat.
	## Wraps the enemy_power portion of TIER_SCALARS.
	var scalars: Dictionary = get_tier_scalars(tier)
	var power: Dictionary = scalars.get("enemy_power", {})
	var hp_mul: float = float(power.get("hp_mul", 1.0))
	var atk_mul: float = float(power.get("atk_mul", 1.0))
	var agi_mul: float = float(power.get("agi_mul", 1.0))
	return {
		"hp_mul": hp_mul,
		"atk_mul": atk_mul,
		"agi_mul": agi_mul,
	}

# ---------------------------------------------------------
# EMOTION / VIRTUE REALM THEMES (canon §6B)
# Realms themed around a virtue get small bumps.
# These are intentionally small so they don't break base pacing.
# These are not wired directly here; other systems can combine
# virtue from REALM_LIST with these multipliers when needed.
# ---------------------------------------------------------
const REALM_OF_COURAGE_ATK_MUL: float = 1.1
const REALM_OF_WISDOM_DEF_MUL: float = 1.1
const REALM_OF_FAITH_HP_MUL: float = 1.1
const REALM_OF_HARMONY_MORALE_MUL: float = 1.1

# ---------------------------------------------------------
# LOOT / REWARD BASELINES
# RealmRewardCalc will combine these with TIER_SCALARS.
# ---------------------------------------------------------
const REWARD_BASE := {
	# Base Ase/Ekwan per cleared stage at tier 1.
	"ase": 20,
	"ekwan": 12,
	# Simple rarity weights for MVP relic rolls.
	"relic_weights": {
		"common": 85,
		"rare": 15,
	},
}

# Legacy Ase reward multipliers kept for compatibility and readability.
const REWARD_ASE_MUL_TIER1: float = 1.0
const REWARD_ASE_MUL_TIER2: float = 1.25
const REWARD_ASE_MUL_TIER3: float = 1.5

static func get_reward_base() -> Dictionary:
	## Returns the base reward configuration.
	return REWARD_BASE
