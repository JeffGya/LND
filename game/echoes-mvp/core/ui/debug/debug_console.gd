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

# Shared preloads
const Seedbook = preload("res://core/seed/Seedbook.gd")

# Optional: attach a label later without hard dependency
@export var output_label_path: NodePath
@onready var _output_label: Node = get_node_or_null(output_label_path)

func _ready() -> void:
	_register_default_commands()
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
	var name := cmd.split(" ", false, 1)[0]
	var args := []
	if cmd.find(" ") != -1:
		args = cmd.substr(cmd.find(" ") + 1).split(" ")
	if _commands.has(name):
		var fn = _commands[name]
		var ok := true
		var err := ""
		if typeof(fn) == TYPE_CALLABLE:
			var res = null
			var status = OK
			status = fn.call(args)
			if status is bool:
				ok = bool(status)
			elif status is int:
				ok = int(status) == 0
		else:
			ok = false
			err = "Invalid command handler"
		if not ok and err != "":
			_print_line("Error: %s" % err)
		emit_signal("command_executed", name, ok)
	else:
		_print_line("Unknown command: %s (try /help)" % name)
		emit_signal("command_executed", name, false)

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
			var abs := ProjectSettings.globalize_path(p)
			if FileAccess.file_exists(p):
				var f := FileAccess.open(p, FileAccess.READ)
				var size := f.get_length()
				var text := f.get_as_text(); f.close()
				var last := ""
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					last = String((parsed as Dictionary).get("last_saved_utc", ""))
				_print_line("%s => EXISTS (%d bytes) last_saved_utc=%s" % [abs, int(size), last])
			else:
				_print_line("%s => missing" % abs)
		return 0


# --- Private helpers ---

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
