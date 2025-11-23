# core/combat/CombatEngine.gd
# -----------------------------------------------------------------------------
# Deterministic, step-based round engine.
# Drives INITIATIVE → SELECT → RESOLVE → TICK → CHECK using the pure modules:
#   - Initiative.compute_order(ctx)
#   - EchoActionChooser.choose_action(hero, ctx)
#   - EnemyActionChooser.choose_action(enemy, ctx)
#   - ActionResolver.apply_major/apply_minor(action, ctx)
#
# Scope (MVP):
#  - Mutates *combat-local* state only. It does NOT write back to the meta-game
#    roster/save. Post-battle persistence belongs to the Recovery/Legacy epic.
#  - Returns per-round snapshots and a final result with final_state for consumers.
#
# Canon notes
#  - §3 Visible cadence: round structure is explicit and logged by CombatLog later.
#  - §4 Action economy: one intent per actor per round (ATTACK/REFUSE = Major,
#    GUARD/MOVE = Minor).
#  - §9 Determinism: same seed + same inputs ⇒ identical snapshots.
#  - §12 Gentle pacing: fear tick + morale decay applied as global round ticks.
# -----------------------------------------------------------------------------
# EnemyActionChooser.gd owns all enemy AI; CombatEngine only calls into it.

class_name CombatEngine


const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")
const CombatEntities = preload("res://core/combat/CombatEntities.gd")
const CombatEmotionSystem = preload("res://core/combat/CombatEmotionSystem.gd")
const CombatObjectives = preload("res://core/combat/CombatObjectives.gd")
const EnemyActionChooser = preload("res://core/combat/EnemyActionChooser.gd")
const CombatSnapshotBuilder = preload("res://core/combat/CombatSnapshotBuilder.gd")

# --- Engine state -------------------------------------------------------------
var _state: Dictionary = {}
# Morale overrides persist across battles (debug/QA support).
var _morale_overrides: Dictionary = {}

# --- Public API ---------------------------------------------------------------

## Initializes a deterministic battle state. Allies may be ids (ints) or dicts.
func start_battle(battle_seed: int, allies: Array, enemies: Array[Dictionary], objective: String = "defeat", round_limit: int = 10) -> void:
	_state = {
		"seed": battle_seed,
		"round": 1,
		"over": false,
		"objective": objective,
		"round_limit": max(1, round_limit),
		"attack_range": 1,  # MVP: everyone is adjacent unless a distance map is provided by caller
		"allies": _normalize_allies(allies),
		"enemies": _normalize_enemies(enemies),
		"last_snapshot": {},
		"result": {},
		# Fractional damage carryover buckets (per-attacker); populated/used by ActionResolver when enabled.
		"damage_bucket": {},
		"emotion_baseline": {},
		"shrine_purified_this_round": false,
		"shrine_purify_cd_remaining": 0,
		"shrine_purify_stacks": [],
		"designated_purifier_id": -1,
	}
	# Apply any persisted morale overrides into the freshly built state
	_apply_morale_overrides()
	CombatEmotionSystem.capture_baseline(_state)
	_assign_designated_purifier()
	_state["objective_context"] = CombatObjectives.build_objective_context(_state)

