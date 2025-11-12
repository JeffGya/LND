extends Label

const EconomyServiceScript := preload("res://core/services/EconomyService.gd")

## AseStatusLabel.gd — lightweight status UI for the Ase Flame
## Canon intent:
##  - Reassure the Keeper that the flame is alive, even before first tick.
##  - Surface current Ase (approximate) and time until next pulse.
##  - Read-only: never mutates economy state.

@onready var _ase_tick: Node = get_node("/root/Node/AseTickService")

var _ase_amount: float = 0.0
var _state: String = "initializing"

func _ready() -> void:
	if _ase_tick:
		# Listen for state changes so we can show Waking / Kindling / Flowing / Quiet
		if _ase_tick.has_signal("state_changed"):
			_ase_tick.state_changed.connect(_on_ase_state_changed)
		# Listen for generated Ase to keep a local running total
		if _ase_tick.has_signal("ase_generated"):
			_ase_tick.ase_generated.connect(_on_ase_generated)

	# Initial text
	_update_text_for_state(_state)

func _process(delta: float) -> void:
	if not _ase_tick:
		text = "Ase Flame (%d Ase): (offline)" % _get_display_ase()
		return

	# Only show countdown when running
	if _state == "running" and _ase_tick.has_method("is_running") and _ase_tick.is_running():
		var seconds_left: int = 0
		if _ase_tick.has_method("get_seconds_until_next_tick"):
			seconds_left = int(ceil(_ase_tick.get_seconds_until_next_tick()))
			if seconds_left < 0:
				seconds_left = 0

		# Live countdown while flowing
		var ase_display := _get_display_ase()
		text = "Ase Flame (%d Ase): Flowing — next pulse in %ds" % [
			ase_display,
			seconds_left
		]

func _on_ase_generated(amount: float, total_after: float, tick_index: int) -> void:
	# Use the total from AseTickService as our approximate "current Ase" for this label.
	_ase_amount = total_after

	# If we're not in the running state yet, keep using the state-specific template;
	# _process() will take over once state == "running".
	if _state != "running":
		_update_text_for_state(_state)

func _on_ase_state_changed(state: String) -> void:
	var normalized := state
	if state.begins_with("faith_updated"):
		normalized = "running"
	elif state.begins_with("initializing"):
		normalized = "initializing"
	elif state.begins_with("starting"):
		normalized = "starting"
	elif state.begins_with("running"):
		normalized = "running"
	elif state.begins_with("stopped"):
		normalized = "stopped"

	_state = normalized
	_update_text_for_state(_state)

func _update_text_for_state(state: String) -> void:
	var ase_int := _get_display_ase()

	match state:
		"initializing":
			text = "Ase Flame (%d Ase): Waking…" % ase_int
		"starting":
			text = "Ase Flame (%d Ase): Kindling…" % ase_int
		"running":
			# "Flowing" text with countdown is handled in _process,
			# but we set a sensible initial line here before the first _process() tick.
			text = "Ase Flame (%d Ase): Flowing — next pulse soon" % ase_int
		"stopped":
			text = "Ase Flame (%d Ase): Quiet." % ase_int

func _get_display_ase() -> int:
	# Prefer global banked Ase from EconomyService; fallback to local tally if unavailable.
	# EconomyService exposes get_ase_banked() as a static helper, so we can call it directly
	# on the script rather than via an instance.
	if EconomyServiceScript:
		return int(EconomyServiceScript.get_ase_banked())
	return int(round(_ase_amount))
