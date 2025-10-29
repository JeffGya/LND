extends RefCounted

static func register(console: Node, commands: Dictionary) -> void:
	# /new_game
	commands["/new_game"] = func(args: Array) -> int:
		var seed_arg := ""
		if args.size() > 0:
			seed_arg = String(args[0])
		var parsed_seed: Variant = console._parse_seed(seed_arg)
		if parsed_seed == null:
			var r := randi()
			parsed_seed = int(r & 0x7fffffff)
			console._print_line("[new_game] No seed provided, using random: %d (0x%08X)" % [parsed_seed, parsed_seed])
		SaveService.new_game(parsed_seed)
		var info = console.Seedbook.get_all_seed_info()
		console._print_line("[new_game] Campaign Seed => %s" % String(info.get("campaign_seed","")))
		if console.has_node("/root/SaveService"):
			var ss := console.get_node("/root/SaveService")
			if ss and ss.has_method("heroes_list"):
				var roster: Array = ss.heroes_list()
				if roster.size() > 0:
					var h: Dictionary = roster[0]
					console._print_line("[new_game] Starter hero granted: " + console._format_hero_summary(h))
					var bark_arch := String(h.get("archetype", ""))
					var bark_name := String(h.get("name", ""))
					var bark_line: String = String(console.ArchetypeBarks.arrival(bark_arch, bark_name))
					if bark_line != "":
						console._print_line("  " + "“%s”" % bark_line)
		return 0

	# /save
	commands["/save"] = func(_args: Array) -> int:
		var ok := SaveService.save_game()
		var ok_text := "OK" if ok else str(ok)
		console._print_line("[save] %s" % ok_text)
		return 0

	# /snapshot
	commands["/snapshot"] = func(_args: Array) -> int:
		var snap := SaveService.snapshot()
		var realms: Array = (snap.get("realm_states", []) as Array)
		var rb: Dictionary = (snap.get("campaign_run", {}) as Dictionary).get("rng_book", {})
		console._print_line("[snapshot] realms=%d, has_rng_book=%s" % [realms.size(), str(rb.size() > 0)])
		if rb.has("campaign_seed"):
			console._print_line("  campaign_seed=%s" % String(rb.get("campaign_seed","")))
		return 0

	# /diagnose_save
	commands["/diagnose_save"] = func(_args: Array) -> int:
		if SaveService.has_method("diagnose_load"):
			var diag := SaveService.diagnose_load()
			console._print_line("[diagnose_save] %s" % str(diag))
			return 0
		else:
			console._print_line("[diagnose_save] SaveService.diagnose_load() not available")
			return 1

	# /list_streams
	commands["/list_streams"] = func(_args: Array) -> int:
		var book := RNCatalogIO.pack_current()
		var subs: Dictionary = book.get("subseeds", {})
		var curs: Dictionary = book.get("cursors", {})
		console._print_line("Streams (%d):" % subs.size())
		for k in subs.keys():
			var cur := int(curs.get(k, 0))
			console._print_line(" - %s => %s (cursor=%d)" % [String(k), String(subs[k]), cur])
		return 0

	# /load
	commands["/load"] = func(args: Array) -> int:
		var target := ""
		if args.size() > 0:
			target = String(args[0])
		var ok := false
		var res: Variant = null
		if target == "" and SaveService.has_method("load_last"):
			res = SaveService.load_last()
			ok = bool(res)
		elif target != "" and SaveService.has_method("load_game"):
			res = SaveService.load_game(target)
			ok = bool(res)
		elif target == "" and SaveService.has_method("load_game"):
			res = SaveService.load_game()
			ok = bool(res)
		elif target != "" and SaveService.has_method("load_from_path"):
			res = SaveService.load_from_path(target)
			ok = bool(res)
		else:
			console._print_line("[load] No compatible load method on SaveService (expected: load_last, load_game, or load_from_path)")
			return 1
		console._print_line("[load] %s" % ("OK" if ok else "FAILED"))
		if ok:
			var info: Dictionary = console.Seedbook.get_all_seed_info()
			console._print_line("[load] Campaign Seed => %s" % String(info.get("campaign_seed", "")))
		return 0 if ok else 1

	# /list_saves
	commands["/list_saves"] = func(_args: Array) -> int:
		var paths := [SaveService.SAVE_PATH, SaveService.BAK_PATH]
		console._print_line("Save directory: %s" % ProjectSettings.globalize_path("user://"))
		for p in paths:
			var abs_path := ProjectSettings.globalize_path(p)
			if FileAccess.file_exists(p):
				var f := FileAccess.open(p, FileAccess.READ)
				var size := f.get_length()
				var text := f.get_as_text(); f.close()
				var last := ""
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					last = String((parsed as Dictionary).get("last_saved_utc", ""))
				console._print_line("%s => EXISTS (%d bytes) last_saved_utc=%s" % [abs_path, int(size), last])
			else:
				console._print_line("%s => missing" % abs_path)
		return 0
