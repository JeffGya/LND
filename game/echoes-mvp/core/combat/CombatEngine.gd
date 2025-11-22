# core/combat/CombatEngine.gd
# -----------------------------------------------------------------------------
# Deterministic, step-based round engine.
# Drives INITIATIVE → SELECT → RESOLVE → TICK → CHECK using the pure modules:
#   - Initiative.compute_order(ctx)
#   - EchoActionChooser.choose_action(hero, ctx)
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

class_name CombatEngine


const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")

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
	_capture_emotion_baseline()
	_assign_designated_purifier()

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
		for a in _state.get("allies", []):
			if typeof(a) == TYPE_DICTIONARY and bool((a as Dictionary).get("is_shrine", false)):
				shrine_id = int((a as Dictionary).get("id", -1))
				break

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

	# Build a name map for readable logs
	var name_by_id: Dictionary = _build_name_map()

	# 2) SELECT + 3) RESOLVE ----------------------------------------------------
	var actions: Array[Dictionary] = []
	var focus_hits: Dictionary = {}  # target_id -> number of times hit this round
	for actor_id in order:
		var ent: Variant = _find_entity(actor_id)
		if ent == null or typeof(ent) != TYPE_DICTIONARY:
			continue
		var ent_dict: Dictionary = ent
		# Shrine and other non-acting entities never take turns.
		if _is_shrine_entity(ent_dict):
			continue
		if ent_dict.has("can_act") and not bool(ent_dict.get("can_act", true)):
			continue
		if not _entity_alive(ent_dict):
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
			action = _choose_enemy_action(ent_dict, ctx)

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
				var hp_pair: Dictionary = _read_hp_pair(target_ent)
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
					var m_val: int = _get_morale(ent_dict)
					# Use enum tier to avoid string drift, then map to label and multiplier
					var tier_enum: int = CombatConstants.morale_tier(m_val)
					var tier_label: String = _morale_tier_label(m_val)
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

		# Mark shrine purification and add a time-limited stack when a PURIFY_SHRINE action succeeds.
		if eff_type == CombatConstants.ActionType.PURIFY_SHRINE and effect.get("ok", true):
			# Per-round flag: useful for logs / QA tick summaries.
			_state["shrine_purified_this_round"] = true

			# Party‑wide cooldown: after a successful Purify, the whole party shares a cooldown.
			var cd_base: int = int(HeroBal.SHRINE_PURIFY_COOLDOWN_ROUNDS)
			if cd_base < 0:
				cd_base = 0
			var current_cd: int = int(_state.get("shrine_purify_cd_remaining", 0))
			_state["shrine_purify_cd_remaining"] = max(current_cd, cd_base)

			# Time‑limited drain reduction stack:
			# The resolver may specify stack duration / magnitude; otherwise fall back to balance defaults.
			var default_stack_rounds: int = int(HeroBal.SHRINE_PURIFY_STACK_DURATION_ROUNDS)
			if default_stack_rounds < 0:
				default_stack_rounds = 0

			# Default reduction is derived from the base drain and the config multiplier:
			# base_drain - reduction = base_drain * MULTIPLIER  ⇒  reduction = base_drain * (1 - MULTIPLIER)
			var base_drain: int = int(HeroBal.SHRINE_DRAIN_PER_ROUND_BASE)
			var default_reduction: int = 0
			if base_drain > 0:
				var frac: float = 1.0 - float(HeroBal.SHRINE_PURIFY_BASE_DRAIN_REDUCTION)
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
				if _state.has("shrine_purify_stacks") and typeof(_state["shrine_purify_stacks"]) == TYPE_ARRAY:
					stacks = _state["shrine_purify_stacks"]
				stacks.append({
					"rounds_left": stack_rounds,
					"reduction": stack_reduction,
				})
				_state["shrine_purify_stacks"] = stacks

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
				_increase_fear_on_entity(tid2, HeroBal.FEAR_PER_HIT + extra_focus)
				# store back hit count
				focus_hits[tid2] = prev_hits + 1
		actions.append(effect)

	# After all actions, apply KO shock to surviving allies
	_apply_fear_from_ally_ko()

	# Capture current HP and guard states for readable per-round summaries
	var state_after: Dictionary = {"allies": [], "enemies": []}
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var hp_info: Dictionary = _read_hp_pair(a)
		var ko_flag: bool = not _entity_alive(a)
		var guard_val: int = int((a as Dictionary).get("guard_shield", 0))
		var item: Dictionary = {
			"id": int(a.get("id", -1)),
			"name": str(name_by_id.get(int(a.get("id", -1)), str(a.get("id", -1)))),
			"hp": int(hp_info.get("hp", 0)),
			"max_hp": int(hp_info.get("max_hp", 0)),
			"ko": ko_flag,
			"guard": guard_val,
			"morale": _get_morale(a),
			"morale_tier": _morale_tier_label(_get_morale(a)),
		}
		state_after["allies"].append(item)
	for e in _state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var hp_info_e: Dictionary = _read_hp_pair(e)
		var ko_flag_e: bool = not _entity_alive(e)
		var guard_val_e: int = int((e as Dictionary).get("guard_shield", 0))
		var item_e: Dictionary = {
			"id": int(e.get("id", -1)),
			"name": str(name_by_id.get(int(e.get("id", -1)), str(e.get("id", -1)))),
			"hp": int(hp_info_e.get("hp", 0)),
			"max_hp": int(hp_info_e.get("max_hp", 0)),
			"ko": ko_flag_e,
			"guard": guard_val_e,
		}
		state_after["enemies"].append(item_e)
	# 4) TICK (fear & morale cadence) ------------------------------------------
	var tick_info: Dictionary = _apply_ticks()

	# 5) CHECK end conditions ---------------------------------------------------
	var end_info: Dictionary = _check_end()

	var snapshot: Dictionary = {
		"round": round_index,
		"order": order,
		"actions": actions,
		"ticks": tick_info,
		"end": end_info,
		"name_by_id": name_by_id,
		"state_after": state_after,
	}

	_state.last_snapshot = snapshot

	# Prepare next round or finalize
	if not _state.over:
		_state.round = round_index + 1
	else:
		# Package a final_state for external consumers (no persistence here)
		var final_state: Dictionary = {
			"allies": _state.allies,
			"enemies": _state.enemies,
		}
		_state.last_snapshot["final_state"] = final_state

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
		if _is_shrine_entity(ent):
			continue
		if not _entity_alive(ent):
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
	score += _get_morale(ent) * HeroBal.PURIFIER_SCORE_MORALE_WEIGHT

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

