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
	}
	# Apply any persisted morale overrides into the freshly built state
	_apply_morale_overrides()

## Steps one round through INITIATIVE → SELECT → RESOLVE → TICK → CHECK.
## Returns a snapshot for logging/inspection.
func step_round() -> Dictionary:
	if _state.get("over", false):
		return _state.get("last_snapshot", {})

	var battle_seed: int = int(_state.seed)
	var round_index: int = int(_state.round)

	# 1) INITIATIVE -------------------------------------------------------------
	var ctx: Dictionary = {
		"seed": battle_seed,
		"round_index": round_index,
		"allies": _state.allies,
		"enemies": _state.enemies,
		"attack_range": int(_state.attack_range),
		"damage_bucket": _state.damage_bucket,
	}
	var order: Array[int] = Initiative.compute_order(ctx)

	# Build a name map for readable logs
	var name_by_id: Dictionary = _build_name_map()

	# 2) SELECT + 3) RESOLVE ----------------------------------------------------
	var actions: Array[Dictionary] = []
	for actor_id in order:
		var ent: Variant = _find_entity(actor_id)
		if ent == null:
			continue
		if not _entity_alive(ent):
			continue

		# Build latest ctx (mutated state is shared across loop iterations)
		ctx.allies = _state.allies
		ctx.enemies = _state.enemies

		var side := _side_of(actor_id)
		var action: Dictionary
		if side == "ALLY":
			action = EchoActionChooser.choose_action(ent, ctx)
		else:
			action = _choose_enemy_action(ent, ctx)

		# Apply via resolver according to action type
		var t := int(action.get("type", -1))
		var effect: Dictionary
		match t:
			CombatConstants.ActionType.ATTACK, CombatConstants.ActionType.REFUSE:
				effect = ActionResolver.apply_major(action, ctx)
			CombatConstants.ActionType.GUARD, CombatConstants.ActionType.MOVE:
				effect = ActionResolver.apply_minor(action, ctx)
			_:
				effect = {
					"ok": false,
					"type": t,
					"actor_id": int(action.get("actor_id", -1)),
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

		# --- Preserve / derive morale QA fields so CombatLog can display them ----------
		var eff_type := int(effect.get("type", -1))
		if eff_type == CombatConstants.ActionType.ATTACK:
			# If the resolver already set morale fields, keep them; otherwise derive them here.
			var has_mult := effect.has("morale_mult")
			var has_tier := effect.has("morale_tier")
			if side == "ALLY":
				if (not has_mult) or (not has_tier):
					# Derive from the current attacker entity
					var m_val: int = _get_morale(ent as Dictionary)
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

		actions.append(effect)

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
				if not d_in.has("id"): d_in["id"] = 0
				var d_out: Dictionary = d_in
				if not d_out.has("stats") or typeof(d_out["stats"]) != TYPE_DICTIONARY:
					d_out["stats"] = _fallback_stats()
				else:
					d_out["stats"] = _fill_missing_stats(d_out["stats"])
				if not d_out.has("fear"): d_out["fear"] = 0
				if not d_out.has("status"): d_out["status"] = "idle"
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
			_ensure_stat_int(s, EchoConstants.STAT_HP, int(e.get("hp", 10)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_HP, 10)

		if flat_max_hp_set:
			_ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(e.get("max_hp", int(s.get(EchoConstants.STAT_HP, 10)))))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, 10)))

		if flat_atk_set:
			_ensure_stat_int(s, EchoConstants.STAT_ATK, int(e.get("atk", 3)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_ATK, 3)

		if flat_def_set:
			_ensure_stat_int(s, EchoConstants.STAT_DEF, int(e.get("def", 0)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_DEF, 0)

		if flat_agi_set:
			_ensure_stat_int(s, EchoConstants.STAT_AGI, int(e.get("agi", 5)))
		else:
			_ensure_stat_int(s, EchoConstants.STAT_AGI, 5)

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
		_ensure_stat_int(s, EchoConstants.STAT_MORALE, 50)
		_ensure_stat_int(s, EchoConstants.STAT_FEAR, int(e.get("fear", 0)))

		# Save back canonical stats
		e["stats"] = s

		# Backfill flat keys from stats when missing (compat with any legacy readers)
		if not flat_hp_set:
			e["hp"] = int(s.get(EchoConstants.STAT_HP, 10))
		if not flat_max_hp_set:
			e["max_hp"] = int(s.get(EchoConstants.STAT_MAX_HP, e.get("hp", 10)))
		if not flat_atk_set:
			e["atk"] = int(s.get(EchoConstants.STAT_ATK, 3))
		if not flat_def_set:
			e["def"] = int(s.get(EchoConstants.STAT_DEF, 0))
		if not flat_agi_set:
			e["agi"] = int(s.get(EchoConstants.STAT_AGI, 5))
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
	return {
		"id": ent_id,
		"name": name_s,
		"archetype": arch_s,
		"stats": stats_out,
		"fear": int(hero.get("fear", 0)),
		"status": String(hero.get("status", "idle")),
	}

static func _fallback_stats() -> Dictionary:
	# Safe typed defaults for when hero has no stats (older saves or bad data).
	return {
		EchoConstants.STAT_HP: 1,
		EchoConstants.STAT_MAX_HP: 1,
		EchoConstants.STAT_ATK: 0,
		EchoConstants.STAT_DEF: 0,
		EchoConstants.STAT_AGI: 0,
		EchoConstants.STAT_CHA: 0,
		EchoConstants.STAT_INT: 0,
		EchoConstants.STAT_ACC: 0,
		EchoConstants.STAT_EVA: 0,
		EchoConstants.STAT_CRIT: 0,
		EchoConstants.STAT_MORALE: 50,
		EchoConstants.STAT_FEAR: 0,
	}

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

	# Allies: fear + morale decay
	for ent in _state.get("allies", []):
		if not _entity_alive(ent):
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

	return {"fear": fear_tick, "morale_decay": morale_decay_applied}

func _check_end() -> Dictionary:
	var allies_alive: bool = false
	for a in _state.get("allies", []):
		if _entity_alive(a):
			allies_alive = true
			break
	var enemies_alive: bool = false
	for e in _state.get("enemies", []):
		if _entity_alive(e):
			enemies_alive = true
			break

	var reason: String = ""
	var victory: bool = false

	if not enemies_alive and allies_alive:
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
		return _state.result
	else:
		return {"ongoing": true}

func _alive_count(group: Array[Dictionary]) -> int:
	var c := 0
	for ent in group:
		if _entity_alive(ent):
			c += 1
	return c

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
		var id_a := int((a as Dictionary).get("id", -1))
		if id_a >= 0 and _morale_overrides.has(id_a):
			_write_morale(a as Dictionary, int(_morale_overrides[id_a]))
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
		var hp := 10
		var max_hp := 10
		if a.has("stats") and typeof(a.stats) == TYPE_DICTIONARY:
			hp = int(a.stats.get("hp", 10))
			max_hp = int(a.stats.get("max_hp", 10))
		else:
			hp = int(a.get("hp", 10))
			max_hp = int(a.get("max_hp", 10))
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
		var hp := 10
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
		var id_val: int = int(a.get("id", -1))
		if id_val < 0:
			continue
		var nm: String = ""
		if (a as Dictionary).has("name"):
			nm = str((a as Dictionary).get("name", ""))
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
