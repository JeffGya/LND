# core/combat/Initiative.gd
# -----------------------------------------------------------------------------
# Deterministic initiative ordering for each round.
# Given the same ctx (seed, round_index, combatants), this returns the same
# ordered list of ids. Pure module: no IO, no singletons, no randomness.
#
# Canon notes
#  - §3 Visible cadence: order is printed each round by the CombatLog.
#  - §5 Traits matter: Courage/Wisdom & Morale tier influence tempo.
#  - §9 Determinism: seed+round+id tiebreak; stable sort; integer math.
#  - §12 Knobs live in CombatConstants; formula here is gentle and legible.
# -----------------------------------------------------------------------------
class_name Initiative

## Public API ---------------------------------------------------------------
## Computes the acting order (first → last) for the current round.
## @param ctx Dictionary with keys:
##   seed:int, round_index:int,
##   allies:Array[Dictionary], enemies:Array[Dictionary]
## @return Array[int] ordered list of entity ids
static func compute_order(ctx: Dictionary) -> Array[int]:
	var battle_seed: int = int(ctx.get("seed", 0))
	var round_index: int = max(1, int(ctx.get("round_index", 1)))

	var entries: Array[Dictionary] = _collect_entries(ctx, battle_seed, round_index)

	# Sort by (score desc, tiebreak desc, id asc) deterministically
	entries.sort_custom(func(a, b):
		if int(a["score"]) == int(b["score"]):
			if int(a["tiebreak"]) == int(b["tiebreak"]):
				return int(a["id"]) < int(b["id"])  # final stable fallback
			return int(a["tiebreak"]) > int(b["tiebreak"])
		return int(a["score"]) > int(b["score"])
	)

	var order: Array[int] = []
	for e in entries:
		order.append(int(e["id"]))
	return order


# Internal helpers -----------------------------------------------------------

## Gathers allies and enemies into a flat list of {id, score, tiebreak}.
static func _collect_entries(ctx: Dictionary, battle_seed: int, round_index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var allies: Array = ctx.get("allies", [])
	var enemies: Array = ctx.get("enemies", [])

	for ent in allies:
		var e: Dictionary = _build_entry(ent, battle_seed, round_index)
		if e.size() > 0:
			out.append(e)
	for ent in enemies:
		var e2: Dictionary = _build_entry(ent, battle_seed, round_index)
		if e2.size() > 0:
			out.append(e2)
	return out

## Builds a single entry dictionary for sorting. Returns empty dict on bad data.
static func _build_entry(entity: Dictionary, battle_seed: int, round_index: int) -> Dictionary:
	if typeof(entity) != TYPE_DICTIONARY:
		return {}
	var id_val: int = int(entity.get("id", -1))
	if id_val < 0:
		return {}

	var courage: int = _extract_stat(entity, ["stats", "courage"], 40)
	var wisdom: int = _extract_stat(entity, ["stats", "wisdom"], 40)
	var morale: int = _extract_stat(entity, ["stats", "morale"], 50)
	# Enemies from EnemyFactory may not have stats; fallbacks above cover that.
	if morale == 50 and entity.has("morale"):
		morale = int(entity.get("morale", 50))

	var tier_bonus: int = _morale_tier_bonus(morale)
	# Gentle, integer-based formula that reads well in logs.
	var base: int = 10
	var c_term: int = int(floor(float(courage) / 10.0))     # 0..10 for 0..100
	var w_term: int = int(floor(float(wisdom) / 20.0))      # 0..5  for 0..100
	var score: int = base + c_term + w_term + tier_bonus

	var tiebreak: int = _tiebreak(battle_seed, round_index, id_val)
	return {
		"id": id_val,
		"score": score,
		"tiebreak": tiebreak,
	}

## Reads a nested integer safely from a dictionary using a path.
static func _extract_stat(entity: Dictionary, path: Array, default_val: int) -> int:
	var cur: Variant = entity
	for key in path:
		if typeof(cur) != TYPE_DICTIONARY:
			return default_val
		if not cur.has(key):
			return default_val
		cur = cur[key]
	if typeof(cur) == TYPE_INT:
		return int(cur)
	elif typeof(cur) == TYPE_FLOAT:
		return int(float(cur))
	else:
		return default_val

## Converts morale (0..100) into a small initiative bonus using CombatConstants.
static func _morale_tier_bonus(morale: int) -> int:
	var m: int = CombatConstants.clamp_morale(int(morale))
	var tier: int = CombatConstants.morale_tier(m)
	match tier:
		CombatConstants.MoraleTier.INSPIRED:
			return 2
		CombatConstants.MoraleTier.STEADY:
			return 1
		CombatConstants.MoraleTier.SHAKEN:
			return 0
		CombatConstants.MoraleTier.BROKEN:
			return -2
		_:
			return 0

## Deterministic, signed-int-safe tiebreaker derived from seed+round+id.
static func _tiebreak(battle_seed: int, round_index: int, id_val: int) -> int:
	var s: int = battle_seed & 0x7fffffff   # keep in positive 31-bit range
	var r: int = max(1, round_index)
	var i: int = id_val & 0x7fffffff
	return int((s + r * 1009 + i * 9173) % 1000)