## Steps one round through INITIATIVE → SELECT → RESOLVE → TICK → CHECK.
## Returns a snapshot for logging/inspection.
func step_round() -> Dictionary:
	if _state.get("over", false):
		return _state.get("last_snapshot", {})

	var battle_seed: int = int(_state.seed)
	var round_index: int = int(_state.round)

	# 1) INITIATIVE -------------------------------------------------------------
	# Shrine-aware context: expose objective type and shrine id (if any) so
	# ActionResolver can treat negative shrine ids as valid targets and apply
	# shrine-specific rules.
	var objective_type: String = String(_state.get("objective", ""))
	var shrine_id: int = -9999
	if objective_type == "purify_shrine":
		var shrine_ent: Dictionary = CombatEntities.find_alive_shrine(_state.get("allies", []))
		if shrine_ent.size() > 0:
			shrine_id = int(shrine_ent.get("id", -1))

	var ctx: Dictionary = {
		"seed": battle_seed,
		"round_index": round_index,
		"allies": _state.allies,
		"enemies": _state.enemies,
		"attack_range": int(_state.attack_range),
		"damage_bucket": _state.damage_bucket,
		"objective_type": objective_type,
		"shrine_id": shrine_id,
		"shrine_purify_cd_remaining": int(_state.get("shrine_purify_cd_remaining", 0)),
		"designated_purifier_id": int(_state.get("designated_purifier_id", -1)),
	}
	var order: Array[int] = Initiative.compute_order(ctx)

	# Build a name map for readable logs (centralized in CombatSnapshotBuilder)
	var name_by_id: Dictionary = CombatSnapshotBuilder.build_name_map(_state)

	# 2) SELECT + 3) RESOLVE ----------------------------------------------------
	var actions: Array[Dictionary] = []
	var focus_hits: Dictionary = {}  # target_id -> number of times hit this round
	for actor_id in order:
		var ent: Variant = _find_entity(actor_id)
		if ent == null or typeof(ent) != TYPE_DICTIONARY:
			continue
		var ent_dict: Dictionary = ent
		# Shrine and other non-acting entities never take turns.
		if CombatEntities.is_shrine(ent_dict):
			continue
		if ent_dict.has("can_act") and not bool(ent_dict.get("can_act", true)):
			continue
		if not CombatEntities.is_alive(ent_dict):
			continue

		# Fear-first refusal check (MVP)
		# We do this BEFORE normal action selection so that fear can override
		# even when morale is still STEADY. ActionResolver pulls values from
		# GameBalance_HeroCombat.gd so we don't hardcode thresholds here.
		var fear_check: Dictionary = ActionResolver.should_refuse_turn(ent_dict)
		if bool(fear_check.get("refuse", false)):
			var fear_effect: Dictionary = _apply_fear_outcome(fear_check, ent_dict, ctx)
			# Decorate effect with names just like normal actions so logs stay consistent
			var actor_name_fc: String = str(name_by_id.get(actor_id, str(actor_id)))
			fear_effect["actor_name"] = actor_name_fc
			# Canonical verb for logging
			fear_effect["verb"] = _action_type_to_verb(int(fear_effect.get("type", -1)))
			actions.append(fear_effect)
			continue

		# Build latest ctx (mutated state is shared across loop iterations)
		ctx.allies = _state.allies
		ctx.enemies = _state.enemies

		var side := _side_of(actor_id)
		var action: Dictionary
		if side == "ALLY":
			action = EchoActionChooser.choose_action(ent_dict, ctx)
		else:
			action = EnemyActionChooser.choose_action(ent_dict, ctx)

		# Apply via resolver according to action type
		var t := int(action.get("type", -1))
		var effect: Dictionary
		match t:
			CombatConstants.ActionType.ATTACK, CombatConstants.ActionType.REFUSE, CombatConstants.ActionType.PURIFY_SHRINE:
				effect = ActionResolver.apply_major(action, ctx)
			CombatConstants.ActionType.GUARD, CombatConstants.ActionType.MOVE:
				effect = ActionResolver.apply_minor(action, ctx)
			_:
				effect = {
					"ok": false,
					"type": t,
					"actor_id": int(action.get("actor_id", -1)),
					"verb": _action_type_to_verb(t),
					"notes": "unsupported_action",
				}
		# Decorate effect with names and post-effect context for logging
		var actor_name: String = str(name_by_id.get(actor_id, str(actor_id)))
		effect["actor_name"] = actor_name
		if effect.has("target_id"):
			var tid: int = int(effect.get("target_id", -1))
			var target_ent: Variant = _find_entity(tid)
			var target_name: String = str(name_by_id.get(tid, str(tid)))
			effect["target_name"] = target_name
			if target_ent != null and typeof(target_ent) == TYPE_DICTIONARY:
				var hp_pair: Dictionary = CombatEntities.read_hp_pair(target_ent)
				effect["target_hp_after"] = int(hp_pair.get("hp", 0))
				effect["target_max_hp"] = int(hp_pair.get("max_hp", 0))
				# For guard actions, surface guard stack after application
				if int(effect.get("type", -1)) == CombatConstants.ActionType.GUARD:
					var guard_after: int = int((target_ent as Dictionary).get("guard_shield", 0))
					effect["target_guard_after"] = guard_after
		# Canonical verb for logging
		effect["verb"] = _action_type_to_verb(int(effect.get("type", -1)))

		# --- Preserve / derive morale QA fields so CombatLog can display them ----------
		var eff_type := int(effect.get("type", -1))
		if eff_type == CombatConstants.ActionType.ATTACK:
			# If the resolver already set morale fields, keep them; otherwise derive them here.
			var has_mult := effect.has("morale_mult")
			var has_tier := effect.has("morale_tier")
			if side == "ALLY":
				if (not has_mult) or (not has_tier):
					# Derive from the current attacker entity
					var m_val: int = CombatEmotionSystem.get_morale(ent_dict)
					# Use enum tier to avoid string drift, then map to label and multiplier
					var tier_enum: int = CombatConstants.morale_tier(m_val)
					var tier_label: String = CombatEmotionSystem.morale_tier_label(m_val)
					var mult_val: float = 1.0
					if CombatConstants.MORALE_MULTIPLIERS is Dictionary:
						mult_val = float(CombatConstants.MORALE_MULTIPLIERS.get(tier_enum, 1.0))
					# Only write if missing to avoid clobbering resolver values
					if not has_tier:
						effect["morale_tier"] = tier_label
					if not has_mult:
						effect["morale_mult"] = mult_val
			else:
				# Enemies ignore morale in MVP; ensure tag stays neutral
				if not has_tier:
					effect["morale_tier"] = null
				if not has_mult:
					effect["morale_mult"] = 1.0
		elif eff_type == CombatConstants.ActionType.REFUSE:
			# If refusal is due to broken state, ensure tier is surfaced for clarity
			var note_s := String(effect.get("notes", ""))
			if note_s == "broken":
				if not effect.has("morale_tier"):
					effect["morale_tier"] = "BROKEN"
				if not effect.has("morale_mult"):
					effect["morale_mult"] = 1.0

		# Shrine purification effects (moved to CombatObjectives)
		CombatObjectives.apply_purify_shrine_effects(_state, effect, HeroBal)

		# Fear accrual from impactful events (MVP)
		# If this action actually hit a target, increase that target's fear.
		# We look for an ATTACK effect with a target_id and ok=true.
		if eff_type == CombatConstants.ActionType.ATTACK and effect.get("ok", true):
			var tid2: int = int(effect.get("target_id", -1))
			if tid2 >= 0:
				# track focus hits in this round
				var prev_hits: int = int(focus_hits.get(tid2, 0))
				var extra_focus: int = 0
				if prev_hits > 0:
					extra_focus = HeroBal.FEAR_PER_FOCUS_HIT
				# apply to the actual entity so the next turn sees the higher fear
				CombatEmotionSystem.increase_fear_on_entity(_state, tid2, HeroBal.FEAR_PER_HIT + extra_focus, HeroBal)
				# store back hit count
				focus_hits[tid2] = prev_hits + 1
		actions.append(effect)

	# After all actions, apply KO shock to surviving allies
	CombatEmotionSystem.apply_ally_ko_fear(_state, HeroBal)

	# 4) TICK (fear & morale cadence) ------------------------------------------
	var tick_info: Dictionary = CombatEmotionSystem.apply_round_tick(_state, HeroBal)

	# 5) CHECK end conditions ---------------------------------------------------
	var end_info: Dictionary = _check_end()

	# Refresh objective context each round so any objective-driven UIs or
	# loggers see up-to-date shrine HP and alive counts instead of the
	# initial snapshot created at battle start.
	_state["objective_context"] = CombatObjectives.build_objective_context(_state)

	# Build canonical snapshot via CombatSnapshotBuilder so UI/loggers see
	# a stable, centralized shape.
	var snapshot: Dictionary = CombatSnapshotBuilder.build_round_snapshot(
		_state,
		round_index,
		order,
		actions,
		tick_info,
		end_info,
		name_by_id
	)

	_state.last_snapshot = snapshot

	# Prepare next round or finalize
	if not _state.over:
		_state.round = round_index + 1
	else:
		# Package a final_state for external consumers (no persistence here)
		CombatSnapshotBuilder.attach_final_state(_state.last_snapshot, _state)

	return _state.last_snapshot

