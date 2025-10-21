extends Resource
class_name TelemetryIO

## TelemetryIO — packs/unpacks the `telemetry_log` module for SaveService (Task 4)
## Schema (docs/schemas/json/telemetry.schema.json):
## {
##   "ring":   object[],   # free-form event objects
##   "cursor": int >= 0,   # write index into the ring
##   "enabled": bool
## }
##
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • pack_default()/pack_current() return safe defaults (no dependency yet).
##   • unpack() validates payload; wiring into a real telemetry buffer is a later task.

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default telemetry block for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"ring": [],
		"cursor": 0,
		"enabled": true
	}

## Export current runtime telemetry state.
## Task 4: stateless → return defaults.
## Later: read from your Telemetry subsystem/buffer.
static func pack_current() -> Dictionary:
	return pack_default()

## Import a saved telemetry block back into runtime.
## Task 4: validate only; real writes happen when the subsystem exists.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("TelemetryIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write values into your Telemetry subsystem/buffer
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["ring","cursor","enabled"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	# ring must be an array of objects (free-form events allowed)
	if typeof(d.ring) != TYPE_ARRAY:
		return {"ok": false, "message": "ring must be array"}
	for ev in (d.ring as Array):
		if typeof(ev) != TYPE_DICTIONARY:
			return {"ok": false, "message": "ring must contain objects"}

	# cursor must be int >= 0
	if typeof(d.cursor) != TYPE_INT or int(d.cursor) < 0:
		return {"ok": false, "message": "cursor must be int >= 0"}

	# enabled must be boolean
	if typeof(d.enabled) != TYPE_BOOL:
		return {"ok": false, "message": "enabled must be boolean"}

	return {"ok": true, "message": "OK"}
