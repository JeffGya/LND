extends Node
## Sanity test: AseTickService math (10 ticks ≈ expected within 1%)
## Run this scene/script to verify the tick math independent of SaveService.

const AseTickService := preload("res://core/economy/AseTickService.gd")
const EconomyConstants := preload("res://core/economy/EconomyConstants.gd")

var _sum: float = 0.0
var _ticks: int = 0

func _ready() -> void:
	print("[TEST] AseTickService sanity test starting…")
	# Arrange
	var ase := AseTickService.new()
	ase.autostart = false
	ase.base_ase_per_min = 2.0
	ase.set_faith(60)  # Faith=60 → multiplier per canon curve
	ase.set_tick_seconds(1.0)  # 1s per tick simplifies expected math
	add_child(ase)
	ase.ase_generated.connect(_on_ase_generated)

	# Act — advance 10 ticks manually (call the internal tick handler)
	for i in range(10):
		ase._on_tick()

	var mult: float = EconomyConstants.faith_to_multiplier(60)
	if ase.has_method("get_faith_multiplier"):
		var m_rt := ase.get_faith_multiplier()
		assert(abs(m_rt - mult) <= 0.0005)

	# Assert — expected within 1%
	# per_min = base * mult
	# per_tick (1s) = per_min * (1/60)
	# ten ticks expected = per_tick * 10
	var expected: float = 2.0 * mult * (1.0/60.0) * 10.0
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


## Deterministic runner for CI/console: no scene tree, no timers.
func run(verbose: bool = true) -> Dictionary:
	# Arrange
	var ase := AseTickService.new()
	ase.autostart = false
	ase.base_ase_per_min = 2.0
	ase.set_tick_seconds(1.0)  # 1s per tick
	ase.set_faith(60)          # Faith=60 → multiplier per canon curve

	# Expected per tick using the single source of truth
	var mult: float = EconomyConstants.faith_to_multiplier(60)
	var expected_per_tick: float = (ase.base_ase_per_min * mult) * (1.0 / 60.0)

	# Act — compute 10 ticks directly via the service math (no scene)
	var acc: float = 0.0
	var ticks: int = 10
	for i in range(ticks):
		acc += ase._compute_tick_amount()

	# Assert — within 1%
	var expected_total: float = expected_per_tick * float(ticks)
	var diff: float = abs(acc - expected_total)
	var tol: float = max(0.01 * expected_total, 0.0001)
	var ok: bool = diff <= tol
	if verbose:
		print("[TestAseTick] ticks=%d acc=%.5f expected=%.5f diff=%.5f tol=%.5f -> %s" % [ticks, acc, expected_total, diff, tol, ("PASS" if ok else "FAIL")])

	return {
		"name": "economy:test_ase_tick",
		"total": 1,
		"passed": 1 if ok else 0,
		"failed": 0 if ok else 1,
		"failures": [] if ok else [{"case": "10 ticks @ faith=60", "acc": acc, "expected": expected_total, "diff": diff}]
	}