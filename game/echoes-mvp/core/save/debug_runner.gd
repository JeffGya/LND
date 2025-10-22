extends Node
# DebugRunner — Save/RNG DoD verifier
# Runs on scene start. Prints PASS/FAIL lines to the Output panel.

const SEED := 0xA2B94D10
const SAVE_PATH := "user://echoes.save"
const BAK_PATH  := "user://echoes.bak"

func _ready() -> void:
	print("=== DebugRunner starting ===")
	var ok_all: bool = true

	# 1) NEW GAME
	SaveService.new_game(SEED)
	print("New game ✓")

	# 2) RNG determinism – draw some values from a named stream
	var stream_key := "combat/battle/alpha"
	var a: Array[int] = _draw_n(stream_key, 10)  # cursor now 10
	print("RNG first 10:", a)
	# Take an rng_book snapshot at cursor 10
	var rb_pre := RNCatalogIO.pack_current()
	print("Cursor before save (", stream_key, "): ", int(rb_pre.get("cursors", {}).get(stream_key, -1)))

	# Compute expected continuation **without** changing live state:
	# Re-hydrate from the saved rng_book snapshot, draw 10 into expected_after,
	# then restore live RNG state back to cursor 10 by unpacking rb_pre again.
	RNCatalogIO.unpack(rb_pre)
	var expected_after: Array[int] = _draw_n(stream_key, 10)  # what we expect after reload
	RNCatalogIO.unpack(rb_pre)  # restore cursor back to 10 for a fair save

	# 3) SNAPSHOT *RIGHT BEFORE SAVE* (captures rng_book cursor at 10)
	var pre: Dictionary = SaveService.snapshot()
	print("Snapshot pre-save ✓ (keys=", pre.keys(), ")")

	# 3b) TELEMETRY SMOKE — log a couple of events before saving
	var pre_cursor: int = int(rb_pre.get("cursors", {}).get(stream_key, -1))
	var seed_tag := "%s@%d" % [stream_key, pre_cursor]
	TelemetryIO.log_realm_enter("ase-forest", 0)
	TelemetryIO.log_encounter_end("ase-forest", 0, 0, seed_tag)

	# 4) SAVE
	var ok_save: bool = SaveService.save_game()
	print("Save ok:", ok_save)
	# Inspect files on disk after save
	_inspect_save(SAVE_PATH)
	_inspect_save(BAK_PATH)
	print("diagnose_load:", SaveService.diagnose_load(SAVE_PATH))
	ok_all = ok_all and ok_save

	# 6) LOAD (should restore rng_book & other modules)
	var ok_load: bool = SaveService.load_game()
	print("Load ok:", ok_load)
	ok_all = ok_all and ok_load
	# Show cursor after load (should match pre-save cursor)
	var rb_post_load := RNCatalogIO.pack_current()
	print("Cursor after load (", stream_key, "): ", int(rb_post_load.get("cursors", {}).get(stream_key, -1)))

	# Telemetry ring tail after load
	var tel_after: Dictionary = TelemetryIO.pack_current()
	var ring_after: Array = tel_after.get("ring", []) as Array
	var tail_ev: Dictionary = {} if ring_after.size() == 0 else (ring_after[ring_after.size() - 1] as Dictionary)
	print("Telemetry tail:", tail_ev)

	# 7) ROUNDTRIP DEEP-EQUAL (ignore timestamps) — do this BEFORE drawing more
	var post: Dictionary = SaveService.snapshot()
	var rh: Dictionary = post.get("replay_header", {}) as Dictionary
	print("Replay header:", rh)
	var roundtrip_ok: bool = _deep_equal_ignore_meta(pre, post)
	print("Roundtrip deep-equal (ignoring timestamps) →", ("PASS" if roundtrip_ok else "FAIL"))
	ok_all = ok_all and roundtrip_ok

	# 8) RNG after load — should match the expected continuation
	var after_load: Array[int] = _draw_n(stream_key, 10)
	var rng_ok: bool = _arrays_equal(expected_after, after_load)
	print("Determinism (continuation across save/load) →", ("PASS" if rng_ok else "FAIL"), ": ", after_load)
	ok_all = ok_all and rng_ok

	# 9) VALIDATION CHECK
	var v: Dictionary = SaveService.validate(post)
	var validate_ok: bool = bool(v.get("ok", false))
	print("Validate():", v)
	ok_all = ok_all and validate_ok

	# 10) CORRUPTION SAFETY — only run if we have a good .bak present
	print("Exists .save:", FileAccess.file_exists(SAVE_PATH), ", Exists .bak:", FileAccess.file_exists(BAK_PATH))
	var did_corrupt: bool = false
	if FileAccess.file_exists(BAK_PATH):
		# overwrite primary save with junk, then attempt load (should fall back to .bak)
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string("{ not: json")
			f.flush(); f.close()
			did_corrupt = true
			var ok_recover: bool = SaveService.load_game()
			print("Backup auto-recovery after corruption →", ("PASS" if ok_recover else "FAIL"))
			ok_all = ok_all and ok_recover
	else:
		print("(Skip corruption test — no .bak yet)")

	# 11) MIGRATION TESTS (Task 7) — SAFE: uses a temp path and falls back to .bak on failure
	var mig_ok_all: bool = true
	var tmp_ver_path := "user://echoes.version_test"
	# Build a future-major version string based on what's on disk
	var current_on_disk := _read_schema_version(SAVE_PATH)
	var future_major := _bump_major(current_on_disk)
	# Write a temp file with future-major schema_version and try to load it (should fallback to .bak and succeed)
	var wrote_tmp := _write_schema_version_to(SAVE_PATH, tmp_ver_path, future_major)
	if wrote_tmp:
		var ok_future_major := SaveService.load_game(tmp_ver_path)
		print("Migration: future major (", future_major, ") fallback →", ("PASS" if ok_future_major else "FAIL"))
		mig_ok_all = mig_ok_all and ok_future_major
		# Clean up temp file
		if FileAccess.file_exists(tmp_ver_path):
			DirAccess.remove_absolute(tmp_ver_path)
	else:
		print("Migration test skipped: couldn't write temp versioned file")

	# Summary
	print("=== DoD Summary:")
	print("Determinism:", rng_ok)
	print("Roundtrip:", roundtrip_ok)
	print("Validation:", validate_ok)
	if did_corrupt:
		print("Backup Recovery: checked")
	else:
		print("Backup Recovery: skipped (no .bak)")
	print("OVERALL:", ("PASS" if ok_all else "FAIL"))

