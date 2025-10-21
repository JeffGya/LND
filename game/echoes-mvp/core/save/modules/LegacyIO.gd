

extends Resource
class_name LegacyIO

## LegacyIO — packs/unpacks the `legacy` module for SaveService (Task 4)
## Schema (docs/schemas/json/legacy.schema.json):
## {
##   "fragments":  Fragment[],
##   "lineages":   string[],
##   "memorials":  string[]
## }
## Fragment shape:
##   hero_id: string (required)
##   summary: string (required)
##   date_utc: string (ISO8601Z, optional)
##
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • pack_default()/pack_current() return empty structures (no dependency yet).
##   • unpack() validates payload; wiring into a real Legacy subsystem is a later task.

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default legacy block for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"fragments": [],
		"lineages": [],
		"memorials": []
	}

## Export current runtime legacy state.
## Task 4: stateless → return defaults.
## Later: read from your Legacy subsystem.
static func pack_current() -> Dictionary:
	return pack_default()

## Import a saved legacy block back into runtime.
## Task 4: validate only; real writes happen when the subsystem exists.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("LegacyIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write values into your Legacy subsystem/state
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["fragments","lineages","memorials"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	# fragments: array of objects with hero_id/summary (+ optional date_utc)
	if typeof(d.fragments) != TYPE_ARRAY:
		return {"ok": false, "message": "fragments must be array"}
	for fr in (d.fragments as Array):
		var chk := _validate_fragment(fr)
		if not chk.ok:
			return chk

	# lineages/memorials: arrays of strings
	for arr_key in ["lineages","memorials"]:
		if typeof(d[arr_key]) != TYPE_ARRAY:
			return {"ok": false, "message": "%s must be array" % arr_key}
		for v in (d[arr_key] as Array):
			if typeof(v) != TYPE_STRING:
				return {"ok": false, "message": "%s must contain strings" % arr_key}

	return {"ok": true, "message": "OK"}

static func _validate_fragment(f: Variant) -> Dictionary:
	if typeof(f) != TYPE_DICTIONARY:
		return {"ok": false, "message": "fragment must be object"}
	var fd := f as Dictionary
	for req in ["hero_id","summary"]:
		if not fd.has(req):
			return {"ok": false, "message": "fragment missing %s" % req}
	if typeof(fd.hero_id) != TYPE_STRING or fd.hero_id == "":
		return {"ok": false, "message": "fragment.hero_id must be non-empty string"}
	if typeof(fd.summary) != TYPE_STRING or fd.summary == "":
		return {"ok": false, "message": "fragment.summary must be non-empty string"}

	if fd.has("date_utc"):
		if typeof(fd.date_utc) != TYPE_STRING:
			return {"ok": false, "message": "fragment.date_utc must be string if present"}
		if not _looks_like_iso8601z(fd.date_utc):
			return {"ok": false, "message": "fragment.date_utc must be ISO8601Z (YYYY-MM-DDTHH:MM:SSZ)"}

	return {"ok": true, "message": "OK"}

static func _looks_like_iso8601z(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	return re.search(s) != null