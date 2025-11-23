extends RefCounted
class_name CombatEmotionSystem

# -----------------------------------------------------------------------------
# CombatEmotionSystem
# -----------------------------------------------------------------------------
# Shared combat-local emotion rules:
#  - Morale + fear helpers for entities
#  - KO fear shock
#  - Round tick cadence (fear tick, morale decay, shrine drain)
#  - Emotion baselines & final emotion result payload
#
# IMPORTANT:
#  - This module operates on the *combat-local* `state` dictionary used by
#    CombatEngine. It does NOT own any campaign persistence.
#  - EmotionService remains the campaign owner of morale/fear and will consume
#    the final emotion result via ObjectiveRunner or other callers.
#
# Expected `state` shape (subset, as used here):
#  {
#    "round": int,
#    "allies": Array[Dictionary],
#    "enemies": Array[Dictionary],
#    "objective": String,
#    "shrine_purified_this_round": bool,
#    "shrine_purify_cd_remaining": int,
#    "shrine_purify_stacks": Array[Dictionary],
#    "emotion_baseline": Dictionary[int, Dictionary],
#    ...
#  }
#
# Dependencies:
#  - CombatEntities: generic entity helpers (HP read/write, shrine tagging)
#  - CombatConstants: fear/morale cadence config
#  - EchoConstants: canonical stat keys (HP / MAX_HP / FEAR / MORALE)
#
# All logic here is copied/adapted from the existing CombatEngine.gd so that
# behavior (including shrine drain and emotion payload shape) remains 1:1.
# -----------------------------------------------------------------------------

const CombatEntities = preload("res://core/combat/CombatEntities.gd")
const CombatConstants = preload("res://core/combat/CombatConstants.gd")


# --- Public API ---------------------------------------------------------------

# Morale helpers ---------------------------------------------------------------

static func get_morale(ent: Dictionary) -> int:
	# Allies: real morale lives under stats.morale (preferred) or fallback `morale`.
	if ent.get("stats") is Dictionary:
		var stats := ent["stats"] as Dictionary
		if stats.has("morale"):
			var m := int(stats.get("morale", 50))
			return max(0, min(100, m))
	if ent.has("morale"):
		return max(0, min(100, int(ent.get("morale", 50))))
	# MVP: enemies do not use morale; return steady baseline for completeness.
	return 50


static func write_morale(ent: Dictionary, morale_value: int) -> void:
	var v: int = max(0, min(100, int(morale_value)))
	if ent.has("stats") and typeof(ent["stats"]) == TYPE_DICTIONARY:
		var stats := ent["stats"] as Dictionary
		stats["morale"] = v
		ent["stats"] = stats
	else:
		ent["morale"] = v


static func morale_tier_label(morale_value: int) -> String:
	var t := CombatConstants.morale_tier(int(morale_value))
	match t:
		CombatConstants.MoraleTier.INSPIRED: return "INSPIRED"
		CombatConstants.MoraleTier.STEADY:  return "STEADY"
		CombatConstants.MoraleTier.SHAKEN:  return "SHAKEN"
		_:                                   return "BROKEN"


# Fear helpers -----------------------------------------------------------------

# Increase fear on a specific entity by id, clamping to config max.
# `hero_bal` is expected to be the GameBalance_HeroCombat script (or similar).
static func increase_fear_on_entity(state: Dictionary, ent_id: int, amount: int, hero_bal) -> void:
	if amount <= 0:
		return

	var ent: Variant = _find_entity(state, ent_id)
	if ent == null or typeof(ent) != TYPE_DICTIONARY:
		return

	var ent_dict: Dictionary = ent as Dictionary
	# Shrines do not accumulate fear.
	if CombatEntities.is_shrine(ent_dict):
		return

	var fear_cur: int = int(ent_dict.get("fear", 0))
	var fear_max: int = 100
	if hero_bal != null and "FEAR_MAX" in hero_bal:
		# Access as property on the script instance / class
		fear_max = int(hero_bal.FEAR_MAX)

	var fear_new: int = min(fear_max, max(0, fear_cur + amount))
	ent_dict["fear"] = fear_new

	# Also mirror into stats if present so shape stays consistent
	if ent_dict.has("stats") and typeof(ent_dict["stats"]) == TYPE_DICTIONARY:
		var stats := ent_dict["stats"] as Dictionary
		stats["fear"] = fear_new
		ent_dict["stats"] = stats


