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
	var actor: Dictionary = _find_entity(ctx, actor_id) as Dictionary
	var target: Dictionary = _find_entity(ctx, target_id) as Dictionary
	if actor == null or target == null:
		return {
			"ok": false,
			"type": CombatConstants.ActionType.ATTACK,
			"actor_id": actor_id,
			"target_id": target_id,
			"dmg": 0,
			"ko": false,
			"notes": "invalid_actor_or_target",
			"morale_tier": null,
			"morale_mult": 1.0,
		}

	# Read attacker stats with gentle defaults (plus temp debug boost from ctx)
	var atk: int = _read_stat(actor, ["stats", "atk"], int(actor.get("atk", 3)))
	var atk_boost: int = 0
	if typeof(ctx) == TYPE_DICTIONARY and ctx.has("temp_atk_boost") and typeof(ctx["temp_atk_boost"]) == TYPE_DICTIONARY:
		var tb: Dictionary = ctx["temp_atk_boost"]
		if tb.has(actor_id):
			atk_boost = int(tb[actor_id])
	atk += atk_boost

	var morale: int = _read_morale_for(actor)

	# Read defender stats with gentle defaults
	var def: int = _read_stat(target, ["stats", "def"], int(target.get("def", 0)))
	var hp: int = _read_stat(target, ["stats", "hp"], int(target.get("hp", 10)))
	var max_hp: int = _read_stat(target, ["stats", "max_hp"], int(target.get("max_hp", max(10, hp))))

	# Compute base damage using CombatConstants helper
	var dmg: int = CombatConstants.compute_mvp_damage(atk, def, 50) # compute base using Steady baseline; morale applied post-guard
	var base_dmg: int = dmg # keep a copy for guard delta calculations

	# Guard interaction: one-shot shield halves final damage (floor), then consumes 1
	var guard_shield: int = int(target.get("guard_shield", 0))
	var guarded: bool = false
	if guard_shield > 0 and dmg > 0:
		dmg = int(floor(float(dmg) * 0.5))
		guard_shield -= 1
		target["guard_shield"] = guard_shield
		guarded = true

	# --- Morale application (MVP): allies only; enemies ignore morale. ----------------
	var guard_reduced_by: int = 0
	var tier_label: String = ""
	var applied_mult: float = 1.0
	var actor_is_ally: bool = _is_ally(ctx, actor_id)
	# --- BUCKET VARS (for optional fractional carryover) ---
	var bucket_used: bool = false
	var bucket_before: float = 0.0
	var bucket_after: float = 0.0
	var bucket_spill: int = 0
	if actor_is_ally:
		var tier: int = CombatConstants.morale_tier(morale)
		tier_label = _tier_label(tier)
		var mult: float = CombatConstants.morale_multiplier_for_tier(tier)
		# MVP rule: Broken attackers refuse their major action entirely.
		if tier == CombatConstants.MoraleTier.BROKEN:
			return {
				"ok": true,
				"type": CombatConstants.ActionType.REFUSE,
				"actor_id": actor_id,
				"target_id": target_id,
				"notes": "broken",
				"morale_tier": "BROKEN",
				"morale_mult": 1.0,
			}
		# Apply multiplier on the finalized pre-morale damage (after guard), with readable rounding.
		applied_mult = mult
		if CombatConstants.USE_FRACTIONAL_BUCKET and (not CombatConstants.BUCKET_ONLY_FOR_BOOSTS or mult > 1.0):
			# Fractional carryover path (deterministic, per-battle)
			var exact: float = float(dmg) * mult
			var base_int: int = int(floor(exact))
			var remainder: float = exact - float(base_int)
			var dmg_bucket: Dictionary = {}
			if typeof(ctx) == TYPE_DICTIONARY and ctx.has("damage_bucket") and typeof(ctx["damage_bucket"]) == TYPE_DICTIONARY:
				dmg_bucket = ctx["damage_bucket"]
			bucket_before = float(dmg_bucket.get(actor_id, 0.0))
			bucket_after = bucket_before + remainder
			if bucket_after >= 1.0:
				base_int += 1
				bucket_after -= 1.0
				bucket_spill = 1
			dmg_bucket[actor_id] = bucket_after
			dmg = max(0, base_int)
			bucket_used = true
		else:
			# MVP rounding: buffs ceil, debuffs floor (readable at low numbers)
			var dmg_f: float = float(dmg) * mult
			if mult >= 1.0:
				dmg = int(ceil(dmg_f))
			else:
				dmg = int(floor(dmg_f))
			dmg = max(0, dmg)

		# Derive guard mitigation as the difference between a comparable pre-guard-after-morale value and the final dmg.
		# We mirror the same rounding rule used above so the delta matches what the player "feels".
		if guarded:
			var pre_guard_after_morale: float = float(base_dmg) * applied_mult
			var pre_guard_after_morale_round: int = 0
			if CombatConstants.USE_FRACTIONAL_BUCKET and (not CombatConstants.BUCKET_ONLY_FOR_BOOSTS or applied_mult > 1.0):
				# Bucket path uses floor before spill
				pre_guard_after_morale_round = int(floor(pre_guard_after_morale))
			else:
				if applied_mult >= 1.0:
					pre_guard_after_morale_round = int(ceil(pre_guard_after_morale))
				else:
					pre_guard_after_morale_round = int(floor(pre_guard_after_morale))
			guard_reduced_by = max(0, pre_guard_after_morale_round - dmg)
	else:
		# Enemies ignore morale in MVP; still compute guard delta if guarded.
		if guarded:
			# With multiplier at 1.0 and same rounding policy, the intuitive delta is simply base_dmg - dmg.
			guard_reduced_by = max(0, base_dmg - dmg)

	# Apply damage and clamp
	var new_hp: int = max(0, hp - dmg)
	# Persist back into ctx entity (Dictionaries are references in Godot)
	if target.has("stats") and typeof(target["stats"]) == TYPE_DICTIONARY:
		(target["stats"] as Dictionary)["hp"] = new_hp
	else:
		target["hp"] = new_hp

	# KO handling
	var ko: bool = false
	var note: String = "hit"
	if dmg <= 0:
		note = "no_effect"
	elif guarded:
		note = "hit_guarded"
	if new_hp <= 0:
		ko = true
		target["ko"] = true
		target["status"] = "downed"
		note += ":ko"

	return {
		"ok": true,
		"type": CombatConstants.ActionType.ATTACK,
		"actor_id": actor_id,
		"target_id": target_id,
		"dmg": dmg,
		"ko": ko,
		"notes": note,
		"morale_tier": (tier_label if actor_is_ally else null),
		"morale_mult": applied_mult,
		"guard_reduced_by": guard_reduced_by,
		"target_guard_after": guard_shield,
		"atk_boost": atk_boost,
		# --- bucket keys for logging/QA ---
		"bucket_used": bucket_used,
		"bucket_before": (bucket_before if bucket_used else null),
		"bucket_after": (bucket_after if bucket_used else null),
		"bucket_spill": bucket_spill,
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

	var before: int = int(target.get("guard_shield", 0))
	target["guard_shield"] = before + 1
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

## Returns clamped morale 0..100 from an entity dictionary.
static func _read_morale_for(ent: Dictionary) -> int:
	var m := 50
	if ent.has("stats") and typeof(ent["stats"]) == TYPE_DICTIONARY and (ent["stats"] as Dictionary).has("morale"):
		m = int((ent["stats"] as Dictionary).get("morale", 50))
	elif ent.has("morale"):
		m = int(ent.get("morale", 50))
	return max(0, min(100, m))

## True if the given id belongs to an ally inside ctx.
static func _is_ally(ctx: Dictionary, id_val: int) -> bool:
	if id_val < 0:
		return false
	for a in ctx.get("allies", []):
		if typeof(a) == TYPE_DICTIONARY and int((a as Dictionary).get("id", -1)) == id_val:
			return true
	return false

static func _tier_label(tier: int) -> String:
	match tier:
		CombatConstants.MoraleTier.INSPIRED: return "INSPIRED"
		CombatConstants.MoraleTier.STEADY:  return "STEADY"
		CombatConstants.MoraleTier.SHAKEN:  return "SHAKEN"
		_:                                   return "BROKEN"

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
