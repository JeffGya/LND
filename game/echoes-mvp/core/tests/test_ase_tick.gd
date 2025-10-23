extends Node
## Sanity test: AseTickService math (10 ticks ≈ expected within 1%)
## Run this scene/script to verify the tick math independent of SaveService.

const AseTickService := preload("res://core/economy/AseTickService.gd")

var _sum: float = 0.0
var _ticks: int = 0

func _ready() -> void:
	print("[TEST] AseTickService sanity test starting…")
	# Arrange
	var ase := AseTickService.new()
	ase.autostart = false
	ase.base_ase_per_min = 2.0
	ase.set_faith(60)  # 1 + 0.015*(60-50) = 1.15x
	ase.set_tick_seconds(1.0)  # 1s per tick simplifies expected math
	add_child(ase)
	ase.ase_generated.connect(_on_ase_generated)

	# Act — advance 10 ticks manually (call the internal tick handler)
	for i in range(10):
		ase._on_tick()

	# Assert — expected within 1%
	# per_min = 2.0 * 1.15 = 2.30
	# per_tick (1s) = 2.30 * (1/60) = 0.0383333333
	# ten ticks expected = 0.3833333333
	var expected: float = 2.0 * 1.15 * (1.0/60.0) * 10.0
	var diff: float = abs(_sum - expected)
	var tol: float = max(0.01 * expected, 0.0001)
	var ok: bool = diff <= tol
	print("[TEST] ticks=", _ticks, ", sum=", _sum, ", expected=", expected, ", diff=", diff, ", tol=", tol)
	assert(ok)
	print("[TEST] PASS: AseTickService 10-tick sum within tolerance.")
	get_tree().quit()

func _on_ase_generated(amount: float, _total_after: float, tick_index: int) -> void:
	_ticks = tick_index
	_sum += amount