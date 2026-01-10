

# core/combat/CombatSnapshotBuilder.gd
# -----------------------------------------------------------------------------
# Snapshot + helper builder for CombatEngine.
# Centralizes:
#   - name map (hero/enemy labels)
#   - per-round state_after summaries
#   - round snapshot dictionaries
#   - optional final_state attachment
#
# Pure formatting/state-shaping: no mutation of combat rules or RNG.
# -----------------------------------------------------------------------------
class_name CombatSnapshotBuilder

const CombatEntities = preload("res://core/combat/CombatEntities.gd")
const CombatEmotionSystem = preload("res://core/combat/CombatEmotionSystem.gd")

# Build a mapping from entity id -> display name for allies + enemies.
# Mirrors the previous CombatEngine._build_name_map implementation so that
# CombatLog and any debug UIs see identical labels.
static func build_name_map(state: Dictionary) -> Dictionary:
	var map: Dictionary = {}

	# Allies: try in-entity name, else hydrate from SaveService
	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a
		var id_val: int = int(ent.get("id", -1))

		# Shrine entries may use a reserved/negative id; always name them from the entity.
		if CombatEntities.is_shrine(ent):
			var shrine_name: String = str(ent.get("name", "Shrine"))
			map[id_val] = shrine_name
			continue

		if id_val < 0:
			continue

		var nm: String = ""
		if ent.has("name"):
			nm = str(ent.get("name", ""))
		if nm == "":
			nm = _hero_name_from_save(id_val)
		if nm == "":
			nm = "Hero %d" % id_val
		map[id_val] = nm

	# Enemies usually have a name inline; keep current fallback
	for e in state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_e: int = int(e.get("id", -1))
		if id_e < 0:
			continue
		var nm_e: String = ""
		if (e as Dictionary).has("name"):
			nm_e = str((e as Dictionary).get("name", ""))
		if nm_e == "":
			nm_e = "Enemy %d" % id_e
		map[id_e] = nm_e

	return map

# Internal helper: pull hero name from SaveService, matching legacy behavior.
static func _hero_name_from_save(id_val: int) -> String:
	var nm: String = ""
	# Prefer engine singleton SaveService if available
	if Engine.has_singleton("SaveService"):
		var svc: Variant = Engine.get_singleton("SaveService")
		if svc and svc.has_method("hero_get"):
			var v: Variant = svc.call("hero_get", id_val)
			if typeof(v) == TYPE_DICTIONARY:
				var d: Dictionary = v
				if d.has("name"):
					nm = str(d.get("name", ""))
					if nm != "":
						return nm
	# Fallback to autoload script instance if present
	if typeof(SaveService) != TYPE_NIL and SaveService.has_method("hero_get"):
		var v2: Variant = SaveService.hero_get(id_val)
		if typeof(v2) == TYPE_DICTIONARY:
			var d2: Dictionary = v2
			if d2.has("name"):
				nm = str(d2.get("name", ""))
				if nm != "":
					return nm
	return nm

# Build the per-round state_after block from the current engine state.
# This mirrors the previous inline implementation in CombatEngine so that
# CombatLog sees the same structure and values.
static func build_state_after(state: Dictionary, name_by_id: Dictionary) -> Dictionary:
	var out: Dictionary = {"allies": [], "enemies": []}

	# Allies: include morale info for QA / future UI hooks
	for a in state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent_a: Dictionary = a
		var hp_info: Dictionary = CombatEntities.read_hp_pair(ent_a)
		var ko_flag: bool = not _entity_alive(ent_a)
		var guard_val: int = int(ent_a.get("guard_shield", 0))
		var id_a: int = int(ent_a.get("id", -1))
		var item: Dictionary = {
			"id": id_a,
			"name": str(name_by_id.get(id_a, str(id_a))),
			"hp": int(hp_info.get("hp", 0)),
			"max_hp": int(hp_info.get("max_hp", 0)),
			"ko": ko_flag,
			"guard": guard_val,
			"morale": CombatEmotionSystem.get_morale(ent_a),
			"morale_tier": CombatEmotionSystem.morale_tier_label(CombatEmotionSystem.get_morale(ent_a)),
		}
		# Add grid metadata
		item["grid_pos"] = CombatEntities.get_grid_pos(ent_a)
		item["is_shrine"] = CombatEntities.is_shrine(ent_a)
		item["is_totem"] = CombatEntities.is_totem(ent_a)
		out["allies"].append(item)

	# Enemies: HP + guard, no morale (ignored in MVP)
	for e in state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ent_e: Dictionary = e
		var hp_info_e: Dictionary = CombatEntities.read_hp_pair(ent_e)
		var ko_flag_e: bool = not _entity_alive(ent_e)
		var guard_val_e: int = int(ent_e.get("guard_shield", 0))
		var id_e: int = int(ent_e.get("id", -1))
		var item_e: Dictionary = {
			"id": id_e,
			"name": str(name_by_id.get(id_e, str(id_e))),
			"hp": int(hp_info_e.get("hp", 0)),
			"max_hp": int(hp_info_e.get("max_hp", 0)),
			"ko": ko_flag_e,
			"guard": guard_val_e,
		}
		# Add grid metadata
		item_e["grid_pos"] = CombatEntities.get_grid_pos(ent_e)
		item_e["is_shrine"] = CombatEntities.is_shrine(ent_e)
		item_e["is_totem"] = CombatEntities.is_totem(ent_e)
		out["enemies"].append(item_e)

	return out

# Round snapshot builder. Takes the raw pieces from CombatEngine.step_round(...)
# and shapes them into the canonical snapshot dictionary used by CombatLog.
static func build_round_snapshot(
	state: Dictionary,
	round_index: int,
	order: Array,
	actions: Array,
	ticks: Dictionary,
	end_info: Dictionary,
	name_by_id: Dictionary
) -> Dictionary:
	var snapshot: Dictionary = {
		"round": round_index,
		"order": order,
		"actions": actions,
		"ticks": ticks,
		"end": end_info,
		"name_by_id": name_by_id,
		"state_after": build_state_after(state, name_by_id),
		"objective_context": state.get("objective_context", {}),
		"board_cols": int(state.get("board_cols", 0)),
		"board_rows": int(state.get("board_rows", 0)),
		"board_meta": {
			"cols": int(state.get("board_cols", 0)),
			"rows": int(state.get("board_rows", 0)),
		},
	}
	return snapshot

# Attach a final_state block when the battle concludes. This mirrors the
# previous behavior in CombatEngine so external callers see the same shape.
static func attach_final_state(snapshot: Dictionary, state: Dictionary) -> void:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return
	var final_state: Dictionary = {
		"allies": state.get("allies", []),
		"enemies": state.get("enemies", []),
	}
	snapshot["final_state"] = final_state

# Local helper: minimal alive check replicated from CombatEngine so we can
# correctly mark KO flags in build_state_after without mutating rules.
static func _entity_alive(ent: Dictionary) -> bool:
	var hp_pair: Dictionary = CombatEntities.read_hp_pair(ent)
	var hp: int = int(hp_pair.get("hp", 0))
	if hp <= 0:
		return false
	if str(ent.get("status", "")) == "downed":
		return false
	return true