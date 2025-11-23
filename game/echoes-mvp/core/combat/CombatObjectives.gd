

# core/combat/CombatObjectives.gd
# -----------------------------------------------------------------------------
# Centralized objective and end-condition handling for CombatEngine.
#
# Scope (MVP):
#  - defeat
#  - purify_shrine
#
# The logic here is intentionally kept generic and tag-driven so future
# objectives (escort, defend_structure, destroy_target, multi-objective) can
# extend it without requiring changes inside CombatEngine.
# -----------------------------------------------------------------------------

class_name CombatObjectives

const CombatEntities = preload("res://core/combat/CombatEntities.gd")
const CombatConstants = preload("res://core/combat/CombatConstants.gd")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Evaluates end conditions for the current battle.
##
## - `state` is the live combat state dictionary owned by CombatEngine.
## - `objective` is the current objective id/string (e.g. "defeat", "purify_shrine").
## - `round_limit` mirrors the engine-configured round cap.
## - `hero_bal` is provided for future tuning hooks; unused in MVP.
##
## Side-effects:
##  - May set state["over"] = true.
##  - When over, will populate state["result"] with:
##      { "victory": bool, "reason": String, ...optional fields... }
##
## Returns:
##  - When battle ends: the same dictionary stored in state["result"].
##  - When ongoing: { "ongoing": true }.
static func check_end(state: Dictionary, objective: String, round_limit: int, hero_bal) -> Dictionary:
	var objective_s: String = String(objective)

	var shrine_present: bool = false
	var shrine_dead: bool = false
	var shrine_hp_remaining: int = 0

	# Shrine-aware detection & clamping
	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if not CombatEntities.is_shrine(ent):
			continue

		shrine_present = true

		# Read and clamp shrine HP so downstream checks always see sane values.
		var hp_pair: Dictionary = CombatEntities.read_hp_pair(ent)
		var raw_hp: int = int(hp_pair.get("hp", 0))
		var max_hp: int = int(hp_pair.get("max_hp", 0))
		var clamped_hp: int = max(0, raw_hp)
		if max_hp > 0:
			clamped_hp = min(clamped_hp, max_hp)

		# Write clamped HP back into the entity, mirroring both stats and flat keys.
		if ent.has("stats") and typeof(ent["stats"]) == TYPE_DICTIONARY:
			var s: Dictionary = ent["stats"]
			if s.has("hp"):
				s["hp"] = clamped_hp
			if s.has("max_hp"):
				s["max_hp"] = max_hp if max_hp > 0 else clamped_hp
			# Also mirror via canonical EchoConstants keys when available.
			if typeof(EchoConstants) != TYPE_NIL:
				if EchoConstants.STAT_HP in s:
					s[EchoConstants.STAT_HP] = clamped_hp
				if EchoConstants.STAT_MAX_HP in s:
					s[EchoConstants.STAT_MAX_HP] = max_hp if max_hp > 0 else clamped_hp
			ent["stats"] = s
		else:
			ent["hp"] = clamped_hp
			if not ent.has("max_hp"):
				ent["max_hp"] = clamped_hp

		shrine_hp_remaining = clamped_hp
		if not CombatEntities.is_alive(ent):
			shrine_dead = true

		# Only a single shrine is expected in MVP; stop after the first.
		break

	# Alive flags for both sides
	var allies_alive: bool = false
	for a2 in state.get("allies", []):
		if typeof(a2) != TYPE_DICTIONARY:
			continue
		if CombatEntities.is_alive(a2):
			allies_alive = true
			break

	var enemies_alive: bool = false
	for e in state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if CombatEntities.is_alive(e):
			enemies_alive = true
			break

	var reason: String = ""
	var victory: bool = false

	# Shrine-specific failure: in Purify Shrine objectives, shrine destruction
	# immediately ends the battle as a loss, even if heroes are still standing.
	if objective_s == "purify_shrine" and shrine_present and shrine_dead:
		state["over"] = true
		victory = false
		reason = "shrine_destroyed"
	elif not enemies_alive and allies_alive:
		state["over"] = true
		victory = true
		reason = "enemies_defeated"
	elif not allies_alive and enemies_alive:
		state["over"] = true
		victory = false
		reason = "allies_defeated"
	elif not allies_alive and not enemies_alive:
		state["over"] = true
		# Edge-case: double KO → call it a Pyrrhic win for MVP,
		# preserving existing engine behaviour.
		victory = true
		reason = "double_ko"
	elif int(state.get("round", 0)) >= int(round_limit):
		state["over"] = true
		# MVP objective: defeat → side with more survivors wins; tie → round_limit
		var allies_count: int = _alive_count(state.get("allies", []))
		var enemies_count: int = _alive_count(state.get("enemies", []))
		if enemies_count == 0 and allies_count > 0:
			victory = true
			reason = "enemies_defeated"
		elif allies_count > enemies_count:
			victory = true
			reason = "round_limit"
		elif enemies_count > allies_count:
			victory = false
			reason = "round_limit"
		else:
			victory = false
			reason = "round_limit_tie"

	# Package result when over; otherwise return an "ongoing" sentinel.
	if bool(state.get("over", false)):
		var result: Dictionary = {
			"victory": victory,
			"reason": reason,
		}

		# Surface shrine outcome when present so ObjectiveRunner / callers can react.
		if shrine_present:
			result["shrine_destroyed"] = shrine_dead
			result["shrine_hp_remaining"] = shrine_hp_remaining

		state["result"] = result
		return result

	return {"ongoing": true}