## Whether the battle has concluded.
func is_over() -> bool:
	return bool(_state.get("over", false))

## Result after the battle is over.
func result() -> Dictionary:
	return _state.get("result", {})

## Returns a shallow copy of internal state useful for debug UIs.
func get_state() -> Dictionary:
	return _state.duplicate(true)

# --- Internal helpers --------------------------------------------------------


# MVP shrine behaviour:
# - The engine auto-designates a single "purifier" hero for Purify Shrine stages.
# - Post-MVP we may let the Keeper explicitly choose the purifier at stage start.
func _assign_designated_purifier() -> void:
	# MVP: only relevant for Purify Shrine objectives.
	var objective: String = String(_state.get("objective", ""))
	if objective != "purify_shrine":
		_state["designated_purifier_id"] = -1
		return

	var chosen_id: int = -1
	var best_score: int = -2147483648  # simple "minus infinity"

	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a

		# Shrines and dead allies can never be the purifier.
		if CombatEntities.is_shrine(ent):
			continue
		if not CombatEntities.is_alive(ent):
			continue

		var id_val: int = int(ent.get("id", -1))
		if id_val < 0:
			continue

		var score: int = _score_purifier_candidate(ent)

		if chosen_id == -1 or score > best_score or (score == best_score and id_val < chosen_id):
			chosen_id = id_val
			best_score = score

	_state["designated_purifier_id"] = chosen_id

