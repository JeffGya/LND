extends Node
## AseTickService.gd — MVP idle Ase generation
## Canon notes:
##  - Ase is generated over time by the Ase Flame (Sanctum core).
##  - MVP yield is influenced by Faith using the balance curve:
##      multiplier = 1 + 0.015 * (Faith - 50)
##      clamped to [0.5, 2.0] of base (see Balance §12 / Economy §8).
##  - This service only emits per-tick Ase; persistence is wired in Step 3.
##
## Usage (MVP):
##  - Add this node as a child in Main.tscn (or instantiate).
##  - Call start() on _ready().
##  - Connect `ase_generated(amount, total_after, tick_index)` to something
##    that updates the save and/or UI.

signal ase_generated(amount: float, total_after: float, tick_index: int)
signal state_changed(state: String)

@export var base_ase_per_min: float = 2.0   # Base Ase per minute at Faith=50
@export var tick_seconds: float = 60.0       # Seconds per tick
@export var faith: int = 60                  # Temporary source until emotions module
@export var autostart: bool = true           # Start ticking on _ready

# Clamp the multiplier so Faith can only shrink/boost within a sane band
@export var clamp_multiplier: bool = true
@export var min_multiplier: float = 0.5
@export var max_multiplier: float = 2.0

var _timer: Timer
var _running: bool = false
var _tick_index: int = 0
var _last_amount: float = 0.0
var _running_total: float = 0.0  # provisional local total (SaveService becomes source of truth later)

func _ready() -> void:
	emit_signal("state_changed", "initializing")
	_timer = Timer.new()
	_timer.wait_time = max(0.1, tick_seconds)
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_tick)
	if autostart:
		start()

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

func set_tick_seconds(seconds: float) -> void:
	tick_seconds = max(0.1, seconds)
	if _timer:
		_timer.wait_time = tick_seconds

func get_last_tick_amount() -> float:
	return _last_amount

func get_tick_index() -> int:
	return _tick_index

# --- Internals ---

func _on_tick() -> void:
	var amount := _compute_tick_amount()
	_last_amount = amount
	_tick_index += 1
	_running_total += amount
	emit_signal("ase_generated", amount, _running_total, _tick_index)

func _compute_tick_amount() -> float:
	var mult := _compute_faith_multiplier()
	var per_min := base_ase_per_min * mult
	var per_tick := per_min * (tick_seconds / 60.0)
	return per_tick

func _compute_faith_multiplier() -> float:
	var mult := 1.0 + 0.015 * (float(faith) - 50.0)
	if clamp_multiplier:
		mult = clampf(mult, min_multiplier, max_multiplier)
	return mult
