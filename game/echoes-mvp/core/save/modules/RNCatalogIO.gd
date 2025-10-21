extends Resource
class_name RNCatalogIO

## RNCatalogIO — RNG Book (Task 5)
## Holds campaign_seed + per-stream subseeds & cursors, and serves deterministic draws.
##
## Save shape (rng_book.schema.json):
## {
##   "campaign_seed": string,
##   "subseeds": { <stream_key>: string },
##   "cursors":  { <stream_key>: int }
## }

# -------------------------------------------------------------
# Serialized state (lives in save file)
# -------------------------------------------------------------
static var _campaign_seed: String = ""
static var _subseeds: Dictionary = {}
static var _cursors: Dictionary = {}

# -------------------------------------------------------------
# Runtime state (not serialized)
# -------------------------------------------------------------
static var _streams: Dictionary = {}  # key -> { seed:int, cursor:int, pcg:Variant }
static var _pcg_script: Script = null
static var _xxh_script: Script = null

# -------------------------------------------------------------
# Public API used by gameplay and adapters
# -------------------------------------------------------------

static func set_campaign_seed(seed_i64: int) -> void:
	_campaign_seed = str(seed_i64)
	_subseeds.clear()
	_cursors.clear()
	_streams.clear()

## Make a fresh rng_book dictionary from an initial seed (pure, no mutation).
static func pack_from_seed(campaign_seed: int) -> Dictionary:
	return {
		"campaign_seed": str(campaign_seed),
		"subseeds": {},
		"cursors": {}
	}

## Export current in-memory rng_book.
static func pack_current() -> Dictionary:
	return {
		"campaign_seed": _campaign_seed,
		"subseeds": _subseeds.duplicate(true),
		"cursors": _cursors.duplicate(true)
	}

## Import rng_book from save and (lazily) rebuild runtime streams.
static func unpack(d: Dictionary) -> void:
	var res := _validate(d)
	if not res.ok:
		push_warning("RNCatalogIO.unpack: invalid data: %s" % res.message)
		return
	_campaign_seed = String(d.get("campaign_seed", ""))
	_subseeds = (d.get("subseeds", {}) as Dictionary).duplicate(true)
	_cursors  = (d.get("cursors",  {}) as Dictionary).duplicate(true)
	_streams.clear()
	# Eagerly hydrate known streams so next draws are O(1)
	for k in _subseeds.keys():
		ensure_stream(String(k))

# -------------------------------------------------------------
# Drawing API (deterministic per-named stream)
# -------------------------------------------------------------
static func next_u32(key: String) -> int:
	ensure_stream(key)
	var s: Dictionary = _streams[key]
	var gen: Variant = s["pcg"]
	var v: int = _pcg_next_u32(gen, int(s["seed"]), int(s["cursor"]))
	# advance cursor
	s["cursor"] = int(s["cursor"]) + 1
	_streams[key] = s
	_cursors[key] = int(s["cursor"])
	return v

static func next_range(key: String, min_i: int, max_i: int) -> int:
	var span := (max_i - min_i + 1)
	if span <= 0:
		return min_i
	var r := int(next_u32(key)) % span
	return min_i + r

## Ensure a stream exists; derive seed if missing and hydrate runtime pcg.
static func ensure_stream(key: String, parent_key: String = "") -> void:
	if _streams.has(key):
		return
	# choose parent seed string
	var parent_seed_str: String = _campaign_seed
	if parent_key != "":
		if not _subseeds.has(parent_key):
			# ensure parent exists first
			ensure_stream(parent_key)
		parent_seed_str = String(_subseeds.get(parent_key, _campaign_seed))
	# child seed
	var child_seed_i64: int = _derive_seed(parent_seed_str, key)
	# persist to subseeds (string in save)
	if not _subseeds.has(key):
		_subseeds[key] = str(child_seed_i64)
	# create runtime generator and fast-forward to cursor
	var cur: int = int(_cursors.get(key, 0))
	var gen: Variant = _pcg_new(child_seed_i64)
	# fast-forward
	if cur > 0:
		for i in cur:
			_pcg_next_u32(gen, child_seed_i64, i)
	_streams[key] = {"seed": child_seed_i64, "cursor": cur, "pcg": gen}

