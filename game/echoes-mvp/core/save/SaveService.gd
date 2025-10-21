extends Node

# SaveService — MVP scaffold (Task 3)
# -------------------------------------------------------------
# Purpose:
#   - Own the save/load/migrate/validate flow for the whole game.
#   - Assemble a ROOT dictionary from module IO adapters.
#   - Write/read JSON atomically in user storage.
#   - Keep timestamps and schema fields aligned with docs/schemas/json/root.schema.json
#
# Notes:
#   - This service is already registered as an AutoLoad (per your setup).
#   - RNG book lives under `campaign_run.rng_book` (NOT at root).
#   - Validation is intentionally lightweight for MVP; we’ll harden later.
#   - To avoid parse errors before module adapters exist (Task 4), we ship
#     TEMP stubs below. Remove the stubs once real adapters are added.
# -------------------------------------------------------------

const SAVE_PATH := "user://echoes.save"
const BAK_PATH  := "user://echoes.bak"
const TMP_PATH  := "user://echoes.tmp"

# These should mirror the schema and your build/versioning process.
const SCHEMA_VERSION := "13.0.0"
const BUILD_ID := "0.1.0-mvp"
const DEBUG_SAVE := false

# Cached root metadata (helps preserve created_utc across saves)
var _created_utc: String = ""
var _last_saved_utc: String = ""
var _content_hash: String = ""   # (optional) leave empty for now
var _integrity_signed: bool = false

# -------------------------------------------------------------
# Lifecycle hooks
# -------------------------------------------------------------
func _ready() -> void:
	# No-op on boot. You can call new_game() from a menu.
	pass

# -------------------------------------------------------------
# Public API
# -------------------------------------------------------------
## Create a fresh in-memory game root and unpack into runtime singletons.
## `campaign_seed` should come from your seeded/PCG32 system.
func new_game(campaign_seed: int) -> void:
	var root: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"build_id": BUILD_ID,
		"created_utc": _now_iso8601_utc(),
		"last_saved_utc": "",
		# Modules (all pack_* functions are pure — no IO here)
		"player_profile": PlayerProfileIO.pack_default(),
		"campaign_run": CampaignRunIO.pack_new(campaign_seed),
		"sanctum_state": SanctumIO.pack_default(),
		"hero_roster": HeroesIO.pack_default(),
		"realm_states": RealmsIO.pack_default(),
		"economy": EconomyIO.pack_default(),
		"research_crafting": ResearchCraftingIO.pack_default(),
		"legacy": LegacyIO.pack_default(),
		"telemetry_log": TelemetryIO.pack_default(),
		# Meta
		"content_hash": _content_hash,
		"integrity": { "signed": _integrity_signed }
	}

	_created_utc = root["created_utc"]
	_last_saved_utc = root["last_saved_utc"]
	_apply_unpack(root)  # populate runtime from this root

## Write the current game state to disk. Returns true on success.
func save_game(path: String = SAVE_PATH) -> bool:
	var root: Dictionary = _assemble_root()
	# Bump timestamp before validation so it’s included in the JSON
	_last_saved_utc = _now_iso8601_utc()
	root["last_saved_utc"] = _last_saved_utc

	var check: Dictionary = validate(root)
	if not bool(check.get("ok", false)):
		push_warning("Save validation failed: %s" % check["message"])
		return false

	var json_text: String = JSON.stringify(root, "\t")
	if DEBUG_SAVE:
		push_warning("[SaveService] save_game: validate ok; writing primary")
	if not _atomic_write(path, json_text):
		push_warning("Save write failed: could not commit file")
		return false

	if DEBUG_SAVE:
		push_warning("[SaveService] save_game: primary written; rotating backup")
	# Rotate backup to last-known-good
	if FileAccess.file_exists(BAK_PATH):
		DirAccess.remove_absolute(BAK_PATH)
	var copy_err := DirAccess.copy_absolute(path, BAK_PATH)
	if copy_err != OK:
		push_warning("Backup copy failed with code: %s" % str(copy_err))
	if DEBUG_SAVE:
		push_warning("[SaveService] save_game: backup done")
	return true

