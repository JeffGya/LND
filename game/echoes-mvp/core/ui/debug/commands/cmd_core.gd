extends RefCounted

static func register(console: Node, commands: Dictionary) -> void:
	# /help
	commands["/help"] = func(_args: Array) -> int:
		console._print_line("Commands:")
		for k in commands.keys():
			console._print_line(" - %s" % String(k))
		return 0

	# /clear
	commands["/clear"] = func(_args: Array) -> int:
		console.clear()
		return 0

	# /seed_info
	commands["/seed_info"] = func(_args: Array) -> int:
		var info: Dictionary = console.Seedbook.get_all_seed_info()
		console._print_line("Campaign Seed: %s" % String(info.get("campaign_seed", "")))
		console._print_line("Realm Seeds:")
		for r in (info.get("realms", []) as Array):
			var rd := r as Dictionary
			console._print_line(" - %s: %s (stage=%d)" % [String(rd.get("realm_id","?")), String(rd.get("realm_seed","")), int(rd.get("stage_index",0))])
		console._print_line("Stage Seeds:")
		for s in (info.get("stages", []) as Array):
			var sd := s as Dictionary
			console._print_line(" - %s[%d]: %s" % [String(sd.get("realm_id","?")), int(sd.get("stage_index",0)), String(sd.get("stage_seed",""))])
		console._print_line("Cursors:")
		for k in (info.get("cursors", {}) as Dictionary).keys():
			console._print_line(" - %s: %d" % [String(k), int((info.get("cursors", {}) as Dictionary)[k])])

		if Engine.has_singleton("Telemetry"):
			var t = Engine.get_singleton("Telemetry")
			if t and t.has_method("log"):
				t.log("seed_info", info)
		return 0

	# /run_tests
	commands["/run_tests"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /run_tests <economy|all>")
			return 1
		var suite := String(args[0]).to_lower()
		match suite:
			"economy":
				var summary: Dictionary = TestRunner.run_economy(true)
				var totals: Dictionary = summary.get("totals", {})
				var passed := int(totals.get("passed", 0))
				var total := int(totals.get("total", 0))
				var failed := int(totals.get("failed", total - passed))
				console._print_line("[run_tests] economy: %d/%d PASS%s" % [passed, total, ("" if failed == 0 else " (" + str(failed) + " FAIL)")])
				return 0 if failed == 0 else 2
			"all":
				var res: Dictionary = TestRunner.run_all(true)
				var econ: Dictionary = res.get("economy", {})
				var totals2: Dictionary = econ.get("totals", {})
				var passed2 := int(totals2.get("passed", 0))
				var total2 := int(totals2.get("total", 0))
				var failed2 := int(totals2.get("failed", total2 - passed2))
				console._print_line("[run_tests] economy: %d/%d PASS%s" % [passed2, total2, ("" if failed2 == 0 else " (" + str(failed2) + " FAIL)")])
				return 0 if failed2 == 0 else 2
			_:
				console._print_line("Usage: /run_tests <economy|all>")
				return 1
