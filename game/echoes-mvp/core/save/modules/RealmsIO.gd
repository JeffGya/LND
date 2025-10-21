extends Resource
class_name RealmsIO

## RealmsIO — packs/unpacks the `realm_states` module for SaveService (Task 4)
## Schema (docs/schemas/json/realm_states.schema.json):
##   realm_states: Array of RealmState objects
##   RealmState fields (required):
##     realm_id:         string
##     tier:             int 1..10
##     realm_seed:       string
##     stage_index:      int >= 0
##     encounter_cursor: int >= 0
##     modifiers:        object (keys arbitrary, numeric values)
##
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • pack_default()/pack_current() return empty arrays (no dependency yet).
##   • unpack() validates payload; wiring into a real Realms subsystem is a later task.

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default realm_states for a brand new game (used by SaveService.new_game)
static func pack_default() -> Array:
	return []

## Export current runtime realm_states.
## Task 4: stateless → return [].
## Later: read from your Realm runner/manager.
static func pack_current() -> Array:
	return []

## Import saved realm_states back into runtime.
## Task 4: validate only; real writes happen when the subsystem exists.
static func unpack(a: Array) -> void:
	var res := _validate(a)
	if not res.ok:
		push_warning("RealmsIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write each realm state into your Realms subsystem
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(a: Array) -> Dictionary:
	# realm_states must be an array
	if typeof(a) != TYPE_ARRAY:
		return {"ok": false, "message": "realm_states must be array"}

	# Validate each realm state object
	for idx in a.size():
		var item: Variant = a[idx]
		var chk := _validate_realm_state(item)
		if not chk.ok:
			return {"ok": false, "message": "[realm %d] %s" % [idx, chk.message]}

	return {"ok": true, "message": "OK"}

static func _validate_realm_state(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "message": "realm state must be object"}
	var d: Dictionary = v as Dictionary

	# Required fields
	for k in ["realm_id","tier","realm_seed","stage_index","encounter_cursor"]:
		if not d.has(k):
			return {"ok": false, "message": "missing key: %s" % k}

	# Types and ranges
	if typeof(d.realm_id) != TYPE_STRING or d.realm_id == "":
		return {"ok": false, "message": "realm_id must be non-empty string"}

	if typeof(d.tier) != TYPE_INT or int(d.tier) < 1 or int(d.tier) > 10:
		return {"ok": false, "message": "tier must be int in 1..10"}

	if typeof(d.realm_seed) != TYPE_STRING or d.realm_seed == "":
		return {"ok": false, "message": "realm_seed must be non-empty string"}

	if typeof(d.stage_index) != TYPE_INT or int(d.stage_index) < 0:
		return {"ok": false, "message": "stage_index must be int >= 0"}

	if typeof(d.encounter_cursor) != TYPE_INT or int(d.encounter_cursor) < 0:
		return {"ok": false, "message": "encounter_cursor must be int >= 0"}

	# modifiers: object with numeric values (optional per schema)
	if d.has("modifiers"):
		if typeof(d.modifiers) != TYPE_DICTIONARY:
			return {"ok": false, "message": "modifiers must be object"}
		for key in (d.modifiers as Dictionary).keys():
			var val: Variant = (d.modifiers as Dictionary)[key]
			if typeof(val) != TYPE_INT and typeof(val) != TYPE_FLOAT:
				return {"ok": false, "message": "modifiers.%s must be number" % String(key)}

	return {"ok": true, "message": "OK"}