## Load a save from disk and unpack it into runtime. Returns true on success.
func load_game(path: String = SAVE_PATH) -> bool:
	if DEBUG_SAVE:
		push_warning("[SaveService] load_game: starting load %s" % path)
	# Load primary file
	if not FileAccess.file_exists(path):
		push_warning("[SaveService] load_game: no save at %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[SaveService] load_game: open failed %s" % path)
		return false
	var text: String = f.get_as_text(); f.close()
	if DEBUG_SAVE:
		push_warning("[SaveService] load_game: read %d bytes" % text.length())
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveService] load_game: JSON corrupt; trying backup…")
		return _try_load_backup()
	var save_dict: Dictionary = parsed as Dictionary
	if DEBUG_SAVE:
		push_warning("[SaveService] load_game: parsed keys %s" % str(save_dict.keys()))
	var check: Dictionary = validate(save_dict)
	if not bool(check.get("ok", false)):
		push_warning("[SaveService] load_game: invalid save: %s; trying backup…" % String(check.get("message", "")))
		return _try_load_backup()
	# Migrate, check migration block, re-validate before unpack
	save_dict = migrate(save_dict)
	# If migration blocked (returns empty dict) fall back to backup
	if save_dict.size() == 0:
		push_warning("[SaveService] load_game: migration blocked; trying backup…")
		return _try_load_backup()
	# Optional: re-validate migrated content before unpacking
	var mcheck: Dictionary = validate(save_dict)
	if not bool(mcheck.get("ok", false)):
		push_warning("[SaveService] load_game: migrated save invalid: %s; trying backup…" % String(mcheck.get("message", "")))
		return _try_load_backup()
	if DEBUG_SAVE:
		push_warning("[SaveService] load_game: applying unpack…")
	_apply_unpack(save_dict)
	_created_utc = save_dict.get("created_utc", "")
	_last_saved_utc = save_dict.get("last_saved_utc", "")
	_content_hash = save_dict.get("content_hash", "")
	_integrity_signed = (save_dict.get("integrity", {}) as Dictionary).get("signed", false)
	if DEBUG_SAVE:
		push_warning("[SaveService] load_game: success")
	return true

## Return a full root dictionary assembled from current runtime state.
func snapshot() -> Dictionary:
	return _assemble_root()

