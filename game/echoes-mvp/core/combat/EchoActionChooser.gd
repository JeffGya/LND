# core/combat/EchoActionChooser.gd
# -----------------------------------------------------------------------------
# Rule-based, deterministic action chooser for the SELECT phase.
# Given a hero and the current battle ctx, returns a single action envelope
# understood by the resolver. Pure module: no IO, no singletons, no RNG.
# -----------------------------------------------------------------------------
class_name EchoActionChooser

const LOW_HP_THRESHOLD := 0.5               # 50% HP → GUARD triage candidate
const FEAR_REFUSE_THRESHOLD := 80           # If fear ≥ 80 ⇒ REFUSE (MVP)

## Public API -----------------------------------------------------------------
## Chooses a single action for the given hero in the provided context.
## @param hero Dictionary - ally combatant (id, stats.hp, stats.max_hp, stats.morale, fear?)
## @param ctx  Dictionary - { seed, round_index, allies[], enemies[], distance?, attack_range? }
## @return Dictionary - { type: CombatConstants.ActionType, actor_id:int, target_id?:int, notes:String }
static func choose_action(hero: Dictionary, ctx: Dictionary) -> Dictionary:
	var actor_id: int = int(hero.get("id", -1))
	if actor_id < 0:
		return _refuse(actor_id, "invalid_actor")

	# --- 1) REFUSAL GATE -------------------------------------------------------
	# Early BROKEN gate (convenience): chooser refuses before resolver.
	# Resolver remains authoritative and will also refuse if anything slips through.
	var morale: int = _get_morale_local(hero)
	var tier: int = CombatConstants.morale_tier(morale)
	if tier == CombatConstants.MoraleTier.BROKEN:
		return _refuse(actor_id, "broken")

	var fear: int = int(hero.get("fear", 0))
	if fear >= FEAR_REFUSE_THRESHOLD:
		return _refuse(actor_id, "overwhelmed")

	# --- 2) EMERGENCY GUARD (ALLY TRIAGE) -------------------------------------
	var allies: Array[Dictionary] = ctx.get("allies", [])
	var triage_target: Dictionary = _pick_lowest_hp_ratio_ally(allies)
	if triage_target.size() > 0:
		var triage_id: int = int(triage_target.get("id", -1))
		var triage_ratio: float = float(triage_target.get("hp_ratio", 1.0))
		if triage_id != actor_id and triage_ratio < LOW_HP_THRESHOLD:
			return {
				"type": CombatConstants.ActionType.GUARD,
				"actor_id": actor_id,
				"target_id": triage_id,
				"notes": "triage",
			}

	# --- 3) ATTACK IF IN RANGE -------------------------------------------------
	var enemies: Array[Dictionary] = ctx.get("enemies", [])
	var weakest: Dictionary = _pick_weakest_enemy(enemies)
	if weakest.size() > 0:
		var weak_id: int = int(weakest.get("id", -1))
		if _is_in_range(actor_id, weak_id, ctx):
			return {
				"type": CombatConstants.ActionType.ATTACK,
				"actor_id": actor_id,
				"target_id": weak_id,
				"notes": "focus_weakest",
			}

		# --- 4) MOVE (fallback) -------------------------------------------------
		var nearest: Dictionary = _pick_nearest_enemy(actor_id, enemies, ctx)
		if nearest.size() > 0:
			return {
				"type": CombatConstants.ActionType.MOVE,
				"actor_id": actor_id,
				"target_id": int(nearest.get("id", -1)),
				"notes": "advance",
			}

	# If there are no enemies, refuse (nothing useful to do in MVP)
	return _refuse(actor_id, "no_targets")


# Internal helpers ------------------------------------------------------------

## Build a standardized REFUSE action; used by BROKEN and fear gates (deterministic, no RNG).
static func _refuse(actor_id: int, reason: String) -> Dictionary:
	return {
		"type": CombatConstants.ActionType.REFUSE,
		"actor_id": actor_id,
		"notes": reason,
	}

## Safely read nested ints with default.
static func _get_int(src: Dictionary, path: Array, default_val: int) -> int:
	var cur: Variant = src
	for key in path:
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(key):
			return default_val
		cur = cur[key]
	if typeof(cur) == TYPE_INT:
		return int(cur)
	elif typeof(cur) == TYPE_FLOAT:
		return int(float(cur))
	else:
		return default_val

## Local morale read (stats.morale → morale → default 50). Mirrors engine accessor semantics.
static func _get_morale_local(src: Dictionary) -> int:
	if src.has("stats") and typeof(src["stats"]) == TYPE_DICTIONARY:
		var stats: Dictionary = src["stats"]
		if stats.has("morale"):
			return int(stats.get("morale", 50))
	# Fallbacks
	if src.has("morale"):
		return int(src.get("morale", 50))
	return 50

