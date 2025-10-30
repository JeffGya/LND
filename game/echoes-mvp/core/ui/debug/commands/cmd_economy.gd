extends RefCounted

static func register(console: Node, commands: Dictionary) -> void:
	# Quick reads
	commands["/get_balances"] = func(_args: Array) -> int:
		var ase_banked: int = int(console.EconomyServiceScript.get_ase_banked())
		var ase_effective: float = float(console.EconomyServiceScript.get_ase_effective())
		var ek_i: int = int(console.EconomyServiceScript.get_ekwan_banked())
		console._print_line("Balances — Ase(banked): %d, Ase(effective): %.2f, Ekwan: %d" % [ase_banked, ase_effective, ek_i])
		return 0

	commands["/get_ase_buffer"] = func(_args: Array) -> int:
		var buf: float = float(console.EconomyServiceScript.get_ase_buffer())
		var banked: int = int(console.EconomyServiceScript.get_ase_banked())
		var eff: float = float(console.EconomyServiceScript.get_ase_effective())
		console._print_line("Ase buffer: %.4f (banked=%d, effective=%.4f)" % [buf, banked, eff])
		return 0

	# Trades
	commands["/trade_ase"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /trade_ase <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			console._print_line("/trade_ase expects a positive integer amount")
			return 1
		var amount: int = int(s)
		if amount <= 0:
			console._print_line("Amount must be a positive integer")
			return 1
		var res: Dictionary = console._econ_service_inst.trade_ase_to_ekwan_inst(amount)
		if bool(res.get("ok", false)):
			console._print_line("Trade OK — Spent Ase: %d, Gained Ekwan: %d, Leftover Ase Requested: %d, Rate: %d" % [
				int(res.get("ase_spent", 0)), int(res.get("ekwan_gained", 0)), int(res.get("leftover_ase_requested", 0)), int(res.get("rate", 0))
			])
			return 0
		else:
			var reason := String(res.get("reason", ""))
			var rate := int(res.get("rate", 0))
			match reason:
				"insufficient_batch":
					console._print_line("Trade failed — insufficient batch. Need at least %d Ase per 1 Ekwan." % rate)
					return 2
				"insufficient_funds":
					console._print_line("Trade failed — not enough Ase for a full batch at rate %d." % rate)
					return 3
				_:
					console._print_line("Trade failed — unknown reason.")
					return 4

	commands["/trade_ekwan"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /trade_ekwan <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			console._print_line("/trade_ekwan expects a positive integer amount")
			return 1
		var amount: int = int(s)
		if amount <= 0:
			console._print_line("Amount must be a positive integer")
			return 1
		var res: Dictionary = console._econ_service_inst.trade_ekwan_to_ase_inst(amount)
		if bool(res.get("ok", false)):
			console._print_line("Trade OK — Spent Ekwan: %d, Gained Ase: %d, Rate: %d" % [
				int(res.get("ekwan_spent", 0)), int(res.get("ase_gained", 0)), int(res.get("rate", 0))
			])
			return 0
		else:
			var reason := String(res.get("reason", ""))
			if reason == "insufficient_funds":
				console._print_line("Trade failed — not enough Ekwan.")
				return 3
			console._print_line("Trade failed — unknown reason.")
			return 4

	# Cheats
	commands["/give_ase"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /give_ase <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			console._print_line("/give_ase expects a positive integer amount")
			return 1
		var amt: int = int(s)
		if amt <= 0:
			console._print_line("Amount must be a positive integer")
			return 1
		var after_banked: int = console.EconomyServiceScript.deposit_ase(amt)
		var eff: float = float(console.EconomyServiceScript.get_ase_effective())
		console._print_line("[give_ase] +%d → banked=%d, effective=%.2f" % [amt, after_banked, eff])
		return 0

	commands["/give_ekwan"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /give_ekwan <amount:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			console._print_line("/give_ekwan expects a positive integer amount")
			return 1
		var amt: int = int(s)
		if amt <= 0:
			console._print_line("Amount must be a positive integer")
			return 1
		var after_ek: int = console.EconomyServiceScript.deposit_ekwan(amt)
		console._print_line("[give_ekwan] +%d → ekwan=%d" % [amt, after_ek])
		return 0

	commands["/set_ase"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /set_ase <target:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			console._print_line("/set_ase expects an integer")
			return 1
		var target: int = int(s)
		if target < 0:
			console._print_line("Target cannot be negative")
			return 1
		var have: int = int(console.EconomyServiceScript.get_ase_banked())
		var delta: int = target - have
		if delta > 0:
			var after_banked: int = console.EconomyServiceScript.deposit_ase(delta)
			var eff: float = float(console.EconomyServiceScript.get_ase_effective())
			console._print_line("[set_ase] banked: %d → %d (Δ+%d), effective=%.2f" % [have, after_banked, delta, eff])
			return 0
		elif delta < 0:
			var res: Dictionary = console.EconomyServiceScript.try_spend_ase(-delta)
			if bool(res.get("ok", false)):
				var rem: int = int(res.get("remaining", 0))
				var eff2: float = float(console.EconomyServiceScript.get_ase_effective())
				console._print_line("[set_ase] banked: %d → %d (Δ%d), effective=%.2f" % [have, rem, delta, eff2])
				return 0
			else:
				console._print_line("[set_ase] failed: insufficient funds (have=%d need=%d)" % [int(res.get("have",0)), int(res.get("need",0))])
				return 2
		else:
			console._print_line("[set_ase] banked already %d" % have)
			return 0

	commands["/set_ekwan"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /set_ekwan <target:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			console._print_line("/set_ekwan expects an integer")
			return 1
		var target: int = int(s)
		if target < 0:
			console._print_line("Target cannot be negative")
			return 1
		var have: int = int(console.EconomyServiceScript.get_ekwan_banked())
		var delta: int = target - have
		if delta > 0:
			var after_ek: int = console.EconomyServiceScript.deposit_ekwan(delta)
			console._print_line("[set_ekwan] ekwan: %d → %d (Δ+%d)" % [have, after_ek, delta])
			return 0
		elif delta < 0:
			var res2: Dictionary = console.EconomyServiceScript.try_spend_ekwan(-delta)
			if bool(res2.get("ok", false)):
				var rem2: int = int(res2.get("remaining", 0))
				console._print_line("[set_ekwan] ekwan: %d → %d (Δ%d)" % [have, rem2, delta])
				return 0
			else:
				console._print_line("[set_ekwan] failed: insufficient funds (have=%d need=%d)" % [int(res2.get("have",0)), int(res2.get("need",0))])
				return 2
		else:
			console._print_line("[set_ekwan] ekwan already %d" % have)
			return 0

	commands["/give_ase_float"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /give_ase_float <amount:float>")
			return 1
		var s := String(args[0])
		if not (s.is_valid_float() or s.is_valid_int()):
			console._print_line("/give_ase_float expects a numeric amount")
			return 1
		var amt_f: float = float(s)
		if amt_f == 0.0:
			console._print_line("Amount must be non-zero")
			return 1
		var eff_after: float = console._econ_service_inst.add_ase_float(amt_f)
		var banked2: int = int(console.EconomyServiceScript.get_ase_banked())
		var buf: float = float(console.EconomyServiceScript.get_ase_buffer())
		console._print_line("[give_ase_float] %+0.3f → buffer=%.3f, effective=%.3f, banked=%d" % [amt_f, buf, eff_after, banked2])
		return 0

	# Tests
	commands["/test_economy"] = func(args: Array) -> int:
		if args.size() > 0 and String(args[0]).to_lower() == "help":
			console._print_line("Usage: /test_economy ase [ticks=10] [faith] [tick_seconds=1.0]")
			console._print_line("       /test_economy live [seconds=5.0]")
			console._print_line("Note: faith is clamped to 0..100 to mirror the service.")
			return 0
		var mode := "ase"
		if args.size() > 0:
			mode = String(args[0]).to_lower()
		if mode == "live":
			var svc: Object = console._find_ase_service()
			if svc == null:
				console._print_line("[test_economy] live: AseTickService not found in the running scene")
				return 1
			# Duration to observe live ticks (default 5.0s); allow override via args[1]
			var seconds: float = 5.0
			if args.size() > 1:
				var sec_str := String(args[1])
				if sec_str.is_valid_float() or sec_str.is_valid_int():
					seconds = float(sec_str)
			if console._econ_live_active and console._econ_live_service and console._econ_live_service.is_connected("ase_generated", Callable(console, "_on_live_ase_generated")):
				console._econ_live_service.disconnect("ase_generated", Callable(console, "_on_live_ase_generated"))
			console._econ_live_active = true
			console._econ_live_sum = 0.0
			console._econ_live_count = 0
			console._econ_live_service = svc
			if not svc.is_connected("ase_generated", Callable(console, "_on_live_ase_generated")):
				svc.connect("ase_generated", Callable(console, "_on_live_ase_generated"))
			console._print_line("[test_economy] live: observing %s for %.1fs…" % [svc.name, seconds])
			var tmr: SceneTreeTimer = console.get_tree().create_timer(seconds)
			tmr.timeout.connect(Callable(console, "_finish_live_summary"))
			return 0
		elif mode != "ase":
			console._print_line("[test_economy] Unknown mode: %s (use 'ase' or 'live')" % mode)
			return 1
		var ticks := 10
		if args.size() > 1 and String(args[1]).is_valid_int():
			ticks = int(args[1])
		var faith := 60
		if console.has_node("/root/SaveService") and console.get_node("/root/SaveService").has_method("emotions_get_faith"):
			faith = int(console.get_node("/root/SaveService").emotions_get_faith())
		if args.size() > 2 and (String(args[2]).is_valid_int() or String(args[2]).is_valid_float()):
			faith = int(float(args[2]))
		var tick_seconds := 1.0
		if args.size() > 3 and String(args[3]).is_valid_float():
			tick_seconds = float(args[3])
		console._print_line("[test_economy] ase: ticks=%d faith=%d tick_seconds=%.3f" % [ticks, faith, tick_seconds])
		var ase: Object = console.AseTickService.new()
		ase.autostart = false
		ase.base_ase_per_min = 2.0
		ase.set_faith(faith)
		ase.set_tick_seconds(tick_seconds)
		var sum_ref := [0.0]
		var _on_ase_tick := func(amount: float, _total_after: float, tick_index: int) -> void:
			sum_ref[0] += amount
			console._print_line("[test_economy] tick %d +%.5f (acc=%.5f)" % [tick_index, amount, sum_ref[0]])
		ase.ase_generated.connect(_on_ase_tick)
		for i in range(ticks):
			ase._on_tick()
		var faith_eff: int = clampi(faith, 0, 100)
		var mult: float = EconomyConstants.faith_to_multiplier(faith_eff)
		var expected: float = (2.0 * mult) * (tick_seconds / 60.0) * float(ticks)
		var diff: float = abs(sum_ref[0] - expected)
		var tol: float = max(0.01 * expected, 0.0001)
		var ok: bool = diff <= tol
		console._print_line("[test_economy] expected=%.5f diff=%.5f tol=%.5f -> %s" % [expected, diff, tol, ("PASS" if ok else "FAIL")])
		return 0 if ok else 1

	# Emotions quick read
	commands["/get_faith"] = func(_args: Array) -> int:
		var val: int = -1
		if console.has_node("/root/SaveService") and console.get_node("/root/SaveService").has_method("emotions_get_faith"):
			val = int(console.get_node("/root/SaveService").emotions_get_faith())
			console._print_line("Faith = %d" % val)
			var svc: Object = console._find_ase_service()
			if svc:
				var v: Variant = svc.get("faith")
				if typeof(v) != TYPE_NIL:
					console._print_line("AseTickService faith (runtime) = %d" % int(v))
			if svc and svc.has_method("get_faith_multiplier"):
				var m := float(svc.get_faith_multiplier())
				console._print_line("Multiplier (runtime) = %.3f" % m)
			else:
				var m2 := EconomyConstants.faith_to_multiplier(int(val))
				console._print_line("Multiplier (by curve) = %.3f" % m2)
			return 0
		else:
			console._print_line("SaveService not available; cannot read faith")
			return 1

	# Alias typo
	commands["/get_fatih"] = commands["/get_faith"]

	# Emotions quick set
	commands["/set_faith"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /set_faith <0..100>")
			return 1
		var v_str := String(args[0])
		if not v_str.is_valid_int() and not v_str.is_valid_float():
			console._print_line("/set_faith expects an integer 0..100")
			return 1
		var v := int(float(v_str))
		var clamped := clampi(v, 0, 100)
		if console.has_node("/root/SaveService") and console.get_node("/root/SaveService").has_method("emotions_set_faith"):
			clamped = console.get_node("/root/SaveService").emotions_set_faith(clamped)
			console._print_line("Faith set to %d" % clamped)
			var svc: Object = console._find_ase_service()
			if svc and svc.has_method("set_faith"):
				svc.set_faith(clamped)
				console._print_line("AseTickService faith updated -> %d" % clamped)
			return 0
		else:
			console._print_line("SaveService not available; cannot persist faith")
			return 1

	# Ase multiplier
	commands["/ase_multiplier"] = func(_args: Array) -> int:
		var svc: Object = console._find_ase_service()
		if svc == null:
			console._print_line("[ase_multiplier] AseTickService not found in the running scene")
			return 1
		var base: float = 2.0
		var tick_s: float = 60.0
		var faith_i: int = 60
		var v: Variant
		v = svc.get("base_ase_per_min"); if typeof(v) != TYPE_NIL: base = float(v)
		v = svc.get("tick_seconds");     if typeof(v) != TYPE_NIL: tick_s = float(v)
		v = svc.get("faith");            if typeof(v) != TYPE_NIL: faith_i = int(v)
		var mult: float = EconomyConstants.faith_to_multiplier(clampi(faith_i, 0, 100))
		var per_tick: float = (base * mult) * (tick_s / 60.0)
		console._print_line("Faith=%d  Mult=%.3f  Base/min=%.3f  Tick_s=%.3f  Ase/tick=%.5f" % [faith_i, mult, base, tick_s, per_tick])
		return 0
