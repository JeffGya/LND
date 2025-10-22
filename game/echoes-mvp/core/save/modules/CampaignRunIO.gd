# res://core/save/modules/CampaignRunIO.gd
extends Resource
class_name CampaignRunIO

## CampaignRunIO — packs/unpacks the `campaign_run` module for SaveService
## Schema: mode (enum), cycle_index (>=0), realm_selection[], realm_order[], rng_book{}

# Allowed campaign modes (mirror JSON schema)
const MODE_MVP: String = "MVP"
const MODE_STANDARD: String = "Standard"
const MODE_IRONKEEPER: String = "IronKeeper"
const ALLOWED_MODES := [MODE_MVP, MODE_STANDARD, MODE_IRONKEEPER]

# Determinism helper (module, not autoload; exists in Task 4 set)
const RNCatalogIO = preload("res://core/save/modules/RNCatalogIO.gd")

# -------------------------------------------------------------------
# Public API used by SaveService (stateless)
# -------------------------------------------------------------------

## Build a fresh campaign_run block from a seed.
static func pack_new(campaign_seed: int) -> Dictionary:
	return {
		"mode": MODE_MVP,
		"cycle_index": 0,
		"realm_selection": [],
		"realm_order": [],
		"rng_book": RNCatalogIO.pack_from_seed(campaign_seed)
	}

## Export the current runtime campaign state.
## Task 4: stateless → we return stable defaults + current RNG cursors.
## Later tasks can replace defaults with live values.
static func pack_current() -> Dictionary:
	return {
		"mode": MODE_MVP,
		"cycle_index": 0,
		"realm_selection": [],
		"realm_order": [],
		"rng_book": RNCatalogIO.pack_current()
	}

## Import a saved campaign_run block back into runtime.
## Task 4: only restore RNG (determinism); other fields stay defaults until later tasks.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("CampaignRunIO.unpack: invalid data: %s" % res.message)
		return

	# Determinism: restore rng_book into the RNG catalog.
	RNCatalogIO.unpack(d.rng_book)

# -------------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["mode","cycle_index","realm_selection","realm_order","rng_book"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	var m := String(d.mode)
	if not ALLOWED_MODES.has(m):
		return {"ok": false, "message": "mode not allowed: %s" % m}

	if typeof(d.cycle_index) != TYPE_INT or int(d.cycle_index) < 0:
		return {"ok": false, "message": "cycle_index must be int >= 0"}

	if typeof(d.realm_selection) != TYPE_ARRAY:
		return {"ok": false, "message": "realm_selection must be array"}
	if typeof(d.realm_order) != TYPE_ARRAY:
		return {"ok": false, "message": "realm_order must be array"}

	if typeof(d.rng_book) != TYPE_DICTIONARY:
		return {"ok": false, "message": "rng_book must be object"}
	var rb := d.rng_book as Dictionary
	for k in ["campaign_seed", "subseeds", "cursors"]:
		if not rb.has(k):
			return {"ok": false, "message": "rng_book.%s missing" % k}

	# campaign_seed can be int or string (schema allows either; UI may render hex)
	var cs_t := typeof(rb.campaign_seed)
	if cs_t != TYPE_INT and cs_t != TYPE_STRING:
		return {"ok": false, "message": "rng_book.campaign_seed must be int or string"}

	# subseeds must be a Dictionary<String, String>
	if typeof(rb.subseeds) != TYPE_DICTIONARY:
		return {"ok": false, "message": "rng_book.subseeds must be object"}
	for sk in (rb.subseeds as Dictionary).keys():
		if typeof(sk) != TYPE_STRING or typeof((rb.subseeds as Dictionary)[sk]) != TYPE_STRING:
			return {"ok": false, "message": "rng_book.subseeds must map String->String"}

	# cursors must be a Dictionary<String, Int>=0
	if typeof(rb.cursors) != TYPE_DICTIONARY:
		return {"ok": false, "message": "rng_book.cursors must be object"}
	for ck in (rb.cursors as Dictionary).keys():
		var cv = (rb.cursors as Dictionary)[ck]
		if typeof(ck) != TYPE_STRING or typeof(cv) != TYPE_INT or int(cv) < 0:
			return {"ok": false, "message": "rng_book.cursors must map String->Int>=0"}

	return {"ok": true, "message": "OK"}
