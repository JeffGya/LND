extends Resource
class_name HeroesIO

## HeroesIO — packs/unpacks the `hero_roster` module for SaveService (Task 4)
## Schema (docs/schemas/json/hero_roster.schema.json):
## {
##   "active":    Hero[],
##   "recovering":Hero[],
##   "retired":   Hero[],
##   "fallen":    Hero[]
## }
## Hero shape (schema-inspired):
##   id: string
##   name: string
##   traits: { courage, ambition, empathy, wisdom, discipline, resolve } each 0..100
##   stats:  { hp >= 0, morale 0..100, fear 0..100 }
##   (optional) conditions: string[], bonds: string[], lineage_id: string, history: string[]
##
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • pack_default()/pack_current() return empty roster; no dependency on future systems.
##   • unpack() validates payload; wiring into a real Heroes subsystem is a later task.

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default roster for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"active": [],
		"recovering": [],
		"retired": [],
		"fallen": []
	}

## Export current runtime roster.
## Task 4: stateless → return defaults.
## Later: read from your Heroes subsystem/registry.
static func pack_current() -> Dictionary:
	return pack_default()

## Import a saved roster back into runtime.
## Task 4: validate only; real writes happen when the subsystem exists.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("HeroesIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write heroes into your runtime hero manager/registry
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["active","recovering","retired","fallen"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}
		if typeof(d[k]) != TYPE_ARRAY:
			return {"ok": false, "message": "%s must be array" % k}
		# Validate each hero object in the list
		for h in (d[k] as Array):
			var hero_res := _validate_hero(h)
			if not hero_res.ok:
				return hero_res
	return {"ok": true, "message": "OK"}

static func _validate_hero(h: Variant) -> Dictionary:
	if typeof(h) != TYPE_DICTIONARY:
		return {"ok": false, "message": "hero must be object"}
	var hd := h as Dictionary
	for req in ["id","name","traits","stats"]:
		if not hd.has(req):
			return {"ok": false, "message": "hero missing %s" % req}
	if typeof(hd.id) != TYPE_STRING or hd.id == "":
		return {"ok": false, "message": "hero.id must be non-empty string"}
	if typeof(hd.name) != TYPE_STRING or hd.name == "":
		return {"ok": false, "message": "hero.name must be non-empty string"}

	# Traits 0..100
	if typeof(hd.traits) != TYPE_DICTIONARY:
		return {"ok": false, "message": "hero.traits must be object"}
	var tr := hd.traits as Dictionary
	for t in ["courage","ambition","empathy","wisdom","discipline","resolve"]:
		if typeof(tr.get(t, null)) != TYPE_INT:
			return {"ok": false, "message": "hero.traits.%s must be int" % t}
		var v: int = tr[t]
		if v < 0 or v > 100:
			return {"ok": false, "message": "hero.traits.%s out of range" % t}

	# Stats hp>=0, morale/fear 0..100
	if typeof(hd.stats) != TYPE_DICTIONARY:
		return {"ok": false, "message": "hero.stats must be object"}
	var st := hd.stats as Dictionary
	for reqs in ["hp","morale","fear"]:
		if typeof(st.get(reqs, null)) != TYPE_INT:
			return {"ok": false, "message": "hero.stats.%s must be int" % reqs}
	var hp: int = st.hp
	var morale: int = st.morale
	var fear: int = st.fear
	if hp < 0:
		return {"ok": false, "message": "hero.stats.hp must be >= 0"}
	if morale < 0 or morale > 100:
		return {"ok": false, "message": "hero.stats.morale out of range"}
	if fear < 0 or fear > 100:
		return {"ok": false, "message": "hero.stats.fear out of range"}

	# Optional arrays checking (conditions, bonds, history) if present
	for arr_key in ["conditions","bonds","history"]:
		if hd.has(arr_key):
			if typeof(hd[arr_key]) != TYPE_ARRAY:
				return {"ok": false, "message": "hero.%s must be array if present" % arr_key}
			for item in (hd[arr_key] as Array):
				if typeof(item) != TYPE_STRING:
					return {"ok": false, "message": "hero.%s must contain strings" % arr_key}

	# Optional lineage_id
	if hd.has("lineage_id") and typeof(hd.lineage_id) != TYPE_STRING:
		return {"ok": false, "message": "hero.lineage_id must be string if present"}

	return {"ok": true, "message": "OK"}
