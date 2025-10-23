extends Node
class_name DebugConsole

## Lightweight debug console (headless-friendly)
## Usage:
##  - Add this node to any scene or run headless.
##  - Call run_command("/seed_info") etc.
##  - Connect to `line_printed` to mirror output in a UI (RichTextLabel, etc.).
##  - Later, you can export a NodePath to hook a RichTextLabel.

signal line_printed(text: String)
signal command_executed(cmd: String, ok: bool)

var _log_lines: Array[String] = []
var _commands := {}

# --- Live test session state for /test_economy live mode ---
var _econ_live_active: bool = false
var _econ_live_sum: float = 0.0
var _econ_live_count: int = 0
var _econ_live_service: Node = null

# Shared preloads
const Seedbook = preload("res://core/seed/Seedbook.gd")
const AseTickService = preload("res://core/economy/AseTickService.gd")

# Optional: attach a label later without hard dependency
@export var output_label_path: NodePath
@export var input_field_path: NodePath
@onready var _output_label: Node = get_node_or_null(output_label_path)
@onready var _input_field: LineEdit = get_node_or_null(input_field_path)

func _ready() -> void:
	_register_default_commands()
	# Resolve label again if path was set in-scene and ensure input UI exists
	if output_label_path != NodePath("") and _output_label == null:
		_output_label = get_node_or_null(output_label_path)
	_ensure_input_ui()
	_print_line("DebugConsole ready. Type /help")

# --- Public API ---
func run_command(input: String) -> void:
	var cmd := input.strip_edges()
	if cmd == "":
		return
	if not cmd.begins_with("/"):
		_print_line(cmd)
		emit_signal("command_executed", cmd, true)
		return
	var cmd_name := cmd.split(" ", false, 1)[0]
	var args := []
	if cmd.find(" ") != -1:
		args = cmd.substr(cmd.find(" ") + 1).split(" ")
	if _commands.has(cmd_name):
		var fn: Callable = _commands[cmd_name]
		var ok: bool = true
		var err: String = ""
		if typeof(fn) == TYPE_CALLABLE:
			var status: Variant = fn.call(args)
			if typeof(status) == TYPE_BOOL:
				ok = bool(status)
			elif typeof(status) == TYPE_INT:
				ok = int(status) == 0
		else:
			ok = false
			err = "Invalid command handler"
		if not ok and err != "":
			_print_line("Error: %s" % err)
		emit_signal("command_executed", cmd_name, ok)
	else:
		_print_line("Unknown command: %s (try /help)" % cmd_name)
		emit_signal("command_executed", cmd_name, false)

func get_log_text() -> String:
	return "\n".join(_log_lines)

func clear() -> void:
	_log_lines.clear()
	if _output_label and _output_label.has_method("clear"):
		_output_label.call("clear")

# --- Internals ---
func _print_line(s: String) -> void:
	_log_lines.append(s)
	print(s)
	emit_signal("line_printed", s)
	if _output_label and _output_label.has_method("append_bbcode"):
		_output_label.call("append_bbcode", s + "\n")
	elif _output_label and _output_label.has_method("add_text"):
		_output_label.call("add_text", s + "\n")
	elif _output_label and _output_label.has_method("append_text"):
		_output_label.call("append_text", s + "\n")
	elif _output_label:
		# Fallback: if it's a plain Label or similar, set text directly
		_output_label.set("text", s)

