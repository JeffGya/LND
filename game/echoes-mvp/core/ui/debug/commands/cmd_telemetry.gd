extends RefCounted

static func register(console: Node, commands: Dictionary) -> void:
	commands["/telemetry"] = func(args: Array) -> int:
		if args.size() == 0:
			console._print_line("Usage: /telemetry <level|max|tail|clear> [value]")
			console._print_line("Levels: 0=OFF, 1=INFO, 2=DEBUG, 3=LIVE")
			return 1
		var sub := String(args[0]).to_lower()
		match sub:
			"level":
				if args.size() == 1:
					var current_level := int(console.get_node("/root/SaveService").telemetry_get_level())
					console._print_line("[telemetry] current level=%d (0=OFF,1=INFO,2=DEBUG,3=LIVE)" % current_level)
					return 0
				var s := String(args[1])
				if not s.is_valid_int():
					console._print_line("/telemetry level <0..3>")
					return 1
				var new_level := clampi(int(s), 0, 3)
				console.get_node("/root/SaveService").telemetry_set_level(new_level)
				console._print_line("[telemetry] level set to %d" % new_level)
				return 0
			"max":
				if args.size() == 1:
					var current_capacity := int(console.get_node("/root/SaveService").telemetry_tail(0).size())
					console._print_line("[telemetry] current max capacity=%d" % current_capacity)
					return 0
				var s2 := String(args[1])
				if not s2.is_valid_int():
					console._print_line("/telemetry max <1..1000>")
					return 1
				var new_max := int(s2)
				console.get_node("/root/SaveService").telemetry_set_max(new_max)
				console._print_line("[telemetry] max capacity set to %d" % new_max)
				return 0
			"tail":
				var count := 10
				if args.size() > 1 and String(args[1]).is_valid_int():
					count = int(args[1])
				var arr: Array = console.get_node("/root/SaveService").telemetry_tail(count)
				console._print_line("[telemetry] last %d events (%d total):" % [count, arr.size()])
				for ev in arr:
					var evt := ev as Dictionary
					var payload: Variant = (evt.get("payload") if evt.has("payload") else null)
					var ts_text := "?"
					if evt.has("ts"):
						ts_text = str(evt.get("ts"))
					elif payload is Dictionary and (payload as Dictionary).has("ts"):
						ts_text = str((payload as Dictionary).get("ts"))
					var type_text := "?"
					if evt.has("type"):
						type_text = str(evt.get("type"))
					elif payload is Dictionary and (payload as Dictionary).has("evt"):
						type_text = str((payload as Dictionary).get("evt"))
					var cat_text := "-"
					if payload is Dictionary and (payload as Dictionary).has("cat"):
						cat_text = str((payload as Dictionary).get("cat"))
					elif evt.has("cat"):
						cat_text = str(evt.get("cat"))
					var data_obj: Variant = {}
					if payload is Dictionary and (payload as Dictionary).has("data"):
						data_obj = (payload as Dictionary).get("data")
					elif evt.has("data"):
						data_obj = evt.get("data")
					console._print_line(" - %s [%s/%s] %s" % [ts_text, type_text, cat_text, str(data_obj)])
				return 0
			"clear":
				console.get_node("/root/SaveService").telemetry_clear()
				console._print_line("[telemetry] cleared")
				return 0
			_:
				console._print_line("Usage: /telemetry <level|max|tail|clear> [value]")
				return 1