# Returns a clamped morale (0..100). Allies have real morale; enemies return a steady baseline.
func _get_morale(ent: Dictionary) -> int:
	# Allies: real morale lives under stats.morale (preferred) or fallback `morale`.
	if ent.get("stats") is Dictionary:
		if (ent.stats as Dictionary).has("morale"):
			var m := int((ent.stats as Dictionary).get("morale", 50))
			return max(0, min(100, m))
	if ent.has("morale"):
		return max(0, min(100, int(ent.get("morale", 50))))
	# MVP: enemies do not use morale; return steady baseline for completeness.
	return 50

# Compact label for snapshot/log readability.
func _morale_tier_label(morale_value: int) -> String:
	var t := CombatConstants.morale_tier(int(morale_value))
	match t:
		CombatConstants.MoraleTier.INSPIRED: return "INSPIRED"
		CombatConstants.MoraleTier.STEADY:  return "STEADY"
		CombatConstants.MoraleTier.SHAKEN:  return "SHAKEN"
		_:                                   return "BROKEN"

func _is_shrine_entity(ent: Dictionary) -> bool:
	if typeof(ent) != TYPE_DICTIONARY:
		return false
	return bool(ent.get("is_shrine", false))

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

					out.append(shrine_out)
					continue

				var d_out: Dictionary = d_in
				if not d_out.has("stats") or typeof(d_out["stats"]) != TYPE_DICTIONARY:
					d_out["stats"] = _fallback_stats_from_balance()
				else:
					d_out["stats"] = _fill_missing_stats_with_balance(d_out["stats"])
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
			_ensure_stat_int(s, EchoConstants.STAT_HP, int(e.get("hp", HeroBal.FALLBACK_HP)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)

		if flat_max_hp_set:
			_ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(e.get("max_hp", int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))

		if flat_atk_set:
			_ensure_stat_int(s, EchoConstants.STAT_ATK, int(e.get("atk", HeroBal.FALLBACK_ATK)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_ATK, HeroBal.FALLBACK_ATK)

		if flat_def_set:
			_ensure_stat_int(s, EchoConstants.STAT_DEF, int(e.get("def", HeroBal.FALLBACK_DEF)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_DEF, HeroBal.FALLBACK_DEF)

		if flat_agi_set:
			_ensure_stat_int(s, EchoConstants.STAT_AGI, int(e.get("agi", HeroBal.FALLBACK_AGI)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_AGI, HeroBal.FALLBACK_AGI)

		if flat_cha_set:
			_ensure_stat_int(s, EchoConstants.STAT_CHA, int(e.get("cha", 0)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_CHA, 0)

		if flat_int_set:
			_ensure_stat_int(s, EchoConstants.STAT_INT, int(e.get("int", 0)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_INT, 0)

		if flat_acc_set:
			_ensure_stat_int(s, EchoConstants.STAT_ACC, int(e.get("acc", 0)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_ACC, 0)

		if flat_eva_set:
			_ensure_stat_int(s, EchoConstants.STAT_EVA, int(e.get("eva", 0)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_EVA, 0)

		if flat_crit_set:
			_ensure_stat_int(s, EchoConstants.STAT_CRIT, int(e.get("crit", 0)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_CRIT, 0)

		# Morale/Fear (enemies ignore morale in MVP but keep a neutral value for shape)
		_ensure_stat_int(s, EchoConstants.STAT_MORALE, HeroBal.FALLBACK_MORALE)
		_ensure_stat_int(s, EchoConstants.STAT_FEAR, int(e.get("fear", 0)))

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
	var stats_out: Dictionary = _fill_missing_stats(stats_in) if stats_in.size() > 0 else _fallback_stats()

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

static func _fallback_stats() -> Dictionary:
	# Safe typed defaults for when hero has no stats (older saves or bad data).
	return {
		EchoConstants.STAT_HP: HeroBal.FALLBACK_HP,
		EchoConstants.STAT_MAX_HP: HeroBal.FALLBACK_HP,
		EchoConstants.STAT_ATK: HeroBal.FALLBACK_ATK,
		EchoConstants.STAT_DEF: HeroBal.FALLBACK_DEF,
		EchoConstants.STAT_AGI: HeroBal.FALLBACK_AGI,
		EchoConstants.STAT_CHA: 0,
		EchoConstants.STAT_INT: 0,
		EchoConstants.STAT_ACC: 0,
		EchoConstants.STAT_EVA: 0,
		EchoConstants.STAT_CRIT: 0,
		EchoConstants.STAT_MORALE: HeroBal.FALLBACK_MORALE,
		EchoConstants.STAT_FEAR: 0,
	}

static func _fallback_stats_from_balance() -> Dictionary:
	return {
		EchoConstants.STAT_HP: HeroBal.FALLBACK_HP,
		EchoConstants.STAT_MAX_HP: HeroBal.FALLBACK_HP,
		EchoConstants.STAT_ATK: HeroBal.FALLBACK_ATK,
		EchoConstants.STAT_DEF: HeroBal.FALLBACK_DEF,
		EchoConstants.STAT_AGI: HeroBal.FALLBACK_AGI,
		EchoConstants.STAT_CHA: 0,
		EchoConstants.STAT_INT: 0,
		EchoConstants.STAT_ACC: 0,
		EchoConstants.STAT_EVA: 0,
		EchoConstants.STAT_CRIT: 0,
		EchoConstants.STAT_MORALE: HeroBal.FALLBACK_MORALE,
		EchoConstants.STAT_FEAR: 0,
	}

static func _fill_missing_stats_with_balance(stats_in: Dictionary) -> Dictionary:
	var s: Dictionary = stats_in.duplicate(true)
	_ensure_stat_int(s, EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)
	_ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))
	_ensure_stat_int(s, EchoConstants.STAT_ATK, HeroBal.FALLBACK_ATK)
	_ensure_stat_int(s, EchoConstants.STAT_DEF, HeroBal.FALLBACK_DEF)
	_ensure_stat_int(s, EchoConstants.STAT_AGI, HeroBal.FALLBACK_AGI)
	_ensure_stat_int(s, EchoConstants.STAT_CHA, 0)
	_ensure_stat_int(s, EchoConstants.STAT_INT, 0)
	_ensure_stat_int(s, EchoConstants.STAT_ACC, 0)
	_ensure_stat_int(s, EchoConstants.STAT_EVA, 0)
	_ensure_stat_int(s, EchoConstants.STAT_CRIT, 0)
	_ensure_stat_int(s, EchoConstants.STAT_MORALE, HeroBal.FALLBACK_MORALE)
	_ensure_stat_int(s, EchoConstants.STAT_FEAR, 0)
	return s

static func _fill_missing_stats(stats_in: Dictionary) -> Dictionary:
	# Ensure all canonical keys exist and are ints; do not change provided values.
	var s: Dictionary = stats_in.duplicate(true)
	_ensure_stat_int(s, EchoConstants.STAT_HP, 1)
	_ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, 1)))
	_ensure_stat_int(s, EchoConstants.STAT_ATK, 0)
	_ensure_stat_int(s, EchoConstants.STAT_DEF, 0)
	_ensure_stat_int(s, EchoConstants.STAT_AGI, 0)
	_ensure_stat_int(s, EchoConstants.STAT_CHA, 0)
	_ensure_stat_int(s, EchoConstants.STAT_INT, 0)
	_ensure_stat_int(s, EchoConstants.STAT_ACC, 0)
	_ensure_stat_int(s, EchoConstants.STAT_EVA, 0)
	_ensure_stat_int(s, EchoConstants.STAT_CRIT, 0)
	_ensure_stat_int(s, EchoConstants.STAT_MORALE, 50)
	_ensure_stat_int(s, EchoConstants.STAT_FEAR, 0)
	return s

func _find_entity(id_val: int) -> Variant:
	for a in _state.get("allies", []):
		if int(a.get("id", -1)) == id_val:
			return a
	for e in _state.get("enemies", []):
		if int(e.get("id", -1)) == id_val:
			return e
	return null

func _entity_alive(ent: Dictionary) -> bool:
	var hp := 0
	if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY and ent.stats.has("hp"):
		hp = int(ent.stats.hp)
	else:
		hp = int(ent.get("hp", 0))
	if hp <= 0:
		return false
	if str(ent.get("status", "")) == "downed":
		return false
	return true

func _side_of(id_val: int) -> String:
	for a in _state.get("allies", []):
		if int(a.get("id", -1)) == id_val:
			return "ALLY"
	for e in _state.get("enemies", []):
		if int(e.get("id", -1)) == id_val:
			return "ENEMY"
	return "UNKNOWN"

func _apply_ticks() -> Dictionary:
	var fear_tick: int = CombatConstants.FEAR_PER_ROUND
	var morale_decay_applied: bool = false
	var do_decay: bool = (int(_state.round) % CombatConstants.MORALE_DECAY_EVERY_N_ROUNDS) == 0
	var shrine_drain_applied: int = 0
	var shrine_purified: bool = bool(_state.get("shrine_purified_this_round", false))

	# Global Purify cooldown (party‑wide): tick down once per round after all actions.
	var cd_remaining: int = int(_state.get("shrine_purify_cd_remaining", 0))
	if cd_remaining > 0:
		cd_remaining -= 1
		if cd_remaining < 0:
			cd_remaining = 0
	_state["shrine_purify_cd_remaining"] = cd_remaining

	# Update Purify stacks: apply their reduction this round and decay their remaining duration.
	var stacks_in: Array = []
	if _state.has("shrine_purify_stacks") and typeof(_state["shrine_purify_stacks"]) == TYPE_ARRAY:
		stacks_in = _state["shrine_purify_stacks"]
	var stacks_out: Array = []
	var shrine_purify_reduction: int = 0
	for s in stacks_in:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var rounds_left: int = int((s as Dictionary).get("rounds_left", 0))
		var reduction: int = int((s as Dictionary).get("reduction", 0))
		if rounds_left <= 0 or reduction <= 0:
			continue
		# This stack applies to the current round.
		shrine_purify_reduction += reduction
		# Then decay duration for future rounds.
		rounds_left -= 1
		if rounds_left > 0:
			var s_next: Dictionary = (s as Dictionary).duplicate(true)
			s_next["rounds_left"] = rounds_left
			stacks_out.append(s_next)
	_state["shrine_purify_stacks"] = stacks_out

	# Allies: fear + morale decay
	for ent in _state.get("allies", []):
		if not _entity_alive(ent):
			continue
		if _is_shrine_entity(ent):
			continue
		# Fear accrual
		var fear: int = int(ent.get("fear", 0))
		fear = min(100, max(0, fear + fear_tick))
		ent["fear"] = fear
		# Morale decay cadence (allies only)
		if do_decay:
			var morale: int = _get_morale(ent)
			morale = max(0, morale - CombatConstants.MORALE_DECAY_AMOUNT)
			if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
				ent.stats["morale"] = morale
			else:
				ent["morale"] = morale
			morale_decay_applied = true

	# Enemies: fear only (MVP — enemies ignore morale)
	for ent_e in _state.get("enemies", []):
		if not _entity_alive(ent_e):
			continue
		var fear_e: int = int(ent_e.get("fear", 0))
		fear_e = min(100, max(0, fear_e + fear_tick))
		ent_e["fear"] = fear_e

		# Shrine: per-round passive HP drain (Purify Shrine objective only)
	# We treat the shrine as a special allied entity with `is_shrine = true`.
	# Drain amount is driven by GameBalance_HeroCombat.SHRINE_DRAIN_PER_ROUND_BASE
	# and reduced by any active, time-limited Purify stacks.
	if String(_state.get("objective", "")) == "purify_shrine" and HeroBal.SHRINE_DRAIN_PER_ROUND_BASE != 0:
		for ent_shrine in _state.get("allies", []):
			if typeof(ent_shrine) != TYPE_DICTIONARY:
				continue
			var shrine_dict: Dictionary = ent_shrine
			if not _is_shrine_entity(shrine_dict):
				continue

			# Read current HP / Max HP using the same helper used elsewhere for logs.
			var hp_pair: Dictionary = _read_hp_pair(shrine_dict)
			var hp_before: int = int(hp_pair.get("hp", 0))
			var max_hp: int = int(hp_pair.get("max_hp", 0))
			if hp_before <= 0:
				break

			var drain: int = HeroBal.SHRINE_DRAIN_PER_ROUND_BASE

			# Apply any active Purify stacks as a reduction to this round's drain.
			if shrine_purify_reduction > 0:
				drain = max(0, drain - shrine_purify_reduction)

			if drain <= 0:
				break

			var hp_after: int = max(0, hp_before - drain)

			# Persist back into stats and flat HP so both views stay in sync.
			if shrine_dict.has("stats") and typeof(shrine_dict["stats"]) == TYPE_DICTIONARY:
				var s: Dictionary = shrine_dict["stats"]
				if s.has(EchoConstants.STAT_HP):
					s[EchoConstants.STAT_HP] = hp_after
				shrine_dict["stats"] = s

			shrine_dict["hp"] = hp_after
			shrine_dict["max_hp"] = max_hp

			shrine_drain_applied = hp_before - hp_after
			break
	# Purify effect is per-round: clear the flag after applying this tick.
	_state["shrine_purified_this_round"] = false

	return {
		"fear": fear_tick,
		"morale_decay": morale_decay_applied,
		"shrine_drain": shrine_drain_applied,
		"shrine_purified": shrine_purified,
		"shrine_purify_reduction": shrine_purify_reduction,
		"shrine_purify_cd": int(_state.get("shrine_purify_cd_remaining", 0)),
	}

func _check_end() -> Dictionary:
	# Shrine-aware end condition handling.
	var objective: String = String(_state.get("objective", "defeat"))
	var shrine_present: bool = false
	var shrine_dead: bool = false
	var shrine_hp_remaining: int = 0
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if bool(ent.get("is_shrine", false)):
			shrine_present = true
			var hp_pair: Dictionary = _read_hp_pair(ent)
			var raw_hp: int = int(hp_pair.get("hp", 0))
			var max_hp: int = int(hp_pair.get("max_hp", 0))
			var clamped_hp: int = max(0, raw_hp)
			if max_hp > 0:
				clamped_hp = min(clamped_hp, max_hp)
			# Write clamped HP back into the entity so downstream checks see a sane value
			if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
				(ent.stats as Dictionary)[EchoConstants.STAT_HP] = clamped_hp
				ent.stats["hp"] = clamped_hp
			else:
				ent["hp"] = clamped_hp
			shrine_hp_remaining = clamped_hp
			if not _entity_alive(ent):
				shrine_dead = true
			break

	var allies_alive: bool = false
	for a2 in _state.get("allies", []):
		if _entity_alive(a2):
			allies_alive = true
			break
	var enemies_alive: bool = false
	for e in _state.get("enemies", []):
		if _entity_alive(e):
			enemies_alive = true
			break

	var reason: String = ""
	var victory: bool = false

	# Shrine-specific failure: in Purify Shrine objectives, shrine destruction
	# immediately ends the battle as a loss, even if heroes are still standing.
	if objective == "purify_shrine" and shrine_present and shrine_dead:
		_state.over = true
		victory = false
		reason = "shrine_destroyed"
	elif not enemies_alive and allies_alive:
		_state.over = true
		victory = true
		reason = "enemies_defeated"
	elif not allies_alive and enemies_alive:
		_state.over = true
		victory = false
		reason = "allies_defeated"
	elif not allies_alive and not enemies_alive:
		_state.over = true
		victory = true  # edge-case: double KO → call it a Pyrrhic win for MVP
		reason = "double_ko"
	elif int(_state.round) >= int(_state.round_limit):
		_state.over = true
		# MVP objective: defeat → side with more survivors wins; tie → round_limit
		var allies_count: int = _alive_count(_state.allies)
		var enemies_count: int = _alive_count(_state.enemies)
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

	if _state.over:
		_state.result = {"victory": victory, "reason": reason}
		# Surface shrine outcome when present so ObjectiveRunner can react.
		if shrine_present:
			_state.result["shrine_destroyed"] = shrine_dead
			_state.result["shrine_hp_remaining"] = shrine_hp_remaining
		var emo_result: Dictionary = _build_emotion_result()
		if emo_result.size() > 0:
			_state.result["emotion"] = emo_result
		return _state.result
	else:
		return {"ongoing": true}

func _alive_count(group: Array[Dictionary]) -> int:
	var c := 0
	for ent in group:
		if _entity_alive(ent):
			c += 1
	return c

#
# --- Emotion baselines & result packaging ------------------------------------
## Capture starting morale/fear for all allies at the beginning of a battle.
## This is called once after start_battle has hydrated entities and applied
## any morale overrides, so it represents the true combat starting point.
func _capture_emotion_baseline() -> void:
	var baseline: Dictionary = {}
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if _is_shrine_entity(ent):
			continue
		var hero_id: int = int(ent.get("id", -1))
		if hero_id <= 0:
			continue
		var start_morale: int = _get_morale(ent)
		var start_fear: int = int(ent.get("fear", 0))
		baseline[hero_id] = {
			"morale": start_morale,
			"fear": start_fear,
		}
	_state["emotion_baseline"] = baseline

## Build a structured emotion result payload comparing final vs baseline
## morale/fear. Consumers (ObjectiveRunner, debug harness) can pass this to
## EmotionService to persist deltas across the campaign.
func _build_emotion_result() -> Dictionary:
	var heroes: Dictionary = {}
	var baseline: Dictionary = _state.get("emotion_baseline", {})
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if _is_shrine_entity(ent):
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
			start_morale = _get_morale(ent)
		if base.has("fear"):
			start_fear = int(base.get("fear", 0))
		else:
			start_fear = int(ent.get("fear", 0))

		var final_morale: int = _get_morale(ent)
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

# --- Morale override API (persist across fights for QA/debug) ---------------
## Set/Update a morale override for an entity id. Also updates current state if present.
func morale_override_set(id_val: int, morale_value: int) -> void:
	var v : Variant = max(0, min(100, int(morale_value)))
	_morale_overrides[int(id_val)] = v
	# Update live entity if present
	var ent: Variant = _find_entity(int(id_val))
	if ent != null and typeof(ent) == TYPE_DICTIONARY:
		_write_morale(ent as Dictionary, v)

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
		if _is_shrine_entity(ent_a):
			continue
		var id_a := int(ent_a.get("id", -1))
		if id_a >= 0 and _morale_overrides.has(id_a):
			_write_morale(ent_a, int(_morale_overrides[id_a]))
	# Enemies (supported for completeness, even if MVP ignores morale for them)
	for e in _state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_e := int((e as Dictionary).get("id", -1))
		if id_e >= 0 and _morale_overrides.has(id_e):
			_write_morale(e as Dictionary, int(_morale_overrides[id_e]))

## Internal: write morale into an entity respecting stats container shape.
func _write_morale(ent: Dictionary, morale_value: int) -> void:
	var v : Variant = max(0, min(100, int(morale_value)))
	if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
		(ent.stats as Dictionary)["morale"] = v
	else:
		ent["morale"] = v

func _find_alive_shrine(allies: Array) -> Dictionary:
	var shrine: Dictionary = {}
	for a in allies:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		if not _is_shrine_entity(ent):
			continue
		if not _entity_alive(ent):
			continue
		shrine = ent
		break
	return shrine

# Simple mirrored chooser for enemies (deterministic, no RNG) -----------------
func _choose_enemy_action(enemy: Dictionary, ctx: Dictionary) -> Dictionary:
	var actor_id := int(enemy.get("id", -1))
	if actor_id < 0:
		return {"type": CombatConstants.ActionType.REFUSE, "actor_id": actor_id, "notes": "invalid_actor"}

	# REFUSE if fear high (MVP: enemies ignore morale)
	var fear := int(enemy.get("fear", 0))
	if fear >= 80:
		return {"type": CombatConstants.ActionType.REFUSE, "actor_id": actor_id, "notes": "overwhelmed"}

	# GUARD lowest-hp% fellow enemy (rare in MVP dummies but deterministic)
	var triage: Dictionary = _pick_lowest_hp_ratio(ctx.get("enemies", []))
	if typeof(triage) == TYPE_DICTIONARY and triage.size() > 0 and int(triage["id"]) != actor_id and float(triage["hp_ratio"]) < 0.5:
		return {"type": CombatConstants.ActionType.GUARD, "actor_id": actor_id, "target_id": int(triage["id"]), "notes": "triage"}

	# Shrine priority in Purify Shrine objectives (MVP):
	var objective: String = String(_state.get("objective", "defeat"))
	if objective == "purify_shrine":
		var shrine_ent: Dictionary = _find_alive_shrine(ctx.get("allies", []))
		if shrine_ent.size() > 0:
			var shrine_id: int = int(shrine_ent.get("id", -1))
			# Always prioritize attacking shrine when in range.
			if _is_in_range(actor_id, shrine_id, ctx):
				return {
					"type": CombatConstants.ActionType.ATTACK,
					"actor_id": actor_id,
					"target_id": shrine_id,
					"notes": "focus_shrine"
				}
			# If somehow out of range (future distance systems), move toward shrine.
			return {
				"type": CombatConstants.ActionType.MOVE,
				"actor_id": actor_id,
				"target_id": shrine_id,
				"notes": "approach_shrine"
			}

	# ATTACK weakest ally if in range; else MOVE toward nearest ally
	var weakest: Dictionary = _pick_weakest(ctx.get("allies", []))
	if weakest.size() > 0:
		if _is_in_range(actor_id, int(weakest["id"]), ctx):
			return {"type": CombatConstants.ActionType.ATTACK, "actor_id": actor_id, "target_id": int(weakest["id"]), "notes": "focus_weakest"}
		var nearest: Dictionary = _pick_nearest(actor_id, ctx.get("allies", []), ctx)
		if nearest.size() > 0:
			return {"type": CombatConstants.ActionType.MOVE, "actor_id": actor_id, "target_id": int(nearest["id"]), "notes": "advance"}

	return {"type": CombatConstants.ActionType.REFUSE, "actor_id": actor_id, "notes": "no_targets"}

# Shared tiny utilities (mirrors chooser helpers) -----------------------------
func _pick_lowest_hp_ratio(group: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for a in group:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var id_val := int(a.get("id", -1))
		if id_val < 0:
			continue
		var hp := HeroBal.FALLBACK_HP
		var max_hp := HeroBal.FALLBACK_HP
		if a.has("stats") and typeof(a.stats) == TYPE_DICTIONARY:
			hp = int(a.stats.get("hp", HeroBal.FALLBACK_HP))
			max_hp = int(a.stats.get("max_hp", HeroBal.FALLBACK_HP))
		else:
			hp = int(a.get("hp", HeroBal.FALLBACK_HP))
			max_hp = int(a.get("max_hp", HeroBal.FALLBACK_HP))
		var ratio := float(hp) / float(max(1, max_hp))
		var cand := {"id": id_val, "hp_ratio": ratio}
		if best.size() == 0:
			best = cand
		else:
			if float(cand["hp_ratio"]) == float(best["hp_ratio"]):
				if int(cand["id"]) < int(best["id"]):
					best = cand
			elif float(cand["hp_ratio"]) < float(best["hp_ratio"]):
				best = cand
	return best

func _pick_weakest(group: Array[Dictionary]) -> Dictionary:
	var pool: Array[Dictionary] = []
	for e in group:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_val := int(e.get("id", -1))
		if id_val < 0:
			continue
		var hp := HeroBal.FALLBACK_HP
		if e.has("stats") and typeof(e.stats) == TYPE_DICTIONARY and e.stats.has("hp"):
			hp = int(e.stats.hp)
		elif e.has("hp"):
			hp = int(e.hp)
		pool.append({"id": id_val, "hp": hp})
	if pool.is_empty():
		return {}
	pool.sort_custom(Callable(self, "_cmp_hp_asc_id_asc"))
	return pool[0]

func _pick_nearest(actor_id: int, group: Array[Dictionary], ctx: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var has_map := ctx.has("distance") and ctx.has("attack_range")
	for e in group:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_val := int(e.get("id", -1))
		if id_val < 0:
			continue
		var metric: int = 0
		if has_map:
			var dist_map: Dictionary = ctx.get("distance", {})
			var key: int = _pair_key(actor_id, id_val)
			metric = int(dist_map.get(key, 9999))
		else:
			metric = id_val
		var cand := {"id": id_val, "metric": metric}
		if best.size() == 0:
			best = cand
		else:
			if int(cand["metric"]) == int(best["metric"]):
				if int(cand["id"]) < int(best["id"]):
					best = cand
			elif int(cand["metric"]) < int(best["metric"]):
				best = cand
	return best

func _is_in_range(actor_id: int, target_id: int, ctx: Dictionary) -> bool:
	if not ctx.has("distance") or not ctx.has("attack_range"):
		return true
	var dist_map: Dictionary = ctx.get("distance", {})
	var atk_range: int = int(ctx.get("attack_range", 1))
	var key: int = _pair_key(actor_id, target_id)
	var tiles: int = int(dist_map.get(key, atk_range))
	return tiles <= atk_range

# --- Name/Info helpers for logging and context -------------------------------

func _build_name_map() -> Dictionary:
	var map: Dictionary = {}
	# Allies: try in-entity name, else hydrate from SaveService
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		var id_val: int = int(ent.get("id", -1))

		# Shrine entries may use a reserved/negative id; always name them from the entity.
		if _is_shrine_entity(ent):
			var shrine_name: String = str(ent.get("name", "Shrine"))
			map[id_val] = shrine_name
			continue

		if id_val < 0:
			continue

		var nm: String = ""
		if ent.has("name"):
			nm = str(ent.get("name", ""))
		if nm == "":
			nm = _hero_name_from_save(id_val)
		if nm == "":
			nm = "Hero %d" % id_val
		map[id_val] = nm
	# Enemies usually have a name inline; keep current fallback
	for e in _state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_e: int = int(e.get("id", -1))
		if id_e < 0:
			continue
		var nm_e: String = ""
		if (e as Dictionary).has("name"):
			nm_e = str((e as Dictionary).get("name", ""))
		if nm_e == "":
			nm_e = "Enemy %d" % id_e
		map[id_e] = nm_e
	return map

func _hero_name_from_save(id_val: int) -> String:
	var nm: String = ""
	# Prefer engine singleton SaveService if available
	if Engine.has_singleton("SaveService"):
		var svc: Variant = Engine.get_singleton("SaveService")
		if svc and svc.has_method("hero_get"):
			var v: Variant = svc.call("hero_get", id_val)
			if typeof(v) == TYPE_DICTIONARY:
				var d: Dictionary = v
				if d.has("name"):
					nm = str(d.get("name", ""))
					if nm != "":
						return nm
	# Fallback to autoload script instance if present
	if typeof(SaveService) != TYPE_NIL and SaveService.has_method("hero_get"):
		var v2: Variant = SaveService.hero_get(id_val)
		if typeof(v2) == TYPE_DICTIONARY:
			var d2: Dictionary = v2
			if d2.has("name"):
				nm = str(d2.get("name", ""))
				if nm != "":
					return nm
	return nm

func _read_hp_pair(ent: Dictionary) -> Dictionary:
	var hp: int = 0
	var max_hp: int = 0
	if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
		hp = int(ent.stats.get("hp", 0))
		max_hp = int(ent.stats.get("max_hp", 0))
	else:
		hp = int(ent.get("hp", 0))
		max_hp = int(ent.get("max_hp", 0))
	return {"hp": hp, "max_hp": max_hp}

func _pair_key(a: int, b: int) -> int:
	var aa: int = a & 0x7fff
	var bb: int = b & 0x7fff
	return (aa << 15) | bb

# Map numeric action types to canonical logger verbs
static func _action_type_to_verb(t: int) -> String:
	match t:
		CombatConstants.ActionType.ATTACK:        return "ATTACK"
		CombatConstants.ActionType.GUARD:         return "GUARD"
		CombatConstants.ActionType.MOVE:          return "MOVE"
		CombatConstants.ActionType.REFUSE:        return "REFUSE"
		CombatConstants.ActionType.PURIFY_SHRINE: return "PURIFY_SHRINE"
		_:                                        return ""

# Comparator for sorting candidate entities by hp ascending, then id ascending
static func _cmp_hp_asc_id_asc(a: Dictionary, b: Dictionary) -> bool:
	var ahp: int = int(a.get("hp", 0))
	var bhp: int = int(b.get("hp", 0))
	if ahp == bhp:
		return int(a.get("id", 0)) < int(b.get("id", 0))
	return ahp < bhp

# Ensure an int value exists under a key in a dictionary, else write default
static func _ensure_stat_int(s: Dictionary, k: String, v: int) -> void:
	if not s.has(k) or typeof(s[k]) != TYPE_INT:
		s[k] = int(v)

# Increase fear on a specific entity by id, clamping to config max.
func _increase_fear_on_entity(ent_id: int, amount: int) -> void:
	if amount <= 0:
		return
	var ent: Variant = _find_entity(ent_id)
	if ent == null or typeof(ent) != TYPE_DICTIONARY:
		return
	var ent_dict: Dictionary = ent as Dictionary
	if _is_shrine_entity(ent_dict):
		return
	var fear_cur: int = int(ent_dict.get("fear", 0))
	var fear_new: int = min(HeroBal.FEAR_MAX, max(0, fear_cur + amount))
	ent_dict["fear"] = fear_new
	# Also mirror into stats if present so shape stays consistent
	if ent_dict.has("stats") and typeof(ent_dict.stats) == TYPE_DICTIONARY:
		(ent_dict.stats as Dictionary)[EchoConstants.STAT_FEAR] = fear_new

# Apply KO shock: when an ally goes down during this round, surviving allies
# gain FEAR_PER_ALLY_KO. This scans the live state and compares hp/status.
func _apply_fear_from_ally_ko() -> void:
	# Collect KO allies
	var ko_allies: Array[int] = []
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent_a: Dictionary = a
		if _is_shrine_entity(ent_a):
			continue
		if not _entity_alive(ent_a):
			ko_allies.append(int(ent_a.get("id", -1)))
	if ko_allies.is_empty():
		return
	# For each alive ally (non-shrine), add KO fear once (per round).
	for a2 in _state.get("allies", []):
		if typeof(a2) != TYPE_DICTIONARY:
			continue
		var ent_a2: Dictionary = a2
		if _is_shrine_entity(ent_a2):
			continue
		if not _entity_alive(ent_a2):
			continue
		var id_a2: int = int(ent_a2.get("id", -1))
		_increase_fear_on_entity(id_a2, HeroBal.FEAR_PER_ALLY_KO)