# -------------------------------------------------------------
# Validation & Migration (MVP — light checks)
# -------------------------------------------------------------
## Validate a ROOT dictionary roughly against the v0.1 schema.
## We keep it simple so it’s fast and has zero deps.
func validate(root: Dictionary) -> Dictionary:
	# --- Required top-level keys ---
	var required: Array = [
		"schema_version","build_id","player_profile","campaign_run",
		"sanctum_state","hero_roster","realm_states","economy",
		"research_crafting","legacy","telemetry_log","content_hash","integrity",
		"created_utc","last_saved_utc"
	]
	for k in required:
		if not root.has(k):
			return {"ok": false, "message": "Missing key: %s" % k}

	# --- Types sanity ---
	var cr: Dictionary = (root.get("campaign_run", {}) as Dictionary)
	if typeof(cr) != TYPE_DICTIONARY:
		return {"ok": false, "message": "campaign_run must be object"}
	if not cr.has("rng_book"):
		return {"ok": false, "message": "campaign_run.rng_book missing (must not be at root)"}

	# --- Validate rng_book ---
	var rng_book: Dictionary = (cr.get("rng_book", {}) as Dictionary)
	var rb_chk: Dictionary = _validate_rng_book(rng_book)
	if not bool(rb_chk.get("ok", false)):
		return rb_chk

	# --- Emotions range (sanctum_state.emotions.* in 0..100) ---
	var sanctum: Dictionary = (root.get("sanctum_state", {}) as Dictionary)
	var emotions: Dictionary = (sanctum.get("emotions", {}) as Dictionary)
	for field in ["faith","harmony","favor"]:
		var v: int = int(emotions.get(field, -1))
		if v < 0 or v > 100:
			return {"ok": false, "message": "sanctum_state.emotions.%s out of range" % field}

	# --- Telemetry shape ---
	var tel: Dictionary = (root.get("telemetry_log", {}) as Dictionary)
	if typeof(tel) != TYPE_DICTIONARY:
		return {"ok": false, "message": "telemetry_log must be object"}
	# ring must be an array
	if not tel.has("ring"):
		return {"ok": false, "message": "telemetry_log.ring must be array"}
	if typeof(tel["ring"]) != TYPE_ARRAY:
		return {"ok": false, "message": "telemetry_log.ring must be array"}
	# cursor: allow numeric types, then coerce and range-check
	if not tel.has("cursor"):
		return {"ok": false, "message": "telemetry_log.cursor must be int >= 0"}
	var cur_val: Variant = tel["cursor"]
	var cur_i: int = int(cur_val)
	if cur_i < 0:
		return {"ok": false, "message": "telemetry_log.cursor must be int >= 0"}
	# enabled: allow bool or numeric 0/1; coerce acceptance based on type
	if not tel.has("enabled"):
		return {"ok": false, "message": "telemetry_log.enabled must be boolean"}
	var en_val: Variant = tel["enabled"]
	var en_is_bool: bool = (typeof(en_val) == TYPE_BOOL)
	var en_is_num: bool = (typeof(en_val) == TYPE_INT or typeof(en_val) == TYPE_FLOAT)
	if not en_is_bool and not en_is_num:
		return {"ok": false, "message": "telemetry_log.enabled must be boolean"}
	# ring elements sanity
	for ev in (tel["ring"] as Array):
		if typeof(ev) != TYPE_DICTIONARY:
			return {"ok": false, "message": "telemetry_log.ring must contain objects"}

	# --- Realm states minimal check ---
	var realms: Array = (root.get("realm_states", []) as Array)
	for i in realms.size():
		var rs: Variant = realms[i]
		if typeof(rs) != TYPE_DICTIONARY:
			return {"ok": false, "message": "realm_states[%d] must be object" % i}
		var rd: Dictionary = rs as Dictionary
		for req in ["realm_id","tier","realm_seed","stage_index","encounter_cursor"]:
			if not rd.has(req):
				return {"ok": false, "message": "realm_states[%d] missing %s" % [i, req]}

	# --- Hero roster presence + id uniqueness (lightweight) ---
	var roster: Dictionary = (root.get("hero_roster", {}) as Dictionary)
	var id_set: Dictionary = {}
	for bucket in ["active","recovering","retired","fallen"]:
		var arr: Array = (roster.get(bucket, []) as Array)
		for h in arr:
			if typeof(h) != TYPE_DICTIONARY:
				return {"ok": false, "message": "hero_roster.%s must contain objects" % bucket}
			var hd: Dictionary = h as Dictionary
			var hid: String = String(hd.get("id", ""))
			if hid == "":
				return {"ok": false, "message": "hero without id in %s" % bucket}
			if id_set.has(hid):
				return {"ok": false, "message": "duplicate hero id: %s" % hid}
			id_set[hid] = true

	# --- Cross-module referential integrity (legacy → heroes) ---
	var legacy: Dictionary = (root.get("legacy", {}) as Dictionary)
	var frags: Array = (legacy.get("fragments", []) as Array)
	for idx in frags.size():
		var fr: Variant = frags[idx]
		if typeof(fr) != TYPE_DICTIONARY:
			return {"ok": false, "message": "legacy.fragments[%d] must be object" % idx}
		var f: Dictionary = fr as Dictionary
		var ref_id: String = String(f.get("hero_id", ""))
		if ref_id != "" and not id_set.has(ref_id):
			return {"ok": false, "message": "legacy.fragments[%d].hero_id not found in hero_roster: %s" % [idx, ref_id]}

	# --- Date format quick check ---
	var cu: String = String(root.get("created_utc", ""))
	var lu: String = String(root.get("last_saved_utc", ""))
	if cu == "" or not _looks_like_iso8601z(cu):
		return {"ok": false, "message": "created_utc not ISO8601Z (YYYY-MM-DDTHH:MM:SSZ)"}
	if lu != "" and not _looks_like_iso8601z(lu):
		return {"ok": false, "message": "last_saved_utc not ISO8601Z (YYYY-MM-DDTHH:MM:SSZ)"}

	return {"ok": true, "message": "OK"}