# -------------------------------------------------------------
# Discovery and fallbacks (PCG32 + xxhash64)
# -------------------------------------------------------------
static func _pcg_new(seed_i64: int) -> Variant:
	if _pcg_script == null:
		_pcg_script = _try_load_first([
			"res://core/rng/PCG32.gd",
			"res://core/utils/PCG32.gd",
			"res://core/lib/PCG32.gd",
			"res://core/prng/PCG32.gd"
		])
	if _pcg_script != null:
		# Expect the external PCG to accept a seed in its constructor
		return _pcg_script.new(seed_i64)
	# Fallback to a tiny internal LCG (deterministic, not cryptographic)
	return {"state": int(seed_i64) & 0x7fffffff}

static func _pcg_next_u32(gen: Variant, seed_i64: int, _cursor: int) -> int:
	if gen is Object and gen.has_method("next_u32"):
		return int(gen.call("next_u32"))
	# Fallback LCG: x = (1103515245*x + 12345) mod 2^31, then expand to 32-bit
	var st: int = int(gen["state"])
	st = int((1103515245 * st + 12345) & 0x7fffffff)
	gen["state"] = st
	# mix with seed to vary per-stream
	return int((st ^ (seed_i64 & 0xffffffff)) & 0xffffffff)

static func _derive_seed(parent_seed_str: String, key: String) -> int:
	if _xxh_script == null:
		_xxh_script = _try_load_first([
			"res://core/hash/XXHash64.gd",
			"res://core/utils/XXHash64.gd",
			"res://core/lib/XXHash64.gd"
		])
	var bytes: PackedByteArray = PackedByteArray()
	bytes.append_array(parent_seed_str.to_utf8_buffer())
	bytes.append(0x3A) # ':'
	bytes.append_array(key.to_utf8_buffer())
	if _xxh_script != null:
		# Try common static methods
		if _xxh_script.has_method("hash64_bytes"):
			var u64 := int(_xxh_script.call("hash64_bytes", bytes))
			return int(u64 & 0x7fffffffffffffff)
		elif _xxh_script.has_method("hash64"):
			var u64b := int(_xxh_script.call("hash64", bytes))
			return int(u64b & 0x7fffffffffffffff)
	# Fallback: FNV-1a 64-bit (deterministic)
	var fnv: int = 0xcbf29ce484222325
	var prime: int = 0x100000001b3
	for b in bytes:
		fnv = int((fnv ^ int(b)) & 0xffffffffffffffff)
		# simulate 64-bit wrap
		var hi: int = int((fnv >> 32) & 0xffffffff)
		var lo: int = int(fnv & 0xffffffff)
		var mul: int = int(hi * int(prime & 0xffffffff) + int((lo * int(prime & 0xffffffff)) & 0xffffffff))
		fnv = int((mul) & 0xffffffffffffffff)
	return int(fnv & 0x7fffffffffffffff)

static func _try_load_first(paths: Array) -> Script:
	for p in paths:
		var s: Resource = load(p)
		if s is Script:
			return s
	return null

# -------------------------------------------------------------
# Simple accessors
# -------------------------------------------------------------
static func get_campaign_seed() -> String:
	return _campaign_seed

static func get_subseed(key: String, default_val: String = "") -> String:
	return String(_subseeds.get(key, default_val))

static func set_subseed(key: String, value: String) -> void:
	_subseeds[key] = value

static func get_cursor(key: String, default_val: int = 0) -> int:
	return int(_cursors.get(key, default_val))

static func set_cursor(key: String, value: int) -> void:
	_cursors[key] = int(value)
	if _streams.has(key):
		var s: Dictionary = _streams[key]
		s["cursor"] = int(value)
		_streams[key] = s

# -------------------------------------------------------------
# Validation (schema-inspired)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["campaign_seed","subseeds","cursors"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}
	if typeof(d.campaign_seed) != TYPE_STRING:
		return {"ok": false, "message": "campaign_seed must be string"}
	if typeof(d.subseeds) != TYPE_DICTIONARY:
		return {"ok": false, "message": "subseeds must be object"}
	for kk in (d.subseeds as Dictionary).keys():
		if typeof((d.subseeds as Dictionary)[kk]) != TYPE_STRING:
			return {"ok": false, "message": "subseeds.%s must be string" % String(kk)}
	if typeof(d.cursors) != TYPE_DICTIONARY:
		return {"ok": false, "message": "cursors must be object"}
	for kk in (d.cursors as Dictionary).keys():
		if typeof((d.cursors as Dictionary)[kk]) != TYPE_INT:
			return {"ok": false, "message": "cursors.%s must be int" % String(kk)}
	return {"ok": true, "message": "OK"}
