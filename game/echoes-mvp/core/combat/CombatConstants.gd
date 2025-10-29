# core/combat/CombatConstants.gd
# -----------------------------------------------------------------------------
# Single source of truth for combat-related enums and gentle MVP tuning knobs.
# Pure module (no state, no singletons) so downstream systems share the same
# definitions and can be tweaked from one place.
#
# Canon notes
#  - §3 Loop pacing: round cadence must be visible and easy to read.
#  - §4 Action economy: Major + Minor actions; refusal exists as a first-class action.
#  - §9 Determinism: constants are versioned and referenced by all subsystems.
#  - §12 Balance: morale/fear curves are gentle for MVP and easy to tune later.
# -----------------------------------------------------------------------------
class_name CombatConstants

# --- Enums --------------------------------------------------------------------
# Teams participating in combat.
enum Team { ALLY, ENEMY }

# Atomic action types used by the chooser and resolver.
enum ActionType { ATTACK, GUARD, MOVE, INTERACT, REFUSE }

# Round orchestration states (Engine steps through these deterministically).
enum RoundState { INITIATIVE, SELECT, RESOLVE, TICK, CHECK }

# Coarse morale tiers. Numbers are mapped to these bands for readable behavior.
enum MoraleTier { INSPIRED, STEADY, SHAKEN, BROKEN }

# --- Tuning knobs (MVP, gentle values) ---------------------------------------
# Fear accrues each round to slowly increase pressure.
const FEAR_PER_ROUND: int = 1

# Every N rounds, morale decays by a tiny amount to push decisions.
const MORALE_DECAY_EVERY_N_ROUNDS: int = 2
const MORALE_DECAY_AMOUNT: int = 1

# Baseline damage math (class math will arrive later; keep MVP simple/legible).

const BASE_ATTACK_MULT: float = 1.0
const DAMAGE_FLOOR: int = 0

# Optional smoothing (MVP: disabled)
# If enabled, ActionResolver will accumulate fractional damage remainders per attacker
# so that, over many hits, average damage matches the morale multiplier exactly.
# Deterministic and per-battle only (no persistence).
const USE_FRACTIONAL_BUCKET: bool = false
# When true, only accumulate buckets when multiplier > 1.0 (i.e., Inspired).
# This keeps SHAKEN simple/visible for MVP. Set to false to accumulate for any multiplier.
const BUCKET_ONLY_FOR_BOOSTS: bool = true

# Broken behavior (MVP): Broken units should REFUSE their major action.
# The resolver/AI enforces REFUSE; if an attack still slips through (scripted),
# use the safety multiplier from MORALE_MULTIPLIERS (currently -10%).
const BROKEN_REFUSE_DEFAULT: bool = true

# --- Morale bands & multipliers ----------------------------------------------
# Thresholds for mapping raw morale (0..100) into tiers.
const INSPIRED_MIN: int = 80
const STEADY_MIN: int = 50
const SHAKEN_MIN: int = 30
# Anything below SHAKEN_MIN is BROKEN.

# Effectiveness multipliers per tier (used in damage and possibly support).
# MVP canon: INSPIRED +10%; STEADY 0%; SHAKEN -10%.
# BROKEN: REFUSE major action in MVP; if an attack still occurs, treat as -10% for safety.
const MORALE_MULTIPLIERS := {
	MoraleTier.INSPIRED: 1.10,
	MoraleTier.STEADY: 1.00,
	MoraleTier.SHAKEN: 0.90,
	MoraleTier.BROKEN: 0.90, # Safety: resolver will typically REFUSE on BROKEN in MVP
}

# --- Helpers (pure) -----------------------------------------------------------
## Returns a clamped morale value (0..100) for safety in calculations.
static func clamp_morale(morale: int) -> int:
	return clamp(morale, 0, 100)

## Maps a raw morale (0..100) to a coarse MoraleTier.
static func morale_tier(morale: int) -> int:
	var m: int = clamp_morale(morale)
	if m >= INSPIRED_MIN:
		return MoraleTier.INSPIRED
	elif m >= STEADY_MIN:
		return MoraleTier.STEADY
	elif m >= SHAKEN_MIN:
		return MoraleTier.SHAKEN
	else:
		return MoraleTier.BROKEN

## Multiplier lookup by tier. Defaults to 1.0 if an unknown tier is provided.
static func morale_multiplier_for_tier(tier: int) -> float:
	return float(MORALE_MULTIPLIERS.get(tier, 1.0))

## Convenience wrapper: get the multiplier directly from a raw morale value.
static func morale_multiplier_for(morale: int) -> float:
	return morale_multiplier_for_tier(morale_tier(morale))

## Computes a simple MVP damage preview given attacker atk, defender def,
## and the attacker's morale. Resolver can call this and then apply KO logic.
static func compute_mvp_damage(atk: int, defense: int, attacker_morale: int) -> int:
	var mult: float = morale_multiplier_for(attacker_morale)
	var pre: float = float(atk) * BASE_ATTACK_MULT * mult
	var pre_int: int = int(round(pre))
	var raw: int = pre_int - max(defense, 0)
	return max(raw, DAMAGE_FLOOR)