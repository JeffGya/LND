# core/combat/CombatEntities.gd
# -----------------------------------------------------------------------------
# Pure helpers for combat entity shape and stat handling.
# Subtask C1: initial extraction from CombatEngine.gd
#
# Scope (C1):
#  - Provide stat helpers and HP readers that exactly mirror the existing
#    inline implementations in CombatEngine.gd.
#  - No behavior changes, no call sites updated yet.
#  - Later subtasks will move full normalization logic and tag helpers here.
#
# Invisible grid layer (A1.1):
#  - Combat entities may carry an optional `grid_pos` field that encodes their
#    position on the invisible combat board.
#  - Type: Vector2i (integer x/y coordinates).
#  - Coordinate system:
#      x => column, increasing left → right
#      y => row,     increasing top  → bottom
#  - A special sentinel value is used to represent "not placed on the board":
#      Vector2i(-1, -1)
#  - MVP rule: all grid logic is optional. Existing callers that never set
#    `grid_pos` continue to behave exactly as before.

class_name CombatEntities

const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")

# Sentinel "not placed" value for optional grid positions on entities.
const GRID_POS_UNSET: Vector2i = Vector2i(-1, -1)

# Ensure an int value exists under a key in a dictionary, else write default.
# This mirrors CombatEngine._ensure_stat_int exactly so behavior is unchanged
# once call sites are migrated.
static func ensure_stat_int(s: Dictionary, k: String, v: int) -> void:
	if not s.has(k) or typeof(s[k]) != TYPE_INT:
		s[k] = int(v)

# Read a pair of {hp, max_hp} from an entity dictionary.
# Mirrors CombatEngine._read_hp_pair so snapshot builders and shrine logic can
# depend on a single canonical implementation once wired.
static func read_hp_pair(ent: Dictionary) -> Dictionary:
	var hp: int = 0
	var max_hp: int = 0
	if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
		var stats: Dictionary = ent.stats
		# Prefer canonical stat keys, fall back to legacy synonyms, then flat fields.
		if stats.has(EchoConstants.STAT_HP):
			hp = int(stats.get(EchoConstants.STAT_HP, 0))
		elif stats.has("hp"):
			hp = int(stats.get("hp", 0))
		else:
			hp = int(ent.get("hp", 0))

		if stats.has(EchoConstants.STAT_MAX_HP):
			max_hp = int(stats.get(EchoConstants.STAT_MAX_HP, hp))
		elif stats.has("max_hp"):
			max_hp = int(stats.get("max_hp", hp))
		else:
			max_hp = int(ent.get("max_hp", hp))
	else:
		hp = int(ent.get("hp", 0))
		max_hp = int(ent.get("max_hp", hp))
	return {"hp": hp, "max_hp": max_hp}

# -----------------------------------------------------------------------------
# Fallback and normalization helpers
# These mirror the helper implementations originally hosted in CombatEngine.gd,
# but live here so that any system constructing or normalizing combat entities
# can share a single canonical source of truth.
# -----------------------------------------------------------------------------

static func fallback_stats() -> Dictionary:
	# Safe typed defaults for when a hero/entity has no stats at all (older
	# saves or bad data). Uses HeroBal fallbacks for core combat knobs.
	var s: Dictionary = {
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
	# Mirror canonical HP into legacy synonyms inside stats for older readers.
	s["hp"] = int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP))
	s["max_hp"] = int(s.get(EchoConstants.STAT_MAX_HP, s.get("hp", HeroBal.FALLBACK_HP)))
	return s

static func fallback_stats_from_balance() -> Dictionary:
	# Same defaults as fallback_stats, kept separate for clarity so callers can
	# explicitly indicate they are seeding from balance-configured values.
	var s: Dictionary = {
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
	# Mirror canonical HP into legacy synonyms inside stats for older readers.
	s["hp"] = int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP))
	s["max_hp"] = int(s.get(EchoConstants.STAT_MAX_HP, s.get("hp", HeroBal.FALLBACK_HP)))
	return s