# Scores a candidate hero for the purifier role. Focuses on faith and devout archetype.
func _score_purifier_candidate(ent: Dictionary) -> int:
	var score: int = 0

	# Prefer heroes whose archetype is explicitly devout.
	var arch_s: String = String(ent.get("archetype", "none"))
	if arch_s == "devout":
		score += HeroBal.PURIFIER_SCORE_DEVOUT_BONUS

	# Pull hero stats if present; we keep this flexible so lore / personality
	# stats like wisdom/faith can coexist with combat stats.
	if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
		var stats: Dictionary = ent.stats

		# Faith: primary signal for purifier role.
		if stats.has("faith"):
			score += int(stats.get("faith", 0)) * HeroBal.PURIFIER_SCORE_FAITH_WEIGHT

		# Wisdom: secondary tie-breaker (different key spellings allowed).
		if stats.has("wisdom"):
			score += int(stats.get("wisdom", 0)) * HeroBal.PURIFIER_SCORE_WISDOM_WEIGHT
		elif stats.has("wis"):
			score += int(stats.get("wis", 0)) * HeroBal.PURIFIER_SCORE_WISDOM_WEIGHT

	# Morale as a soft tie-breaker: more composed heroes are preferred.
	score += CombatEmotionSystem.get_morale(ent) * HeroBal.PURIFIER_SCORE_MORALE_WEIGHT

	return score

#
# Applies the outcome chosen by ActionResolver.should_refuse_turn(...)
# MVP: only "refuse" and "guard" are supported here. "retreat/abandon" is post-MVP
# and should be triggered by a separate, higher-severity fear check.
# Returns an effect dictionary shaped like other combat actions so the
# caller can append it to the round actions list.
func _apply_fear_outcome(fear_res: Dictionary, ent: Dictionary, ctx: Dictionary) -> Dictionary:
	var mode: String = String(fear_res.get("mode", "refuse"))
	var actor_id: int = int(ent.get("id", -1))
	if actor_id < 0:
		return {
			"ok": false,
			"type": CombatConstants.ActionType.REFUSE,
			"actor_id": actor_id,
			"notes": "fear_invalid_actor",
		}

	match mode:
		"guard":
			# Reuse existing guard resolver so we don't create a parallel system
			var guard_action: Dictionary = {
				"type": CombatConstants.ActionType.GUARD,
				"actor_id": actor_id,
				"target_id": actor_id,
				"notes": "fear_guard",
			}
			var guard_eff: Dictionary = ActionResolver.apply_minor(guard_action, ctx)
			guard_eff["reason"] = "fear"
			guard_eff["fear"] = int(fear_res.get("fear", 0))
			return guard_eff
		_:
			# Default/refuse path
			var refuse_action: Dictionary = {
				"type": CombatConstants.ActionType.REFUSE,
				"actor_id": actor_id,
				"notes": "fear_refusal",
			}
			var refuse_eff: Dictionary = ActionResolver.apply_major(refuse_action, ctx)
			refuse_eff["reason"] = "fear"
			refuse_eff["fear"] = int(fear_res.get("fear", 0))
			return refuse_eff