func _inspect_save(path: String) -> void:
	var exists := FileAccess.file_exists(path)
	print("Inspect ", path, " exists:", exists)
	if not exists:
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var readable := f != null
	print("  readable:", readable)
	if not readable:
		return
	var text := f.get_as_text(); f.close()
	print("  size:", text.length())
	var parsed: Variant = JSON.parse_string(text)
	var is_dict: bool = (typeof(parsed) == TYPE_DICTIONARY)
	print("  parse:", ("DICT" if is_dict else str(typeof(parsed))))
	if is_dict:
		var keys: Array = (parsed as Dictionary).keys()
		print("  keys:", keys)
		var cr: Dictionary = ((parsed as Dictionary).get("campaign_run", {}) as Dictionary)
		var has_rb: bool = cr.has("rng_book")
		print("  campaign_run has rng_book:", has_rb)
		if has_rb:
			var rb: Dictionary = (cr.get("rng_book", {}) as Dictionary)
			print("    rng_book keys:", rb.keys())
		var tel: Dictionary = ((parsed as Dictionary).get("telemetry_log", {}) as Dictionary)
		print("  telemetry_log.cursor:", int(tel.get("cursor", -999)))
		var rh: Dictionary = ((parsed as Dictionary).get("replay_header", {}) as Dictionary)
		print("  replay_header keys:", rh.keys())

# --- helpers ---

func _draw_n(key: String, n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		var v: int = RNCatalogIO.next_u32(key)
		out.append(v)
	return out

func _arrays_equal(a: Array[int], b: Array[int]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true

func _deep_equal_ignore_meta(pre: Dictionary, post: Dictionary) -> bool:
	var a := pre.duplicate(true)
	var b := post.duplicate(true)
	# Ignore timestamps
	a.erase("created_utc"); a.erase("last_saved_utc")
	b.erase("created_utc"); b.erase("last_saved_utc")
	# Ignore observational/derived blocks that can differ after JSON roundtrip
	a.erase("telemetry_log"); a.erase("replay_header")
	b.erase("telemetry_log"); b.erase("replay_header")
	# Ignore meta that legitimately changes across save boundaries
	a.erase("content_hash"); a.erase("integrity")
	b.erase("content_hash"); b.erase("integrity")
	# JSON compare for simplicity
	var sa: String = JSON.stringify(a)
	var sb: String = JSON.stringify(b)
	return sa == sb


# --- MIGRATION TEST HELPERS ---

func _read_schema_version(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "0.0.0"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "0.0.0"
	var txt := f.get_as_text(); f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "0.0.0"
	return String((parsed as Dictionary).get("schema_version", "0.0.0"))

func _bump_major(ver: String) -> String:
	var parts := ver.split(".")
	if parts.size() < 3:
		return "1.0.0"
	var maj: int = int(parts[0]) + 1
	return String.num_int64(maj) + ".0.0"

func _write_schema_version_to(_src_path: String, dst_path: String, new_ver: String) -> bool:
	# Build from the current in-memory snapshot to avoid read/parse failures
	var root: Dictionary = SaveService.snapshot()
	root["schema_version"] = new_ver
	var out_txt: String = JSON.stringify(root, "\t")
	# Write atomically: write to a temp, then rename
	var tmp_path := dst_path + ".tmp"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	var wf := FileAccess.open(tmp_path, FileAccess.WRITE)
	if wf == null:
		return false
	wf.store_string(out_txt)
	wf.flush(); wf.close()
	if FileAccess.file_exists(dst_path):
		DirAccess.remove_absolute(dst_path)
	return DirAccess.rename_absolute(tmp_path, dst_path) == OK
