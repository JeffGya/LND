# core/combat/CombatLog.gd
# -----------------------------------------------------------------------------
# Human-readable logger for CombatEngine snapshots + tiny ring buffer.
# Prints a concise summary of each round: initiative, actions, ticks, end lines.
# Pure formatting: no coupling to engine internals beyond the snapshot shape.
# -----------------------------------------------------------------------------
class_name CombatLog

var _buffer: Array[Dictionary] = []
var _max_snapshots: int = 10

## Configure optional in-memory ring buffer (last N snapshots)
func _init(max_snapshots: int = 10) -> void:
	_max_snapshots = max(1, max_snapshots)

## Accepts a snapshot from CombatEngine.step_round() and prints nicely.
func print_round(snapshot: Dictionary) -> void:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return

	# --- Ring buffer maintenance ---------------------------------------------
	_buffer.append(snapshot)
	while _buffer.size() > _max_snapshots:
		_buffer.pop_front()

	# --- Header ---------------------------------------------------------------
	var r: int = int(snapshot.get("round", 0))
	print("\n— Round ", r, " —")

	# Optional name map for readable output (provided by CombatEngine)
	var name_by_id: Dictionary = snapshot.get("name_by_id", {})

	# --- Initiative list ------------------------------------------------------
	var order: Array = snapshot.get("order", [])
	if order.size() > 0:
		if typeof(name_by_id) == TYPE_DICTIONARY and name_by_id.size() > 0:
			print("Init:", _join_names(order, name_by_id))
		else:
			print("Init:", _join_ids(order))
	else:
		print("Init: (none)")

	# --- Actions --------------------------------------------------------------
	var actions: Array = snapshot.get("actions", [])
	for a in actions:
		print(_format_action(a))
	if actions.is_empty():
		print("(no actions)")

	# --- Ticks ---------------------------------------------------------------
	var ticks: Dictionary = snapshot.get("ticks", {})
	var fear_tick: int = int(ticks.get("fear", 0))
	var morale_decay: bool = bool(ticks.get("morale_decay", false))
	var md_text: String = "no"
	if morale_decay:
		md_text = "yes"
	print("Tick: fear+", fear_tick, "  morale_decay=", md_text)

	# --- Per-round state summary (if provided) -------------------------------
	var state_after: Dictionary = snapshot.get("state_after", {})
	if typeof(state_after) == TYPE_DICTIONARY and (state_after.has("allies") or state_after.has("enemies")):
		var allies_now: Array = state_after.get("allies", [])
		var enemies_now: Array = state_after.get("enemies", [])
		var allies_txt: String = _format_state_after_group(allies_now)
		var enemies_txt: String = _format_state_after_group(enemies_now)
		print("State: Allies ", allies_txt, " | Enemies ", enemies_txt)

	# --- End / Final state ----------------------------------------------------
	var end_info: Dictionary = snapshot.get("end", {})
	if typeof(end_info) == TYPE_DICTIONARY and end_info.has("victory"):
		var victory: bool = bool(end_info.get("victory", false))
		var reason: String = str(end_info.get("reason", ""))
		print("End: victory=", victory, " reason=", reason)

		var final_state: Dictionary = snapshot.get("final_state", {})
		if typeof(final_state) == TYPE_DICTIONARY and (final_state.has("allies") or final_state.has("enemies")):
			if typeof(name_by_id) == TYPE_DICTIONARY and name_by_id.size() > 0:
				print("Allies:", _format_group_with_names(final_state.get("allies", []), name_by_id))
				print("Enemies:", _format_group_with_names(final_state.get("enemies", []), name_by_id))
			else:
				print("Allies:", _format_group(final_state.get("allies", [])))
				print("Enemies:", _format_group(final_state.get("enemies", [])))
	elif typeof(end_info) == TYPE_DICTIONARY and end_info.has("ongoing"):
		print("(battle continues)")

## Returns a copy of the recent snapshot history (ring buffer contents)
func get_history() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _buffer:
		out.append(s)
	return out

## Clears the ring buffer
func clear() -> void:
	_buffer.clear()

# --- Formatting helpers -----------------------------------------------------

static func _join_ids(ids: Array) -> String:
	var parts: Array[String] = []
	for v in ids:
		parts.append(str(int(v)))
	return String(", ").join(parts)

static func _join_names(ids: Array, name_by_id: Dictionary) -> String:
	var parts: Array[String] = []
	for v in ids:
		var id_val: int = int(v)
		var nm: String = str(name_by_id.get(id_val, str(id_val)))
		parts.append(nm)
	return String(", ").join(parts)