func _validate_rng_book(rb: Dictionary) -> Dictionary:
	for k in ["campaign_seed","subseeds","cursors"]:
		if not rb.has(k):
			return {"ok": false, "message": "rng_book missing %s" % k}
	if typeof(rb["campaign_seed"]) != TYPE_STRING:
		return {"ok": false, "message": "rng_book.campaign_seed must be string"}
	if typeof(rb["subseeds"]) != TYPE_DICTIONARY:
		return {"ok": false, "message": "rng_book.subseeds must be object"}
	if typeof(rb["cursors"]) != TYPE_DICTIONARY:
		return {"ok": false, "message": "rng_book.cursors must be object"}
	# cursors must be ints >= 0; subseeds must be strings
	for key in (rb["subseeds"] as Dictionary).keys():
		if typeof((rb["subseeds"] as Dictionary)[key]) != TYPE_STRING:
			return {"ok": false, "message": "rng_book.subseeds[%s] must be string" % String(key)}
	for key in (rb["cursors"] as Dictionary).keys():
		var c: int = int((rb["cursors"] as Dictionary)[key])
		if c < 0:
			return {"ok": false, "message": "rng_book.cursors[%s] must be >= 0" % String(key)}
	return {"ok": true, "message": "OK"}

## Migrations: versioning & migration stub (Task 7)
func migrate(root: Dictionary) -> Dictionary:
	# --- Versioning and migration stub (Task 7) ---
	var incoming_version_str: String = String(root.get("schema_version", "0.0.0"))
	var incoming_parts: Array = incoming_version_str.split(".")
	var current_parts: Array = SCHEMA_VERSION.split(".")
	if incoming_parts.size() < 3:
		push_warning("[Migrate] Invalid schema_version format in save: %s" % incoming_version_str)
		return root

	var incoming_major: int = int(incoming_parts[0])
	var incoming_minor: int = int(incoming_parts[1])
	var current_major: int = int(current_parts[0])
	var current_minor: int = int(current_parts[1])

	# Future or higher-major version → block load
	if incoming_major > current_major:
		push_warning("[Migrate] Save from future major version (%s > %s). Load blocked." % [incoming_version_str, SCHEMA_VERSION])
		return {}
	if incoming_major < current_major:
		push_warning("[Migrate] Save from older major version (%s < %s). Requires manual migrator." % [incoming_version_str, SCHEMA_VERSION])
		return {}

	# Same major, older minor → allow but warn and enrich missing optional fields
	if incoming_minor < current_minor:
		push_warning("[Migrate] Minor schema mismatch (%s < %s). Applying default enrichment." % [incoming_version_str, SCHEMA_VERSION])
		# Inject optional defaults if missing (safe additions only)
		var tel: Dictionary = root.get("telemetry_log", {}) as Dictionary
		if not tel.has("enabled"):
			tel["enabled"] = true
		if not tel.has("cursor"):
			tel["cursor"] = 0
		if not tel.has("ring"):
			tel["ring"] = []
		root["telemetry_log"] = tel

	# Otherwise same version (or same major + same minor) → pass through
	return root

# -------------------------------------------------------------
# Internal helpers
# -------------------------------------------------------------
func _assemble_root() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"build_id": BUILD_ID,
		"created_utc": _created_utc if _created_utc != "" else _now_iso8601_utc(),
		"last_saved_utc": _last_saved_utc,
		"player_profile": PlayerProfileIO.pack_current(),
		"campaign_run": CampaignRunIO.pack_current(),
		"sanctum_state": SanctumIO.pack_current(),
		"hero_roster": HeroesIO.pack_current(),
		"realm_states": RealmsIO.pack_current(),
		"economy": EconomyIO.pack_current(),
		"research_crafting": ResearchCraftingIO.pack_current(),
		"legacy": LegacyIO.pack_current(),
		"telemetry_log": TelemetryIO.pack_current(),
		"content_hash": _content_hash,
		"integrity": { "signed": _integrity_signed }
	}