static func fill_missing_stats_with_balance(stats_in: Dictionary) -> Dictionary:
	# Preserve provided values, but ensure all canonical combat stats exist and
	# are typed ints, using HeroBal defaults where necessary.
	var s: Dictionary = stats_in.duplicate(true)
	ensure_stat_int(s, EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)
	ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))
	ensure_stat_int(s, EchoConstants.STAT_ATK, HeroBal.FALLBACK_ATK)
	ensure_stat_int(s, EchoConstants.STAT_DEF, HeroBal.FALLBACK_DEF)
	ensure_stat_int(s, EchoConstants.STAT_AGI, HeroBal.FALLBACK_AGI)
	ensure_stat_int(s, EchoConstants.STAT_CHA, 0)
	ensure_stat_int(s, EchoConstants.STAT_INT, 0)
	ensure_stat_int(s, EchoConstants.STAT_ACC, 0)
	ensure_stat_int(s, EchoConstants.STAT_EVA, 0)
	ensure_stat_int(s, EchoConstants.STAT_CRIT, 0)
	ensure_stat_int(s, EchoConstants.STAT_MORALE, HeroBal.FALLBACK_MORALE)
	ensure_stat_int(s, EchoConstants.STAT_FEAR, 0)
	# Mirror canonical HP into legacy synonyms inside stats for older readers.
	s["hp"] = int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP))
	s["max_hp"] = int(s.get(EchoConstants.STAT_MAX_HP, s.get("hp", HeroBal.FALLBACK_HP)))
	return s

# -----------------------------------------------------------------------------
# Tag and role helpers (generic entity model)
# -----------------------------------------------------------------------------

# Returns true if the entity dictionary contains the given tag in its "tags" array.
static func has_tag(ent: Dictionary, tag: String) -> bool:
	if tag == "" or typeof(ent) != TYPE_DICTIONARY:
		return false
	if not ent.has("tags") or typeof(ent["tags"]) != TYPE_ARRAY:
		return false
	var tags: Array = ent["tags"]
	return tag in tags

# Ensures the entity has a "tags" array and adds the tag if not present.
static func add_tag(ent: Dictionary, tag: String) -> void:
	if tag == "" or typeof(ent) != TYPE_DICTIONARY:
		return
	if not ent.has("tags") or typeof(ent["tags"]) != TYPE_ARRAY:
		ent["tags"] = []
	var tags: Array = ent["tags"]
	if not (tag in tags):
		tags.append(tag)
		ent["tags"] = tags

# Ensures all tags in the provided array are present in the entity's "tags".
static func ensure_tags(ent: Dictionary, tags: Array) -> void:
	if typeof(ent) != TYPE_DICTIONARY or typeof(tags) != TYPE_ARRAY:
		return
	for tag in tags:
		if typeof(tag) == TYPE_STRING and tag != "":
			add_tag(ent, tag)


# Returns true if the entity is a shrine (tag-aware).
static func is_shrine(ent: Dictionary) -> bool:
	if typeof(ent) != TYPE_DICTIONARY:
		return false
	if ent.has("tags") and typeof(ent["tags"]) == TYPE_ARRAY:
		var tags: Array = ent["tags"]
		if "objective:shrine" in tags or "shrine" in tags:
			return true
	return bool(ent.get("is_shrine", false))

# Returns true if the entity is a totem (tag-aware).
static func is_totem(ent: Dictionary) -> bool:
	if typeof(ent) != TYPE_DICTIONARY:
		return false
	if ent.has("tags") and typeof(ent["tags"]) == TYPE_ARRAY:
		var tags: Array = ent["tags"]
		# Canonical MVP tags for totems:
		#   - "objective:totem" (primary)
		#   - "totem"           (fallback / legacy)
		if "objective:totem" in tags or "totem" in tags:
			return true
	# Legacy/defensive support: allow an explicit boolean flag as a fallback.
	return bool(ent.get("is_totem", false))