## Builds a lightweight ally descriptor with hp ratio for triage selection.
static func _pick_lowest_hp_ratio_ally(allies: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for a in allies:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var id_val: int = int(a.get("id", -1))
		if id_val < 0:
			continue
		var hp: int = _get_int(a, ["stats", "hp"], 10)
		var max_hp: int = max(1, _get_int(a, ["stats", "max_hp"], 10))
		var ratio: float = float(hp) / float(max_hp)
		var candidate: Dictionary = {"id": id_val, "hp_ratio": ratio}
		if best.size() == 0:
			best = candidate
		else:
			var best_ratio: float = float(best.get("hp_ratio", 1.0))
			var cand_ratio: float = float(candidate.get("hp_ratio", 1.0))
			if cand_ratio == best_ratio:
				# tie -> lowest id (deterministic)
				if int(candidate.get("id", -1)) < int(best.get("id", -1)):
					best = candidate
			elif cand_ratio < best_ratio:
				best = candidate
	return best

## Weakest enemy by (hp asc, id asc). If hp missing, treat as 10.
static func _pick_weakest_enemy(enemies: Array[Dictionary]) -> Dictionary:
	var pool: Array[Dictionary] = []
	for e in enemies:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_val: int = int(e.get("id", -1))
		if id_val < 0:
			continue
		var hp: int = 10
		if e.has("stats") and typeof(e["stats"]) == TYPE_DICTIONARY and e["stats"].has("hp"):
			hp = int((e["stats"] as Dictionary).get("hp", 10))
		elif e.has("hp"):
			hp = int(e.get("hp", 10))
		# Skip defeated targets (KO, downed, or zero HP)
		var ko_flag: bool = bool(e.get("ko", false))
		var status_down: bool = str(e.get("status", "")) == "downed"
		if hp <= 0 or ko_flag or status_down:
			continue
		pool.append({"id": id_val, "hp": hp})

	if pool.is_empty():
		return {}

	pool.sort_custom(func(a, b):
		var ah: int = int(a["hp"])
		var bh: int = int(b["hp"])
		if ah == bh:
			return int(a["id"]) < int(b["id"]) 
		return ah < bh
	)
	return pool[0]

## Range check using optional ctx.distance + ctx.attack_range. If missing,
## assume everyone is in range for MVP (text autobattle).
static func _is_in_range(actor_id: int, target_id: int, ctx: Dictionary) -> bool:
	if not ctx.has("distance") or not ctx.has("attack_range"):
		return true
	var dist_map: Dictionary = ctx.get("distance", {})
	var atk_range: int = int(ctx.get("attack_range", 1))
	var key: int = _pair_key(actor_id, target_id)
	var tiles: int = int(dist_map.get(key, atk_range))
	return tiles <= atk_range

## Choose the nearest enemy using the optional distance map; if absent, fall
## back to lowest id for determinism.
static func _pick_nearest_enemy(actor_id: int, enemies: Array[Dictionary], ctx: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var has_map: bool = ctx.has("distance") and ctx.has("attack_range")
	var dist_map: Dictionary = ctx.get("distance", {})
	for e in enemies:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_val: int = int(e.get("id", -1))
		if id_val < 0:
			continue
		# Skip defeated targets (KO, downed, or zero HP)
		var hp_n: int = 10
		if e.has("stats") and typeof(e["stats"]) == TYPE_DICTIONARY and e["stats"].has("hp"):
			hp_n = int((e["stats"] as Dictionary).get("hp", 10))
		elif e.has("hp"):
			hp_n = int(e.get("hp", 10))
		var ko_n: bool = bool(e.get("ko", false))
		var down_n: bool = str(e.get("status", "")) == "downed"
		if hp_n <= 0 or ko_n or down_n:
			continue
		var metric: int = 0
		if has_map:
			metric = int(dist_map.get(_pair_key(actor_id, id_val), 9999))
		else:
			metric = id_val  # deterministic fallback
		var candidate: Dictionary = {"id": id_val, "metric": metric}
		if best.size() == 0:
			best = candidate
		else:
			var best_m: int = int(best.get("metric", 9999))
			if metric == best_m:
				if int(candidate.get("id", -1)) < int(best.get("id", -1)):
					best = candidate
			elif metric < best_m:
				best = candidate
	return best

## Stable pairing key for (actor_id, target_id) in a flat dictionary map.
static func _pair_key(a: int, b: int) -> int:
	# Use 15-bit halves inside a 30-bit int to avoid signed overflow headaches.
	var aa: int = a & 0x7fff
	var bb: int = b & 0x7fff
	return (aa << 15) | bb