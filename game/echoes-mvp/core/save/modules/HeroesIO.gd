extends Resource
class_name HeroesIO

## HeroesIO — roster persistence module (Subtask 2)
## Purpose: own the heroes roster block for SaveService, assign IDs, and provide a tiny API.
## Design:
##  • Instance-based state (_active, _recovering, _retired, _fallen, _next_id).
##  • MVP hero schema at birth now includes personality: (name, rank, class, traits{courage,wisdom,faith}, archetype, seed, created_utc).
##    Archetype is stored at creation (EchoFactory) and is tolerant in validation for backward-compat.
##  • Validation accepts BOTH MVP-minimal and future rich schemas (stats, 6-traits, etc.).
##  • IDs are assigned here (monotonic int starting at 1).
##  • Active list is the working roster for MVP (recovering/retired/fallen reserved for later).

# -------------------------------------------------------------
# Internal state (persisted via pack_current/unpack)
# -------------------------------------------------------------
var _active: Array[Dictionary] = []
var _recovering: Array[Dictionary] = []
var _retired: Array[Dictionary] = []
var _fallen: Array[Dictionary] = []
var _next_id: int = 1

# -------------------------------------------------------------
# SaveService-facing API
# -------------------------------------------------------------
func pack_default() -> Dictionary:
	# Fresh campaign save shape. Keep future buckets for forward-compatibility.
	return {
		"active": [],
		"recovering": [],
		"retired": [],
		"fallen": [],
		"next_id": 1
	}

func pack_current() -> Dictionary:
	return {
		"active": _clone_array(_active),
		"recovering": _clone_array(_recovering),
		"retired": _clone_array(_retired),
		"fallen": _clone_array(_fallen),
		"next_id": _next_id
	}

func unpack(d: Dictionary) -> void:
	# Defensive defaults
	var data := d if typeof(d) == TYPE_DICTIONARY else {}
	var res := _validate_roster(data)
	if not res.ok:
		push_warning("HeroesIO.unpack: invalid data: %s" % res.message)
		# Reset to defaults on invalid input
		var def := pack_default()
		_active = def.active
		_recovering = def.recovering
		_retired = def.retired
		_fallen = def.fallen
		_next_id = def.next_id
		return

	_active = _sanitize_list(data.get("active", []))
	_recovering = _sanitize_list(data.get("recovering", []))
	_retired = _sanitize_list(data.get("retired", []))
	_fallen = _sanitize_list(data.get("fallen", []))

	# next_id: prefer saved value; if missing or bad, compute from max existing id + 1
	var saved_next: Variant = data.get("next_id", null)
	if typeof(saved_next) == TYPE_INT and int(saved_next) >= 1:
		_next_id = int(saved_next)
	else:
		_next_id = _compute_next_id()

# -------------------------------------------------------------
# Roster operations (used by services/UI/tests)
# -------------------------------------------------------------
func append_hero(hero: Dictionary) -> int:
	# Validate minimal MVP hero shape; do NOT trust incoming id.
	var v := _validate_hero(hero)
	if not v.ok:
		push_warning("HeroesIO.append_hero: rejecting hero: %s" % v.message)
		return -1

	var clean := hero.duplicate(true)
	clean["id"] = _next_id
	_next_id += 1
	_active.append(clean)
	return int(clean["id"]) 

func get_roster() -> Array[Dictionary]:
	# MVP: return active roster only; future: concatenate other buckets if needed.
	return _clone_array(_active)

func get_hero_by_id(id: int) -> Dictionary:
	for h in _active:
		if int(h.get("id", -1)) == id:
			return h.duplicate(true)
	for h in _recovering:
		if int(h.get("id", -1)) == id:
			return h.duplicate(true)
	for h in _retired:
		if int(h.get("id", -1)) == id:
			return h.duplicate(true)
	for h in _fallen:
		if int(h.get("id", -1)) == id:
			return h.duplicate(true)
	return {}

func count() -> int:
	return _active.size()

# -------------------------------------------------------------
# Validation helpers — permissive for MVP, stricter later
# -------------------------------------------------------------
func _validate_roster(d: Dictionary) -> Dictionary:
	for k in ["active","recovering","retired","fallen"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}
		if typeof(d[k]) != TYPE_ARRAY:
			return {"ok": false, "message": "%s must be array" % k}
		for h in (d[k] as Array):
			var hr := _validate_hero(h)
			if not hr.ok:
				return hr
	return {"ok": true, "message": "OK"}

func _validate_hero(h: Variant) -> Dictionary:
	if typeof(h) != TYPE_DICTIONARY:
		return {"ok": false, "message": "hero must be object"}
	var hd := h as Dictionary

	# Personality note (MVP):
	#  • Heroes are assigned an archetype string at birth (see EchoFactory) and it is persisted in saves.
	#  • Validation remains permissive: archetype is not required for older saves, but if present it should be a String.
	#  • Future tightening can assert membership in EchoConstants.ARCHETYPES.

	# --- MVP minimal requirements ---
	# name:String, rank:int, class:String, traits:{courage,wisdom,faith:int}, seed:int (optional), created_utc:String (optional)
	var has_name := typeof(hd.get("name", null)) == TYPE_STRING and String(hd.name) != ""
	var has_rank := typeof(hd.get("rank", null)) == TYPE_INT
	var has_class := typeof(hd.get("class", null)) == TYPE_STRING
	var traits_ok := false
	if typeof(hd.get("traits", null)) == TYPE_DICTIONARY:
		var tr := hd.traits as Dictionary
		var req := ["courage","wisdom","faith"]
		traits_ok = true
		for t in req:
			if typeof(tr.get(t, null)) != TYPE_INT:
				traits_ok = false
				break

	if has_name and has_rank and has_class and traits_ok:
		return {"ok": true, "message": "OK (MVP)"}

	# --- Future richer schema (backward-compat) ---
	# Accept earlier scaffold with stats and 6-trait model
	if typeof(hd.get("traits", null)) == TYPE_DICTIONARY and typeof(hd.get("stats", null)) == TYPE_DICTIONARY:
		var tr2 := hd.traits as Dictionary
		var st2 := hd.stats as Dictionary
		var six := ["courage","ambition","empathy","wisdom","discipline","resolve"]
		var six_ok := true
		for t2 in six:
			if typeof(tr2.get(t2, null)) != TYPE_INT:
				six_ok = false
				break
		var stats_ok := typeof(st2.get("hp", null)) == TYPE_INT and typeof(st2.get("morale", null)) == TYPE_INT and typeof(st2.get("fear", null)) == TYPE_INT
		if six_ok and stats_ok and has_name:
			return {"ok": true, "message": "OK (legacy rich)"}

	return {"ok": false, "message": "hero does not match MVP or legacy schema"}

# -------------------------------------------------------------
# Utilities
# -------------------------------------------------------------
# Deep-copy an array of hero dictionaries as a typed Array[Dictionary]
func _clone_array(src: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in src:
		if typeof(it) == TYPE_DICTIONARY:
			out.append((it as Dictionary).duplicate(true))
	return out

func _sanitize_list(src: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in src:
		if typeof(it) == TYPE_DICTIONARY:
			out.append(it as Dictionary)
	return out

func _compute_next_id() -> int:
	var max_id := 0
	for arr in [_active, _recovering, _retired, _fallen]:
		for h in arr:
			var hid := int(h.get("id", 0))
			if hid > max_id:
				max_id = hid
	return max_id + 1