## Builds a generic objective context snapshot from the current state.
##
## This is intentionally conservative for MVP but already exposes:
##  - shrine entity & id (when present)
##  - counts of allies / enemies alive
##
## Future objectives (escort, defend, destroy, multi-objective) can extend
## this shape with additional fields (escort targets, structures, etc.).
static func build_objective_context(state: Dictionary) -> Dictionary:
	var ctx: Dictionary = {}

	# Shrine descriptor, if any
	var shrine_ent: Dictionary = {}
	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if CombatEntities.is_shrine(ent):
			shrine_ent = ent
			break

	if shrine_ent.size() > 0:
		var hp_pair: Dictionary = CombatEntities.read_hp_pair(shrine_ent)
		ctx["shrine"] = {
			"id": int(shrine_ent.get("id", -1)),
			"name": str(shrine_ent.get("name", "Shrine")),
			"hp": int(hp_pair.get("hp", 0)),
			"max_hp": int(hp_pair.get("max_hp", 0)),
		}

	# Basic alive counts
	ctx["allies_alive"] = _alive_count(state.get("allies", []))
	ctx["enemies_alive"] = _alive_count(state.get("enemies", []))

	return ctx

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _alive_count(group: Array) -> int:
	var c: int = 0
	for ent in group:
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		if CombatEntities.is_alive(ent):
			c += 1
	return c
## Applies shrine purification effects when a PURIFY_SHRINE action succeeds.
##
## This updates:
##   - state["shrine_purified_this_round"]
##   - state["shrine_purify_cd_remaining"]
##   - state["shrine_purify_stacks"]
static func apply_purify_shrine_effects(state: Dictionary, effect: Dictionary, hero_bal) -> void:
	# Purify Shrine handling is now wired directly via the shared CombatConstants
	# module rather than trying to discover a global singleton. This keeps the
	# logic simple and avoids engine-version-specific APIs.
	var eff_type := int(effect.get("type", -1))
	if eff_type != int(CombatConstants.ActionType.PURIFY_SHRINE) or not effect.get("ok", true):
		return

	# Per-round flag: useful for logs / QA tick summaries.
	state["shrine_purified_this_round"] = true

	# Party‑wide cooldown: after a successful Purify, the whole party shares a cooldown.
	var cd_base: int = int(hero_bal.SHRINE_PURIFY_COOLDOWN_ROUNDS)
	if cd_base < 0:
		cd_base = 0
	var current_cd: int = int(state.get("shrine_purify_cd_remaining", 0))
	state["shrine_purify_cd_remaining"] = max(current_cd, cd_base)

	# Time‑limited drain reduction stack:
	# The resolver may specify stack duration / magnitude; otherwise fall back to balance defaults.
	var default_stack_rounds: int = int(hero_bal.SHRINE_PURIFY_STACK_DURATION_ROUNDS)
	if default_stack_rounds < 0:
		default_stack_rounds = 0

	# Default reduction is derived from the base drain and the config multiplier:
	# base_drain - reduction = base_drain * MULTIPLIER  ⇒  reduction = base_drain * (1 - MULTIPLIER)
	var base_drain: int = int(hero_bal.SHRINE_DRAIN_PER_ROUND_BASE)
	var default_reduction: int = 0
	if base_drain > 0:
		var frac: float = 1.0 - float(hero_bal.SHRINE_PURIFY_BASE_DRAIN_REDUCTION)
		if frac < 0.0:
			frac = 0.0
		if frac > 1.0:
			frac = 1.0
		default_reduction = int(round(float(base_drain) * frac))
		if default_reduction < 1 and frac > 0.0:
			default_reduction = 1

	var stack_rounds: int = int(effect.get("shrine_stack_rounds", default_stack_rounds))
	var stack_reduction: int = int(effect.get("shrine_reduction", default_reduction))

	if stack_rounds > 0 and stack_reduction > 0:
		var stacks: Array = []
		if state.has("shrine_purify_stacks") and typeof(state["shrine_purify_stacks"]) == TYPE_ARRAY:
			stacks = state["shrine_purify_stacks"]
		stacks.append({
			"rounds_left": stack_rounds,
			"reduction": stack_reduction,
		})
		state["shrine_purify_stacks"] = stacks
