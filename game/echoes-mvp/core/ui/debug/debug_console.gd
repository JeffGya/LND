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
# --- Combat demo session state (Subtask 9) ---
var _staged_party: Array[int] = []
var _last_fight: Dictionary = {}  # { seed:int, rounds:int, party_ids:Array[int>, enemy_count:int }
var _econ_live_service: Node = null
var _current_eng: Object = null  # holds the most recent CombatEngine instance for QA hooks
var _morale_overrides_persist: Dictionary = {}  # persists morale overrides across demo engines

# Shared preloads
const Seedbook = preload("res://core/seed/SeedBook.gd")
const AseTickService = preload("res://core/economy/AseTickService.gd")
const EconomyServiceScript = preload("res://core/services/EconomyService.gd")
const SummonServiceScript = preload("res://core/services/SummonService.gd")
const EchoConstants = preload("res://core/echoes/EchoConstants.gd")
const PersonalityArchetype = preload("res://core/echoes/PersonalityArchetype.gd")
const ArchetypeBarks = preload("res://core/echoes/ArchetypeBarks.gd")
const PartyRoster = preload("res://core/combat/PartyRoster.gd")
const EnemyFactory = preload("res://core/combat/EnemyFactory.gd")
const CombatEngine = preload("res://core/combat/CombatEngine.gd")
const CombatLog = preload("res://core/combat/CombatLog.gd")
const CmdCore = preload("res://core/ui/debug/commands/cmd_core.gd")
const CmdHeroes = preload("res://core/ui/debug/commands/cmd_heroes.gd")
const CmdSave = preload("res://core/ui/debug/commands/cmd_save.gd")
const CmdEconomy = preload("res://core/ui/debug/commands/cmd_economy.gd")
const CmdTelemetry = preload("res://core/ui/debug/commands/cmd_telemetry.gd")
const CmdCombat = preload("res://core/ui/debug/commands/cmd_combat.gd")
@onready var _econ_service_inst: Node = EconomyServiceScript.new()

# Optional: attach a label later without hard dependency
@export var output_label_path: NodePath
@export var input_field_path: NodePath
@onready var _output_label: Node = get_node_or_null(output_label_path)
@onready var _input_field: LineEdit = get_node_or_null(input_field_path)

