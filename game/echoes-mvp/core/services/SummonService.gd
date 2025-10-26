extends Resource
class_name SummonService

## SummonService — spend Ase → generate Echo(es) → persist → telemetry (Subtask 6)
##
## Contract
##   • Public static API: can_afford(), summon(), summon_cost().
##   • No UI; this is a headless service. Uses SaveService/EconomyService.
##   • Determinism lives in EchoFactory; we just provide seed/indices in order.
##   • Side-effect safety: On failure (insufficient Ase / debit failed), no roster changes.

# --------------
# Public API
# --------------
static func summon_cost() -> int:
	return EconomyConstants.ASE_SUMMON_COST

static func can_afford(count: int = 1) -> Dictionary:
	var c: int = max(1, count)
	var unit: int = summon_cost()
	var cost: int = unit * c
	var have: int = 0
	# EconomyService is a global class (not an autoload); call its static API directly.
	have = int(EconomyService.get_ase_banked())
	var need: int = max(0, cost - have)
	return {
		"ok": have >= cost,
		"have": have,
		"cost": cost,
		"need": need,
		"count": c
	}

static func summon(count: int = 1) -> Dictionary:
	# Validate request
	if count < 1:
		return {"ok": false, "reason": "bad_count", "have": 0, "cost": 0, "need": 0}

	var unit: int = summon_cost()
	var total_cost: int = unit * count

	# Balance check
	var have: int = int(EconomyService.get_ase_banked())
	if have < total_cost:
		return {"ok": false, "reason": "insufficient_ase", "have": have, "cost": total_cost, "need": total_cost - have}

	# Atomic debit (handle dict or bool result)
	var debit_ok: bool = false
	var spend_res: Variant = EconomyService.try_spend_ase(total_cost)
	if typeof(spend_res) == TYPE_DICTIONARY:
		debit_ok = bool(spend_res.get("ok", false))
	elif typeof(spend_res) == TYPE_BOOL:
		debit_ok = spend_res
	elif typeof(spend_res) == TYPE_INT:
		debit_ok = int(spend_res) != 0
	if not debit_ok:
		return {"ok": false, "reason": "debit_failed", "have": have, "cost": total_cost, "need": 0}

	# Deterministic generation loop
	var ids: Array = []
	var heroes: Array = []

	var save := _get_node_autoload("SaveService")
	var campaign_seed: int = _get_campaign_seed(save)
	var base_roster_size: int = 0
	if save and save.has_method("heroes_list"):
		base_roster_size = (save.heroes_list() as Array).size()

	for i in range(count):
		var roster_count: int = base_roster_size + i
		var utc_now := Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system(), true)
		var hero := EchoFactory.summon_one(campaign_seed, roster_count, utc_now)
		var new_id: int = -1
		if save and save.has_method("heroes_add"):
			new_id = int(save.heroes_add(hero))
		else:
			# Should not happen in MVP; warn and break to avoid partial roster
			push_warning("SummonService: SaveService.heroes_add not available")
			break
		ids.append(new_id)
		heroes.append(hero)

	# Telemetry breadcrumb (best-effort)
	_telemetry_summon(total_cost, count, ids, heroes)

	return {"ok": true, "cost_ase": total_cost, "count": count, "ids": ids, "heroes": heroes}

# --------------
# Private helpers
# --------------
static func _get_campaign_seed(save: Object) -> int:
	if save and save.has_method("get_campaign_seed"):
		return int(save.get_campaign_seed())
	if save and save.has_method("campaign_seed"):
		return int(save.campaign_seed)
	push_warning("SummonService: campaign_seed unavailable; using 0 (determinism reduced)")
	return 0

static func _telemetry_summon(total_cost: int, count: int, ids: Array, heroes: Array) -> void:
	# Best-effort: if a TelemetryService autoload exists with `log(event: Dictionary)`, use it.
	# Include a compact heroes preview so distributions can be analyzed later without loading saves.
	var preview: Array = []
	var n: int = min(ids.size(), heroes.size())
	for i in n:
		var id_i := int(ids[i])
		var h := heroes[i] as Dictionary
		var name := String(h.get("name", "?"))
		var arch := String(h.get("archetype", "n/a"))
		preview.append({
			"id": id_i,
			"name": name,
			"arch": arch,
			"seed": int(h.get("seed", 0))
		})

	var evt := {
		"evt": "summon",
		"cat": "heroes",
		"cost_ase": total_cost,
		"count": count,
		"ids": ids.duplicate(true),
		"heroes_preview": preview
	}
	var tele := _get_node_autoload("TelemetryService")
	if tele:
		_telemetry_emit(tele, evt)

		# Emit per-hero events to align with tailing that lists individual hero entries.
		# This mirrors the starter-hero event format and ensures summon-created heroes appear in tails.
		for p in preview:
			var pid := int((p as Dictionary).get("id", -1))
			var pname := String((p as Dictionary).get("name", "?"))
			var parch := String((p as Dictionary).get("arch", "n/a"))
			_telemetry_emit(tele, {
				"evt": "hero",
				"cat": "heroes",
				"id": pid,
				"name": pname,
				"arch": parch
			})

static func _get_node_autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var p := "/root/%s" % name
		if tree.root.has_node(p):
			return tree.root.get_node(p)
	return null

static func _telemetry_emit(tele: Object, evt: Dictionary) -> void:
	# Try several common logging method names for compatibility.
	if tele == null:
		return
	if tele.has_method("log"):
		tele.log(evt)
		return
	if tele.has_method("append"):
		tele.append(evt)
		return
	if tele.has_method("push"):
		tele.push(evt)
		return
