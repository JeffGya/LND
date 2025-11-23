

# core/combat/EnemyActionChooser.gd
# -----------------------------------------------------------------------------
# Rule-based, deterministic enemy action chooser for the SELECT phase.
# Mirrors the legacy enemy AI that previously lived inside CombatEngine.gd,
# but as a pure, reusable module that depends only on the passed-in context.
#
# Scope (F1):
#  - Copy existing enemy behavior 1:1 (no balance or logic changes).
#  - Keep fear threshold, shrine focus logic, and weakest-target focus intact.
#  - Do NOT yet remove the old helpers from CombatEngine (wired in F2).
# -----------------------------------------------------------------------------
class_name EnemyActionChooser

const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")
const CombatEntities = preload("res://core/combat/CombatEntities.gd")
const CombatConstants = preload("res://core/combat/CombatConstants.gd")

const FEAR_REFUSE_THRESHOLD := 80  # MVP: enemies REFUSE if fear ≥ 80

# Public API ------------------------------------------------------------------
## Chooses a single action for the given enemy in the provided context.
## @param enemy Dictionary - enemy combatant (id, stats.hp, stats.max_hp, fear?)
## @param ctx   Dictionary - { allies[], enemies[], objective_type?, distance?, attack_range? }
## @return Dictionary - { type: CombatConstants.ActionType, actor_id:int, target_id?:int, notes:String }
static func choose_action(enemy: Dictionary, ctx: Dictionary) -> Dictionary:
	var actor_id := int(enemy.get("id", -1))
	if actor_id < 0:
		return {
			"type": CombatConstants.ActionType.REFUSE,
			"actor_id": actor_id,
			"notes": "invalid_actor",
		}

	# REFUSE if fear high (MVP: enemies ignore morale)
	var fear := int(enemy.get("fear", 0))
	if fear >= FEAR_REFUSE_THRESHOLD:
		return {
			"type": CombatConstants.ActionType.REFUSE,
			"actor_id": actor_id,
			"notes": "overwhelmed",
		}

	# GUARD lowest-hp% fellow enemy (rare in MVP dummies but deterministic)
	var triage: Dictionary = _pick_lowest_hp_ratio(ctx.get("enemies", []))
	if typeof(triage) == TYPE_DICTIONARY and triage.size() > 0 and int(triage["id"]) != actor_id and float(triage["hp_ratio"]) < 0.5:
		return {
			"type": CombatConstants.ActionType.GUARD,
			"actor_id": actor_id,
			"target_id": int(triage["id"]),
			"notes": "triage",
		}

	# Shrine priority in Purify Shrine objectives (MVP):
	var objective: String = String(ctx.get("objective_type", "defeat"))
	if objective == "purify_shrine":
		var shrine_ent: Dictionary = CombatEntities.find_alive_shrine(ctx.get("allies", []))
		if shrine_ent.size() > 0:
			var shrine_id: int = int(shrine_ent.get("id", -1))
			# Always prioritize attacking shrine when in range.
			if _is_in_range(actor_id, shrine_id, ctx):
				return {
					"type": CombatConstants.ActionType.ATTACK,
					"actor_id": actor_id,
					"target_id": shrine_id,
					"notes": "focus_shrine",
				}
			# If somehow out of range (future distance systems), move toward shrine.
			return {
				"type": CombatConstants.ActionType.MOVE,
				"actor_id": actor_id,
				"target_id": shrine_id,
				"notes": "approach_shrine",
			}

	# ATTACK weakest ally if in range; else MOVE toward nearest ally
	var weakest: Dictionary = _pick_weakest(ctx.get("allies", []))
	if weakest.size() > 0:
		var weak_id: int = int(weakest["id"])
		if _is_in_range(actor_id, weak_id, ctx):
			return {
				"type": CombatConstants.ActionType.ATTACK,
				"actor_id": actor_id,
				"target_id": weak_id,
				"notes": "focus_weakest",
			}
		var nearest: Dictionary = _pick_nearest(actor_id, ctx.get("allies", []), ctx)
		if nearest.size() > 0:
			return {
				"type": CombatConstants.ActionType.MOVE,
				"actor_id": actor_id,
				"target_id": int(nearest["id"]),
				"notes": "advance",
			}

	# Fallback: refuse if no valid targets
	return {
		"type": CombatConstants.ActionType.REFUSE,
		"actor_id": actor_id,
		"notes": "no_targets",
	}

# Internal helpers ------------------------------------------------------------

# Pick the enemy with the lowest HP ratio (hp / max_hp), tie-breaking by id.
static func _pick_lowest_hp_ratio(group: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for a in group:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var id_val := int(a.get("id", -1))
		if id_val < 0:
			continue
		var hp_pair: Dictionary = CombatEntities.read_hp_pair(a)
		var hp: int = int(hp_pair.get("hp", HeroBal.FALLBACK_HP))
		var max_hp: int = int(hp_pair.get("max_hp", HeroBal.FALLBACK_HP))
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

# Pick the weakest target by HP (ascending), tie-breaking by id (ascending).
static func _pick_weakest(group: Array[Dictionary]) -> Dictionary:
	var pool: Array[Dictionary] = []
	for e in group:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_val := int(e.get("id", -1))
		if id_val < 0:
			continue
		var hp_pair: Dictionary = CombatEntities.read_hp_pair(e)
		var hp: int = int(hp_pair.get("hp", HeroBal.FALLBACK_HP))
		pool.append({"id": id_val, "hp": hp})
	if pool.is_empty():
		return {}

	pool.sort_custom(func(a, b):
		var ahp: int = int(a.get("hp", 0))
		var bhp: int = int(b.get("hp", 0))
		if ahp == bhp:
			return int(a.get("id", 0)) < int(b.get("id", 0))
		return ahp < bhp
	)
	return pool[0]

# Pick the nearest target using optional ctx.distance map; if missing, fall
# back to lowest id for determinism.
static func _pick_nearest(actor_id: int, group: Array[Dictionary], ctx: Dictionary) -> Dictionary:
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
			var best_metric: int = int(best.get("metric", 9999))
			if metric == best_metric:
				if int(cand.get("id", -1)) < int(best.get("id", -1)):
					best = cand
			elif metric < best_metric:
				best = cand
	return best

# Range check using optional ctx.distance + ctx.attack_range. If missing,
# assume everyone is in range for MVP.
static func _is_in_range(actor_id: int, target_id: int, ctx: Dictionary) -> bool:
	if not ctx.has("distance") or not ctx.has("attack_range"):
		return true
	var dist_map: Dictionary = ctx.get("distance", {})
	var atk_range: int = int(ctx.get("attack_range", 1))
	var key: int = _pair_key(actor_id, target_id)
	var tiles: int = int(dist_map.get(key, atk_range))
	return tiles <= atk_range

# Stable pairing key for (actor_id, target_id) in a flat dictionary map.
static func _pair_key(a: int, b: int) -> int:
	var aa: int = a & 0x7fff
	var bb: int = b & 0x7fff
	return (aa << 15) | bb
