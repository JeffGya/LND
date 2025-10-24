extends Resource
class_name EconomyIO

# Minimal runtime cache so SaveService reads/writes consistent values (MVP)
static var _runtime: Dictionary = {}

# -------------------------------------------------------------
# Internal helpers
# -------------------------------------------------------------
static func _ensure_runtime() -> void:
	if _runtime.is_empty():
		_runtime = pack_default()

## EconomyIO — packs/unpacks the `economy` module for SaveService (Task 4)
## Schema fields (docs/schemas/json/economy.schema.json):
##   ase: int >= 0
##   ekwan: int >= 0
##   (Migration-ready: if ekwan missing in old saves → default to 0)
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
	_ensure_runtime()
	return _runtime.duplicate(true)

## Import a saved economy block back into runtime.
## Task 4: validate only; wiring to a subsystem comes in a later task.
static func unpack(d: Dictionary) -> void:
	var dd := _apply_defaults(d)
	var res := _validate(dd)
	if not res.ok:
		push_warning("EconomyIO.unpack: invalid data: %s" % res.message)
		return
	# Commit into the runtime cache so subsequent reads reflect changes
	_runtime = dd.duplicate(true)

# -------------------------------------------------------------
# Migration helpers (fill missing keys with safe defaults)
# -------------------------------------------------------------
static func _apply_defaults(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	if not out.has("ase"):
		out["ase"] = 0
	if not out.has("ekwan"):
		out["ekwan"] = 0
	if not out.has("relics"):
		out["relics"] = []
	if not out.has("yields"):
		out["yields"] = {"daily_ase": 0}
	else:
		var y: Dictionary = out["yields"]
		if typeof(y.get("daily_ase", 0)) != TYPE_INT:
			out["yields"] = {"daily_ase": int(y.get("daily_ase", 0))}
	if not out.has("sinks"):
		out["sinks"] = {}
	# Coerce numeric fields and clamp ≥ 0 to be defensive
	out["ase"] = max(0, int(out["ase"]))
	out["ekwan"] = max(0, int(out["ekwan"]))
	return out

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	# Keys are expected to exist after _apply_defaults()
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