# Apply KO shock: when an ally goes down during this round, surviving allies
# gain FEAR_PER_ALLY_KO. This scans the live state and compares hp/status.
static func apply_ally_ko_fear(state: Dictionary, hero_bal) -> void:
	if hero_bal == null or not ("FEAR_PER_ALLY_KO" in hero_bal):
		return

	var fear_per_ally_ko: int = int(hero_bal.FEAR_PER_ALLY_KO)

	# Collect KO allies
	var ko_allies: Array[int] = []
	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent_a: Dictionary = a
		if CombatEntities.is_shrine(ent_a):
			continue
		if not _entity_alive(ent_a):
			ko_allies.append(int(ent_a.get("id", -1)))

	if ko_allies.is_empty():
		return

	# For each alive ally (non-shrine), add KO fear once (per round).
	for a2 in state.get("allies", []):
		if typeof(a2) != TYPE_DICTIONARY:
			continue
		var ent_a2: Dictionary = a2
		if CombatEntities.is_shrine(ent_a2):
			continue
		if not _entity_alive(ent_a2):
			continue
		var id_a2: int = int(ent_a2.get("id", -1))
		increase_fear_on_entity(state, id_a2, fear_per_ally_ko, hero_bal)


# Round tick (fear, morale decay, shrine drain) --------------------------------

