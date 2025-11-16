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

	# Normalize stats on all buckets for forward-compat (Subtask I)
	_active = _normalize_bucket(_active)
	_recovering = _normalize_bucket(_recovering)
	_retired = _normalize_bucket(_retired)
	_fallen = _normalize_bucket(_fallen)

	# next_id: prefer saved value; if missing or bad, compute from max existing id + 1
	var saved_next: Variant = data.get("next_id", null)
	if typeof(saved_next) == TYPE_INT and int(saved_next) >= 1:
		_next_id = int(saved_next)
	else:
		_next_id = _compute_next_id()

func _normalize_bucket(src: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in src:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var normalized := _normalize_hero_stats(h)
		normalized = _normalize_hero_emotion(normalized)
		out.append(normalized)
	return out

func _normalize_hero_stats(hero: Dictionary) -> Dictionary:
	var h: Dictionary = hero.duplicate(true)
	# If hero already has stats, fill missing safe canon keys; else leave hero as-is (combat will fallback)
	if h.has("stats") and typeof(h["stats"]) == TYPE_DICTIONARY:
		var s: Dictionary = (h["stats"] as Dictionary).duplicate(true)
		# Required MVP keys (ints)
		if not s.has("hp") or typeof(s["hp"]) != TYPE_INT:
			s["hp"] = 0
		if not s.has("max_hp") or typeof(s["max_hp"]) != TYPE_INT:
			s["max_hp"] = int(s.get("hp", 0))
		# Clamp hp to max_hp
		if int(s["max_hp"]) < 1:
			s["max_hp"] = 1
		if int(s["hp"]) > int(s["max_hp"]):
			s["hp"] = int(s["max_hp"])
		# Optional combat keys
		if not s.has("atk") or typeof(s["atk"]) != TYPE_INT:
			s["atk"] = 0
		if not s.has("def") or typeof(s["def"]) != TYPE_INT:
			s["def"] = 0
		if not s.has("agi") or typeof(s["agi"]) != TYPE_INT:
			s["agi"] = 0
		if not s.has("cha") or typeof(s["cha"]) != TYPE_INT:
			s["cha"] = 0
		if not s.has("int") or typeof(s["int"]) != TYPE_INT:
			s["int"] = 0
		if not s.has("acc") or typeof(s["acc"]) != TYPE_INT:
			s["acc"] = 0
		if not s.has("eva") or typeof(s["eva"]) != TYPE_INT:
			s["eva"] = 0
		if not s.has("crit") or typeof(s["crit"]) != TYPE_INT:
			s["crit"] = 0
		h["stats"] = s
	return h

func _normalize_hero_emotion(hero: Dictionary) -> Dictionary:
	var h: Dictionary = hero.duplicate(true)

	# Emotion block is the canonical home for morale/fear going forward.
	# It is structured as:
	#   emotion = {
	#     "morale_base": int,
	#     "morale_current": int,
	#     "fear_current": int,
	#   }

	var e: Dictionary = {}
	if h.has("emotion") and typeof(h["emotion"]) == TYPE_DICTIONARY:
		e = (h["emotion"] as Dictionary).duplicate(true)
	else:
		e = {}

	var stats_dict: Dictionary = {}
	if h.has("stats") and typeof(h["stats"]) == TYPE_DICTIONARY:
		stats_dict = h["stats"] as Dictionary

	# If emotion is effectively empty but legacy stats.morale/fear exist, migrate them.
	var has_emotion_keys := e.has("morale_base") or e.has("morale_current") or e.has("fear_current")
	if not has_emotion_keys and not stats_dict.is_empty():
		var base := 60
		var current := 60
		var fear := 5
		if stats_dict.has("morale") and typeof(stats_dict["morale"]) == TYPE_INT:
			base = int(stats_dict["morale"])
			current = base
		if stats_dict.has("fear") and typeof(stats_dict["fear"]) == TYPE_INT:
			fear = int(stats_dict["fear"])
		e["morale_base"] = base
		e["morale_current"] = current
		e["fear_current"] = fear

	# Fill any missing fields with defaults (kept in sync with HeroModel).
	if not e.has("morale_base") or typeof(e["morale_base"]) != TYPE_INT:
		e["morale_base"] = 60
	if not e.has("morale_current") or typeof(e["morale_current"]) != TYPE_INT:
		e["morale_current"] = int(e["morale_base"])
	if not e.has("fear_current") or typeof(e["fear_current"]) != TYPE_INT:
		e["fear_current"] = 5

	# Clamp values into allowed ranges.
	e["morale_base"] = clamp(int(e["morale_base"]), 0, 100)
	e["morale_current"] = clamp(int(e["morale_current"]), 0, 100)
	e["fear_current"] = clamp(int(e["fear_current"]), 0, 100)

	h["emotion"] = e
	return h

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

	# Normalize combat stats and emotional state at the moment the hero enters the
	# roster so that newly created heroes have consistent fields even before any
	# save/load cycle.
	clean = _normalize_hero_stats(clean)
	clean = _normalize_hero_emotion(clean)

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

# -------------------------------------------------------------
# HeroModel API helper
# -------------------------------------------------------------
func get_hero_model_by_id(id: int) -> HeroModel:
	## Convenience helper: return a HeroModel for the given hero id.
	## This keeps HeroesIO as the persistence owner (dictionaries), while allowing
	## higher-level systems (EmotionService, combat, Sanctum) to work with the
	## structured HeroModel API.
	var h := get_hero_by_id(id)
	if h.is_empty():
		return null
	return HeroModel.from_dict(h)


func update_hero_from_model(model: HeroModel) -> void:
	## Replace the stored hero dictionary for the given model.id with the
	## contents of model.to_dict(), if the hero exists in any roster bucket.
	## This keeps HeroesIO as the single owner of hero storage while allowing
	## services (like EmotionService) to modify heroes through HeroModel.
	if model == null:
		return

	var hero_id := int(model.id)
	var updated: Dictionary = model.to_dict()

	# Search each roster bucket in turn and replace the matching hero entry.
	for i in range(_active.size()):
		var h_active := _active[i]
		if typeof(h_active) != TYPE_DICTIONARY:
			continue
		var stored_id_active := int((h_active as Dictionary).get("id", -1))
		if stored_id_active == hero_id:
			_active[i] = updated
			return

	for i in range(_recovering.size()):
		var h_rec := _recovering[i]
		if typeof(h_rec) != TYPE_DICTIONARY:
			continue
		var stored_id_rec := int((h_rec as Dictionary).get("id", -1))
		if stored_id_rec == hero_id:
			_recovering[i] = updated
			return

	for i in range(_retired.size()):
		var h_ret := _retired[i]
		if typeof(h_ret) != TYPE_DICTIONARY:
			continue
		var stored_id_ret := int((h_ret as Dictionary).get("id", -1))
		if stored_id_ret == hero_id:
			_retired[i] = updated
			return

	for i in range(_fallen.size()):
		var h_fall := _fallen[i]
		if typeof(h_fall) != TYPE_DICTIONARY:
			continue
		var stored_id_fall := int((h_fall as Dictionary).get("id", -1))
		if stored_id_fall == hero_id:
			_fallen[i] = updated
			return


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
	# Accept earlier scaffold with stats and 6-trait model, but allow missing optional combat keys.
	if typeof(hd.get("traits", null)) == TYPE_DICTIONARY and typeof(hd.get("stats", null)) == TYPE_DICTIONARY:
		var tr2: Dictionary = hd.traits as Dictionary
		var st2: Dictionary = hd.stats as Dictionary
		var six: Array[String] = ["courage","ambition","empathy","wisdom","discipline","resolve"]
		var six_ok: bool = true
		for t2 in six:
			if typeof(tr2.get(t2, null)) != TYPE_INT:
				six_ok = false
				break
		# For stats, require only hp; morale/fear can be missing (we'll fill on unpack)
		var has_hp: bool = typeof(st2.get("hp", null)) == TYPE_INT
		if six_ok and has_name and has_hp:
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
