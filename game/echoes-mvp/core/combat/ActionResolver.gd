# core/combat/ActionResolver.gd
# -----------------------------------------------------------------------------
# Applies Major/Minor combat actions to the shared battle context.
# Pure rule engine: no RNG, no IO. Deterministic given (action, ctx) inputs.
# -----------------------------------------------------------------------------
class_name ActionResolver

# -- Public API ---------------------------------------------------------------
## Applies a Major action (ATTACK, REFUSE) to the context.
## Returns an effect envelope for logging/tests.
static func apply_major(action: Dictionary, ctx: Dictionary) -> Dictionary:
	var t: int = int(action.get("type", -1))
	match t:
		CombatConstants.ActionType.ATTACK:
			return _resolve_attack(action, ctx)
		CombatConstants.ActionType.REFUSE:
			return _resolve_refuse(action)
		_:
			return _unsupported(action, "major")

## Applies a Minor action (GUARD, MOVE) to the context.
## Returns an effect envelope for logging/tests.
static func apply_minor(action: Dictionary, ctx: Dictionary) -> Dictionary:
	var t: int = int(action.get("type", -1))
	match t:
		CombatConstants.ActionType.GUARD:
			return _resolve_guard(action, ctx)
		CombatConstants.ActionType.MOVE:
			return _resolve_move(action)
		_:
			return _unsupported(action, "minor")

# -- Major Resolvers ----------------------------------------------------------

static func _resolve_attack(action: Dictionary, ctx: Dictionary) -> Dictionary:
	var actor_id: int = int(action.get("actor_id", -1))
	var target_id: int = int(action.get("target_id", -1))
	var actor: Variant = _find_entity(ctx, actor_id)
	var target: Variant = _find_entity(ctx, target_id)
	if actor == null or target == null:
		return {
			"ok": false,
			"type": CombatConstants.ActionType.ATTACK,
			"actor_id": actor_id,
			"target_id": target_id,
			"dmg": 0,
			"ko": false,
			"notes": "invalid_actor_or_target",
		}

	# Read attacker stats with gentle defaults
	var atk: int = _read_stat(actor, ["stats", "atk"], int((actor as Dictionary).get("atk", 3)))
	var morale: int = _read_stat(actor, ["stats", "morale"], int((actor as Dictionary).get("morale", 50)))

	# Read defender stats with gentle defaults
	var def: int = _read_stat(target, ["stats", "def"], int((target as Dictionary).get("def", 0)))
	var hp: int = _read_stat(target, ["stats", "hp"], int((target as Dictionary).get("hp", 10)))
	var max_hp: int = _read_stat(target, ["stats", "max_hp"], int((target as Dictionary).get("max_hp", max(10, hp))))

	# Compute base damage using CombatConstants helper
	var dmg: int = CombatConstants.compute_mvp_damage(atk, def, morale)

	# Guard interaction: one-shot shield halves final damage (floor), then consumes 1
	var guard_shield: int = int((target as Dictionary).get("guard_shield", 0))
	var guarded: bool = false
	if guard_shield > 0 and dmg > 0:
		dmg = int(floor(float(dmg) * 0.5))
		guard_shield -= 1
		(target as Dictionary)["guard_shield"] = guard_shield
		guarded = true

	# Apply damage and clamp
	var new_hp: int = max(0, hp - dmg)
	# Persist back into ctx entity (Dictionaries are references in Godot)
	if (target as Dictionary).has("stats") and typeof((target as Dictionary)["stats"]) == TYPE_DICTIONARY:
		((target as Dictionary)["stats"] as Dictionary)["hp"] = new_hp
	else:
		(target as Dictionary)["hp"] = new_hp

	# KO handling
	var ko: bool = false
	var note: String = "hit"
	if dmg <= 0:
		note = "no_effect"
	elif guarded:
		note = "hit_guarded"
	if new_hp <= 0:
		ko = true
		(target as Dictionary)["ko"] = true
		(target as Dictionary)["status"] = "downed"
		note += ":ko"

	return {
		"ok": true,
		"type": CombatConstants.ActionType.ATTACK,
		"actor_id": actor_id,
		"target_id": target_id,
		"dmg": dmg,
		"ko": ko,
		"notes": note,
	}

static func _resolve_refuse(action: Dictionary) -> Dictionary:
	var actor_id: int = int(action.get("actor_id", -1))
	var reason: String = str(action.get("notes", "refuse"))
	return {
		"ok": true,
		"type": CombatConstants.ActionType.REFUSE,
		"actor_id": actor_id,
		"notes": reason,
	}

# -- Minor Resolvers ----------------------------------------------------------

static func _resolve_guard(action: Dictionary, ctx: Dictionary) -> Dictionary:
	var actor_id: int = int(action.get("actor_id", -1))
	var target_id: int = int(action.get("target_id", -1))
	var target: Variant = _find_entity(ctx, target_id)
	if target == null:
		return {
			"ok": false,
			"type": CombatConstants.ActionType.GUARD,
			"actor_id": actor_id,
			"target_id": target_id,
			"notes": "guard_invalid_target",
		}

	var before: int = int((target as Dictionary).get("guard_shield", 0))
	(target as Dictionary)["guard_shield"] = before + 1
	var self_guard: bool = (actor_id == target_id)
	var note_str: String = "guard_applied"
	if self_guard:
		note_str = "guard_self"
	return {
		"ok": true,
		"type": CombatConstants.ActionType.GUARD,
		"actor_id": actor_id,
		"target_id": target_id,
		"notes": note_str,
	}

static func _resolve_move(action: Dictionary) -> Dictionary:
	# No grid yet—return cosmetic effect only.
	var actor_id: int = int(action.get("actor_id", -1))
	var target_id: int = int(action.get("target_id", -1))
	return {
		"ok": true,
		"type": CombatConstants.ActionType.MOVE,
		"actor_id": actor_id,
		"target_id": target_id,
		"notes": "advance",
	}

# -- Utilities ----------------------------------------------------------------

## Finds a combatant (ally or enemy) by id within the context. Returns null if missing.
static func _find_entity(ctx: Dictionary, id_val: int) -> Variant:
	if id_val < 0:
		return null
	var allies: Array = ctx.get("allies", [])
	for a in allies:
		if typeof(a) == TYPE_DICTIONARY and int((a as Dictionary).get("id", -1)) == id_val:
			return a
	var enemies: Array = ctx.get("enemies", [])
	for e in enemies:
		if typeof(e) == TYPE_DICTIONARY and int((e as Dictionary).get("id", -1)) == id_val:
			return e
	return null

## Reads an integer stat from nested paths with a default; tolerant of flat fallbacks.
static func _read_stat(entity: Variant, path: Array, fallback: int) -> int:
	var cur: Variant = entity
	for key in path:
		if typeof(cur) != TYPE_DICTIONARY or not (cur as Dictionary).has(key):
			return fallback
		cur = (cur as Dictionary)[key]
	if typeof(cur) == TYPE_INT:
		return int(cur)
	elif typeof(cur) == TYPE_FLOAT:
		return int(float(cur))
	else:
		return fallback

static func _unsupported(action: Dictionary, phase: String) -> Dictionary:
	return {
		"ok": false,
		"type": int(action.get("type", -1)),
		"actor_id": int(action.get("actor_id", -1)),
		"target_id": int(action.get("target_id", -1)),
		"notes": "unsupported_" + phase,
	}