# Apply per-round emotion cadence and shrine passive drain.
# Returns a summary dictionary used for logging:
#  {
#    "fear": FEAR_PER_ROUND,
#    "morale_decay": bool,
#    "shrine_drain": int,
#    "shrine_purified": bool,
#    "shrine_purify_reduction": int,
#    "shrine_purify_cd": int,
#  }
static func apply_round_tick(state: Dictionary, hero_bal) -> Dictionary:
	# Emotion cadence tuning: prefer hero_bal (GameBalance_HeroCombat) as single source of truth,
	# fall back to CombatConstants for safety/legacy callers.
	var fear_tick: int = CombatConstants.FEAR_PER_ROUND
	var decay_every: int = CombatConstants.MORALE_DECAY_EVERY_N_ROUNDS
	var decay_amount: int = CombatConstants.MORALE_DECAY_AMOUNT

	if hero_bal != null:
		if "COMBAT_FEAR_PER_ROUND" in hero_bal:
			fear_tick = int(hero_bal.COMBAT_FEAR_PER_ROUND)
		if "COMBAT_MORALE_DECAY_EVERY_N_ROUNDS" in hero_bal:
			decay_every = int(hero_bal.COMBAT_MORALE_DECAY_EVERY_N_ROUNDS)
		if "COMBAT_MORALE_DECAY_AMOUNT" in hero_bal:
			decay_amount = int(hero_bal.COMBAT_MORALE_DECAY_AMOUNT)

	var morale_decay_applied: bool = false
	var round_index: int = int(state.get("round", 1))
	var do_decay: bool = decay_every > 0 and (round_index % decay_every) == 0
	var shrine_drain_applied: int = 0
	var shrine_purified: bool = bool(state.get("shrine_purified_this_round", false))

	# Global Purify cooldown (party‑wide): tick down once per round after all actions.
	var cd_remaining: int = int(state.get("shrine_purify_cd_remaining", 0))
	if cd_remaining > 0:
		cd_remaining -= 1
		if cd_remaining < 0:
			cd_remaining = 0
	state["shrine_purify_cd_remaining"] = cd_remaining

	# Update Purify stacks: apply their reduction this round and decay their remaining duration.
	var stacks_in: Array = []
	if state.has("shrine_purify_stacks") and typeof(state["shrine_purify_stacks"]) == TYPE_ARRAY:
		stacks_in = state["shrine_purify_stacks"]
	var stacks_out: Array = []
	var shrine_purify_reduction: int = 0
	for s in stacks_in:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var s_dict: Dictionary = s
		var rounds_left: int = int(s_dict.get("rounds_left", 0))
		var reduction: int = int(s_dict.get("reduction", 0))
		if rounds_left <= 0 or reduction <= 0:
			continue
		# This stack applies to the current round.
		shrine_purify_reduction += reduction
		# Then decay duration for future rounds.
		rounds_left -= 1
		if rounds_left > 0:
			var s_next: Dictionary = s_dict.duplicate(true)
			s_next["rounds_left"] = rounds_left
			stacks_out.append(s_next)
	state["shrine_purify_stacks"] = stacks_out

	# Allies: fear + morale decay
	for ent in state.get("allies", []):
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		var ent_dict: Dictionary = ent
		if not _entity_alive(ent_dict):
			continue
		if CombatEntities.is_shrine(ent_dict):
			continue
		# Fear accrual
		var fear: int = int(ent_dict.get("fear", 0))
		fear = min(100, max(0, fear + fear_tick))
		ent_dict["fear"] = fear
		# Morale decay cadence (allies only)
		if do_decay and decay_amount > 0:
			var morale: int = get_morale(ent_dict)
			morale = max(0, morale - decay_amount)
			if ent_dict.get("stats") is Dictionary:
				var stats2 := ent_dict["stats"] as Dictionary
				stats2["morale"] = morale
				ent_dict["stats"] = stats2
			else:
				ent_dict["morale"] = morale
			morale_decay_applied = true

	# Enemies: fear only (MVP — enemies ignore morale)
	for ent_e in state.get("enemies", []):
		if typeof(ent_e) != TYPE_DICTIONARY:
			continue
		var ent_e_dict: Dictionary = ent_e
		if not _entity_alive(ent_e_dict):
			continue
		var fear_e: int = int(ent_e_dict.get("fear", 0))
		fear_e = min(100, max(0, fear_e + fear_tick))
		ent_e_dict["fear"] = fear_e

	# Shrine: per-round passive HP drain (Purify Shrine objective only)
	# We treat the shrine as a special allied entity with `is_shrine = true`.
	# Drain amount is driven by hero_bal.SHRINE_DRAIN_PER_ROUND_BASE
	# and reduced by any active, time-limited Purify stacks.
	var drain_base: int = 0
	if hero_bal != null and "SHRINE_DRAIN_PER_ROUND_BASE" in hero_bal:
		drain_base = int(hero_bal.SHRINE_DRAIN_PER_ROUND_BASE)

	if String(state.get("objective", "")) == "purify_shrine" and drain_base != 0:
		for ent_shrine in state.get("allies", []):
			if typeof(ent_shrine) != TYPE_DICTIONARY:
				continue
			var shrine_dict: Dictionary = ent_shrine
			if not CombatEntities.is_shrine(shrine_dict):
				continue

			# Read current HP / Max HP using the same helper used elsewhere for logs.
			var hp_pair: Dictionary = CombatEntities.read_hp_pair(shrine_dict)
			var hp_before: int = int(hp_pair.get("hp", 0))
			var max_hp: int = int(hp_pair.get("max_hp", 0))
			if hp_before <= 0:
				break

			var drain: int = drain_base

			# Apply any active Purify stacks as a reduction to this round's drain.
			if shrine_purify_reduction > 0:
				drain = max(0, drain - shrine_purify_reduction)

			if drain <= 0:
				break

			var hp_after: int = max(0, hp_before - drain)

			# Persist back into stats and flat HP so both views stay in sync.
			if shrine_dict.has("stats") and typeof(shrine_dict["stats"]) == TYPE_DICTIONARY:
				var s: Dictionary = shrine_dict["stats"]
				s["hp"] = hp_after
				s["max_hp"] = max_hp
				shrine_dict["stats"] = s

			shrine_dict["hp"] = hp_after
			shrine_dict["max_hp"] = max_hp

			shrine_drain_applied = hp_before - hp_after
			break

	# Purify effect is per-round: clear the flag after applying this tick.
	state["shrine_purified_this_round"] = false

	return {
		"fear": fear_tick,
		"morale_decay": morale_decay_applied,
		"shrine_drain": shrine_drain_applied,
		"shrine_purified": shrine_purified,
		"shrine_purify_reduction": shrine_purify_reduction,
		"shrine_purify_cd": int(state.get("shrine_purify_cd_remaining", 0)),
	}


