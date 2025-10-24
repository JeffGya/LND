extends Resource
class_name TelemetryIO

## TelemetryIO — packs/unpacks the `telemetry_log` module for SaveService (Tasks 4 & 8)
## Shape (docs/schemas/json/telemetry.schema.json):
## {
##   "ring":   object[],   # free-form event objects (bounded ring buffer)
##   "cursor": int >= 0,   # next write index (monotonic)
##   "enabled": bool       # gate for writes
##   "level": int    # 0=OFF, 1=INFO, 2=DEBUG, 3=LIVE (verbosity gate)
##   "max_events": int  # ring capacity (<= CAPACITY)
## Importance gating: events are recorded only if (enabled == true) AND (importance <= level).
## }
##
## Task 8 adds:
##   • A tiny in-module ring buffer (capacity CAPACITY) with helpers to log events.
##   • Stateless to the rest of the codebase: no external singletons required.
##   • Determinism guard: logging never mutates sim state; it only records.

# -------------------------------------------------------------
# Configuration
# -------------------------------------------------------------
const CAPACITY: int = 256  # bounded size of the telemetry ring

# -------------------------------------------------------------
# Lightweight internal backing store (module-local)
# -------------------------------------------------------------
static var _enabled: bool = true
static var _cursor: int = 0
static var _ring: Array = []  # Array[Dictionary], untyped to avoid generic warnings
static var _level: int = 1        # 0=OFF, 1=INFO, 2=DEBUG, 3=LIVE
static var _max_events: int = CAPACITY

# -------------------------------------------------------------
# Public API used by SaveService
# -------------------------------------------------------------

## Default telemetry block for a brand new game (used by SaveService.new_game)
static func pack_default() -> Dictionary:
	return {
		"ring": [],
		"cursor": 0,
		"enabled": true,
		"level": 1,
		"max_events": CAPACITY
	}

## Export current runtime telemetry state.
static func pack_current() -> Dictionary:
	var ring_copy: Array = _ring.duplicate(true) as Array
	return {
		"ring": ring_copy,
		"cursor": _cursor,
		"enabled": _enabled,
		"level": _level,
		"max_events": _max_events
	}

## Import a saved telemetry block back into runtime (sanitized).
static func unpack(d: Dictionary) -> void:
	var res: Dictionary = _validate(d)
	if not bool(res.get("ok", false)):
		push_warning("TelemetryIO.unpack: invalid data: %s" % String(res.get("message", "")))
		return
	# sanitize/coerce and clamp
	_enabled = bool(d.get("enabled", true))
	_cursor = int(d.get("cursor", 0))
	if _cursor < 0:
		_cursor = 0
	# Import verbosity level and max size (optional in older saves)
	_level = int(d.get("level", 1))
	if _level < 0: _level = 0
	if _level > 3: _level = 3
	_max_events = int(d.get("max_events", CAPACITY))
	if _max_events < 1: _max_events = 1
	if _max_events > CAPACITY: _max_events = CAPACITY
	var ring_in: Array = (d.get("ring", []) as Array)
	# Keep at most _max_events entries; prefer newest entries if oversized
	var cap: int = min(_max_events, CAPACITY)
	var trimmed: Array = ring_in
	if ring_in.size() > cap:
		trimmed = ring_in.slice(ring_in.size() - cap, ring_in.size())
	# Ensure only dictionaries are stored
	var clean: Array = []
	for ev in trimmed:
		if typeof(ev) == TYPE_DICTIONARY:
			clean.append(ev)
	_ring = clean

# -------------------------------------------------------------
# Event logging API (does not affect game logic)
# -------------------------------------------------------------

## Turn logging on/off at runtime.
static func set_enabled(v: bool) -> void:
	_enabled = v

static func is_enabled() -> bool:
	return _enabled

## Record a generic event into the ring. payload is merged and may override defaults.
static func log_event(event_type: String, payload: Dictionary, importance: int = 1) -> void:
	if not _enabled:
		return
	if importance > _level:
		return
	var ev: Dictionary = _make_event(event_type, payload)
	var cap: int = min(_max_events, CAPACITY)
	if cap < 1:
		cap = 1
	var idx: int = _cursor % cap
	if _ring.size() < cap:
		# Grow or overwrite within current bounds
		if idx < _ring.size():
			_ring[idx] = ev
		else:
			_ring.append(ev)
	else:
		# Full: overwrite oldest slot (true ring behavior)
		_ring[idx] = ev
	# advance cursor for every recorded event
	_cursor += 1

