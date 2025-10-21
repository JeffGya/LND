

extends Resource
class_name SanctumIO

## SanctumIO — packs/unpacks the `sanctum_state` module for SaveService (Task 4)
## Schema (docs/schemas/json/sanctum_state.schema.json):
##   wings_unlocked: string[]
##   emotions: { faith: int 0..100, harmony: int 0..100, favor: int 0..100 }
##   upgrades: object (free-form map for now)
##   queues: {
##     healing:   QueueItem[],
##     research:  QueueItem[],
##     crafting:  QueueItem[]
##   }
##   QueueItem: { id: string, start_utc: ISO8601Z, end_utc: ISO8601Z, status: enum("pending","running","done") }
##
## Design notes (Task 4 scope):
##   • Stateless adapter with static methods so SaveService can call directly.
##   • pack_default()/pack_current() return safe defaults (no dependency yet).
##   • unpack() validates payload; wiring into a real Sanctum subsystem is a later task.

const QUEUE_STATUSES := ["pending", "running", "done"]

# -------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------

## Default sanctum for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"wings_unlocked": [],
		"emotions": { "faith": 60, "harmony": 55, "favor": 10 },
		"upgrades": {},
		"queues": {
			"healing": [],
			"research": [],
			"crafting": []
		}
	}

## Export current runtime sanctum.
## Task 4: stateless → return defaults.
## Later: read from your Sanctum subsystem.
static func pack_current() -> Dictionary:
	return pack_default()

## Import a saved sanctum block back into runtime.
## Task 4: validate only; real writes happen when the subsystem exists.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("SanctumIO.unpack: invalid data: %s" % res.message)
		return
	# TODO (later): write values into your Sanctum subsystem/state
	pass

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["wings_unlocked","emotions","upgrades","queues"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	# wings_unlocked: array of strings
	if typeof(d.wings_unlocked) != TYPE_ARRAY:
		return {"ok": false, "message": "wings_unlocked must be array"}
	for wid in (d.wings_unlocked as Array):
		if typeof(wid) != TYPE_STRING:
			return {"ok": false, "message": "wings_unlocked must contain strings"}

	# emotions: object with three ints in 0..100
	if typeof(d.emotions) != TYPE_DICTIONARY:
		return {"ok": false, "message": "emotions must be object"}
	var em: Dictionary = d.emotions as Dictionary
	for e in ["faith","harmony","favor"]:
		var v: int = int(em.get(e, -1))
		if v < 0 or v > 100:
			return {"ok": false, "message": "emotions.%s out of range" % e}

	# upgrades: object (free-form for now)
	if typeof(d.upgrades) != TYPE_DICTIONARY:
		return {"ok": false, "message": "upgrades must be object"}

	# queues: object with three arrays
	if typeof(d.queues) != TYPE_DICTIONARY:
		return {"ok": false, "message": "queues must be object"}
	var q := d.queues as Dictionary
	for qk in ["healing","research","crafting"]:
		if typeof(q.get(qk, null)) != TYPE_ARRAY:
			return {"ok": false, "message": "queues.%s must be array" % qk}
		for item in (q[qk] as Array):
			var chk := _validate_queue_item(item)
			if not chk.ok:
				return {"ok": false, "message": "queues.%s: %s" % [qk, chk.message]}

	return {"ok": true, "message": "OK"}

static func _validate_queue_item(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "message": "queue item must be object"}
	var d := v as Dictionary
	for req in ["id","start_utc","end_utc","status"]:
		if not d.has(req):
			return {"ok": false, "message": "queue item missing %s" % req}
	if typeof(d.id) != TYPE_STRING or d.id == "":
		return {"ok": false, "message": "queue item id must be non-empty string"}
	if typeof(d.status) != TYPE_STRING or not QUEUE_STATUSES.has(d.status):
		return {"ok": false, "message": "queue item status not allowed"}
	if typeof(d.start_utc) != TYPE_STRING or not _looks_like_iso8601z(d.start_utc):
		return {"ok": false, "message": "queue item start_utc must be ISO8601Z"}
	if typeof(d.end_utc) != TYPE_STRING or not _looks_like_iso8601z(d.end_utc):
		return {"ok": false, "message": "queue item end_utc must be ISO8601Z"}
	return {"ok": true, "message": "OK"}

static func _looks_like_iso8601z(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	return re.search(s) != null