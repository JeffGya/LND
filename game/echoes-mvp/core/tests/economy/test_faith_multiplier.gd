

## test_faith_multiplier.gd
## Purpose: Unit-ish checks for the canon Faith → Ase multiplier curve.
## Canon trace: §12 "Ase Yield Curve" — multiplier = 1.0 + 0.015*(Faith-50),
## clamped to [0.5, 2.0]. Targets: 30→0.7, 50→1.0, 70→1.3, 100→2.0.

class_name TestFaithMultiplier
extends Object

const EconomyConstants = preload("res://core/economy/EconomyConstants.gd")

static func _approx_equal(a: float, b: float, eps: float = 0.0005) -> bool:
	return abs(a - b) <= eps

## Runs the table-driven tests. If `verbose` is true, prints each case.
## Returns a summary dictionary you can inspect or pretty-print.
static func run(verbose: bool = true) -> Dictionary:
	var cases: Array = [
		{ "faith": -20, "expected": 0.5 },   # underflow clamps to 0.5
		{ "faith": 0,   "expected": 0.5 },   # 1 + 0.015*(0-50) = 0.25 → clamp 0.5
		{ "faith": 30,  "expected": 0.7 },
		{ "faith": 50,  "expected": 1.0 },
		{ "faith": 70,  "expected": 1.3 },
		{ "faith": 100, "expected": 2.0 },
		{ "faith": 140, "expected": 2.0 },  # overflow clamps to 2.0
	]

	var passed := 0
	var failed_cases: Array = []

	for c in cases:
		var f := int(c["faith"])
		var exp := float(c["expected"])
		var got := EconomyConstants.faith_to_multiplier(f)
		var ok := _approx_equal(got, exp)
		if verbose:
			print("[TestFaithMultiplier] faith=%d expected=%.5f got=%.5f diff=%.5f -> %s" % [f, exp, got, abs(got-exp), ("PASS" if ok else "FAIL")])
		if ok:
			passed += 1
		else:
			failed_cases.append({"faith": f, "expected": exp, "got": got, "diff": abs(got-exp)})

	var summary := {
		"name": "test_faith_multiplier",
		"total": cases.size(),
		"passed": passed,
		"failed": cases.size() - passed,
		"failures": failed_cases,
	}
	if verbose:
		print("[TestFaithMultiplier] summary: %d/%d PASS" % [passed, cases.size()])
	return summary