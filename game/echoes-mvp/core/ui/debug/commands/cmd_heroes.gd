extends RefCounted

static func register(console: Node, commands: Dictionary) -> void:
	# /summon
	commands["/summon"] = func(args: Array) -> int:
		var n: int = 1
		if args.size() > 0:
			var s := String(args[0])
			if not s.is_valid_int():
				console._print_line("Usage: /summon [count:int>=1]")
				return 1
			n = int(s)
			if n < 1:
				console._print_line("Count must be >= 1")
				return 1
		var res: Dictionary = console.SummonServiceScript.summon(n)
		if not bool(res.get("ok", false)):
			var reason := String(res.get("reason", ""))
			match reason:
				"insufficient_ase":
					var have := int(res.get("have", 0))
					var cost := int(res.get("cost", 0))
					var need := int(res.get("need", max(0, cost - have)))
					console._print_line("[summon] FAILED — Insufficient Ase (have=%d, need=%d, cost=%d)" % [have, need, cost])
					return 2
				"bad_count":
					console._print_line("[summon] FAILED — bad count (must be >= 1)")
					return 2
				"debit_failed":
					console._print_line("[summon] FAILED — economy debit failed")
					return 2
				_:
					console._print_line("[summon] FAILED — unknown reason")
					return 2
		var ids: Array = res.get("ids", [])
		var cost_ase: int = int(res.get("cost_ase", 0))
		console._print_line("[summon] OK — cost=%d, created=%d" % [cost_ase, ids.size()])
		if ids.is_empty():
			console._print_line("(warning) No heroes returned; check SaveService.heroes_add()")
			return 0
		var ss := console.get_node("/root/SaveService")
		for raw_id in ids:
			var id_i: int = int(raw_id)
			var h: Dictionary = ss.hero_get(id_i)
			console._print_line("✨ " + console._format_hero_summary(h))
			var bark_arch := String(h.get("archetype", ""))
			var bark_name := String(h.get("name", ""))
			var bark_line: String = console.ArchetypeBarks.arrival(bark_arch, bark_name)
			if bark_line != "":
				console._print_line("  " + "“%s”" % bark_line)
		return 0

	# /list_heroes
	commands["/list_heroes"] = func(args: Array) -> int:
		var limit: int = 10
		if args.size() > 0:
			var s := String(args[0])
			if not s.is_valid_int():
				console._print_line("Usage: /list_heroes [limit:int]")
				return 1
			limit = max(1, int(s))
		var ss := console.get_node("/root/SaveService")
		var roster: Array = ss.heroes_list()
		var total := roster.size()
		if total == 0:
			console._print_line("[list_heroes] No heroes yet.")
			return 0
		var start: int = max(0, total - limit)
		console._print_line("[list_heroes] showing %d of %d" % [total - start, total])
		for i in range(start, total):
			var h: Dictionary = roster[i]
			console._print_line(" - " + console._format_hero_summary(h))
		return 0

	# /hero_info
	commands["/hero_info"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /hero_info <id:int>")
			return 1
		var s := String(args[0])
		if not s.is_valid_int():
			console._print_line("/hero_info expects an integer id")
			return 1
		var id_i: int = int(s)
		var ss := console.get_node("/root/SaveService")
		var h: Dictionary = ss.hero_get(id_i)
		if typeof(h) != TYPE_DICTIONARY or h.is_empty():
			console._print_line("No hero with id %d" % id_i)
			return 1
		var name := String(h.get("name", "?"))
		var rank := int(h.get("rank", 0))
		var cls := String(h.get("class", "?"))
		var gen := String(h.get("gender", "?"))
		console._print_line("Hero %d: %s — r%d, class=%s, gender=%s" % [id_i, name, rank, cls, gen])
		var arch := String(h.get("archetype", ""))
		if arch != "":
			var arch_display := arch
			if typeof(console.EchoConstants) == TYPE_OBJECT and console.EchoConstants.ARCHETYPE_META.has(arch):
				var meta: Dictionary = console.EchoConstants.ARCHETYPE_META[arch]
				arch_display = String(meta.get("display_name", arch))
			console._print_line("  Archetype: %s  [debug: arch=%s]" % [arch_display, arch])
		else:
			console._print_line("  Archetype: n/a")
		var bark_line: String = console.ArchetypeBarks.arrival(arch, name)
		if bark_line != "":
			console._print_line("  Intro Bark: " + "“%s”" % bark_line)
		var tr: Dictionary = h.get("traits", {})
		var c := int(tr.get("courage", 0))
		var w := int(tr.get("wisdom", 0))
		var f := int(tr.get("faith", 0))
		var seed := int(h.get("seed", 0))
		var created := String(h.get("created_utc", ""))
		console._print_line("  Traits: Courage %d, Wisdom %d, Faith %d  |  Seed: %d  |  Created: %s" % [c, w, f, seed, created])
		return 0
