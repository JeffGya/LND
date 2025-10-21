

extends Resource
class_name ResearchCraftingIO

## ResearchCraftingIO — packs/unpacks the `research_crafting` module for SaveService (Task 4)
## Schema (docs/schemas/json/research_crafting.schema.json):
## {
##   "research_tree": {
##     "faith": string[],
##     "war": string[],
##     "knowledge": string[]
##   },
##   "active_projects": Project[],
##   "known_recipes": string[]
## }
## Project shape (required):
##   id: string
##   recipe_id: string
##   start_utc: ISO8601Z string (YYYY-MM-DDTHH:MM:SSZ)
##   end_utc?:  ISO8601Z string
##   status: "pending" | "running" | "done" | "failed"
##
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • pack_default()/pack_current() return safe defaults (no dependency yet).
##   • unpack() validates payload; wiring into a real Research/Crafting subsystem is a later task.

const STATUSES := ["pending", "running", "done", "failed"]

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default block for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"research_tree": { "faith": [], "war": [], "knowledge": [] },
		"active_projects": [],
		"known_recipes": []
	}

## Export current runtime state.
## Task 4: stateless → return defaults.
## Later: read from your Research/Crafting subsystem.
static func pack_current() -> Dictionary:
	return pack_default()

## Import a saved block back into runtime.
## Task 4: validate only; real writes happen when the subsystem exists.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("ResearchCraftingIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write values into your Research/Crafting subsystem/state
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["research_tree","active_projects","known_recipes"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	# research_tree
	if typeof(d.research_tree) != TYPE_DICTIONARY:
		return {"ok": false, "message": "research_tree must be object"}
	var rt := d.research_tree as Dictionary
	for branch in ["faith","war","knowledge"]:
		if typeof(rt.get(branch, null)) != TYPE_ARRAY:
			return {"ok": false, "message": "research_tree.%s must be array" % branch}
		for node_id in (rt[branch] as Array):
			if typeof(node_id) != TYPE_STRING:
				return {"ok": false, "message": "research_tree.%s must contain strings" % branch}

	# known_recipes: array of strings
	if typeof(d.known_recipes) != TYPE_ARRAY:
		return {"ok": false, "message": "known_recipes must be array"}
	for rid in (d.known_recipes as Array):
		if typeof(rid) != TYPE_STRING:
			return {"ok": false, "message": "known_recipes must contain strings"}

	# active_projects: array of Project
	if typeof(d.active_projects) != TYPE_ARRAY:
		return {"ok": false, "message": "active_projects must be array"}
	for pr in (d.active_projects as Array):
		var chk := _validate_project(pr)
		if not chk.ok:
			return chk

	return {"ok": true, "message": "OK"}

static func _validate_project(p: Variant) -> Dictionary:
	if typeof(p) != TYPE_DICTIONARY:
		return {"ok": false, "message": "project must be object"}
	var pd := p as Dictionary
	for req in ["id","recipe_id","start_utc","status"]:
		if not pd.has(req):
			return {"ok": false, "message": "project missing %s" % req}

	if typeof(pd.id) != TYPE_STRING or pd.id == "":
		return {"ok": false, "message": "project.id must be non-empty string"}
	if typeof(pd.recipe_id) != TYPE_STRING or pd.recipe_id == "":
		return {"ok": false, "message": "project.recipe_id must be non-empty string"}

	if typeof(pd.start_utc) != TYPE_STRING or not _looks_like_iso8601z(pd.start_utc):
		return {"ok": false, "message": "project.start_utc must be ISO8601Z (YYYY-MM-DDTHH:MM:SSZ)"}
	if pd.has("end_utc"):
		if typeof(pd.end_utc) != TYPE_STRING or not _looks_like_iso8601z(pd.end_utc):
			return {"ok": false, "message": "project.end_utc must be ISO8601Z if present"}

	if typeof(pd.status) != TYPE_STRING or not STATUSES.has(pd.status):
		return {"ok": false, "message": "project.status not allowed"}

	return {"ok": true, "message": "OK"}

static func _looks_like_iso8601z(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	return re.search(s) != null