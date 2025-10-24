extends Node

@onready var _ase_status_label: Label = get_node_or_null("AseStatusLabel")

const AseTickService := preload("res://core/economy/AseTickService.gd")
const EconomyServiceScript := preload("res://core/services/EconomyService.gd")
@onready var _econ_service_inst: Node = EconomyServiceScript.new()

## Entry point of Echoes of the Sankofa MVP
## Headless-friendly: allows passing /seed_info via command line argument
## Example:
##   godot --headless --main-pack echoes-mvp.pck --seed_info

func _ready() -> void:
	# Detect CLI arguments for headless mode
	var args: Array = OS.get_cmdline_args()
	if args.has("--seed_info"):
		_run_headless_seed_info()
	else:
		# Ensure exactly one Ase tick service is active
		var ase_tick: Node = get_node_or_null("AseTickService")
		if ase_tick == null:
			ase_tick = AseTickService.new()
			ase_tick.name = "AseTickService"
			add_child(ase_tick)
		# Pull Faith from SaveService if the autoload exists; fallback to 60
		var faith_val := 60
		if has_node("/root/SaveService"):
			faith_val = get_node("/root/SaveService").emotions_get_faith()
		# Fast dev defaults so you can see output immediately
		if ase_tick.has_method("set_tick_seconds"):
			ase_tick.set_tick_seconds(2.0)  # 2s ticks for visible logging
		if ase_tick.has_method("set_faith"):
			ase_tick.set_faith(faith_val)
		# Connect once and start
		if not ase_tick.ase_generated.is_connected(_on_ase_generated):
			ase_tick.ase_generated.connect(_on_ase_generated)
		if ase_tick.has_signal("state_changed") and not ase_tick.state_changed.is_connected(_on_ase_state_changed):
			ase_tick.state_changed.connect(_on_ase_state_changed)
		if ase_tick.has_method("start"):
			ase_tick.start()
	print("Echoes of the Sankofa — Main initialized.")

func _run_headless_seed_info() -> void:
	print("[HEADLESS] Running /seed_info debug command...")
	var DebugConsole = preload("res://core/ui/debug/debug_console.gd").new()
	add_child(DebugConsole)
	DebugConsole.run_command("/seed_info")
	print("[HEADLESS] Seed info printed successfully.")
	get_tree().quit()  # terminate after printing


func _on_ase_generated(amount: float, total_after: float, tick_index: int) -> void:
	# Accumulate fractional Ase via EconomyService (commits whole units to banked)
	var eff_after: float = total_after
	if _econ_service_inst != null:
		eff_after = _econ_service_inst.add_ase_float(amount)
	# Query banked (int) via EconomyService static getters for clarity
	var banked: int = int(EconomyServiceScript.get_ase_banked())
	print("[AseTick] +%.2f → effective=%.2f, banked=%d (tick %d)" % [amount, eff_after, banked, tick_index])
	if _ase_status_label:
		_ase_status_label.text = "Ase: running — +%.2f (tick %d) • eff=%.2f • banked=%d" % [amount, tick_index, eff_after, banked]

func _on_ase_state_changed(state: String) -> void:
	if _ase_status_label:
		match state:
			"initializing":
				_ase_status_label.text = "Ase: initializing…"
			"starting":
				_ase_status_label.text = "Ase: starting…"
			"running":
				_ase_status_label.text = "Ase: running"
			"stopped":
				_ase_status_label.text = "Ase: stopped"
			_:
				_ase_status_label.text = "Ase: " + state
