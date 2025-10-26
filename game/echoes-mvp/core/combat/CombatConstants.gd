

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

# Broken behavior: by default, Broken units are *eligible* to refuse entirely.
# The AI chooser will typically translate BROKEN into REFUSE; if they still act
# (e.g., scripted or special), we also expose a conservative damage multiplier.
const BROKEN_REFUSE_DEFAULT: bool = true

# --- Morale bands & multipliers ----------------------------------------------
# Thresholds for mapping raw morale (0..100) into tiers.
const INSPIRED_MIN: int = 75
const STEADY_MIN: int = 40
const SHAKEN_MIN: int = 15
# Anything below SHAKEN_MIN is BROKEN.

# Effectiveness multipliers per tier (used in damage and possibly support).
# INSPIRED: +20%; STEADY: +0%; SHAKEN: -20%; BROKEN: -40% (if they act at all).
const MORALE_MULTIPLIERS := {
	MoraleTier.INSPIRED: 1.20,
	MoraleTier.STEADY: 1.00,
	MoraleTier.SHAKEN: 0.80,
	MoraleTier.BROKEN: 0.60,
}

# --- Helpers (pure) -----------------------------------------------------------
## Returns a clamped morale value (0..100) for safety in calculations.
static func clamp_morale(morale: int) -> int:
	return clamp(morale, 0, 100)

## Maps a raw morale (0..100) to a coarse MoraleTier.
static func morale_tier(morale: int) -> int:
	var m := clamp_morale(morale)
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
	var mult := morale_multiplier_for(attacker_morale)
	var raw := int(round(atk * BASE_ATTACK_MULT * mult)) - max(defense, 0)
	return max(raw, DAMAGE_FLOOR)