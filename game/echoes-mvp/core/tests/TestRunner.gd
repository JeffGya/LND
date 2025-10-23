## TestRunner.gd — ultra-light test harness
## Goal: run small, deterministic checks inside the running game (no plugins).
## Usage (console):
##   TestRunner.run_economy(true)
##   TestRunner.run_all(true)
## Later we will wire this into DebugConsole as `/run_tests economy`.

class_name TestRunner
extends Node

static func _print_case(case_name: String, summary: Dictionary) -> void:
	var passed := int(summary.get("passed", 0))
	var total := int(summary.get("total", 0))
	var failed := int(summary.get("failed", total - passed))
	print("[TestRunner] %s: %d/%d PASS%s" % [case_name, passed, total, ("" if failed == 0 else " ("+str(failed)+" FAIL)")])

## Runs the Faith→Ase multiplier table tests (pure function).
static func run_economy(verbose: bool = true) -> Dictionary:
	var results: Array = []
	var totals := {"total": 0, "passed": 0, "failed": 0}

	# --- test: faith multiplier ---
	var fm_path := "res://core/tests/economy/test_faith_multiplier.gd"
	var fm := load(fm_path)
	if fm == null:
		print("[TestRunner] Missing file: ", fm_path)
	else:
		var summary: Dictionary = fm.new().run(verbose)
		_print_case("economy:test_faith_multiplier", summary)
		results.append({"name": "economy:test_faith_multiplier", "summary": summary})
		totals["total"] += int(summary.get("total", 0))
		totals["passed"] += int(summary.get("passed", 0))
		totals["failed"] += int(summary.get("failed", 0))

	var ase_tick_path := "res://core/tests/economy/test_ase_tick.gd"
	var ase_tick := load(ase_tick_path)
	if ase_tick == null:
		print("[TestRunner] Missing file: ", ase_tick_path)
	else:
		var inst: Object = ase_tick.new()
		if inst.has_method("run"):
			var s2: Dictionary = inst.run(verbose)
			_print_case("economy:test_ase_tick", s2)
			results.append({"name": "economy:test_ase_tick", "summary": s2})
			totals["total"] += int(s2.get("total", 0))
			totals["passed"] += int(s2.get("passed", 0))
			totals["failed"] += int(s2.get("failed", 0))
		else:
			print("[TestRunner] Skipped economy:test_ase_tick — no run() method found.")

	var out := {"suite": "economy", "results": results, "totals": totals}
	if verbose:
		print("[TestRunner] economy totals: %d/%d PASS" % [totals["passed"], totals["total"]])
	return out

## Convenience: run all known suites (currently just economy).
static func run_all(verbose: bool = true) -> Dictionary:
	return {"economy": run_economy(verbose)}