## Verbosity controls
static func set_level(level: int) -> void:
	_level = clampi(level, 0, 3)

static func get_level() -> int:
	return _level

## Capacity controls (hard-capped by CAPACITY)
static func set_max(max_events: int) -> void:
	_max_events = max(1, min(max_events, CAPACITY))
	# If current ring exceeds new cap, drop oldest
	var cap: int = min(_max_events, CAPACITY)
	if _ring.size() > cap:
		_ring = _ring.slice(_ring.size() - cap, _ring.size())
		# Reset cursor modulo cap to avoid huge modulo costs; keep monotonic nature by not resetting to 0

static func get_max() -> int:
	return _max_events

## Readback helpers
static func tail(n: int) -> Array:
	var cap: int = min(_max_events, CAPACITY)
	var k: int = max(0, min(n, cap))
	if _ring.size() <= k:
		return _ring.duplicate(true)
	return _ring.slice(_ring.size() - k, _ring.size())

static func clear() -> void:
	_ring.clear()
	_cursor = 0

## Convenience: log realm enter
static func log_realm_enter(realm_id: String, stage_index: int) -> void:
	var p: Dictionary = {
		"realm": realm_id,
		"stage": stage_index
	}
	log_event("realm_enter", p)

## Convenience: log encounter end with a seed@cursor tag (string formed by caller)
static func log_encounter_end(realm_id: String, stage_index: int, encounter_index: int, seed_cursor: String) -> void:
	var p: Dictionary = {
		"realm": realm_id,
		"stage": stage_index,
		"encounter": encounter_index,
		"seed": seed_cursor,
		"notes": "ok"
	}
	log_event("encounter_end", p)

# -------------------------------------------------------------
# Internals
# -------------------------------------------------------------

static func _make_event(t: String, payload: Dictionary) -> Dictionary:
	# Minimal, deterministic-friendly shape with ISO8601Z timestamp
	var ev: Dictionary = {
		"t": t,
		"utc": Time.get_datetime_string_from_system(true)
	}
	for k in payload.keys():
		ev[k] = payload[k]
	return ev

# -------------------------------------------------------------
# Validation (schema-inspired, fast, no deps)
# -------------------------------------------------------------
static func _validate(d: Dictionary) -> Dictionary:
	for k in ["ring","cursor","enabled"]:
		if not d.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	# ring must be an array of objects (free-form events allowed)
	if typeof(d.get("ring")) != TYPE_ARRAY:
		return {"ok": false, "message": "ring must be array"}
	for ev in (d.get("ring") as Array):
		if typeof(ev) != TYPE_DICTIONARY:
			return {"ok": false, "message": "ring must contain objects"}

	# cursor must be int-like >= 0 (accept numeric and coerce)
	var cur_v: Variant = d.get("cursor")
	var cur_i: int = int(cur_v)
	if cur_i < 0:
		return {"ok": false, "message": "cursor must be int >= 0"}

	# enabled must be boolean-ish (accept 0/1)
	var en_v: Variant = d.get("enabled")
	var en_t: int = typeof(en_v)
	var en_ok: bool = (en_t == TYPE_BOOL) or (en_t == TYPE_INT) or (en_t == TYPE_FLOAT)
	if not en_ok:
		return {"ok": false, "message": "enabled must be boolean"}

	# Optional: level in [0..3]
	if d.has("level"):
		var lvl: int = int(d.get("level"))
		if lvl < 0 or lvl > 3:
			return {"ok": false, "message": "level must be 0..3"}

	# Optional: max_events in [1..CAPACITY]
	if d.has("max_events"):
		var mx: int = int(d.get("max_events"))
		if mx < 1 or mx > CAPACITY:
			return {"ok": false, "message": "max_events must be 1..%d" % CAPACITY}

	return {"ok": true, "message": "OK"}