# Returns true if the entity is a structure (tag-aware).
static func is_structure(ent: Dictionary) -> bool:
	if typeof(ent) != TYPE_DICTIONARY:
		return false
	if ent.has("tags") and typeof(ent["tags"]) == TYPE_ARRAY:
		var tags: Array = ent["tags"]
		if "structure" in tags:
			return true
		# Allow more specific structure roles to imply structure-hood, e.g. "structure:defense"
		for t in tags:
			if typeof(t) == TYPE_STRING and t.begins_with("structure:"):
				return true
	# Legacy/defensive support: keep optional boolean flag for older callers.
	return bool(ent.get("is_structure", false))

# Returns true if the entity is an objective (tag-aware).
static func is_objective(ent: Dictionary) -> bool:
	if typeof(ent) != TYPE_DICTIONARY:
		return false
	if ent.has("tags") and typeof(ent["tags"]) == TYPE_ARRAY:
		var tags: Array = ent["tags"]
		# Generic objective tag
		if "objective" in tags:
			return true
		# Any "objective:*" tag also counts, e.g. "objective:shrine", "objective:escort"
		for t in tags:
			if typeof(t) == TYPE_STRING and t.begins_with("objective:"):
				return true
	# Legacy/defensive support: optional flag or an explicit objective_id
	if bool(ent.get("is_objective", false)):
		return true
	if ent.has("objective_id") and int(ent.get("objective_id", -1)) >= 0:
		return true
	return false

static func is_alive(ent: Dictionary) -> bool:
	if typeof(ent) != TYPE_DICTIONARY:
		return false
	var hp_pair: Dictionary = read_hp_pair(ent)
	var hp: int = int(hp_pair.get("hp", 0))
	if hp <= 0:
		return false
	if String(ent.get("status", "")) == "downed":
		return false
	return true

# Finds the first entity in the group array that has the given tag.

static func find_first_with_tag(group: Array, tag: String) -> Dictionary:
	if typeof(group) != TYPE_ARRAY:
		return {}
	for ent in group:
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		if has_tag(ent, tag):
			return ent
	return {}

# Finds the first alive shrine in the group array.
static func find_alive_shrine(group: Array) -> Dictionary:
	if typeof(group) != TYPE_ARRAY:
		return {}
	for ent in group:
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		if not is_alive(ent):
			continue
		if is_shrine(ent):
			return ent
	return {}

# Finds the first alive totem in the group array.
static func find_alive_totem(group: Array) -> Dictionary:
	if typeof(group) != TYPE_ARRAY:
		return {}
	for ent in group:
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		if not is_alive(ent):
			continue
		if is_totem(ent):
			return ent
	return {}

static func fill_missing_stats(stats_in: Dictionary) -> Dictionary:
	# Generic "shape fixer": ensure all canonical stats exist and are ints,
	# without changing any explicit values that were already present.
	var s: Dictionary = stats_in.duplicate(true)
	ensure_stat_int(s, EchoConstants.STAT_HP, 1)
	ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, 1)))
	ensure_stat_int(s, EchoConstants.STAT_ATK, 0)
	ensure_stat_int(s, EchoConstants.STAT_DEF, 0)
	ensure_stat_int(s, EchoConstants.STAT_AGI, 0)
	ensure_stat_int(s, EchoConstants.STAT_CHA, 0)
	ensure_stat_int(s, EchoConstants.STAT_INT, 0)
	ensure_stat_int(s, EchoConstants.STAT_ACC, 0)
	ensure_stat_int(s, EchoConstants.STAT_EVA, 0)
	ensure_stat_int(s, EchoConstants.STAT_CRIT, 0)
	ensure_stat_int(s, EchoConstants.STAT_MORALE, 50)
	ensure_stat_int(s, EchoConstants.STAT_FEAR, 0)
	# Mirror canonical HP into legacy synonyms inside stats for older readers.
	s["hp"] = int(s.get(EchoConstants.STAT_HP, 1))
	s["max_hp"] = int(s.get(EchoConstants.STAT_MAX_HP, s.get("hp", 1)))
	return s

# -----------------------------------------------------------------------------
# Grid metadata (invisible combat board)
# -----------------------------------------------------------------------------