func _apply_unpack(root: Dictionary) -> void:
	if DEBUG_SAVE: push_warning("[SaveService] unpack: player_profile")
	PlayerProfileIO.unpack(root["player_profile"] as Dictionary)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: campaign_run")
	CampaignRunIO.unpack(root["campaign_run"] as Dictionary)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: sanctum_state")
	SanctumIO.unpack(root["sanctum_state"] as Dictionary)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: hero_roster")
	HeroesIO.unpack(root["hero_roster"] as Dictionary)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: realm_states")
	RealmsIO.unpack(root["realm_states"] as Array)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: economy")
	EconomyIO.unpack(root["economy"] as Dictionary)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: research_crafting")
	ResearchCraftingIO.unpack(root["research_crafting"] as Dictionary)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: legacy")
	LegacyIO.unpack(root["legacy"] as Dictionary)
	if DEBUG_SAVE: push_warning("[SaveService] unpack: telemetry_log")
	TelemetryIO.unpack(root["telemetry_log"] as Dictionary)

func _atomic_write(path: String, text: String) -> bool:
	# Write to a temporary file, flush, then atomically rename into place.
	# This prevents half-written saves if the app crashes mid-write.
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(TMP_PATH, path) == OK

func _try_load_backup() -> bool:
	if DEBUG_SAVE: push_warning("[SaveService] _try_load_backup: start")
	if FileAccess.file_exists(BAK_PATH):
		var bf := FileAccess.open(BAK_PATH, FileAccess.READ)
		if bf != null:
			var text: String = bf.get_as_text(); bf.close()
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				var dict: Dictionary = parsed as Dictionary
				var check: Dictionary = validate(dict)
				if not bool(check.get("ok", false)):
					return false
				# Migrate backup too; if blocked or invalid after migration, fail
				dict = migrate(dict)
				if dict.size() == 0:
					return false
				var mcheck: Dictionary = validate(dict)
				if not bool(mcheck.get("ok", false)):
					return false
				_apply_unpack(dict)
				_created_utc = dict.get("created_utc", "")
				_last_saved_utc = dict.get("last_saved_utc", "")
				_content_hash = dict.get("content_hash", "")
				_integrity_signed = (dict.get("integrity", {}) as Dictionary).get("signed", false)
				if DEBUG_SAVE: push_warning("[SaveService] _try_load_backup: success")
				return true
	push_warning("[SaveService] _try_load_backup: missing or invalid")
	return false

func _now_iso8601_utc() -> String:
	# Build an ISO8601 UTC string matching the schema regex: YYYY-MM-DDTHH:MM:SSZ
	var dt := Time.get_datetime_dict_from_system(true)  # UTC
	var y := str(dt.year)
	var mo := str(dt.month).pad_zeros(2)
	var d := str(dt.day).pad_zeros(2)
	var h := str(dt.hour).pad_zeros(2)
	var mi := str(dt.minute).pad_zeros(2)
	var s := str(dt.second).pad_zeros(2)
	return "%s-%s-%sT%s:%s:%sZ" % [y, mo, d, h, mi, s]


func _looks_like_iso8601z(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	return re.search(s) != null

# -------------------------------------------------------------
# Diagnostic: load stage breakdown (non-invasive, does not mutate state)
# -------------------------------------------------------------
func diagnose_load(path: String = SAVE_PATH) -> Dictionary:
	# Returns a map describing where load would fail without mutating state.
	var out: Dictionary = {"ok": false, "stage": "start", "message": ""}
	out["path"] = path
	if not FileAccess.file_exists(path):
		out["stage"] = "exists"; out["message"] = "missing"; return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["stage"] = "open"; out["message"] = "open failed"; return out
	var text: String = f.get_as_text(); f.close()
	out["stage"] = "read"; out["bytes"] = text.length()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		out["stage"] = "parse"; out["message"] = "json not dict"; return out
	var save_dict: Dictionary = parsed as Dictionary
	out["stage"] = "parsed"; out["keys"] = save_dict.keys()
	var check: Dictionary = validate(save_dict)
	if not bool(check.get("ok", false)):
		out["stage"] = "validate"; out["message"] = String(check.get("message", "")); return out
	out["stage"] = "ready"; out["ok"] = true
	return out

func _bad(msg: String) -> Dictionary:
	return {"ok": false, "message": msg}
