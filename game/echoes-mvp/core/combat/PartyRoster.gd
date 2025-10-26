# core/combat/PartyRoster.gd
# -----------------------------------------------------------------------------
# Deterministic, side‑effect‑free helpers for building a legal player party.
# MVP rules are intentionally simple and tolerant of missing fields so we can
# wire this into the debug console and combat engine without blocking on
# nonessential data plumbing.
#
# Canon notes
#  - §3 Guidance > Control: player chooses; engine simulates.
#  - §9 Deterministic: pure functions; stable sort; no singletons.
#  - §12 Balance knobs will later adjust availability (injury, morale, etc.).
# -----------------------------------------------------------------------------
class_name PartyRoster

## Status values that render a hero temporarily unavailable for selection.
const UNAVAILABLE_STATUSES := ["on_mission", "resting"]

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Returns a stable, filtered list of available allies from a state snapshot.
##
## @param ss Dictionary - state snapshot that contains at least
##        ss.hero_roster.active : Array[Dictionary]
##        ss.sanctum_state.now_utc : String (ISO 8601, e.g. "2025-10-26T12:34:56Z")
##        (If fields are missing, we assume availability by MVP rule.)
## @return Array[Dictionary] - each entry is a light hero summary:
##         { id:int, name:String, arch:String, hp:int, status:String }
static func list_available_allies(ss: Dictionary) -> Array[Dictionary]:
	var active: Array[Dictionary] = _read_active_list(ss)
	var now_iso: String = _read_now_utc(ss)

	var out: Array[Dictionary] = []
	for hero in active:
		if _is_hero_available(hero, now_iso):
			# Build a compact, stable summary used by UI/debug and validators.
			out.append({
				"id": int(hero.get("id", 0)),
				"name": str(hero.get("name", "Unknown")),
				"arch": str(hero.get("arch", "")),
				"hp": int(hero.get("stats", {}).get("hp", -1)),
				"status": str(hero.get("status", "")),
			})

	# Deterministic ordering (by id asc) so downstream behavior is reproducible.
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out


## Validates a proposed party against MVP rules.
##
## @param ss Dictionary - state snapshot (see list_available_allies)
## @param ids Array[int] - proposed hero ids (order is preserved after de‑dupe)
## @param max_size int - maximum allowed party size (default 3)
## @return Dictionary envelope:
##         { ok:bool, party:Array[int], errors:Array[String] }
static func validate_party(ss: Dictionary, ids: Array, max_size: int = 3) -> Dictionary:
	var errors: Array[String] = []
	var party: Array[int] = normalize_ids(ids)

	if party.is_empty():
		errors.append("no ids provided")

	if party.size() > max_size:
		errors.append("party too large: %d > %d" % [party.size(), max_size])

	# Build a quick lookup of active and available heroes
	var active: Array[Dictionary] = _read_active_list(ss)
	var active_by_id: Dictionary = {}
	for h in active:
		active_by_id[int(h.get("id", 0))] = h

	var available_ids: Dictionary = {}
	var now_iso: String = _read_now_utc(ss)
	for h in active:
		if _is_hero_available(h, now_iso):
			available_ids[int(h.get("id", 0))] = true

	# Validate existence + availability per id, preserving input order
	for id in party:
		if not active_by_id.has(id):
			errors.append("unknown hero id: %d" % id)
		elif not available_ids.has(id):
			var st: String = str(active_by_id[id].get("status", ""))
			var suffix: String = ""
			if st != "":
				suffix = " (status=%s)" % st
			errors.append("id not available: %d%s" % [id, suffix])

	return {
		"ok": errors.is_empty(),
		"party": party,
		"errors": errors,
	}


## Normalizes a list of ids coming from user input (numbers or strings).
##  - converts numeric strings to ints
##  - drops non‑numeric / negative values
##  - removes duplicates while preserving the first occurrence order
static func normalize_ids(ids: Array) -> Array[int]:
	var out: Array[int] = []
	var seen: Dictionary = {}
	for v in ids:
		var id_val: int = _to_int_or_neg1(v)
		if id_val < 0:
			continue
		if not seen.has(id_val):
			seen[id_val] = true
			out.append(id_val)
	return out


# -----------------------------------------------------------------------------
# Internal helpers (pure)
# -----------------------------------------------------------------------------

## Returns an Array of hero Dictionaries (may be empty). Tolerates missing paths.
static func _read_active_list(ss: Dictionary) -> Array[Dictionary]:
	var roster: Dictionary = ss.get("hero_roster", {})
	var active: Array = roster.get("active", [])
	# Ensure we only return dictionaries (defensive against bad data)
	var out: Array[Dictionary] = []
	for h in active:
		if typeof(h) == TYPE_DICTIONARY:
			out.append(h)
	return out

## Returns ISO utc string from snapshot or a safe default.
static func _read_now_utc(ss: Dictionary) -> String:
	var sanctum: Dictionary = ss.get("sanctum_state", {})
	var now_iso: String = str(sanctum.get("now_utc", ""))
	return now_iso

## MVP availability predicate. Missing data ⇒ we err on the side of available.
static func _is_hero_available(hero: Dictionary, now_iso: String) -> bool:
	# Status gate (missing = available)
	var status: String = str(hero.get("status", ""))
	if status in UNAVAILABLE_STATUSES:
		return false

	# Downed (hp <= 0) if stats are present; missing stats ⇒ assume available
	var stats: Dictionary = hero.get("stats", {})
	if typeof(stats) == TYPE_DICTIONARY and stats.has("hp"):
		if int(stats.hp) <= 0:
			return false

	# Injury timer (if present): available only when injured_until_utc <= now
	var injured_until: String = str(hero.get("injured_until_utc", ""))
	if injured_until != "" and now_iso != "":
		# Lexicographic compare works for RFC 3339/ISO 8601 Zulu timestamps
		if injured_until > now_iso:
			return false

	return true

## Converts a value to int if it is already an int or a numeric string; otherwise -1.
static func _to_int_or_neg1(v) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_STRING:
			var s: String = v.strip_edges()
			if s.is_valid_int():
				var parsed: int = int(s)
				if parsed >= 0:
					return parsed
				else:
					return -1
			return -1
		_:
			return -1