# Baseline capture & emotion result packaging ----------------------------------

# Capture starting morale/fear for all allies at the beginning of a battle.
# This is called once after CombatEngine.start_battle has hydrated entities and
# applied any morale overrides, so it represents the true combat starting point.
static func capture_baseline(state: Dictionary) -> void:
	var baseline: Dictionary = {}
	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if CombatEntities.is_shrine(ent):
			continue
		var hero_id: int = int(ent.get("id", -1))
		if hero_id <= 0:
			continue
		var start_morale: int = get_morale(ent)
		var start_fear: int = int(ent.get("fear", 0))
		baseline[hero_id] = {
			"morale": start_morale,
			"fear": start_fear,
		}
	state["emotion_baseline"] = baseline


# Build a structured emotion result payload comparing final vs baseline
# morale/fear. Consumers (ObjectiveRunner, debug harness) can pass this to
# EmotionService to persist deltas across the campaign.
static func build_emotion_result(state: Dictionary) -> Dictionary:
	var heroes: Dictionary = {}
	var baseline: Dictionary = state.get("emotion_baseline", {})

	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if CombatEntities.is_shrine(ent):
			continue
		var hero_id: int = int(ent.get("id", -1))
		if hero_id <= 0:
			continue

		# Baseline values; if missing, treat current as baseline so deltas are 0.
		var base: Dictionary = {}
		if baseline.has(hero_id):
			base = baseline[hero_id]
		var start_morale: int = 0
		var start_fear: int = 0
		if base.has("morale"):
			start_morale = int(base.get("morale", 0))
		else:
			start_morale = get_morale(ent)
		if base.has("fear"):
			start_fear = int(base.get("fear", 0))
		else:
			start_fear = int(ent.get("fear", 0))

		var final_morale: int = get_morale(ent)
		var final_fear: int = int(ent.get("fear", 0))

		var morale_delta: int = final_morale - start_morale
		var fear_delta: int = final_fear - start_fear

		heroes[hero_id] = {
			"start_morale": start_morale,
			"final_morale": final_morale,
			"morale_delta": morale_delta,
			"start_fear": start_fear,
			"final_fear": final_fear,
			"fear_delta": fear_delta,
		}

	if heroes.size() == 0:
		return {}
	return {"heroes": heroes}


# --- Internal helpers ---------------------------------------------------------

# Local version of entity_alive for emotion logic.
static func _entity_alive(ent: Dictionary) -> bool:
	var hp_pair: Dictionary = CombatEntities.read_hp_pair(ent)
	var hp: int = int(hp_pair.get("hp", 0))
	if hp <= 0:
		return false
	if String(ent.get("status", "")) == "downed":
		return false
	return true


# Find an entity in allies/enemies by id within the given state.
static func _find_entity(state: Dictionary, id_val: int) -> Variant:
	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if int((a as Dictionary).get("id", -1)) == id_val:
			return a
	for e in state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if int((e as Dictionary).get("id", -1)) == id_val:
			return e
	return null
