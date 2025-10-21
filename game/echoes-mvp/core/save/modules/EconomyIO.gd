

extends Resource
class_name EconomyIO

## EconomyIO — packs/unpacks the `economy` module for SaveService (Task 4)
## Schema fields (docs/schemas/json/economy.schema.json):
##   ase: int >= 0
##   ekwan: int >= 0
##   relics: string[]
##   yields: { daily_ase: int }
##   sinks:  { ... } (free-form counters, left as object)
##
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • No dependency on future AutoLoads; returns safe defaults in pack_current().
##   • unpack() validates the payload; hook up writes to your real Economy system later.

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default economy for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"ase": 0,
		"ekwan": 0,
		"relics": [],
		"yields": { "daily_ase": 0 },
		"sinks": {}
	}

## Export current runtime economy.
## Task 4: stateless → return defaults (no runtime system yet).
## Later: read from your Economy subsystem.
static func pack_current() -> Dictionary:
	return pack_default()

## Import a saved economy block back into runtime.
## Task 4: validate only; wiring to a subsystem comes in a later task.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("EconomyIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write values into your Economy subsystem/state
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["ase","ekwan","relics","yields","sinks"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	if typeof(d.ase) != TYPE_INT or int(d.ase) < 0:
		return {"ok": false, "message": "ase must be int >= 0"}
	if typeof(d.ekwan) != TYPE_INT or int(d.ekwan) < 0:
		return {"ok": false, "message": "ekwan must be int >= 0"}

	if typeof(d.relics) != TYPE_ARRAY:
		return {"ok": false, "message": "relics must be array"}
	else:
		for i in d.relics:
			if typeof(i) != TYPE_STRING:
				return {"ok": false, "message": "relics must contain strings"}

	if typeof(d.yields) != TYPE_DICTIONARY:
		return {"ok": false, "message": "yields must be object"}
	if typeof((d.yields as Dictionary).get("daily_ase", 0)) != TYPE_INT:
		return {"ok": false, "message": "yields.daily_ase must be int"}

	if typeof(d.sinks) != TYPE_DICTIONARY:
		return {"ok": false, "message": "sinks must be object"}

	return {"ok": true, "message": "OK"}