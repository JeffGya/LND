extends Node

var BAL = GameBalance_EconomySanctum
var ECON = EconomyConstants

## AseTickService.gd — MVP idle Ase generation
## Canon notes:
##  - Ase is generated over time by the Ase Flame (Sanctum core).
##  - MVP yield is influenced by Faith using the balance curve:
##      multiplier = 1 + 0.015 * (Faith - 50)
##      clamped to [0.5, 2.0] of base (see Balance §12 / Economy §8).
##  - This service only emits per-tick Ase; persistence is wired in Step 3.
##  - Sources balance from GameBalance_EconomySanctum and Faith from EmotionsService when available.
##
## Usage (MVP):
##  - Add this node as a child in Main.tscn (or instantiate).
##  - Call start() on _ready().
##  - Connect `ase_generated(amount, total_after, tick_index)` to something
##    that updates the save and/or UI.

## Uses EconomyConstants.faith_to_multiplier() per canon §12.

signal ase_generated(amount: float, total_after: float, tick_index: int)
signal state_changed(state: String)
signal ase_generated_ex(amount: float, total_after: float, tick_index: int, meta: Dictionary)

# Debug overrides (exported for convenience)
@export var base_ase_per_min: float = 2.0   # Base Ase per minute at Faith=50
@export var tick_seconds: float = 60.0 : set = _locked_set_tick_seconds      # Seconds per tick
@export var faith: int = 60                  # Temporary source until emotions module
@export var autostart: bool = true           # Start ticking on _ready

# Clamp the multiplier so Faith can only shrink/boost within a sane band
@export var clamp_multiplier: bool = true
@export var min_multiplier: float = 0.5
@export var max_multiplier: float = 2.0

## Cached, canon-clamped multiplier updated whenever Faith changes
var _cached_multiplier: float = 1.0

var _timer: Timer
var _running: bool = false
var _tick_index: int = 0
var _last_amount: float = 0.0
var _running_total: float = 0.0  # provisional local total (SaveService becomes source of truth later)
var _effective_tick_seconds: float = 60.0

func _ready() -> void:
	emit_signal("state_changed", "initializing")
	# Enforce canonical GDD economy settings (per-minute yield is source of truth).
	# Tick cadence is fixed at 60s to ensure visible chunks and correct passive yield.
	base_ase_per_min = BAL.ASE_TICK_BASE
	# Canonical tick: one tick per minute.
	tick_seconds = 60.0

	_effective_tick_seconds = tick_seconds
	_timer = Timer.new()
	_timer.wait_time = max(0.1, _effective_tick_seconds)
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_tick)
	_cached_multiplier = _compute_faith_multiplier()
	if autostart:
		start()

	# Pull Faith from EmotionsService if available (source of truth). Fallback to exported value.
	if Engine.has_singleton("EmotionsService"):
		var emo = Engine.get_singleton("EmotionsService")
		if typeof(emo) != TYPE_NIL and emo and emo.has_method("get_faith"):
			faith = int(emo.get_faith())
			# Live updates if service emits a signal.
			if emo.has_signal("faith_changed"):
				emo.connect("faith_changed", Callable(self, "_on_faith_changed"))

func start() -> void:
	if _running:
		return
	_tick_index = 0
	emit_signal("state_changed", "starting")
	_timer.start()
	_running = true
	emit_signal("state_changed", "running")

func stop() -> void:
	if not _running:
		return
	_timer.stop()
	_running = false
	emit_signal("state_changed", "stopped")

func reset_local_total(to_value: float) -> void:
	## Optional: let an external system (SaveService) sync the service's running total.
	_running_total = to_value

func set_faith(value: int) -> void:
	faith = clampi(value, 0, 100)
	_cached_multiplier = _compute_faith_multiplier()
	emit_signal("state_changed", "faith_updated:%d" % faith)

func _on_faith_changed(value: int) -> void:
	set_faith(value)

func set_base_ase_per_min(v: float) -> void:
	base_ase_per_min = max(0.0, v)

func get_base_ase_per_min() -> float:
	return base_ase_per_min

func get_tick_seconds() -> float:
	return _effective_tick_seconds

func get_faith() -> int:
	return faith

func get_faith_multiplier() -> float:
	return _cached_multiplier

func get_last_tick_amount() -> float:
	return _last_amount

func get_tick_index() -> int:
	return _tick_index

func _locked_set_tick_seconds(value: float) -> void:
	# Tick cadence is locked by GDD; ignore external modifications.
	tick_seconds = 60.0
	_effective_tick_seconds = 60.0
	if _timer:
		_timer.wait_time = 60.0

func set_tick_seconds(seconds: float) -> void:
	# Test/debug helper: override the effective tick interval on this instance only.
	# Runtime code does not call this on the main AseTickService node, so the
	# in-game cadence remains 60s unless explicitly overridden for experiments.
	var clamped : Variant = max(0.01, seconds)
	_effective_tick_seconds = clamped
	if _timer:
		_timer.wait_time = clamped

# --- Status Helpers ---

func is_running() -> bool:
	return _running

func get_seconds_until_next_tick() -> float:
	if _timer:
		return _timer.time_left
	return 0.0

# --- Internals ---

func _on_tick() -> void:
	var amount := _compute_tick_amount()
	_last_amount = amount
	_tick_index += 1
	_running_total += amount
	emit_signal("ase_generated", amount, _running_total, _tick_index)
	emit_signal("ase_generated_ex", amount, _running_total, _tick_index, {
		"faith": faith,
		"mult": _cached_multiplier,
		"base_ase_per_min": base_ase_per_min,
		"tick_seconds": tick_seconds
	})

func _compute_tick_amount() -> float:
	var per_min := base_ase_per_min * _cached_multiplier
	var per_tick := per_min * (_effective_tick_seconds / 60.0)
	return per_tick

func _compute_faith_multiplier() -> float:
	var mult := ECON.faith_to_multiplier(faith)
	if clamp_multiplier:
		mult = clampf(mult, min_multiplier, max_multiplier)
	return mult