static func _format_action(a: Dictionary) -> String:
	var t: int = int(a.get("type", -1))
	var actor: int = int(a.get("actor_id", -1))
	var actor_label: String = str(a.get("actor_name", str(actor)))
	match t:
		CombatConstants.ActionType.ATTACK:
			var target: int = int(a.get("target_id", -1))
			var target_label: String = str(a.get("target_name", str(target)))
			var dmg: int = int(a.get("dmg", 0))
			var ko: bool = bool(a.get("ko", false))
			var notes: String = str(a.get("notes", ""))
			var extra: String = ""
			if notes != "":
				extra = "  (" + notes + ")"
			var ko_tag: String = ""
			if ko:
				ko_tag = "  [KO]"
			# Optional hp context after resolution
			var hp_tag: String = ""
			if a.has("target_hp_after") and a.has("target_max_hp"):
				var hp_after: int = int(a.get("target_hp_after", 0))
				var hp_max: int = int(a.get("target_max_hp", 0))
				hp_tag = "  [%d/%d]" % [hp_after, hp_max]
			return "ATTACK %s → %s  dmg=%d%s%s%s" % [actor_label, target_label, dmg, extra, ko_tag, hp_tag]
		CombatConstants.ActionType.GUARD:
			var target_g: int = int(a.get("target_id", -1))
			var target_label_g: String = str(a.get("target_name", str(target_g)))
			var notes_g: String = str(a.get("notes", ""))
			var tag: String = "+shield"
			if notes_g == "guard_self":
				tag = "+shield self"
			var guard_tag: String = ""
			if a.has("target_guard_after"):
				guard_tag = "  [guard=%d]" % int(a.get("target_guard_after", 0))
			return "GUARD %s → %s  (%s)%s" % [actor_label, target_label_g, tag, guard_tag]
		CombatConstants.ActionType.MOVE:
			var target_m: int = int(a.get("target_id", -1))
			var target_label_m: String = str(a.get("target_name", str(target_m)))
			return "MOVE %s → %s  (advance)" % [actor_label, target_label_m]
		CombatConstants.ActionType.REFUSE:
			var notes_r: String = str(a.get("notes", "refuse"))
			return "REFUSE %s  (%s)" % [actor_label, notes_r]
		_:
			return "? %s  (unsupported)" % actor_label

static func _format_group(group: Array) -> String:
	if group.is_empty():
		return "[]"
	var parts: Array[String] = []
	for e in group:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_val: int = int(e.get("id", -1))
		var hp: int = 0
		var max_hp: int = 0
		if e.has("stats") and typeof(e["stats"]) == TYPE_DICTIONARY:
			hp = int((e["stats"] as Dictionary).get("hp", 0))
			max_hp = int((e["stats"] as Dictionary).get("max_hp", 0))
		else:
			hp = int(e.get("hp", 0))
			max_hp = int(e.get("max_hp", 0))
		var ko: bool = bool(e.get("ko", false)) or str(e.get("status", "")) == "downed"
		var ko_text: String = ""
		if ko:
			ko_text = " KO"
		var item: String = "{id:%d hp:%d/%d%s}" % [id_val, hp, max_hp, ko_text]
		parts.append(item)
	return "[ " + String(", ").join(parts) + " ]"

static func _format_group_with_names(group: Array, name_by_id: Dictionary) -> String:
	if group.is_empty():
		return "[]"
	var parts: Array[String] = []
	for e in group:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_val: int = int(e.get("id", -1))
		var name_str: String = str(name_by_id.get(id_val, str(id_val)))
		var hp: int = 0
		var max_hp: int = 0
		if e.has("stats") and typeof(e["stats"]) == TYPE_DICTIONARY:
			hp = int((e["stats"] as Dictionary).get("hp", 0))
			max_hp = int((e["stats"] as Dictionary).get("max_hp", 0))
		else:
			hp = int(e.get("hp", 0))
			max_hp = int(e.get("max_hp", 0))
		var ko: bool = bool(e.get("ko", false)) or str(e.get("status", "")) == "downed"
		var ko_text: String = ""
		if ko:
			ko_text = " KO"
		var item: String = "{%s hp:%d/%d%s}" % [name_str, hp, max_hp, ko_text]
		parts.append(item)
	return "[ " + String(", ").join(parts) + " ]"

# --- Per-round state summary formatter --------------------------------------
static func _format_state_after_group(group: Array) -> String:
	if group.is_empty():
		return "[]"
	var parts: Array[String] = []
	for e in group:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var name_str: String = str((e as Dictionary).get("name", "?"))
		var hp: int = int((e as Dictionary).get("hp", 0))
		var max_hp: int = int((e as Dictionary).get("max_hp", 0))
		var ko: bool = bool((e as Dictionary).get("ko", false))
		var guard_val: int = int((e as Dictionary).get("guard", 0))
		var tags: Array[String] = []
		if ko:
			tags.append("KO")
		if guard_val > 0:
			tags.append("guard=%d" % guard_val)
		var tag_txt: String = ""
		if not tags.is_empty():
			tag_txt = " [" + String(" ").join(tags) + "]"
		var item: String = "%s %d/%d%s" % [name_str, hp, max_hp, tag_txt]
		parts.append(item)
	return "{ " + String(", ").join(parts) + " }"