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

	# --- tests: trade suite ---
	var trade_path := "res://core/tests/economy/test_trade.gd"
	var trade := load(trade_path)
	if trade == null:
		print("[TestRunner] Missing file: ", trade_path)
	else:
		var inst_trade: Node = trade.new()
		# Ensure @onready variables initialize by adding to the scene tree during the run
		var main_loop := Engine.get_main_loop()
		var root: Node = null
		if main_loop is SceneTree:
			root = (main_loop as SceneTree).root
		if root != null:
			root.add_child(inst_trade)

		var s3 := {"total": 0, "passed": 0, "failed": 0}
		if inst_trade.has_method("build_suite"):
			var suite: Array = inst_trade.build_suite()
			for case in suite:
				var fn: Variant = (case as Dictionary).get("fn", null)
				if fn is Callable:
					var ok := bool((fn as Callable).call())
					s3["total"] += 1
					if ok:
						s3["passed"] += 1
					else:
						s3["failed"] += 1
				else:
					print("[TestRunner] Skipped a test case in trade suite — invalid Callable.")
			_print_case("economy:test_trade", s3)
			results.append({"name": "economy:test_trade", "summary": s3})
			totals["total"] += int(s3.get("total", 0))
			totals["passed"] += int(s3.get("passed", 0))
			totals["failed"] += int(s3.get("failed", 0))
		else:
			print("[TestRunner] Skipped economy:test_trade — no build_suite() found.")

		# Detach and free the test node (clean up)
		if root != null and inst_trade.get_parent() == root:
			root.remove_child(inst_trade)
		inst_trade.queue_free()

	var out := {"suite": "economy", "results": results, "totals": totals}
	if verbose:
		print("[TestRunner] economy totals: %d/%d PASS" % [totals["passed"], totals["total"]])
	return out

## Convenience: run all known suites (currently just economy).
static func run_all(verbose: bool = true) -> Dictionary:
	return {"economy": run_economy(verbose)}