func _register_default_commands() -> void:
	_commands["/help"] = func(_args: Array) -> int:
		_print_line("Commands:")
		for k in _commands.keys():
			_print_line(" - %s" % String(k))
		return 0

	_commands["/clear"] = func(_args: Array) -> int:
		clear()
		return 0

	# Seed inspector command wired for Step 3
	# Uses Seedbook accessors without requiring a UI scene
	_commands["/seed_info"] = func(_args: Array) -> int:
		var info: Dictionary = Seedbook.get_all_seed_info()
		_print_line("Campaign Seed: %s" % String(info.get("campaign_seed", "")))
		_print_line("Realm Seeds:")
		for r in (info.get("realms", []) as Array):
			var rd := r as Dictionary
			_print_line(" - %s: %s (stage=%d)" % [String(rd.get("realm_id","?")), String(rd.get("realm_seed","")), int(rd.get("stage_index",0))])
		_print_line("Stage Seeds:")
		for s in (info.get("stages", []) as Array):
			var sd := s as Dictionary
			_print_line(" - %s[%d]: %s" % [String(sd.get("realm_id","?")), int(sd.get("stage_index",0)), String(sd.get("stage_seed",""))])
		_print_line("Cursors:")
		for k in (info.get("cursors", {}) as Dictionary).keys():
			_print_line(" - %s: %d" % [String(k), int((info.get("cursors", {}) as Dictionary)[k])])

		# Optional telemetry if provided via native singleton
		if Engine.has_singleton("Telemetry"):
			var t = Engine.get_singleton("Telemetry")
			if t and t.has_method("log"):
				t.log("seed_info", info)
		return 0

	# --- Core architecture helpers ---
	_commands["/new_game"] = func(args: Array) -> int:
		# Usage: /new_game [seed]
		var seed_arg := ""
		if args.size() > 0:
			seed_arg = String(args[0])
		var parsed_seed: Variant = _parse_seed(seed_arg)
		if parsed_seed == null:
			# default: random but printed for reproducibility
			var r := randi()
			parsed_seed = int(r & 0x7fffffff)
			_print_line("[new_game] No seed provided, using random: %d (0x%08X)" % [parsed_seed, parsed_seed])
		SaveService.new_game(parsed_seed)
		var info = Seedbook.get_all_seed_info()
		_print_line("[new_game] Campaign Seed => %s" % String(info.get("campaign_seed","")))
		return 0

	_commands["/save"] = func(_args: Array) -> int:
		var ok := SaveService.save_game()
		var ok_text := "OK" if ok else str(ok)
		_print_line("[save] %s" % ok_text)
		return 0

	_commands["/snapshot"] = func(_args: Array) -> int:
		var snap := SaveService.snapshot()
		var realms: Array = (snap.get("realm_states", []) as Array)
		var rb: Dictionary = (snap.get("campaign_run", {}) as Dictionary).get("rng_book", {})
		_print_line("[snapshot] realms=%d, has_rng_book=%s" % [realms.size(), str(rb.size() > 0)])
		if rb.has("campaign_seed"):
			_print_line("  campaign_seed=%s" % String(rb.get("campaign_seed","")))
		return 0

	_commands["/diagnose_save"] = func(_args: Array) -> int:
		if SaveService.has_method("diagnose_load"):
			var diag := SaveService.diagnose_load()
			_print_line("[diagnose_save] %s" % str(diag))
			return 0
		else:
			_print_line("[diagnose_save] SaveService.diagnose_load() not available")
			return 1

	_commands["/list_streams"] = func(_args: Array) -> int:
		var book := RNCatalogIO.pack_current()
		var subs: Dictionary = book.get("subseeds", {})
		var curs: Dictionary = book.get("cursors", {})
		_print_line("Streams (%d):" % subs.size())
		for k in subs.keys():
			var cur := int(curs.get(k, 0))
			_print_line(" - %s => %s (cursor=%d)" % [String(k), String(subs[k]), cur])
		return 0

	# Save loading command
	_commands["/load"] = func(args: Array) -> int:
		# Usage: /load            -> try best-effort "last" save
		#        /load <slot|path> -> try explicit slot or path
		var target := ""
		if args.size() > 0:
			target = String(args[0])
		var ok := false
		var res: Variant = null
		if target == "" and SaveService.has_method("load_last"):
			res = SaveService.load_last()
			ok = bool(res)
		elif target != "" and SaveService.has_method("load_game"):
			# Prefer an API that accepts a slot/string
			res = SaveService.load_game(target)
			ok = bool(res)
		elif target == "" and SaveService.has_method("load_game"):
			# Some APIs expose a parameterless load that chooses the most recent
			res = SaveService.load_game()
			ok = bool(res)
		elif target != "" and SaveService.has_method("load_from_path"):
			# Fallback: explicit path-based load
			res = SaveService.load_from_path(target)
			ok = bool(res)
		else:
			_print_line("[load] No compatible load method on SaveService (expected: load_last, load_game, or load_from_path)")
			return 1

		_print_line("[load] %s" % ("OK" if ok else "FAILED"))
		if ok:
			var info: Dictionary = Seedbook.get_all_seed_info()
			_print_line("[load] Campaign Seed => %s" % String(info.get("campaign_seed", "")))
		return 0 if ok else 1

	# Enumerate the single-slot save model (primary + backup)
	_commands["/list_saves"] = func(_args: Array) -> int:
		var paths := [SaveService.SAVE_PATH, SaveService.BAK_PATH]
		_print_line("Save directory: %s" % ProjectSettings.globalize_path("user://"))
		for p in paths:
			var abs_path := ProjectSettings.globalize_path(p)
			if FileAccess.file_exists(p):
				var f := FileAccess.open(p, FileAccess.READ)
				var size := f.get_length()
				var text := f.get_as_text(); f.close()
				var last := ""
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					last = String((parsed as Dictionary).get("last_saved_utc", ""))
				_print_line("%s => EXISTS (%d bytes) last_saved_utc=%s" % [abs_path, int(size), last])
			else:
				_print_line("%s => missing" % abs_path)
		return 0


	# --- Economy tests -------------------------------------------------
	_commands["/test_economy"] = func(args: Array) -> int:
		# Usage:
		#   /test_economy ase [ticks=10] [faith=?default SaveService or 60] [tick_seconds=1.0]
		# Example:
		#   /test_economy ase
		#   /test_economy ase 10 60 1.0
		if args.size() > 0 and String(args[0]).to_lower() == "help":
			_print_line("Usage: /test_economy ase [ticks=10] [faith] [tick_seconds=1.0]")
			_print_line("       /test_economy live [seconds=5.0]")
			_print_line("Note: faith is clamped to 0..100 to mirror the service.")
			return 0

		var mode := "ase"
		if args.size() > 0:
			mode = String(args[0]).to_lower()

		# --- LIVE MODE ---
		if mode == "live":
			var seconds: float = 5.0
			if args.size() > 1 and String(args[1]).is_valid_float():
				seconds = max(0.5, float(args[1]))
			var svc := _find_ase_service()
			if svc == null:
				_print_line("[test_economy] live: AseTickService not found in the running scene")
				return 1
			# Reset session state
			if _econ_live_active and _econ_live_service and _econ_live_service.is_connected("ase_generated", Callable(self, "_on_live_ase_generated")):
				_econ_live_service.disconnect("ase_generated", Callable(self, "_on_live_ase_generated"))
			_econ_live_active = true
			_econ_live_sum = 0.0
			_econ_live_count = 0
			_econ_live_service = svc
			# Connect and schedule summary
			if not svc.is_connected("ase_generated", Callable(self, "_on_live_ase_generated")):
				svc.connect("ase_generated", Callable(self, "_on_live_ase_generated"))
			_print_line("[test_economy] live: observing %s for %.1fs…" % [svc.name, seconds])
			var tmr := get_tree().create_timer(seconds)
			tmr.timeout.connect(Callable(self, "_finish_live_summary"))
			return 0

		# --- Unknown mode guard ---
		elif mode != "ase":
			_print_line("[test_economy] Unknown mode: %s (use 'ase' or 'live')" % mode)
			return 1

		var ticks := 10
		if args.size() > 1 and String(args[1]).is_valid_int():
			ticks = int(args[1])

		# Default faith from SaveService if available; fallback 60
		var faith := 60
		if has_node("/root/SaveService") and get_node("/root/SaveService").has_method("emotions_get_faith"):
			faith = int(get_node("/root/SaveService").emotions_get_faith())
		if args.size() > 2 and (String(args[2]).is_valid_int() or String(args[2]).is_valid_float()):
			faith = int(float(args[2]))

		var tick_seconds := 1.0
		if args.size() > 3 and String(args[3]).is_valid_float():
			tick_seconds = float(args[3])

		_print_line("[test_economy] ase: ticks=%d faith=%d tick_seconds=%.3f" % [ticks, faith, tick_seconds])

		# Arrange — create a service instance (no timer; manual ticks)
		var ase := AseTickService.new()
		ase.autostart = false
		ase.base_ase_per_min = 2.0
		ase.set_faith(faith)
		ase.set_tick_seconds(tick_seconds)

		var sum_ref := [0.0]
		ase.ase_generated.connect(func(amount: float, _total_after: float, tick_index: int) -> void:
			sum_ref[0] += amount
			_print_line("[test_economy] tick %d +%.5f (acc=%.5f)" % [tick_index, amount, sum_ref[0]])
		)

		# Act — run N manual ticks
		for i in range(ticks):
			ase._on_tick()

		# Assert — expected within 1%
		var faith_eff: int = clampi(faith, 0, 100)  # mirror service set_faith()
		var mult: float = clampf(1.0 + 0.015 * (float(faith_eff) - 50.0), 0.5, 2.0)
		var expected: float = (2.0 * mult) * (tick_seconds / 60.0) * float(ticks)
		var diff: float = abs(sum_ref[0] - expected)
		var tol: float = max(0.01 * expected, 0.0001)
		var ok: bool = diff <= tol
		_print_line("[test_economy] expected=%.5f diff=%.5f tol=%.5f -> %s" % [expected, diff, tol, ("PASS" if ok else "FAIL")])
		return 0 if ok else 1

		# --- Emotions quick read ------------------------------------------------
	_commands["/get_faith"] = func(_args: Array) -> int:
		var val: int = -1
		if has_node("/root/SaveService") and get_node("/root/SaveService").has_method("emotions_get_faith"):
			val = int(get_node("/root/SaveService").emotions_get_faith())
			_print_line("Faith = %d" % val)
			# Also echo the running service value if available
			var svc := _find_ase_service()
			if svc:
				var v: Variant = svc.get("faith")  # works because AseTickService exports `faith`
				if typeof(v) != TYPE_NIL:
					_print_line("AseTickService faith (runtime) = %d" % int(v))
			return 0
		else:
			_print_line("SaveService not available; cannot read faith")
			return 1

	# Alias to handle common typo
	_commands["/get_fatih"] = _commands["/get_faith"]

	# --- Emotions quick set -------------------------------------------------
	_commands["/set_faith"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /set_faith <0..100>")
			return 1
		var v_str := String(args[0])
		if not v_str.is_valid_int() and not v_str.is_valid_float():
			_print_line("/set_faith expects an integer 0..100")
			return 1
		var v := int(float(v_str))
		var clamped := clampi(v, 0, 100)

		# Persist via SaveService if available
		if has_node("/root/SaveService") and get_node("/root/SaveService").has_method("emotions_set_faith"):
			clamped = get_node("/root/SaveService").emotions_set_faith(clamped)
			_print_line("Faith set to %d" % clamped)
			# Update live service (if present)
			var svc := _find_ase_service()
			if svc and svc.has_method("set_faith"):
				svc.set_faith(clamped)
				_print_line("AseTickService faith updated -> %d" % clamped)
			return 0
		else:
			_print_line("SaveService not available; cannot persist faith")
			return 1


# --- Private helpers ---

func _find_ase_service() -> Node:
	var scene := get_tree().current_scene
	if scene:
		var n := scene.get_node_or_null("AseTickService")
		if n != null:
			return n
	var queue: Array[Node] = [get_tree().root]
	while queue.size() > 0:
		var cur: Node = queue.pop_front()
		if cur.name == "AseTickService":
			return cur
		for c in cur.get_children():
			queue.push_back(c)
	return null

func _on_live_ase_generated(amount: float, _total_after: float, _tick_index: int) -> void:
	if not _econ_live_active:
		return
	_econ_live_sum += float(amount)
	_econ_live_count += 1

func _finish_live_summary() -> void:
	if _econ_live_service == null:
		_print_line("[test_economy] live: no service bound; aborting")
		_econ_live_active = false
		return
	var base: float = 2.0
	var tick_s: float = 60.0
	var faith_i: int = 60
	var v: Variant
	v = _econ_live_service.get("base_ase_per_min")
	if typeof(v) != TYPE_NIL:
		base = float(v)
	v = _econ_live_service.get("tick_seconds")
	if typeof(v) != TYPE_NIL:
		tick_s = float(v)
	v = _econ_live_service.get("faith")
	if typeof(v) != TYPE_NIL:
		faith_i = int(v)
	var faith_eff: int = clampi(faith_i, 0, 100)
	var mult: float = clampf(1.0 + 0.015 * (float(faith_eff) - 50.0), 0.5, 2.0)
	var per_tick: float = (base * mult) * (tick_s / 60.0)
	var expected: float = per_tick * float(_econ_live_count)
	var diff: float = abs(_econ_live_sum - expected)
	var tol: float = max(0.01 * expected, 0.0001)
	var ok: bool = diff <= tol
	_print_line("[test_economy] live summary: ticks=%d acc=%.5f expected=%.5f diff=%.5f tol=%.5f -> %s" %
		[_econ_live_count, _econ_live_sum, expected, diff, tol, ("PASS" if ok else "WARN")])
	if _econ_live_service.is_connected("ase_generated", Callable(self, "_on_live_ase_generated")):
		_econ_live_service.disconnect("ase_generated", Callable(self, "_on_live_ase_generated"))
	_econ_live_active = false
	_econ_live_service = null
	_econ_live_sum = 0.0
	_econ_live_count = 0

func _parse_seed(s: String) -> Variant:
	# Accept formats: decimal int, hex with 0x, or empty -> null
	s = s.strip_edges()
	if s == "":
		return null
	if s.begins_with("0x") or s.begins_with("0X"):
		return int("0x" + s.substr(2))
	# decimal
	if s.is_valid_int():
		return int(s)
	# fallback: hash the string deterministically via RNCatalogIO
	# Simpler: use built-in hash of string, masked to 31-bit
	return int(s.hash() & 0x7fffffff)

func _ensure_input_ui() -> void:
	if _input_field and is_instance_valid(_input_field):
		return
	# Create a tiny overlay if no input field is provided
	var layer := CanvasLayer.new()
	layer.name = "DebugConsoleLayer"
	add_child(layer)
	var box := LineEdit.new()
	box.name = "DebugConsoleInput"
	box.placeholder_text = "Type a debug command…"
	box.visible = false
	# Simple top bar placement
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 8
	box.offset_bottom = 36
	layer.add_child(box)
	box.text_submitted.connect(_on_console_submit)
	_input_field = box

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_SLASH:
			_ensure_input_ui()
			_input_field.visible = true
			if _input_field.text == "":
				_input_field.text = "/"
			_input_field.caret_column = _input_field.text.length()
			_input_field.grab_focus()
			get_viewport().set_input_as_handled()
		elif key == KEY_ESCAPE and _input_field and _input_field.visible:
			_input_field.visible = false
			_input_field.release_focus()
			get_viewport().set_input_as_handled()

func _on_console_submit(text: String) -> void:
	var cmd := text.strip_edges()
	if cmd == "":
		_input_field.visible = false
		_input_field.release_focus()
		return
	run_command(cmd)
	_input_field.text = ""
	_input_field.visible = false
	_input_field.release_focus()