# Optional grid_pos readers/writers and distance helpers.
# These are pure helpers on the entity dictionary; CombatEngine and higher
# layers can wrap them in state/id-based helpers later.
static func get_grid_pos(ent: Dictionary) -> Vector2i:
	# Returns the entity's grid_pos if present and typed, else GRID_POS_UNSET.
	if typeof(ent) != TYPE_DICTIONARY:
		return GRID_POS_UNSET
	if ent.has("grid_pos") and typeof(ent["grid_pos"]) == TYPE_VECTOR2I:
		return ent["grid_pos"]
	return GRID_POS_UNSET

static func set_grid_pos(ent: Dictionary, pos: Vector2i) -> void:
	# Writes a grid position onto the entity. Callers are responsible for
	# ensuring the position is inside the board (see CombatEngine helpers).
	if typeof(ent) != TYPE_DICTIONARY:
		return
	ent["grid_pos"] = pos

static func clear_grid_pos(ent: Dictionary) -> void:
	# Clears grid_pos back to the sentinel "not placed" value.
	set_grid_pos(ent, GRID_POS_UNSET)

static func has_grid_pos(ent: Dictionary) -> bool:
	# Returns true if the entity has a non-sentinel grid_pos.
	if typeof(ent) != TYPE_DICTIONARY:
		return false
	if not ent.has("grid_pos") or typeof(ent["grid_pos"]) != TYPE_VECTOR2I:
		return false
	return ent["grid_pos"] != GRID_POS_UNSET

static func grid_distance(a: Vector2i, b: Vector2i) -> int:
	# Manhattan distance between two grid cells. Returns -1 if either is unset.
	if a == GRID_POS_UNSET or b == GRID_POS_UNSET:
		return -1
	return abs(a.x - b.x) + abs(a.y - b.y)

static func grid_distance_between_entities(a: Dictionary, b: Dictionary) -> int:
	# Convenience wrapper for computing distance between two entities on the
	# board. Returns -1 if either entity is not placed.
	if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
		return -1
	var pa: Vector2i = get_grid_pos(a)
	var pb: Vector2i = get_grid_pos(b)
	return grid_distance(pa, pb)

static func grid_is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	# Returns true if two positions are in melee range (same cell or 4-neighbour).
	if a == GRID_POS_UNSET or b == GRID_POS_UNSET:
		return false
	return grid_distance(a, b) <= 1

static func entities_are_adjacent(a: Dictionary, b: Dictionary) -> bool:
	# Convenience wrapper that checks adjacency for two entities.
	if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
		return false
	var pa: Vector2i = get_grid_pos(a)
	var pb: Vector2i = get_grid_pos(b)
	return grid_is_adjacent(pa, pb)

# -----------------------------------------------------------------------------
# Grid-aware group helpers
# -----------------------------------------------------------------------------

# Returns all entities in `group` that are located at the given grid position.
# If `only_alive` is true, filters out entities that are not alive.
static func find_entities_at(group: Array, pos: Vector2i, only_alive: bool = false) -> Array:
	if typeof(group) != TYPE_ARRAY:
		return []
	if pos == GRID_POS_UNSET:
		return []
	var results: Array = []
	for ent in group:
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		if only_alive and not is_alive(ent):
			continue
		var gp: Vector2i = get_grid_pos(ent)
		if gp == pos:
			results.append(ent)
	return results

# Returns the single closest entity in `group` to the given grid position.
# If `only_alive` is true, filters out entities that are not alive.
# Returns an empty Dictionary if no suitable entity is found or `pos` is unset.
static func find_closest_entity_to_pos(group: Array, pos: Vector2i, only_alive: bool = false) -> Dictionary:
	if typeof(group) != TYPE_ARRAY:
		return {}
	if pos == GRID_POS_UNSET:
		return {}
	var best_ent: Dictionary = {}
	var best_dist: int = -1
	for ent in group:
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		if only_alive and not is_alive(ent):
			continue
		var gp: Vector2i = get_grid_pos(ent)
		var d: int = grid_distance(pos, gp)
		if d < 0:
			continue
		if best_dist == -1 or d < best_dist:
			best_dist = d
			best_ent = ent
	return best_ent