func _normalize_allies(allies: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in allies:
		match typeof(a):
			TYPE_INT:
				var id_val: int = int(a)
				var hero: Dictionary = _load_hero_by_id(id_val)
				var ent: Dictionary = _to_combat_entity(hero, id_val)
				out.append(ent)
			TYPE_DICTIONARY:
				var d_in: Dictionary = a
				# Ensure minimal shape; keep existing stats if present
				if not d_in.has("id"):
					d_in["id"] = 0

				# Shrine special-case: if an ally dict is marked as a shrine, we
				# preserve its provided shape and skip EmotionService hydration.
				# Shrines do not act and do not participate in morale/fear systems.
				if bool(d_in.get("is_shrine", false)):
					var shrine_out: Dictionary = d_in.duplicate(true)

					shrine_out["can_act"] = false
					shrine_out["fear"] = 0

					if not shrine_out.has("stats") or typeof(shrine_out["stats"]) != TYPE_DICTIONARY:
						var s := {
							EchoConstants.STAT_HP: int(shrine_out.get("hp", 0)),
							EchoConstants.STAT_MAX_HP: int(shrine_out.get("max_hp", shrine_out.get("hp", 0))),
							EchoConstants.STAT_ATK: 0,
							EchoConstants.STAT_DEF: 0,
							EchoConstants.STAT_AGI: 0,
							EchoConstants.STAT_MORALE: 0,
							EchoConstants.STAT_FEAR: 0,
						}
						shrine_out["stats"] = s
					else:
						var s2: Dictionary = shrine_out["stats"]
						if not s2.has(EchoConstants.STAT_HP):
							s2[EchoConstants.STAT_HP] = int(shrine_out.get("hp", 0))
						if not s2.has(EchoConstants.STAT_MAX_HP):
							s2[EchoConstants.STAT_MAX_HP] = int(shrine_out.get("max_hp", shrine_out.get("hp", 0)))
						shrine_out["stats"] = s2

					shrine_out["hp"] = int(shrine_out["stats"][EchoConstants.STAT_HP])
					shrine_out["max_hp"] = int(shrine_out["stats"][EchoConstants.STAT_MAX_HP])

					# Tags: ensure shrine participates in the generic entity model.
					# Canonical shrine tags for MVP:
					# ["ally", "structure", "structure:defense", "objective", "objective:shrine"].
					var shrine_tags: Array = ["ally", "structure", "structure:defense", "objective", "objective:shrine"]
					# Normalize tags container, then ensure canonical shrine tags are present.
					if not shrine_out.has("tags") or typeof(shrine_out["tags"]) != TYPE_ARRAY:
						shrine_out["tags"] = []
					CombatEntities.ensure_tags(shrine_out, shrine_tags)

					out.append(shrine_out)
					continue

				var d_out: Dictionary = d_in
				if not d_out.has("stats") or typeof(d_out["stats"]) != TYPE_DICTIONARY:
					d_out["stats"] = CombatEntities.fallback_stats_from_balance()
				else:
					d_out["stats"] = CombatEntities.fill_missing_stats_with_balance(d_out["stats"])
				if not d_out.has("fear"):
					d_out["fear"] = 0
				if not d_out.has("status"):
					d_out["status"] = "idle"

				# MVP hook: if EmotionService is available, hydrate morale/fear
				# for allies provided as dictionaries, so they still start from
				# the persisted emotional state rather than hardcoded defaults.
				var ent_id2: int = int(d_out.get("id", 0))
				if d_out.has("stats") and typeof(d_out["stats"]) == TYPE_DICTIONARY and ent_id2 > 0:
					var stats2: Dictionary = d_out["stats"]
					var fear2: int = int(d_out.get("fear", 0))
					var fear_hydrated: int = _hydrate_emotion_from_service(ent_id2, stats2, fear2)
					d_out["stats"] = stats2
					d_out["fear"] = fear_hydrated

				# Tags: ensure dictionary allies participate in the generic entity model.
				# Normalize tag container, then ensure "ally" is present.
				if not d_out.has("tags") or typeof(d_out["tags"]) != TYPE_ARRAY:
					d_out["tags"] = []
				CombatEntities.ensure_tags(d_out, ["ally"])

				out.append(d_out)
			_:
				pass
	return out

func _normalize_enemies(enemies: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in enemies:
		if typeof(e) != TYPE_DICTIONARY:
			continue

		# Ensure a stable id for determinism
		if not e.has("id"):
			e["id"] = 1000 + out.size()

		# Start from existing stats if present, else empty dict
		var s: Dictionary = {}
		if e.has("stats") and typeof(e.stats) == TYPE_DICTIONARY:
			s = (e.stats as Dictionary).duplicate(true)

		# Pull flat values if provided (we preserve existing numbers)
		var flat_hp_set: bool = e.has("hp")
		var flat_max_hp_set: bool = e.has("max_hp")
		var flat_atk_set: bool = e.has("atk")
		var flat_def_set: bool = e.has("def")
		var flat_agi_set: bool = e.has("agi")
		var flat_cha_set: bool = e.has("cha")
		var flat_int_set: bool = e.has("int")
		var flat_acc_set: bool = e.has("acc")
		var flat_eva_set: bool = e.has("eva")
		var flat_crit_set: bool = e.has("crit")

		# Write/ensure canonical stats, preferring provided values
		if flat_hp_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_HP, int(e.get("hp", HeroBal.FALLBACK_HP)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)

		if flat_max_hp_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(e.get("max_hp", int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))

		if flat_atk_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ATK, int(e.get("atk", HeroBal.FALLBACK_ATK)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ATK, HeroBal.FALLBACK_ATK)

		if flat_def_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_DEF, int(e.get("def", HeroBal.FALLBACK_DEF)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_DEF, HeroBal.FALLBACK_DEF)

		if flat_agi_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_AGI, int(e.get("agi", HeroBal.FALLBACK_AGI)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_AGI, HeroBal.FALLBACK_AGI)

		if flat_cha_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CHA, int(e.get("cha", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CHA, 0)

		if flat_int_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_INT, int(e.get("int", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_INT, 0)

		if flat_acc_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ACC, int(e.get("acc", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ACC, 0)

		if flat_eva_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_EVA, int(e.get("eva", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_EVA, 0)

		if flat_crit_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CRIT, int(e.get("crit", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CRIT, 0)

		# Morale/Fear (enemies ignore morale in MVP but keep a neutral value for shape)
		CombatEntities.ensure_stat_int(s, EchoConstants.STAT_MORALE, HeroBal.FALLBACK_MORALE)
		CombatEntities.ensure_stat_int(s, EchoConstants.STAT_FEAR, int(e.get("fear", 0)))

		# Save back canonical stats
		e["stats"] = s

		# Backfill flat keys from stats when missing (compat with any legacy readers)
		if not flat_hp_set:
			e["hp"] = int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP))
		if not flat_max_hp_set:
			e["max_hp"] = int(s.get(EchoConstants.STAT_MAX_HP, e.get("hp", HeroBal.FALLBACK_HP)))
		if not flat_atk_set:
			e["atk"] = int(s.get(EchoConstants.STAT_ATK, HeroBal.FALLBACK_ATK))
		if not flat_def_set:
			e["def"] = int(s.get(EchoConstants.STAT_DEF, HeroBal.FALLBACK_DEF))
		if not flat_agi_set:
			e["agi"] = int(s.get(EchoConstants.STAT_AGI, HeroBal.FALLBACK_AGI))
		if not e.has("fear"):
			e["fear"] = int(s.get(EchoConstants.STAT_FEAR, 0))
		if not e.has("status"):
			e["status"] = "idle"

		# Tags: ensure every enemy entity participates in the generic entity model.
		# Normalize tag container, then ensure "enemy" tag is present.
		if not e.has("tags") or typeof(e["tags"]) != TYPE_ARRAY:
			e["tags"] = []
		CombatEntities.ensure_tags(e, ["enemy"])

		out.append(e)
	return out

# --- Ally hydration helpers --------------------------------------------------

static func _load_hero_by_id(id_val: int) -> Dictionary:
	# Path 1: Autoload object (usual in GDScript projects)
	if typeof(SaveService) != TYPE_NIL and SaveService.has_method("hero_get"):
		var hero1: Variant = SaveService.hero_get(int(id_val))
		if typeof(hero1) == TYPE_DICTIONARY:
			return hero1 as Dictionary
	# Path 2: Engine singleton (only if SaveService is exposed that way)
	if Engine.has_singleton("SaveService"):
		var svc: Variant = Engine.get_singleton("SaveService")
		if svc and svc.has_method("hero_get"):
			var hero2: Variant = svc.call("hero_get", int(id_val))
			if typeof(hero2) == TYPE_DICTIONARY:
				return hero2 as Dictionary
	# No source available → return empty to trigger safe fallbacks upstream
	return {}

static func _to_combat_entity(hero: Dictionary, fallback_id: int) -> Dictionary:
	# Build a combat entity from a hero record. Preserve existing stats if present,
	# otherwise create a safe, typed fallback block.
	var ent_id: int = int(hero.get("id", fallback_id))
	var name_s: String = String(hero.get("name", ""))
	var arch_s: String = String(hero.get("archetype", "none"))
	var stats_in: Dictionary = {}
	if hero.has("stats") and typeof(hero["stats"]) == TYPE_DICTIONARY:
		stats_in = hero["stats"]
	var stats_out: Dictionary = CombatEntities.fill_missing_stats(stats_in) if stats_in.size() > 0 else CombatEntities.fallback_stats()

	# MVP hook: hydrate initial morale/fear for this hero from EmotionService
	# when available, so combat always starts from the persisted emotional state.
	var fear_val: int = int(hero.get("fear", 0))
	if ent_id > 0:
		fear_val = _hydrate_emotion_from_service(ent_id, stats_out, fear_val)

	return {
		"id": ent_id,
		"name": name_s,
		"archetype": arch_s,
		"stats": stats_out,
		"fear": fear_val,
		"tags": ["ally", "hero"],
		"status": String(hero.get("status", "idle")),
	}
# Pull morale/fear for a hero from EmotionService when available.
# Returns the final fear value written into stats (so callers can mirror it
# into the flat `fear` field on the combat entity).
static func _hydrate_emotion_from_service(ent_id: int, stats: Dictionary, fallback_fear: int) -> int:
	var fear_val: int = fallback_fear

	# Try to locate EmotionService via the SaveService singleton/autoload.
	var emo: Variant = null
	if Engine.has_singleton("SaveService"):
		var svc: Variant = Engine.get_singleton("SaveService")
		if svc and svc.has_method("emotion_get_service"):
			emo = svc.call("emotion_get_service")
	elif typeof(SaveService) != TYPE_NIL and SaveService.has_method("emotion_get_service"):
		emo = SaveService.emotion_get_service()

	if emo == null:
		# No emotion system wired yet; keep whatever was passed in.
		return fear_val

	# Morale: source of truth is EmotionService; clamp to 0..100 for safety.
	if emo.has_method("get_morale"):
		var m_val: int = int(emo.call("get_morale", ent_id))
		stats[EchoConstants.STAT_MORALE] = max(0, min(100, m_val))

	# Fear: same pattern; also mirror into STAT_FEAR for consistency.
	if emo.has_method("get_fear"):
		fear_val = max(0, min(100, int(emo.call("get_fear", ent_id))))
		stats[EchoConstants.STAT_FEAR] = fear_val

	return fear_val


func _find_entity(id_val: int) -> Variant:
	for a in _state.get("allies", []):
		if int(a.get("id", -1)) == id_val:
			return a
	for e in _state.get("enemies", []):
		if int(e.get("id", -1)) == id_val:
			return e
	return null

func _side_of(id_val: int) -> String:
	for a in _state.get("allies", []):
		if int(a.get("id", -1)) == id_val:
			return "ALLY"
	for e in _state.get("enemies", []):
		if int(e.get("id", -1)) == id_val:
			return "ENEMY"
	return "UNKNOWN"


func _check_end() -> Dictionary:
	# Delegate core end-condition evaluation to CombatObjectives so that
	# defeat / purify_shrine and future objectives live in a single module.
	var objective: String = String(_state.get("objective", "defeat"))
	var round_limit: int = int(_state.get("round_limit", 10))

	var end_result: Dictionary = CombatObjectives.check_end(_state, objective, round_limit, HeroBal)

	# If the battle is still ongoing, CombatObjectives will have returned a
	# lightweight sentinel (e.g. {"ongoing": true}) and left `_state.over`
	# as `false`. No emotion payload is attached in that case.
	if not bool(_state.get("over", false)):
		return end_result

	# When the battle ends, enrich the result with the emotion payload while
	# preserving the existing result shape for callers.
	var emo_result: Dictionary = CombatEmotionSystem.build_emotion_result(_state)
	if emo_result.size() > 0:
		if not _state.has("result") or typeof(_state["result"]) != TYPE_DICTIONARY:
			_state["result"] = {}
		_state["result"]["emotion"] = emo_result
		end_result = _state["result"]

	return end_result

# --- Morale override API (persist across fights for QA/debug) ---------------
## Set/Update a morale override for an entity id. Also updates current state if present.
func morale_override_set(id_val: int, morale_value: int) -> void:
	var v : Variant = max(0, min(100, int(morale_value)))
	_morale_overrides[int(id_val)] = v
	# Update live entity if present
	var ent: Variant = _find_entity(int(id_val))
	if ent != null and typeof(ent) == TYPE_DICTIONARY:
		CombatEmotionSystem.write_morale(ent as Dictionary, v)

## Get an override if present; returns -1 if none.
func morale_override_get(id_val: int) -> int:
	if _morale_overrides.has(int(id_val)):
		return int(_morale_overrides[int(id_val)])
	return -1

## Clear all overrides or a single id when provided.
func morale_override_clear(id_val: int = -1) -> void:
	if int(id_val) >= 0:
		_morale_overrides.erase(int(id_val))
	else:
		_morale_overrides.clear()

## Applies overrides to the active _state (called after start_battle).
func _apply_morale_overrides() -> void:
	if _morale_overrides.is_empty():
		return
	# Allies
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent_a: Dictionary = a
		if CombatEntities.is_shrine(ent_a):
			continue
		var id_a := int(ent_a.get("id", -1))
		if id_a >= 0 and _morale_overrides.has(id_a):
			CombatEmotionSystem.write_morale(ent_a, int(_morale_overrides[id_a]))
	# Enemies (supported for completeness, even if MVP ignores morale for them)
	for e in _state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_e := int((e as Dictionary).get("id", -1))
		if id_e >= 0 and _morale_overrides.has(id_e):
			CombatEmotionSystem.write_morale(e as Dictionary, int(_morale_overrides[id_e]))







# Map numeric action types to canonical logger verbs
static func _action_type_to_verb(t: int) -> String:
	match t:
		CombatConstants.ActionType.ATTACK:        return "ATTACK"
		CombatConstants.ActionType.GUARD:         return "GUARD"
		CombatConstants.ActionType.MOVE:          return "MOVE"
		CombatConstants.ActionType.REFUSE:        return "REFUSE"
		CombatConstants.ActionType.PURIFY_SHRINE: return "PURIFY_SHRINE"
		_:                                        return ""
