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
	}

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

func _normalize_allies(allies: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in allies:
		match typeof(a):
			TYPE_INT:
				out.append({
					"id": int(a),
					"stats": {"hp": 10, "max_hp": 10, "atk": 3, "def": 1, "morale": 50},
					"fear": 0,
					"status": "idle",
				})
			TYPE_DICTIONARY:
				# Ensure minimal fields exist
				var d: Dictionary = a
				if not d.has("id"): d["id"] = 0
				if not d.has("stats"): d["stats"] = {"hp":10, "max_hp":10, "atk":3, "def":1, "morale":50}
				if not d.has("fear"): d["fear"] = 0
				if not d.has("status"): d["status"] = "idle"
				out.append(d)
			_:
				pass
	return out

func _normalize_enemies(enemies: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in enemies:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		# Fill minimal fields if missing (compatible with EnemyFactory)
		if not e.has("id"): e["id"] = 1000 + out.size()
		if not e.has("hp") and (not e.has("stats") or not e.stats.has("hp")):
			e["hp"] = 10
		if not e.has("max_hp") and (not e.has("stats") or not e.stats.has("max_hp")):
			e["max_hp"] = 10
		if not e.has("atk") and (not e.has("stats") or not e.stats.has("atk")):
			e["atk"] = 3
		if not e.has("def") and (not e.has("stats") or not e.stats.has("def")):
			e["def"] = 0
		if not e.has("morale") and (not e.has("stats") or not e.stats.has("morale")):
			e["morale"] = 50
		if not e.has("fear"): e["fear"] = 0
		if not e.has("status"): e["status"] = "idle"
		out.append(e)
	return out

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

	for group in [ _state.allies, _state.enemies ]:
		for ent in group:
			if not _entity_alive(ent):
				continue
			# Fear accrual
			var fear: int = int(ent.get("fear", 0))
			fear = min(100, max(0, fear + fear_tick))
			ent["fear"] = fear
			# Morale decay cadence
			if do_decay:
				var morale: int = 50
				if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY and ent.stats.has("morale"):
					morale = int(ent.stats.morale)
				else:
					morale = int(ent.get("morale", 50))
				morale = max(0, morale - CombatConstants.MORALE_DECAY_AMOUNT)
				if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
					ent.stats["morale"] = morale
				else:
					ent["morale"] = morale
				morale_decay_applied = true

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

# Simple mirrored chooser for enemies (deterministic, no RNG) -----------------
func _choose_enemy_action(enemy: Dictionary, ctx: Dictionary) -> Dictionary:
	var actor_id := int(enemy.get("id", -1))
	if actor_id < 0:
		return {"type": CombatConstants.ActionType.REFUSE, "actor_id": actor_id, "notes": "invalid_actor"}

	# REFUSE if broken or fear high (mirror ally logic)
	var morale := 50
	if enemy.has("stats") and typeof(enemy.stats) == TYPE_DICTIONARY and enemy.stats.has("morale"):
		morale = int(enemy.stats.morale)
	else:
		morale = int(enemy.get("morale", 50))
	var tier := CombatConstants.morale_tier(morale)
	if tier == CombatConstants.MoraleTier.BROKEN:
		return {"type": CombatConstants.ActionType.REFUSE, "actor_id": actor_id, "notes": "broken"}
	var fear := int(enemy.get("fear", 0))
	if fear >= 80:
		return {"type": CombatConstants.ActionType.REFUSE, "actor_id": actor_id, "notes": "overwhelmed"}

	# GUARD lowest-hp% fellow enemy (rare in MVP dummies but deterministic)
	var triage := _pick_lowest_hp_ratio(ctx.get("enemies", []))
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
	pool.sort_custom(func(a, b):
		if int(a["hp"]) == int(b["hp"]):
			return int(a["id"]) < int(b["id"])
		return int(a["hp"]) < int(b["hp"])
	)
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
		var metric := 0
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
		var svc = Engine.get_singleton("SaveService")
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