func _ready() -> void:
	_register_default_commands()
	# Live economy updates in console (optional but helpful)
	if has_node("/root/SaveService"):
		var ss: Node = get_node("/root/SaveService")
		if not ss.is_connected("economy_changed", Callable(self, "_on_economy_changed")):
			ss.connect("economy_changed", Callable(self, "_on_economy_changed"))
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
	# Module-registered commands (pure delegation; in-file handlers below will override if duplicated)
	CmdCore.register(self, _commands)
	CmdHeroes.register(self, _commands)
	CmdSave.register(self, _commands)
	CmdEconomy.register(self, _commands)
	CmdTelemetry.register(self, _commands)
	CmdCombat.register(self, _commands)
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

	# --- Summoning commands ---------------------------------------------------
	_commands["/summon"] = func(args: Array) -> int:
		# Usage: /summon [count:int>=1]
		var n: int = 1
		if args.size() > 0:
			var s := String(args[0])
			if not s.is_valid_int():
				_print_line("Usage: /summon [count:int>=1]")
				return 1
			n = int(s)
			if n < 1:
				_print_line("Count must be >= 1")
				return 1
		var res: Dictionary = SummonServiceScript.summon(n)
		if not bool(res.get("ok", false)):
			var reason := String(res.get("reason", ""))
			match reason:
				"insufficient_ase":
					var have := int(res.get("have", 0))
					var cost := int(res.get("cost", 0))
					var need := int(res.get("need", max(0, cost - have)))
					_print_line("[summon] FAILED — Insufficient Ase (have=%d, need=%d, cost=%d)" % [have, need, cost])
					return 2
				"bad_count":
					_print_line("[summon] FAILED — bad count (must be >= 1)")
					return 2
				"debit_failed":
					_print_line("[summon] FAILED — economy debit failed")
					return 2
				_:
					_print_line("[summon] FAILED — unknown reason")
					return 2
		var ids: Array = res.get("ids", [])
		var cost_ase: int = int(res.get("cost_ase", 0))
		_print_line("[summon] OK — cost=%d, created=%d" % [cost_ase, ids.size()])
		if ids.is_empty():
			_print_line("(warning) No heroes returned; check SaveService.heroes_add()")
			return 0
		var ss := get_node("/root/SaveService")
		for raw_id in ids:
			var id_i: int = int(raw_id)
			var h: Dictionary = ss.hero_get(id_i)
			_print_line("✨ " + _format_hero_summary(h))
			var bark_arch := String(h.get("archetype", ""))
			var bark_name := String(h.get("name", ""))
			var bark_line := ArchetypeBarks.arrival(bark_arch, bark_name)
			if bark_line != "":
				_print_line("  " + "“%s”" % bark_line)
		return 0

	_commands["/list_heroes"] = func(args: Array) -> int:
		# Usage: /list_heroes [limit:int=10]
		var limit: int = 10
		if args.size() > 0:
			var s := String(args[0])
			if not s.is_valid_int():
				_print_line("Usage: /list_heroes [limit:int]")
				return 1
			limit = max(1, int(s))
		var ss := get_node("/root/SaveService")
		var roster: Array = ss.heroes_list()
		var total := roster.size()
		if total == 0:
			_print_line("[list_heroes] No heroes yet.")
			return 0
		var start: int = max(0, total - limit)
		_print_line("[list_heroes] showing %d of %d" % [total - start, total])
		for i in range(start, total):
			var h: Dictionary = roster[i]
			_print_line(" - " + _format_hero_summary(h))
		return 0

	_commands["/hero_info"] = func(args: Array) -> int:
		# Usage: /hero_info <id:int>
		if args.size() == 0:
			_print_line("Usage: /hero_info <id:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			_print_line("/hero_info expects an integer id")
			return 1
		var id_i: int = int(s)
		var ss := get_node("/root/SaveService")
		var h: Dictionary = ss.hero_get(id_i)
		if typeof(h) != TYPE_DICTIONARY or h.is_empty():
			_print_line("No hero with id %d" % id_i)
			return 1
		var name := String(h.get("name", "?"))
		var rank := int(h.get("rank", 0))
		var cls := String(h.get("class", "?"))
		var gen := String(h.get("gender", "?"))
		_print_line("Hero %d: %s — r%d, class=%s, gender=%s" % [id_i, name, rank, cls, gen])
		var arch := String(h.get("archetype", ""))
		if arch != "":
			var arch_display := arch
			if typeof(EchoConstants) == TYPE_OBJECT and EchoConstants.ARCHETYPE_META.has(arch):
				var meta: Dictionary = EchoConstants.ARCHETYPE_META[arch]
				arch_display = String(meta.get("display_name", arch))
			_print_line("  Archetype: %s  [debug: arch=%s]" % [arch_display, arch])
		else:
			_print_line("  Archetype: n/a")
		# Intro Bark (deterministic, display-only)
		var bark_line := ArchetypeBarks.arrival(arch, name)
		if bark_line != "":
			_print_line("  Intro Bark: " + "“%s”" % bark_line)
		var tr: Dictionary = h.get("traits", {})
		var c := int(tr.get("courage", 0))
		var w := int(tr.get("wisdom", 0))
		var f := int(tr.get("faith", 0))
		var seed := int(h.get("seed", 0))
		var created := String(h.get("created_utc", ""))
		_print_line("  Traits: Courage %d, Wisdom %d, Faith %d  |  Seed: %d  |  Created: %s" % [c, w, f, seed, created])
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
		# Announce the free starter hero granted on New Game
		if has_node("/root/SaveService"):
			var ss := get_node("/root/SaveService")
			if ss and ss.has_method("heroes_list"):
				var roster: Array = ss.heroes_list()
				if roster.size() > 0:
					var h: Dictionary = roster[0]
					_print_line("[new_game] Starter hero granted: " + _format_hero_summary(h))
					var bark_arch := String(h.get("archetype", ""))
					var bark_name := String(h.get("name", ""))
					var bark_line := ArchetypeBarks.arrival(bark_arch, bark_name)
					if bark_line != "":
						_print_line("  " + "“%s”" % bark_line)
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

	# --- Archetype distribution sampler -----------------------------------------
	_commands["/archetype_sample"] = func(args: Array) -> int:
		# Usage: /archetype_sample [count:int=1000] [seed]
		var count: int = 1000
		if args.size() > 0:
			var s0 := String(args[0])
			if s0.is_valid_int():
				count = max(1, int(s0))
			elif s0 == "":
				count = 1000
			else:
				_print_line("Usage: /archetype_sample [count:int=1000] [seed]")
				return 1

		var seed_text := ""
		var seed_val: Variant = null
		if args.size() > 1:
			seed_text = String(args[1])
			seed_val = _parse_seed(seed_text)

		var rng := RandomNumberGenerator.new()
		if seed_val != null:
			rng.seed = int(seed_val)
			seed_text = "0x%08X" % int(seed_val)
		else:
			rng.randomize()
			var s := int(rng.randi() & 0x7fffffff)
			seed_text = "0x%08X" % s

		# Tally setup (include all archetypes so zeros show if needed)
		var tally: Dictionary = {}
		for a in EchoConstants.ARCHETYPES:
			tally[a] = 0

		var min_v := int(EchoConstants.TRAIT_ROLL_MIN)
		var max_v := int(EchoConstants.TRAIT_ROLL_MAX)
		for _i in count:
			var c := rng.randi_range(min_v, max_v)
			var w := rng.randi_range(min_v, max_v)
			var f := rng.randi_range(min_v, max_v)
			var arch := PersonalityArchetype.pick_archetype(c, w, f)
			tally[arch] = int(tally[arch]) + 1

		_print_line("[archetype_sample] n=%d seed=%s" % [count, seed_text])
		_print_pct_bars(tally, count)
		return 0

	# --- Economy quick commands ---
	_commands["/get_balances"] = func(_args: Array) -> int:
		var ase_banked: int = int(EconomyServiceScript.get_ase_banked())
		var ase_effective: float = float(EconomyServiceScript.get_ase_effective())
		var ek_i: int = int(EconomyServiceScript.get_ekwan_banked())
		_print_line("Balances — Ase(banked): %d, Ase(effective): %.2f, Ekwan: %d" % [ase_banked, ase_effective, ek_i])
		return 0

	_commands["/get_ase_buffer"] = func(_args: Array) -> int:
		var buf: float = float(EconomyServiceScript.get_ase_buffer())
		var banked: int = int(EconomyServiceScript.get_ase_banked())
		var eff: float = float(EconomyServiceScript.get_ase_effective())
		_print_line("Ase buffer: %.4f (banked=%d, effective=%.4f)" % [buf, banked, eff])
		return 0

	_commands["/trade_ase"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /trade_ase <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			_print_line("/trade_ase expects a positive integer amount")
			return 1
		var amount: int = int(s)
		if amount <= 0:
			_print_line("Amount must be a positive integer")
			return 1
		var res: Dictionary = _econ_service_inst.trade_ase_to_ekwan_inst(amount)
		if bool(res.get("ok", false)):
			_print_line("Trade OK — Spent Ase: %d, Gained Ekwan: %d, Leftover Ase Requested: %d, Rate: %d" % [
				int(res.get("ase_spent", 0)), int(res.get("ekwan_gained", 0)), int(res.get("leftover_ase_requested", 0)), int(res.get("rate", 0))
			])
			return 0
		else:
			var reason := String(res.get("reason", ""))
			var rate := int(res.get("rate", 0))
			match reason:
				"insufficient_batch":
					_print_line("Trade failed — insufficient batch. Need at least %d Ase per 1 Ekwan." % rate)
					return 2
				"insufficient_funds":
					_print_line("Trade failed — not enough Ase for a full batch at rate %d." % rate)
					return 3
				_:
					_print_line("Trade failed — unknown reason.")
					return 4

	_commands["/trade_ekwan"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /trade_ekwan <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			_print_line("/trade_ekwan expects a positive integer amount")
			return 1
		var amount: int = int(s)
		if amount <= 0:
			_print_line("Amount must be a positive integer")
			return 1
		var res: Dictionary = _econ_service_inst.trade_ekwan_to_ase_inst(amount)
		if bool(res.get("ok", false)):
			_print_line("Trade OK — Spent Ekwan: %d, Gained Ase: %d, Rate: %d" % [
				int(res.get("ekwan_spent", 0)), int(res.get("ase_gained", 0)), int(res.get("rate", 0))
			])
			return 0
		else:
			var reason := String(res.get("reason", ""))
			var rate := int(res.get("rate", 0))
			if reason == "insufficient_funds":
				_print_line("Trade failed — not enough Ekwan.")
				return 3
			_print_line("Trade failed — unknown reason.")
			return 4

	# --- Economy dev/cheat commands -----------------------------------------
	# Instantly add banked Ase (whole units)
	_commands["/give_ase"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /give_ase <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			_print_line("/give_ase expects a positive integer amount")
			return 1
		var amt: int = int(s)
		if amt <= 0:
			_print_line("Amount must be a positive integer")
			return 1
		var after_banked: int = EconomyServiceScript.deposit_ase(amt)
		var eff: float = float(EconomyServiceScript.get_ase_effective())
		_print_line("[give_ase] +%d → banked=%d, effective=%.2f" % [amt, after_banked, eff])
		return 0

	# Instantly add banked Ekwan (whole units)
	_commands["/give_ekwan"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /give_ekwan <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			_print_line("/give_ekwan expects a positive integer amount")
			return 1
		var amt: int = int(s)
		if amt <= 0:
			_print_line("Amount must be a positive integer")
			return 1
		var after_ek: int = EconomyServiceScript.deposit_ekwan(amt)
		_print_line("[give_ekwan] +%d → ekwan=%d" % [amt, after_ek])
		return 0

	# Set banked Ase to an exact target value
	_commands["/set_ase"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /set_ase <target:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			_print_line("/set_ase expects an integer")
			return 1
		var target: int = int(s)
		if target < 0:
			_print_line("Target cannot be negative")
			return 1
		var have: int = int(EconomyServiceScript.get_ase_banked())
		var delta: int = target - have
		if delta > 0:
			var after_banked: int = EconomyServiceScript.deposit_ase(delta)
			var eff: float = float(EconomyServiceScript.get_ase_effective())
			_print_line("[set_ase] banked: %d → %d (Δ+%d), effective=%.2f" % [have, after_banked, delta, eff])
			return 0
		elif delta < 0:
			var res: Dictionary = EconomyServiceScript.try_spend_ase(-delta)
			if bool(res.get("ok", false)):
				var rem: int = int(res.get("remaining", 0))
				var eff2: float = float(EconomyServiceScript.get_ase_effective())
				_print_line("[set_ase] banked: %d → %d (Δ%d), effective=%.2f" % [have, rem, delta, eff2])
				return 0
			else:
				_print_line("[set_ase] failed: insufficient funds (have=%d need=%d)" % [int(res.get("have",0)), int(res.get("need",0))])
				return 2
		else:
			_print_line("[set_ase] banked already %d" % have)
			return 0

	# Set banked Ekwan to an exact target value
	_commands["/set_ekwan"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /set_ekwan <target:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			_print_line("/set_ekwan expects an integer")
			return 1
		var target: int = int(s)
		if target < 0:
			_print_line("Target cannot be negative")
			return 1
		var have: int = int(EconomyServiceScript.get_ekwan_banked())
		var delta: int = target - have
		if delta > 0:
			var after_ek: int = EconomyServiceScript.deposit_ekwan(delta)
			_print_line("[set_ekwan] ekwan: %d → %d (Δ+%d)" % [have, after_ek, delta])
			return 0
		elif delta < 0:
			var res2: Dictionary = EconomyServiceScript.try_spend_ekwan(-delta)
			if bool(res2.get("ok", false)):
				var rem2: int = int(res2.get("remaining", 0))
				_print_line("[set_ekwan] ekwan: %d → %d (Δ%d)" % [have, rem2, delta])
				return 0
			else:
				_print_line("[set_ekwan] failed: insufficient funds (have=%d need=%d)" % [int(res2.get("have",0)), int(res2.get("need",0))])
				return 2
		else:
			_print_line("[set_ekwan] ekwan already %d" % have)
			return 0

	# Add to the fractional Ase buffer (commits whole units automatically)
	_commands["/give_ase_float"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /give_ase_float <amount:float>")
			return 1
		var s := String(args[0])
		if not (s.is_valid_float() or s.is_valid_int()):
			_print_line("/give_ase_float expects a numeric amount")
			return 1
		var amt_f: float = float(s)
		if amt_f == 0.0:
			_print_line("Amount must be non-zero")
			return 1
		var eff_after: float = _econ_service_inst.add_ase_float(amt_f)
		var banked2: int = int(EconomyServiceScript.get_ase_banked())
		var buf: float = float(EconomyServiceScript.get_ase_buffer())
		_print_line("[give_ase_float] %+0.3f → buffer=%.3f, effective=%.3f, banked=%d" % [amt_f, buf, eff_after, banked2])
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
		var _on_ase_tick := func(amount: float, _total_after: float, tick_index: int) -> void:
			sum_ref[0] += amount
			_print_line("[test_economy] tick %d +%.5f (acc=%.5f)" % [tick_index, amount, sum_ref[0]])
		ase.ase_generated.connect(_on_ase_tick)

		# Act — run N manual ticks
		for i in range(ticks):
			ase._on_tick()

		# Assert — expected within 1%
		var faith_eff: int = clampi(faith, 0, 100)  # mirror service set_faith()
		var mult: float = EconomyConstants.faith_to_multiplier(faith_eff)
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
			# Print the active multiplier
			if svc and svc.has_method("get_faith_multiplier"):
				var m := float(svc.get_faith_multiplier())
				_print_line("Multiplier (runtime) = %.3f" % m)
			else:
				var m2 := EconomyConstants.faith_to_multiplier(int(val))
				_print_line("Multiplier (by curve) = %.3f" % m2)
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

	# --- Ase multiplier debug -----------------------------------------------
	_commands["/ase_multiplier"] = func(_args: Array) -> int:
		var svc := _find_ase_service()
		if svc == null:
			_print_line("[ase_multiplier] AseTickService not found in the running scene")
			return 1
		var base: float = 2.0
		var tick_s: float = 60.0
		var faith_i: int = 60
		var v: Variant
		v = svc.get("base_ase_per_min"); if typeof(v) != TYPE_NIL: base = float(v)
		v = svc.get("tick_seconds");     if typeof(v) != TYPE_NIL: tick_s = float(v)
		v = svc.get("faith");            if typeof(v) != TYPE_NIL: faith_i = int(v)
		var mult: float = EconomyConstants.faith_to_multiplier(clampi(faith_i, 0, 100))
		var per_tick: float = (base * mult) * (tick_s / 60.0)
		_print_line("Faith=%d  Mult=%.3f  Base/min=%.3f  Tick_s=%.3f  Ase/tick=%.5f" % [faith_i, mult, base, tick_s, per_tick])
		return 0

	# --- Test runner -----------------------------------------------------------
	_commands["/run_tests"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /run_tests <economy|all>")
			return 1
		var suite := String(args[0]).to_lower()
		match suite:
			"economy":
				var summary: Dictionary = TestRunner.run_economy(true)
				var totals: Dictionary = summary.get("totals", {})
				var passed := int(totals.get("passed", 0))
				var total := int(totals.get("total", 0))
				var failed := int(totals.get("failed", total - passed))
				_print_line("[run_tests] economy: %d/%d PASS%s" % [passed, total, ("" if failed == 0 else " (" + str(failed) + " FAIL)")])
				return 0 if failed == 0 else 2
			"all":
				var res: Dictionary = TestRunner.run_all(true)
				var econ: Dictionary = res.get("economy", {})
				var totals2: Dictionary = econ.get("totals", {})
				var passed2 := int(totals2.get("passed", 0))
				var total2 := int(totals2.get("total", 0))
				var failed2 := int(totals2.get("failed", total2 - passed2))
				_print_line("[run_tests] economy: %d/%d PASS%s" % [passed2, total2, ("" if failed2 == 0 else " (" + str(failed2) + " FAIL)")])
				return 0 if failed2 == 0 else 2
			_:
				_print_line("Usage: /run_tests <economy|all>")
				return 1

	# --- Telemetry controls ---------------------------------------------------
	_commands["/telemetry"] = func(args: Array) -> int:
		if args.size() == 0:
			_print_line("Usage: /telemetry <level|max|tail|clear> [value]")
			_print_line("Levels: 0=OFF, 1=INFO, 2=DEBUG, 3=LIVE")
			return 1
		var sub := String(args[0]).to_lower()
		match sub:
			"level":
				if args.size() == 1:
					var current_level := int(get_node("/root/SaveService").telemetry_get_level())
					_print_line("[telemetry] current level=%d (0=OFF,1=INFO,2=DEBUG,3=LIVE)" % current_level)
					return 0
				var s := String(args[1])
				if not s.is_valid_int():
					_print_line("/telemetry level <0..3>")
					return 1
				var new_level := clampi(int(s), 0, 3)
				get_node("/root/SaveService").telemetry_set_level(new_level)
				_print_line("[telemetry] level set to %d" % new_level)
				return 0
			"max":
				if args.size() == 1:
					var current_capacity := int(get_node("/root/SaveService").telemetry_tail(0).size())
					_print_line("[telemetry] current max capacity=%d" % current_capacity)
					return 0
				var s2 := String(args[1])
				if not s2.is_valid_int():
					_print_line("/telemetry max <1..1000>")
					return 1
				var new_max := int(s2)
				get_node("/root/SaveService").telemetry_set_max(new_max)
				_print_line("[telemetry] max capacity set to %d" % new_max)
				return 0
			"tail":
				var count := 10
				if args.size() > 1 and String(args[1]).is_valid_int():
					count = int(args[1])
				var arr: Array = get_node("/root/SaveService").telemetry_tail(count)
				_print_line("[telemetry] last %d events (%d total):" % [count, arr.size()])
				for ev in arr:
					var evt := ev as Dictionary
					var payload: Variant = (evt.get("payload") if evt.has("payload") else null)
					var ts_text := "?"
					if evt.has("ts"):
						ts_text = str(evt.get("ts"))
					elif payload is Dictionary and (payload as Dictionary).has("ts"):
						ts_text = str((payload as Dictionary).get("ts"))
					var type_text := "?"
					if evt.has("type"):
						type_text = str(evt.get("type"))
					elif payload is Dictionary and (payload as Dictionary).has("evt"):
						type_text = str((payload as Dictionary).get("evt"))
					var cat_text := "-"
					if payload is Dictionary and (payload as Dictionary).has("cat"):
						cat_text = str((payload as Dictionary).get("cat"))
					elif evt.has("cat"):
						cat_text = str(evt.get("cat"))
					var data_obj: Variant = {}
					if payload is Dictionary and (payload as Dictionary).has("data"):
						data_obj = (payload as Dictionary).get("data")
					elif evt.has("data"):
						data_obj = evt.get("data")
					_print_line(" - %s [%s/%s] %s" % [ts_text, type_text, cat_text, str(data_obj)])
				return 0
			"clear":
				get_node("/root/SaveService").telemetry_clear()
				_print_line("[telemetry] cleared")
				return 0
			_:
				_print_line("Usage: /telemetry <level|max|tail|clear> [value]")
				return 1

	# --- Combat: party & fights (Subtask 9) -----------------------------------
	var _cmd_party_list := func(_args: Array) -> int:
		var ss_dict: Dictionary = _read_save_snapshot()
		var avail: Array[Dictionary] = PartyRoster.list_available_allies(ss_dict)
		if avail.is_empty():
			_print_line("[party_list] no available heroes")
			return 0
		_print_line("[party_list] %d available:" % avail.size())
		for h in avail:
			var hh: Dictionary = _hydrate_hero_for_display(h)
			var id_i: int = int(hh.get("id", -1))
			_print_line(" - " + _format_hero_summary(hh) + " [id=%d]" % id_i)
		return 0
	_commands["/party_list"] = _cmd_party_list

	var _cmd_party_set := func(args: Array) -> int:
		# Usage: /party_set <ids...>
		if args.is_empty():
			_print_line("Usage: /party_set <ids...>")
			return 1
		var ids_text: String = " ".join(args)
		var ids_raw: Array = ids_text.split(",")
		var ids_flat: Array = []
		for piece in ids_raw:
			var parts: Array = String(piece).strip_edges().split(" ")
			for p in parts:
				if p == "":
					continue
				ids_flat.append(p)
		var ids_norm: Array[int] = PartyRoster.normalize_ids(ids_flat)
		if ids_norm.is_empty():
			_print_line("[party_set] no valid ids; example: /party_set 1 2 3")
			return 1
		var ss_dict: Dictionary = _read_save_snapshot()
		var res: Dictionary = PartyRoster.validate_party(ss_dict, ids_norm, 3)
		if not bool(res.get("ok", false)):
			_print_line("[party_set] invalid party:")
			for e in (res.get("errors", []) as Array):
				_print_line(" - %s" % String(e))
			return 2
		_staged_party = ids_norm
		_print_line("[party_set] Party set: %s" % str(ids_norm))
		return 0
	_commands["/party_set"] = _cmd_party_set

	_commands["/party_show"] = func(_args: Array) -> int:
		if _staged_party.is_empty():
			_print_line("[party_show] no staged party (use /party_set or /party_list)")
			return 0
		_print_line("[party_show] %d heroes:" % _staged_party.size())
		var idx: int = 1
		for pid in _staged_party:
			var id_i: int = int(pid)
			var stub: Dictionary = {"id": id_i}
			var hfull: Dictionary = _hydrate_hero_for_display(stub)
			_print_line(" %d) %s" % [idx, _format_hero_summary(hfull)])
			idx += 1
		return 0

	_commands["/party_clear"] = func(_args: Array) -> int:
		_staged_party.clear()
		_print_line("[party_clear] cleared")
		return 0

	_commands["/fight_demo"] = func(args: Array) -> int:
		# Usage: /fight_demo [seed] [rounds=5] [--auto]
		var seed_text: String = ""
		var rounds: int = 5
		var use_auto: bool = false
		if args.size() > 0:
			seed_text = String(args[0])
		if args.size() > 1 and String(args[1]).is_valid_int():
			rounds = clampi(int(args[1]), 1, 50)
		for a in args:
			if String(a) == "--auto":
				use_auto = true
		var seed_val: Variant = _parse_seed(seed_text)
		if seed_val == null:
			seed_val = 0

		# Determine party
		var party_ids: Array[int] = []
		for pid in _staged_party:
			party_ids.append(int(pid))
		if party_ids.is_empty() and use_auto:
			var ss_dict: Dictionary = _read_save_snapshot()
			var avail: Array[Dictionary] = PartyRoster.list_available_allies(ss_dict)
			for h in avail:
				if party_ids.size() >= 3:
					break
				party_ids.append(int(h.get("id", -1)))
		if party_ids.is_empty():
			_print_line("[fight_demo] no party set. Use /party_set or add --auto")
			return 1

		# Validate party
		var ss_dict2: Dictionary = _read_save_snapshot()
		var res: Dictionary = PartyRoster.validate_party(ss_dict2, party_ids, 3)
		if not bool(res.get("ok", false)):
			_print_line("[fight_demo] invalid party:")
			for e in (res.get("errors", []) as Array):
				_print_line(" - %s" % String(e))
			return 2

		# Enemies and engine
		var enemies: Array[Dictionary] = EnemyFactory.spawn_dummy_pack(3, int(seed_val))
		var eng := CombatEngine.new()
		_current_eng = eng
		# Apply persisted morale overrides before starting the battle so they're seeded into state
		for k in _morale_overrides_persist.keys():
			var id_i := int(k)
			var v_i := int(_morale_overrides_persist[k])
			if eng.has_method("morale_override_set"):
				eng.morale_override_set(id_i, v_i)
		eng.start_battle(int(seed_val), party_ids, enemies, "defeat", rounds)
		var log := CombatLog.new(16)
		_print_line("[fight_demo] party=%s seed=%d rounds=%d" % [str(party_ids), int(seed_val), rounds])
		while not eng.is_over():
			var snap: Dictionary = eng.step_round()
			log.print_round(snap)
		_print_line("[fight_demo] result: %s" % str(eng.result()))
		_last_fight = {
			"seed": int(seed_val),
			"rounds": rounds,
			"party_ids": party_ids,
			"enemy_count": 3,
		}
		return 0

	_commands["/fight_again"] = func(_args: Array) -> int:
		if _last_fight.is_empty():
			_print_line("[fight_again] nothing to replay (run /fight_demo first)")
			return 1
		var seed_v: int = int(_last_fight.get("seed", 0))
		var rounds: int = int(_last_fight.get("rounds", 5))
		var party_ids: Array[int] = _last_fight.get("party_ids", [])
		var enemy_count: int = int(_last_fight.get("enemy_count", 3))
		var enemies: Array[Dictionary] = EnemyFactory.spawn_dummy_pack(enemy_count, seed_v)
		var eng := CombatEngine.new()
		_current_eng = eng
		# Apply persisted morale overrides before starting the battle so they're seeded into state
		for k in _morale_overrides_persist.keys():
			var id_i := int(k)
			var v_i := int(_morale_overrides_persist[k])
			if eng.has_method("morale_override_set"):
				eng.morale_override_set(id_i, v_i)
		eng.start_battle(seed_v, party_ids, enemies, "defeat", rounds)
		var log := CombatLog.new(16)
		_print_line("[fight_again] party=%s seed=%d rounds=%d" % [str(party_ids), seed_v, rounds])
		while not eng.is_over():
			var snap: Dictionary = eng.step_round()
			log.print_round(snap)
		_print_line("[fight_again] result: %s" % str(eng.result()))
		return 0

	# --- Combat morale QA hooks -----------------------------------------------

	var __morale_show := func(_args: Array) -> int:
		if _current_eng == null:
			_print_line("[morale_show] no active demo engine. Run /fight_demo or /fight_again first.")
			return 1
		var st_v: Variant = _current_eng.get("_state")
		if typeof(st_v) != TYPE_DICTIONARY:
			_print_line("[morale_show] engine state unavailable")
			return 1
		var st := st_v as Dictionary
		var allies: Array = st.get("allies", [])
		if allies.is_empty():
			_print_line("[morale_show] no allies present in current engine state")
			return 0
		_print_line("[morale_show] allies=%d" % allies.size())
		for a in allies:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var id_i: int = int((a as Dictionary).get("id", -1))
			var name_s: String = String((a as Dictionary).get("name", str(id_i)))
			# Read morale like the engine accessor: stats.morale -> morale -> default 50
			var stats: Dictionary = (a as Dictionary).get("stats", {})
			var m := 50
			if typeof(stats) == TYPE_DICTIONARY and stats.has("morale"):
				m = int(stats.get("morale", 50))
			elif (a as Dictionary).has("morale"):
				m = int((a as Dictionary).get("morale", 50))
			var info := _morale_label_and_mult(m)
			_print_line(" - id=%d  name=%s  morale=%d  tier=%s  mult=%.2f" % [id_i, name_s, int(info["morale"]), String(info["label"]), float(info["mult"])])
		return 0
	_commands["/morale_show"] = __morale_show

	var __morale_set := func(args: Array) -> int:
		# Usage: /morale_set <ally_id:int> <0..100>
		if args.size() < 2:
			_print_line("Usage: /morale_set <ally_id:int> <0..100>")
			return 1
		var s_id := String(args[0])
		var s_val := String(args[1])
		if not s_id.is_valid_int() or (not s_val.is_valid_int() and not s_val.is_valid_float()):
			_print_line("Usage: /morale_set <ally_id:int> <0..100>")
			return 1
		var id_i := int(s_id)
		var val := int(float(s_val))
		var clamped := clampi(val, 0, 100)
		# Persist for future demo engines
		_morale_overrides_persist[id_i] = clamped
		# Apply to current engine instance if present
		if _current_eng != null and _current_eng.has_method("morale_override_set"):
			_current_eng.morale_override_set(id_i, clamped)
			# Also confirm by reading back if possible
			if _current_eng.has_method("get_actor_morale_tier"):
				var tier: int = int(_current_eng.get_actor_morale_tier(id_i))
				var mult := CombatConstants.morale_multiplier_for_tier(tier)
				var label := "BROKEN"
				match tier:
					CombatConstants.MoraleTier.INSPIRED: label = "INSPIRED"
					CombatConstants.MoraleTier.STEADY:   label = "STEADY"
					CombatConstants.MoraleTier.SHAKEN:   label = "SHAKEN"
					_:                                 label = "BROKEN"
				_print_line("[morale_set] id=%d morale=%d tier=%s mult=%.2f (persisted)" % [id_i, clamped, label, float(mult)])
				return 0
		# Fallback: try to write directly into current engine state (legacy path)
		if _current_eng == null:
			_print_line("[morale_set] persisted for next fight; no active engine.")
			return 0
		var st_v2: Variant = _current_eng.get("_state")
		if typeof(st_v2) != TYPE_DICTIONARY:
			_print_line("[morale_set] engine state unavailable; persisted only.")
			return 0
		var st2 := st_v2 as Dictionary
		var allies2: Array = st2.get("allies", [])
		var found: bool = false
		for i in range(allies2.size()):
			var ent: Dictionary = allies2[i] as Dictionary
			if typeof(ent) != TYPE_DICTIONARY:
				continue
			if int(ent.get("id", -1)) != id_i:
				continue
			found = true
			var stats2: Dictionary = ent.get("stats", {})
			if typeof(stats2) != TYPE_DICTIONARY:
				stats2 = {}
			stats2["morale"] = clamped
			ent["stats"] = stats2
			ent["morale"] = clamped
			var info2 := _morale_label_and_mult(clamped)
			_print_line("[morale_set] id=%d morale=%d tier=%s mult=%.2f (state-updated)" % [id_i, int(info2["morale"]), String(info2["label"]), float(info2["mult"])])
			break
		if not found:
			_print_line("[morale_set] no ally with id=%d in current engine state (persisted for next fight)" % id_i)
		return 0
	_commands["/morale_set"] = __morale_set

	# List/clear persisted morale overrides
	var __morale_overrides := func(_args: Array) -> int:
		if _morale_overrides_persist.is_empty():
			_print_line("[morale_overrides] (none)")
			return 0
		_print_line("[morale_overrides] %d entries:" % _morale_overrides_persist.size())
		for k in _morale_overrides_persist.keys():
			_print_line(" - id=%d => %d" % [int(k), int(_morale_overrides_persist[k])])
		return 0
	_commands["/morale_overrides"] = __morale_overrides

	var __morale_clear := func(args: Array) -> int:
		# Usage: /morale_clear [id]
		if args.size() > 0 and String(args[0]).is_valid_int():
			var id_i := int(String(args[0]))
			_morale_overrides_persist.erase(id_i)
			if _current_eng != null and _current_eng.has_method("morale_override_clear"):
				_current_eng.morale_override_clear(id_i)
			_print_line("[morale_clear] cleared id=%d" % id_i)
			return 0
		# Clear all
		_morale_overrides_persist.clear()
		if _current_eng != null and _current_eng.has_method("morale_override_clear"):
			_current_eng.morale_override_clear(-1)
		_print_line("[morale_clear] cleared all overrides")
		return 0
	_commands["/morale_clear"] = __morale_clear

	# --- Combat temp boost QA ---------------------------------------------------
	var __atk_boost := func(args: Array) -> int:
		# Usage: /atk_boost <id:int> <delta:int>
		if args.size() < 2:
			_print_line("Usage: /atk_boost <id:int> <delta:int>")
			return 1
		var s_id := String(args[0])
		var s_delta := String(args[1])
		if not s_id.is_valid_int() or not s_delta.is_valid_int():
			_print_line("Usage: /atk_boost <id:int> <delta:int>")
			return 1
		if _current_eng == null:
			_print_line("[atk_boost] no active demo engine. Run /fight_demo or /fight_again first.")
			return 1
		var id_i := int(s_id)
		var delta := int(s_delta)
		if not _current_eng.has_method("set_temp_atk_boost") or not _current_eng.has_method("get_temp_atk_boost"):
			_print_line("[atk_boost] engine does not expose temp boost helpers")
			return 2
		_current_eng.set_temp_atk_boost(id_i, delta)
		var now := int(_current_eng.get_temp_atk_boost(id_i))
		_print_line("[atk_boost] id=%d +%d (now=%+d)" % [id_i, delta, now])
		return 0
	_commands["/atk_boost"] = __atk_boost

	var __boost_clear := func(args: Array) -> int:
		# Usage: /boost_clear [id:int]
		if _current_eng == null:
			_print_line("[boost_clear] no active demo engine. Run /fight_demo or /fight_again first.")
			return 1
		if args.size() > 0 and String(args[0]).is_valid_int():
			var id_i := int(String(args[0]))
			if _current_eng.has_method("clear_temp_boosts"):
				_current_eng.clear_temp_boosts(id_i)
				_print_line("[boost_clear] cleared boosts for id=%d" % id_i)
				return 0
		if _current_eng.has_method("clear_temp_boosts"):
			_current_eng.clear_temp_boosts(-1)
			_print_line("[boost_clear] cleared all boosts")
			return 0
		_print_line("[boost_clear] engine does not expose clear_temp_boosts")
		return 2
	_commands["/boost_clear"] = __boost_clear

# --- Private helpers ---

func _morale_label_and_mult(morale_val: int) -> Dictionary:
	var m := clampi(int(morale_val), 0, 100)
	var tier := CombatConstants.morale_tier(m)
	var label := "BROKEN"
	match tier:
		CombatConstants.MoraleTier.INSPIRED:
			label = "INSPIRED"
		CombatConstants.MoraleTier.STEADY:
			label = "STEADY"
		CombatConstants.MoraleTier.SHAKEN:
			label = "SHAKEN"
		_:
			label = "BROKEN"
	var mult := float(CombatConstants.morale_multiplier_for_tier(tier))
	return {"morale": m, "tier": tier, "label": label, "mult": mult}

func _pad_right(s: String, width: int) -> String:
	var pad := width - s.length()
	return s + (" ".repeat(max(0, pad)))

func _print_pct_bars(tally: Dictionary, total: int) -> void:
	if total <= 0:
		_print_line("(no samples)")
		return
	# Build percentage table and find max for scaling
	var percs: Array = []
	for k in tally.keys():
		var n := int(tally[k])
		var pct := (float(n) / float(total)) * 100.0
		percs.append({"k": String(k), "n": n, "pct": pct})
	var _cmp_pct_desc := func(a, b) -> bool: return a["pct"] > b["pct"]
	percs.sort_custom(_cmp_pct_desc)  # desc by pct
	var max_pct := 0.0001
	for row in percs:
		max_pct = max(max_pct, float(row["pct"]))
	var bar_w := 10  # scale bars to 10 blocks
	for row in percs:
		var k := String(row["k"]) 
		var pct_f := float(row["pct"]) 
		var blocks := int(round((pct_f / max_pct) * float(bar_w)))
		if pct_f > 0.0 and blocks == 0:
			blocks = 1
		var bar := "█".repeat(blocks)
		var name := _pad_right(k, 11)
		_print_line("%s  %5.1f%%  %s" % [name, pct_f, bar])

func _format_hero_summary(h: Dictionary) -> String:
	var id_i := int(h.get("id", -1))
	var name := String(h.get("name", "?"))
	var rank := int(h.get("rank", 0))
	var cls := String(h.get("class", "?"))
	var gen := String(h.get("gender", "?"))
	var tr: Dictionary = h.get("traits", {})
	var c := int(tr.get("courage", 0))
	var w := int(tr.get("wisdom", 0))
	var f := int(tr.get("faith", 0))
	var arch := String(h.get("archetype", "n/a"))
	return "%s  [id=%d, r%d, class=%s, arch=%s, gender=%s] — (Courage %d / Wisdom %d / Faith %d)" % [name, id_i, rank, cls, arch, gen, c, w, f]

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
	var mult: float = EconomyConstants.faith_to_multiplier(faith_eff)
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

func _read_save_snapshot() -> Dictionary:
	var ss_dict: Dictionary = {}
	# Prefer engine singleton if present
	if Engine.has_singleton("SaveService"):
		var svc = Engine.get_singleton("SaveService")
		if svc and svc.has_method("snapshot"):
			var v: Variant = svc.call("snapshot")
			if typeof(v) == TYPE_DICTIONARY:
				ss_dict = v
				return ss_dict
	# Fallback to direct autoload script API (used elsewhere in file)
	if typeof(SaveService) != TYPE_NIL and SaveService.has_method("snapshot"):
		ss_dict = SaveService.snapshot()
		return ss_dict
	# Minimal fallback: build roster from heroes_list if available
	if typeof(SaveService) != TYPE_NIL and SaveService.has_method("heroes_list"):
		var roster: Array = SaveService.heroes_list()
		ss_dict["hero_roster"] = {"active": roster}
	return ss_dict

# Helper: Hydrate hero dictionary for display (merge missing fields from SaveService if needed)
func _hydrate_hero_for_display(h: Dictionary) -> Dictionary:
	# Merge missing display fields from SaveService.hero_get(id) if possible (display-only).
	var out: Dictionary = {}
	for k in h.keys():
		out[k] = h[k]
	var id_val: int = int(out.get("id", -1))
	if id_val < 0:
		return out
	# Determine if hydration is needed
	var need_name: bool = str(out.get("name", "")) == "" or str(out.get("name", "")).begins_with("Hero ")
	var need_arch: bool = str(out.get("archetype", "")) == "" or str(out.get("archetype", "")) == "n/a"
	var need_gender: bool = str(out.get("gender", "?")) == "?"
	var traits_dict: Dictionary = out.get("traits", {})
	var c0: int = int(traits_dict.get("courage", 0))
	var w0: int = int(traits_dict.get("wisdom", 0))
	var f0: int = int(traits_dict.get("faith", 0))
	var need_traits: bool = (c0 == 0 and w0 == 0 and f0 == 0)
	var need_rank: bool = int(out.get("rank", 0)) == 0
	var need_class: bool = str(out.get("class", "")) == "" or str(out.get("class", "")) == "none"
	if not (need_name or need_arch or need_gender or need_traits or need_rank or need_class):
		return out
	# Fetch full hero record
	var src: Dictionary = {}
	if Engine.has_singleton("SaveService"):
		var svc = Engine.get_singleton("SaveService")
		if svc and svc.has_method("hero_get"):
			var v: Variant = svc.call("hero_get", id_val)
			if typeof(v) == TYPE_DICTIONARY:
				src = v
	if src.is_empty() and typeof(SaveService) != TYPE_NIL and SaveService.has_method("hero_get"):
		var v2: Variant = SaveService.hero_get(id_val)
		if typeof(v2) == TYPE_DICTIONARY:
			src = v2
	if src.is_empty():
		return out
	# Merge selected fields
	if src.has("name"):
		out["name"] = str(src.get("name", out.get("name", "")))
	if src.has("rank"):
		out["rank"] = int(src.get("rank", out.get("rank", 1)))
	if src.has("class"):
		out["class"] = str(src.get("class", out.get("class", "none")))
	if src.has("archetype"):
		out["archetype"] = str(src.get("archetype", out.get("archetype", "n/a")))
	if src.has("gender"):
		out["gender"] = str(src.get("gender", out.get("gender", "?")))
	# Traits (prefer nested `traits` dict)
	if src.has("traits") and typeof(src["traits"]) == TYPE_DICTIONARY:
		out["traits"] = src["traits"]
	else:
		var merged_traits: Dictionary = traits_dict
		if src.has("courage"):
			merged_traits["courage"] = int(src.get("courage", merged_traits.get("courage", 0)))
		if src.has("wisdom"):
			merged_traits["wisdom"] = int(src.get("wisdom", merged_traits.get("wisdom", 0)))
		if src.has("faith"):
			merged_traits["faith"] = int(src.get("faith", merged_traits.get("faith", 0)))
		out["traits"] = merged_traits
	return out

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
# Handler for live economy updates (signal: economy_changed)
func _on_economy_changed(kind: String, delta: int, new_value: int) -> void:
	_print_line("[economy] %s %+d → %d" % [kind, delta, new_value])
