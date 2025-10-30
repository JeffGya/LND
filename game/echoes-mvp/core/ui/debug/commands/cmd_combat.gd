extends RefCounted

static func register(console: Node, commands: Dictionary) -> void:
	# /party_list
	var _cmd_party_list := func(_args: Array) -> int:
		var ss_dict: Dictionary = console._read_save_snapshot()
		var avail: Array[Dictionary] = console.PartyRoster.list_available_allies(ss_dict)
		if avail.is_empty():
			console._print_line("[party_list] no available heroes")
			return 0
		console._print_line("[party_list] %d available:" % avail.size())
		for h in avail:
			var hh: Dictionary = console._hydrate_hero_for_display(h)
			var id_i: int = int(hh.get("id", -1))
			console._print_line(" - " + console._format_hero_summary(hh) + " [id=%d]" % id_i)
		return 0
	commands["/party_list"] = _cmd_party_list

	# /party_set
	var _cmd_party_set := func(args: Array) -> int:
		if args.is_empty():
			console._print_line("Usage: /party_set <ids...>")
			return 1
		var ids_text: String = " ".join(args)
		var ids_raw: Array = ids_text.split(",")
		var ids_flat: Array = []
		for piece in ids_raw:
			var parts: Array = String(piece).strip_edges().split(" ")
			for p in parts:
				if p == "":
					continue
				ids_flat.append(p)
		var ids_norm: Array[int] = console.PartyRoster.normalize_ids(ids_flat)
		if ids_norm.is_empty():
			console._print_line("[party_set] no valid ids; example: /party_set 1 2 3")
			return 1
		var ss_dict: Dictionary = console._read_save_snapshot()
		var res: Dictionary = console.PartyRoster.validate_party(ss_dict, ids_norm, 3)
		if not bool(res.get("ok", false)):
			console._print_line("[party_set] invalid party:")
			for e in (res.get("errors", []) as Array):
				console._print_line(" - %s" % String(e))
			return 2
		console._staged_party = ids_norm
		console._print_line("[party_set] Party set: %s" % str(ids_norm))
		return 0
	commands["/party_set"] = _cmd_party_set

	# /party_show
	commands["/party_show"] = func(_args: Array) -> int:
		if console._staged_party.is_empty():
			console._print_line("[party_show] no staged party (use /party_set or /party_list)")
			return 0
		console._print_line("[party_show] %d heroes:" % console._staged_party.size())
		var idx: int = 1
		for pid in console._staged_party:
			var id_i: int = int(pid)
			var stub: Dictionary = {"id": id_i}
			var hfull: Dictionary = console._hydrate_hero_for_display(stub)
			console._print_line(" %d) %s" % [idx, console._format_hero_summary(hfull)])
			idx += 1
		return 0

	# /party_clear
	commands["/party_clear"] = func(_args: Array) -> int:
		console._staged_party.clear()
		console._print_line("[party_clear] cleared")
		return 0

	# /fight_demo
	commands["/fight_demo"] = func(args: Array) -> int:
		var seed_text: String = ""
		var rounds: int = 5
		var use_auto: bool = false
		if args.size() > 0:
			seed_text = String(args[0])
		if args.size() > 1 and String(args[1]).is_valid_int():
			rounds = clampi(int(args[1]), 1, 50)
		for a in args:
			if String(a) == "--auto":
				use_auto = true
		var seed_val: Variant = console._parse_seed(seed_text)
		if seed_val == null:
			seed_val = 0
		var party_ids: Array[int] = []
		for pid in console._staged_party:
			party_ids.append(int(pid))
		if party_ids.is_empty() and use_auto:
			var ss_dict: Dictionary = console._read_save_snapshot()
			var avail: Array[Dictionary] = console.PartyRoster.list_available_allies(ss_dict)
			for h in avail:
				if party_ids.size() >= 3:
					break
				party_ids.append(int(h.get("id", -1)))
		if party_ids.is_empty():
			console._print_line("[fight_demo] no party set. Use /party_set or add --auto")
			return 1
		var ss_dict2: Dictionary = console._read_save_snapshot()
		var res: Dictionary = console.PartyRoster.validate_party(ss_dict2, party_ids, 3)
		if not bool(res.get("ok", false)):
			console._print_line("[fight_demo] invalid party:")
			for e in (res.get("errors", []) as Array):
				console._print_line(" - %s" % String(e))
			return 2
		var enemies: Array[Dictionary] = console.EnemyFactory.spawn_dummy_pack(3, int(seed_val))
		var eng: Object = console.CombatEngine.new()
		console._current_eng = eng
		eng.start_battle(int(seed_val), party_ids, enemies, "defeat", rounds)
		var log: Object = console.CombatLog.new(16)
		console._print_line("[fight_demo] party=%s seed=%d rounds=%d" % [str(party_ids), int(seed_val), rounds])
		while not eng.is_over():
			var snap: Dictionary = eng.step_round()
			log.print_round(snap)
		console._print_line("[fight_demo] result: %s" % str(eng.result()))
		console._last_fight = {
			"seed": int(seed_val),
			"rounds": rounds,
			"party_ids": party_ids,
			"enemy_count": 3,
		}
		return 0

	# /fight_again
	commands["/fight_again"] = func(_args: Array) -> int:
		if console._last_fight.is_empty():
			console._print_line("[fight_again] nothing to replay (run /fight_demo first)")
			return 1
		var seed_v: int = int(console._last_fight.get("seed", 0))
		var rounds: int = int(console._last_fight.get("rounds", 5))
		var party_ids: Array[int] = console._last_fight.get("party_ids", [])
		var enemy_count: int = int(console._last_fight.get("enemy_count", 3))
		var enemies: Array[Dictionary] = console.EnemyFactory.spawn_dummy_pack(enemy_count, seed_v)
		var eng: Object = console.CombatEngine.new()
		console._current_eng = eng
		eng.start_battle(seed_v, party_ids, enemies, "defeat", rounds)
		var log: Object = console.CombatLog.new(16)
		console._print_line("[fight_again] party=%s seed=%d rounds=%d" % [str(party_ids), seed_v, rounds])
		while not eng.is_over():
			var snap: Dictionary = eng.step_round()
			log.print_round(snap)
		console._print_line("[fight_again] result: %s" % str(eng.result()))
		return 0

	# /morale_show
	var __morale_show := func(_args: Array) -> int:
		if console._current_eng == null:
			console._print_line("[morale_show] no active demo engine. Run /fight_demo or /fight_again first.")
			return 1
		var st_v: Variant = console._current_eng.get("_state")
		if typeof(st_v) != TYPE_DICTIONARY:
			console._print_line("[morale_show] engine state unavailable")
			return 1
		var st := st_v as Dictionary
		var allies: Array = st.get("allies", [])
		if allies.is_empty():
			console._print_line("[morale_show] no allies present in current engine state")
			return 0
		console._print_line("[morale_show] allies=%d" % allies.size())
		for a in allies:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var id_i: int = int((a as Dictionary).get("id", -1))
			var name_s: String = String((a as Dictionary).get("name", str(id_i)))
			var stats: Dictionary = (a as Dictionary).get("stats", {})
			var m := 50
			if typeof(stats) == TYPE_DICTIONARY and stats.has("morale"):
				m = int(stats.get("morale", 50))
			elif (a as Dictionary).has("morale"):
				m = int((a as Dictionary).get("morale", 50))
			var info: Dictionary = console._morale_label_and_mult(m)
			console._print_line(" - id=%d  name=%s  morale=%d  tier=%s  mult=%.2f" % [id_i, name_s, int(info["morale"]), String(info["label"]), float(info["mult"])])
		return 0
	commands["/morale_show"] = __morale_show

	# /morale_set
	var __morale_set := func(args: Array) -> int:
		if args.size() < 2:
			console._print_line("Usage: /morale_set <ally_id:int> <0..100>")
			return 1
		var s_id := String(args[0])
		var s_val := String(args[1])
		if not s_id.is_valid_int() or (not s_val.is_valid_int() and not s_val.is_valid_float()):
			console._print_line("Usage: /morale_set <ally_id:int> <0..100>")
			return 1
		var id_i := int(s_id)
		var val := int(float(s_val))
		var clamped := clampi(val, 0, 100)
		if console._current_eng == null:
			console._print_line("[morale_set] no active demo engine. Run /fight_demo or /fight_again first.")
			return 1
		var st_v2: Variant = console._current_eng.get("_state")
		if typeof(st_v2) != TYPE_DICTIONARY:
			console._print_line("[morale_set] engine state unavailable")
			return 1
		var st2 := st_v2 as Dictionary
		var allies2: Array = st2.get("allies", [])
		var enemies2: Array = st2.get("enemies", [])
		for e in enemies2:
			if typeof(e) == TYPE_DICTIONARY and int((e as Dictionary).get("id", -1)) == id_i:
				console._print_line("[morale_set] enemies do not use morale in MVP; no change made.")
				return 2
		var found: bool = false
		for i in range(allies2.size()):
			var ent: Dictionary = allies2[i] as Dictionary
			if typeof(ent) != TYPE_DICTIONARY:
				continue
			if int((ent as Dictionary).get("id", -1)) != id_i:
				continue
			found = true
			var name_s2: String = String((ent as Dictionary).get("name", str(id_i)))
			var stats2: Dictionary = (ent as Dictionary).get("stats", {})
			if typeof(stats2) != TYPE_DICTIONARY:
				stats2 = {}
			stats2["morale"] = clamped
			(ent as Dictionary)["stats"] = stats2
			(ent as Dictionary)["morale"] = clamped
			var info2: Dictionary = console._morale_label_and_mult(clamped)
			console._print_line("[morale_set] id=%d name=%s morale=%d tier=%s mult=%.2f" % [id_i, name_s2, int(info2["morale"]), String(info2["label"]), float(info2["mult"])])
			break
		if not found:
			console._print_line("[morale_set] no ally with id=%d in current engine state" % id_i)
			return 1
		return 0
	commands["/morale_set"] = __morale_set
