# core/combat/CombatEngine.gd
# -----------------------------------------------------------------------------
# Deterministic, step-based round engine.
# Drives INITIATIVE → SELECT → RESOLVE → TICK → CHECK using the pure modules:
#   - Initiative.compute_order(ctx)
#   - EchoActionChooser.choose_action(hero, ctx)
#   - EnemyActionChooser.choose_action(enemy, ctx)
#   - ActionResolver.apply_major/apply_minor(action, ctx)
#
# Scope (MVP):
#  - Mutates *combat-local* state only. It does NOT write back to the meta-game
#    roster/save. Post-battle persistence belongs to the Recovery/Legacy epic.
#  - Returns per-round snapshots and a final result with final_state for consumers.
#
# Canon notes
#  - §3 Visible cadence: round structure is explicit and logged by CombatLog later.
#  - §4 Action economy: one intent per actor per round (ATTACK/REFUSE = Major,
#    GUARD/MOVE = Minor).
#  - §9 Determinism: same seed + same inputs ⇒ identical snapshots.
#  - §12 Gentle pacing: fear tick + morale decay applied as global round ticks.
# -----------------------------------------------------------------------------
# EnemyActionChooser.gd owns all enemy AI; CombatEngine only calls into it.

class_name CombatEngine


const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")
const CombatEntities = preload("res://core/combat/CombatEntities.gd")
const CombatEmotionSystem = preload("res://core/combat/CombatEmotionSystem.gd")
const CombatObjectives = preload("res://core/combat/CombatObjectives.gd")
const EnemyActionChooser = preload("res://core/combat/EnemyActionChooser.gd")
const CombatSnapshotBuilder = preload("res://core/combat/CombatSnapshotBuilder.gd")

# --- Engine state -------------------------------------------------------------
var _state: Dictionary = {}
# Morale overrides persist across battles (debug/QA support).
var _morale_overrides: Dictionary = {}

# --- Public API ---------------------------------------------------------------

## Initializes a deterministic battle state. Allies may be ids (ints) or dicts.
func start_battle(
		battle_seed: int,
		allies: Array,
		enemies: Array[Dictionary],
		objective: String = "defeat",
		round_limit: int = 10,
		stage_modifiers: Dictionary = {}
	) -> void:
	_state = {
		"seed": battle_seed,
		"round": 1,
		"over": false,
		"objective": objective,
		"round_limit": max(1, round_limit),
		# --- Board/grid metadata from GameBalance_HeroCombat ---
		"board_cols": HeroBal.COMBAT_BOARD_COLS,
		"board_rows": HeroBal.COMBAT_BOARD_ROWS,
		"ally_spawn_columns": HeroBal.COMBAT_ALLY_SPAWN_COLUMNS,
		"enemy_spawn_columns": HeroBal.COMBAT_ENEMY_SPAWN_COLUMNS,
		"shrine_grid_pos": HeroBal.COMBAT_SHRINE_GRID_POS,
		"totem_static_grid_pos": HeroBal.COMBAT_TOTEM_STATIC_GRID_POS,
		"attack_range": 1,  # MVP: everyone is adjacent unless a distance map is provided by caller
		"allies": _normalize_allies(allies),
		"enemies": _normalize_enemies(enemies),
		"last_snapshot": {},
		"result": {},
		# Fractional damage carryover buckets (per-attacker); populated/used by ActionResolver when enabled.
		"damage_bucket": {},
		"emotion_baseline": {},
		"shrine_purified_this_round": false,
		"shrine_purify_cd_remaining": 0,
		"shrine_purify_stacks": [],
		"designated_purifier_id": -1,
		"stage_modifiers": stage_modifiers,
	}
	# Apply any persisted morale overrides into the freshly built state
	_apply_morale_overrides()
	CombatEmotionSystem.capture_baseline(_state)
	_assign_designated_purifier()
	# Apply any persisted grid positions from stage_modifiers so multi-wave
	# objectives (e.g. Purify Shrine) can preserve hero/shrine locations
	# between waves. Positions are keyed by combat entity id.
	var ally_positions_raw: Variant = stage_modifiers.get("ally_positions_by_id", null)
	if typeof(ally_positions_raw) == TYPE_DICTIONARY:
		var ally_positions: Dictionary = ally_positions_raw
		var allies_arr: Array = _state.get("allies", [])
		for i in range(allies_arr.size()):
			var ent_v: Variant = allies_arr[i]
			if ent_v == null or typeof(ent_v) != TYPE_DICTIONARY:
				continue
			var ent: Dictionary = ent_v
			var id_val: int = int(ent.get("id", -1))
			# Allow special negative ids (e.g. shrine uses id=-1) to be restored.
			if id_val < -1:
				continue
			if ally_positions.has(id_val):
				var pos_v: Variant = ally_positions.get(id_val, null)
				if typeof(pos_v) == TYPE_VECTOR2I:
					CombatEntities.set_grid_pos(ent, pos_v)
					allies_arr[i] = ent
		_state["allies"] = allies_arr
	# After applying any restored positions, place entities for this objective.
	# For preserve_positions shrine waves, _auto_place_entities_for_objective()
	# will place enemies only and keep allies/shrine intact.
	_auto_place_entities_for_objective()
	_state["objective_context"] = CombatObjectives.build_objective_context(_state)

## Steps one round through INITIATIVE → SELECT → RESOLVE → TICK → CHECK.
## Returns a snapshot for logging/inspection.
func step_round() -> Dictionary:
	if _state.get("over", false):
		return _state.get("last_snapshot", {})

	var battle_seed: int = int(_state.seed)
	var round_index: int = int(_state.round)

	# 1) INITIATIVE -------------------------------------------------------------
	# Shrine-aware context: expose objective type and shrine id (if any) so
	# ActionResolver can treat negative shrine ids as valid targets and apply
	# shrine-specific rules.
	var objective_type: String = String(_state.get("objective", ""))
	var shrine_id: int = -9999
	if objective_type == "purify_shrine":
		var shrine_ent: Dictionary = CombatEntities.find_alive_shrine(_state.get("allies", []))
		if shrine_ent.size() > 0:
			shrine_id = int(shrine_ent.get("id", -1))

	var ctx: Dictionary = {
		"seed": battle_seed,
		"round_index": round_index,
		"allies": _state.allies,
		"enemies": _state.enemies,
		"attack_range": int(_state.attack_range),
		"damage_bucket": _state.damage_bucket,
		"objective_type": objective_type,
		"shrine_id": shrine_id,
		"shrine_purify_cd_remaining": int(_state.get("shrine_purify_cd_remaining", 0)),
		"designated_purifier_id": int(_state.get("designated_purifier_id", -1)),
	}
	var order: Array[int] = Initiative.compute_order(ctx)

	# Build a name map for readable logs (centralized in CombatSnapshotBuilder)
	var name_by_id: Dictionary = CombatSnapshotBuilder.build_name_map(_state)

	# 2) SELECT + 3) RESOLVE ----------------------------------------------------
	var actions: Array[Dictionary] = []
	var focus_hits: Dictionary = {}  # target_id -> number of times hit this round
	for actor_id in order:
		var ent: Variant = _find_entity(actor_id)
		if ent == null or typeof(ent) != TYPE_DICTIONARY:
			continue
		var ent_dict: Dictionary = ent
		# Shrine and other non-acting entities never take turns.
		if CombatEntities.is_shrine(ent_dict):
			continue
		if ent_dict.has("can_act") and not bool(ent_dict.get("can_act", true)):
			continue
		if not CombatEntities.is_alive(ent_dict):
			continue

		# Fear-first refusal check (MVP)
		# We do this BEFORE normal action selection so that fear can override
		# even when morale is still STEADY. ActionResolver pulls values from
		# GameBalance_HeroCombat.gd so we don't hardcode thresholds here.
		var fear_check: Dictionary = ActionResolver.should_refuse_turn(ent_dict)
		if bool(fear_check.get("refuse", false)):
			var fear_effect: Dictionary = _apply_fear_outcome(fear_check, ent_dict, ctx)
			# Decorate effect with names just like normal actions so logs stay consistent
			var actor_name_fc: String = str(name_by_id.get(actor_id, str(actor_id)))
			fear_effect["actor_name"] = actor_name_fc
			# Canonical verb for logging
			fear_effect["verb"] = _action_type_to_verb(int(fear_effect.get("type", -1)))
			actions.append(fear_effect)
			continue

		# Build latest ctx (mutated state is shared across loop iterations)
		ctx.allies = _state.allies
		ctx.enemies = _state.enemies

		var side := _side_of(actor_id)
		var action: Dictionary
		if side == "ALLY":
			action = EchoActionChooser.choose_action(ent_dict, ctx)
		else:
			action = EnemyActionChooser.choose_action(ent_dict, ctx)

		# C2: per-turn movement on the invisible grid.
		# If the chosen action is melee-based and the target is out of range,
		# this helper may convert it into a MOVE and perform a 1-cell step.
		_maybe_apply_greedy_step(action, actor_id)

		# Apply via resolver according to action type
		var t := int(action.get("type", -1))
		var effect: Dictionary
		match t:
			CombatConstants.ActionType.ATTACK, CombatConstants.ActionType.REFUSE, CombatConstants.ActionType.PURIFY_SHRINE:
				effect = ActionResolver.apply_major(action, ctx)
			CombatConstants.ActionType.GUARD, CombatConstants.ActionType.MOVE:
				effect = ActionResolver.apply_minor(action, ctx)
			_:
				effect = {
					"ok": false,
					"type": t,
					"actor_id": int(action.get("actor_id", -1)),
					"verb": _action_type_to_verb(t),
					"notes": "unsupported_action",
				}
		# Decorate effect with names and post-effect context for logging
		var actor_name: String = str(name_by_id.get(actor_id, str(actor_id)))
		effect["actor_name"] = actor_name
		if effect.has("target_id"):
			var tid: int = int(effect.get("target_id", -1))
			var target_ent: Variant = _find_entity(tid)
			var target_name: String = str(name_by_id.get(tid, str(tid)))
			effect["target_name"] = target_name
			if target_ent != null and typeof(target_ent) == TYPE_DICTIONARY:
				var hp_pair: Dictionary = CombatEntities.read_hp_pair(target_ent)
				effect["target_hp_after"] = int(hp_pair.get("hp", 0))
				effect["target_max_hp"] = int(hp_pair.get("max_hp", 0))
				# For guard actions, surface guard stack after application
				if int(effect.get("type", -1)) == CombatConstants.ActionType.GUARD:
					var guard_after: int = int((target_ent as Dictionary).get("guard_shield", 0))
					effect["target_guard_after"] = guard_after
		# Canonical verb for logging
		effect["verb"] = _action_type_to_verb(int(effect.get("type", -1)))

		# --- Preserve / derive morale QA fields so CombatLog can display them ----------
		var eff_type := int(effect.get("type", -1))
		if eff_type == CombatConstants.ActionType.ATTACK:
			# If the resolver already set morale fields, keep them; otherwise derive them here.
			var has_mult := effect.has("morale_mult")
			var has_tier := effect.has("morale_tier")
			if side == "ALLY":
				if (not has_mult) or (not has_tier):
					# Derive from the current attacker entity
					var m_val: int = CombatEmotionSystem.get_morale(ent_dict)
					# Use enum tier to avoid string drift, then map to label and multiplier
					var tier_enum: int = CombatConstants.morale_tier(m_val)
					var tier_label: String = CombatEmotionSystem.morale_tier_label(m_val)
					var mult_val: float = 1.0
					if CombatConstants.MORALE_MULTIPLIERS is Dictionary:
						mult_val = float(CombatConstants.MORALE_MULTIPLIERS.get(tier_enum, 1.0))
					# Only write if missing to avoid clobbering resolver values
					if not has_tier:
						effect["morale_tier"] = tier_label
					if not has_mult:
						effect["morale_mult"] = mult_val
			else:
				# Enemies ignore morale in MVP; ensure tag stays neutral
				if not has_tier:
					effect["morale_tier"] = null
				if not has_mult:
					effect["morale_mult"] = 1.0
		elif eff_type == CombatConstants.ActionType.REFUSE:
			# If refusal is due to broken state, ensure tier is surfaced for clarity
			var note_s := String(effect.get("notes", ""))
			if note_s == "broken":
				if not effect.has("morale_tier"):
					effect["morale_tier"] = "BROKEN"
				if not effect.has("morale_mult"):
					effect["morale_mult"] = 1.0

		# Shrine purification effects (moved to CombatObjectives)
		CombatObjectives.apply_purify_shrine_effects(_state, effect, HeroBal)

		# Fear accrual from impactful events (MVP)
		# If this action actually hit a target, increase that target's fear.
		# We look for an ATTACK effect with a target_id and ok=true.
		if eff_type == CombatConstants.ActionType.ATTACK and effect.get("ok", true):
			var tid2: int = int(effect.get("target_id", -1))
			if tid2 >= 0:
				# track focus hits in this round
				var prev_hits: int = int(focus_hits.get(tid2, 0))
				var extra_focus: int = 0
				if prev_hits > 0:
					extra_focus = HeroBal.FEAR_PER_FOCUS_HIT
				# apply to the actual entity so the next turn sees the higher fear
				CombatEmotionSystem.increase_fear_on_entity(_state, tid2, HeroBal.FEAR_PER_HIT + extra_focus, HeroBal)
				# store back hit count
				focus_hits[tid2] = prev_hits + 1
		actions.append(effect)

	# After all actions, apply KO shock to surviving allies
	CombatEmotionSystem.apply_ally_ko_fear(_state, HeroBal)

	# 4) TICK (fear & morale cadence) ------------------------------------------
	var tick_info: Dictionary = CombatEmotionSystem.apply_round_tick(_state, HeroBal)

	# 5) CHECK end conditions ---------------------------------------------------
	var end_info: Dictionary = _check_end()

	# Refresh objective context each round so any objective-driven UIs or
	# loggers see up-to-date shrine HP and alive counts instead of the
	# initial snapshot created at battle start.
	_state["objective_context"] = CombatObjectives.build_objective_context(_state)

	# Build canonical snapshot via CombatSnapshotBuilder so UI/loggers see
	# a stable, centralized shape.
	var snapshot: Dictionary = CombatSnapshotBuilder.build_round_snapshot(
		_state,
		round_index,
		order,
		actions,
		tick_info,
		end_info,
		name_by_id
	)

	_state.last_snapshot = snapshot

	# Prepare next round or finalize
	if not _state.over:
		_state.round = round_index + 1
	else:
		# Package a final_state for external consumers (no persistence here)
		CombatSnapshotBuilder.attach_final_state(_state.last_snapshot, _state)

	return _state.last_snapshot

## Whether the battle has concluded.
func is_over() -> bool:
	return bool(_state.get("over", false))

## Result after the battle is over.
func result() -> Dictionary:
	return _state.get("result", {})

## Returns a shallow copy of internal state useful for debug UIs.
func get_state() -> Dictionary:
	return _state.duplicate(true)


# --- Internal helpers --------------------------------------------------------


# --- Board/grid helpers ----------------------------------------------
# These helpers and the associated state keys form the *public contract* for
# the invisible grid:
#   - `board_cols`, `board_rows`
#   - `ally_spawn_columns`, `enemy_spawn_columns`
#   - `shrine_grid_pos`, `totem_static_grid_pos`
#
# They are populated once in `start_battle()` from GameBalance_HeroCombat and
# then treated as authoritative for the lifetime of the battle. Callers should
# query them via these helpers instead of reaching into `_state` directly.
#
# All helpers are intentionally tiny and defensive. They do not assume that
# board metadata has already been configured; if board_cols/board_rows are
# missing or zero, they simply treat the board as "non-existent" so callers
# can early-out safely.

func _get_board_cols(state: Dictionary) -> int:
	# Returns configured board_cols from the given state dictionary, or 0 if
	# not present or invalid. Using state.get(...) keeps this tolerant of
	# older battles that don't yet carry grid metadata.
	if typeof(state) != TYPE_DICTIONARY:
		return 0
	return int(state.get("board_cols", 0))

func _get_board_rows(state: Dictionary) -> int:
	# Returns configured board_rows from the given state dictionary, or 0 if
	# not present or invalid.
	if typeof(state) != TYPE_DICTIONARY:
		return 0
	return int(state.get("board_rows", 0))

func is_inside_board(pos: Vector2i, state: Dictionary) -> bool:
	# True if the given grid position lies within the configured board
	# rectangle. If the board is not configured yet (cols/rows <= 0), this
	# returns false for all positions.
	var cols := _get_board_cols(state)
	var rows := _get_board_rows(state)
	if cols <= 0 or rows <= 0:
		return false
	return pos.x >= 0 and pos.x < cols and pos.y >= 0 and pos.y < rows

func clamp_to_board(pos: Vector2i, state: Dictionary) -> Vector2i:
	# Clamps the given grid position into the valid board rectangle. If the
	# board is not configured yet (cols/rows <= 0), this returns the input
	# position unchanged so callers don't accidentally fabricate coordinates.
	var cols := _get_board_cols(state)
	var rows := _get_board_rows(state)
	if cols <= 0 or rows <= 0:
		return pos
	return Vector2i(
		clamp(pos.x, 0, cols - 1),
		clamp(pos.y, 0, rows - 1)
	)

func cycle_row(index: int, state: Dictionary) -> int:
	# Utility for placement helpers: cycles an arbitrary index into a valid
	# row index using the configured board_rows. If rows are not configured
	# yet (rows <= 0), this returns the original index so test harnesses and
	# legacy callers can still pass integers through without crashing.
	var rows := _get_board_rows(state)
	if rows <= 0:
		return index
	# Use modulo to wrap into [0, rows-1].
	return index % rows

# --- Board/grid wrappers ----------------------------------------------
# Thin engine-level helpers that operate on the current `_state` and delegate
# position math to CombatEntities. These are intentionally small so that
# ActionResolver, EnemyActionChooser and future objective logic can ask the
# engine simple spatial questions without touching `_state` internals.

func get_board_size() -> Vector2i:
	# Returns the current board size as a Vector2i(cols, rows). If the board
	# is not configured yet, this returns (0, 0).
	var cols := _get_board_cols(_state)
	var rows := _get_board_rows(_state)
	return Vector2i(cols, rows)

func get_entity_grid_pos(entity_id: int) -> Vector2i:
	# Convenience wrapper: resolves an entity by id from the current `_state`
	# and returns its grid_pos via CombatEntities.get_grid_pos. If no such
	# entity exists or it has no grid_pos, returns GRID_POS_UNSET.
	var ent: Variant = _find_entity(entity_id)
	if ent == null or typeof(ent) != TYPE_DICTIONARY:
		return CombatEntities.GRID_POS_UNSET
	return CombatEntities.get_grid_pos(ent as Dictionary)

func get_distance_between_entities(a_id: int, b_id: int) -> int:
	# Convenience wrapper for Manhattan distance between two entities on the
	# current board. Returns -1 if either entity is missing or unplaced.
	var a: Variant = _find_entity(a_id)
	var b: Variant = _find_entity(b_id)
	if a == null or typeof(a) != TYPE_DICTIONARY:
		return -1
	if b == null or typeof(b) != TYPE_DICTIONARY:
		return -1
	return CombatEntities.grid_distance_between_entities(a as Dictionary, b as Dictionary)


func entities_are_adjacent(a_id: int, b_id: int) -> bool:
	# Returns true if two entities are in melee range (same cell or 4-neighbour)
	# according to their grid_pos values.
	var a: Variant = _find_entity(a_id)
	var b: Variant = _find_entity(b_id)
	if a == null or typeof(a) != TYPE_DICTIONARY:
		return false
	if b == null or typeof(b) != TYPE_DICTIONARY:
		return false
	return CombatEntities.entities_are_adjacent(a as Dictionary, b as Dictionary)

# --- Spatial query helpers ---------------------------------------------
# These helpers provide higher-level spatial queries on top of the
# lower-level wrappers above. They are intended for ActionResolver,
# EnemyActionChooser and objective logic so they can ask simple questions
# ("who is on this cell?", "who is the closest enemy?") without recreating
# grid math or digging into `_state`.

func get_entities_at_pos(pos: Vector2i, alive_only: bool = true) -> Array:
	# Returns all entities (allies + enemies) currently occupying the given
	# grid cell. When `alive_only` is true, KO entities are filtered out.
	var all: Array = []
	all.append_array(_state.get("allies", []))
	all.append_array(_state.get("enemies", []))
	if all.is_empty():
		return []
	return CombatEntities.find_entities_at(all, pos, alive_only)

func get_allies_at_pos(pos: Vector2i, alive_only: bool = true) -> Array:
	# Returns all allies occupying the given grid cell. When `alive_only`
	# is true, KO allies are filtered out.
	var allies: Array = _state.get("allies", [])
	if allies.is_empty():
		return []
	return CombatEntities.find_entities_at(allies, pos, alive_only)

func get_enemies_at_pos(pos: Vector2i, alive_only: bool = true) -> Array:
	# Returns all enemies occupying the given grid cell. When `alive_only`
	# is true, KO enemies are filtered out.
	var enemies: Array = _state.get("enemies", [])
	if enemies.is_empty():
		return []
	return CombatEntities.find_entities_at(enemies, pos, alive_only)

func get_closest_enemy_to(entity_id: int, alive_only: bool = true) -> Dictionary:
	# Returns the closest enemy entity (by Manhattan distance) to the given
	# entity id, or an empty dictionary if no suitable enemy exists or the
	# origin entity is not placed on the board.
	var origin_pos: Vector2i = get_entity_grid_pos(entity_id)
	if origin_pos == CombatEntities.GRID_POS_UNSET:
		return {}
	var enemies: Array = _state.get("enemies", [])
	if enemies.is_empty():
		return {}
	var found = CombatEntities.find_closest_entity_to_pos(enemies, origin_pos, alive_only)
	if found == null:
		return {}
	return found

func get_closest_ally_to(entity_id: int, alive_only: bool = true) -> Dictionary:
	# Returns the closest ally entity (by Manhattan distance) to the given
	# entity id, or an empty dictionary if no suitable ally exists or the
	# origin entity is not placed on the board.
	var origin_pos: Vector2i = get_entity_grid_pos(entity_id)
	if origin_pos == CombatEntities.GRID_POS_UNSET:
		return {}
	var allies: Array = _state.get("allies", [])
	if allies.is_empty():
		return {}
	var found = CombatEntities.find_closest_entity_to_pos(allies, origin_pos, alive_only)
	if found == null:
		return {}
	return found


func can_entity_move(entity_id: int) -> bool:
	# Returns true if the given entity is allowed to move on the grid in
	# the current battle. MVP rules:
	#   - entity must exist and be alive
	#   - shrines and other non-mobile structures are treated as immobile
	#   - an explicit `can_move = false` flag on the entity disables movement
	var ent_v: Variant = _find_entity(entity_id)
	if ent_v == null or typeof(ent_v) != TYPE_DICTIONARY:
		return false
	var ent: Dictionary = ent_v
	if not CombatEntities.is_alive(ent):
		return false
	# Structures like shrines are stationary.
	if CombatEntities.is_shrine(ent):
		return false
	if ent.has("can_move"):
		return bool(ent.get("can_move", true))
	return true

# --- C3.1 engine-level spatial helpers for AI/objective logic ---------------
# These helpers provide targeting and counting logic for use by AI and objectives.
# They operate directly on the current `_state`.

func get_melee_targets_for(entity_id: int, side: String, alive_only: bool = true) -> Array:
	# C3.1 helper: Returns all adjacent entities from the opposing side for
	# the given entity_id. `side` describes the origin entity's allegiance
	# ("ALLY" / "ENEMY"). Used by AI/objectives for melee targeting.
	# If side is unknown, we defensively search both sides.
	var origin_v: Variant = _find_entity(entity_id)
	if origin_v == null or typeof(origin_v) != TYPE_DICTIONARY:
		return []
	var origin: Dictionary = origin_v

	var pool: Array = []
	if side == "ALLY" or side == "allies":
		pool = _state.get("enemies", [])
	elif side == "ENEMY" or side == "enemies":
		pool = _state.get("allies", [])
	else:
		# Defensive: search both sides if the side string is unexpected.
		pool = []
		var allies = _state.get("allies", [])
		if typeof(allies) == TYPE_ARRAY:
			pool.append_array(allies)
		var enemies = _state.get("enemies", [])
		if typeof(enemies) == TYPE_ARRAY:
			pool.append_array(enemies)

	if pool.is_empty():
		return []

	var matches: Array = []
	for ent in pool:
		if typeof(ent) != TYPE_DICTIONARY:
			continue
		if alive_only and not CombatEntities.is_alive(ent):
			continue
		if CombatEntities.entities_are_adjacent(origin, ent):
			matches.append(ent)

	return matches

func get_nearest_enemy_for(entity_id: int, alive_only: bool = true) -> Dictionary:
	# C3.1 helper: Returns the nearest enemy entity to the given entity_id, or {} if none found.
	var origin_pos: Vector2i = get_entity_grid_pos(entity_id)
	if origin_pos == CombatEntities.GRID_POS_UNSET:
		return {}
	var side := _side_of(entity_id)
	var pool: Array = []
	if side == "ALLY":
		pool = _state.get("enemies", [])
	elif side == "ENEMY":
		pool = _state.get("allies", [])
	else:
		pool = _state.get("enemies", [])
	if pool.is_empty():
		return {}
	var found = CombatEntities.find_closest_entity_to_pos(pool, origin_pos, alive_only)
	if found == null:
		return {}
	return found

func get_nearest_ally_for(entity_id: int, alive_only: bool = true) -> Dictionary:
	# C3.1 helper: Returns the nearest ally entity to the given entity_id, or {} if none found.
	var origin_pos: Vector2i = get_entity_grid_pos(entity_id)
	if origin_pos == CombatEntities.GRID_POS_UNSET:
		return {}
	var allies: Array = _state.get("allies", [])
	if allies.is_empty():
		return {}
	var found = CombatEntities.find_closest_entity_to_pos(allies, origin_pos, alive_only)
	if found == null:
		return {}
	return found

func get_alive_counts() -> Dictionary:
	# C3.1 helper: Returns a dictionary with counts of alive allies and enemies.
	var allies_alive := 0
	var enemies_alive := 0
	for ent in _state.get("allies", []):
		if typeof(ent) == TYPE_DICTIONARY and CombatEntities.is_alive(ent):
			allies_alive += 1
	for ent in _state.get("enemies", []):
		if typeof(ent) == TYPE_DICTIONARY and CombatEntities.is_alive(ent):
			enemies_alive += 1
	return { "allies": allies_alive, "enemies": enemies_alive }


# --------------------------------------------------------------------------
# Per-turn movement (C2): Greedy step and action conversion helpers
# --------------------------------------------------------------------------

func _compute_step_towards(origin: Vector2i, target: Vector2i) -> Vector2i:
	# C2 helper: returns the next grid cell when taking a 1-tile
	# greedy Manhattan step from `origin` toward `target`.
	# Preference order:
	#   1) Horizontal step that reduces |dx|
	#   2) Vertical step that reduces |dy|
	# If origin == target, returns origin unchanged.
	var dx: int = target.x - origin.x
	var dy: int = target.y - origin.y
	var next: Vector2i = origin

	if dx != 0 and abs(dx) >= abs(dy):
		var step_x: int = 0
		if dx > 0:
			step_x = 1
		else:
			step_x = -1
		next.x += step_x
	elif dy != 0:
		var step_y: int = 0
		if dy > 0:
			step_y = 1
		else:
			step_y = -1
		next.y += step_y

	return next


func _maybe_apply_greedy_step(action: Dictionary, actor_id: int) -> void:
	# Called from step_round() before resolving a major action.
	# If the action is a melee-style ATTACK (or shrine purification attack)
	# and the target is not within attack_range on the grid, we convert the
	# action into a 1-cell MOVE toward the target for this turn.
	if typeof(action) != TYPE_DICTIONARY:
		return

	# Only care about ATTACK-like actions.
	var t: int = int(action.get("type", -1))
	if t != CombatConstants.ActionType.ATTACK and t != CombatConstants.ActionType.PURIFY_SHRINE:
		return

	# Quick board sanity: if the board is not configured, we do not try to
	# apply grid-based movement so legacy/non-grid battles keep working.
	var cols: int = _get_board_cols(_state)
	var rows: int = _get_board_rows(_state)
	if cols <= 0 or rows <= 0:
		return

	# Actor must be allowed to move in this battle.
	if not can_entity_move(actor_id):
		return

	# We need a concrete target id to walk toward. Be tolerant of older
	# action shapes that may use `enemy_id` or `target` instead.
	var target_id: int = -1
	if action.has("target_id"):
		# Preferred modern shape: explicit target id.
		target_id = int(action.get("target_id", -1))
	elif action.has("enemy_id"):
		# Older ATTACK shapes sometimes used `enemy_id`.
		target_id = int(action.get("enemy_id", -1))
	elif action.has("target"):
		# Be tolerant of legacy `target` fields that may already be an id.
		target_id = int(action.get("target", -1))

	# Shrine-aware fallback: for Purify Shrine / Protect Shrine style objectives,
	# some enemy ATTACK intents may not carry a concrete target id even though
	# they conceptually aim at the shrine. In those cases, we resolve the shrine
	# entity from the current state and walk toward it using the same greedy
	# movement rules as for hero-vs-enemy melee.
	if target_id < 0:
		var objective_s: String = String(_state.get("objective", ""))
		var is_shrine_objective := (
			objective_s == "purify_shrine" or
			objective_s == CombatConstants.OBJECTIVE_PROTECT_SHRINE
		)
		if is_shrine_objective and _side_of(actor_id) == "ENEMY":
			var shrine_ent: Dictionary = CombatEntities.find_alive_shrine(_state.get("allies", []))
			if shrine_ent.size() > 0:
				var shrine_id: int = int(shrine_ent.get("id", -1))
				if shrine_id >= 0:
					target_id = shrine_id
					action["target_id"] = shrine_id

	# If we still do not have a valid target id, we cannot apply a spatial
	# step safely; fall back to the original ATTACK behavior.
	if target_id < 0:
		return

	# Normalise: make sure `target_id` is present so later code
	# (resolver/logging) can rely on it.
	action["target_id"] = target_id

	# Read positions from the current engine state.
	var from_pos: Vector2i = get_entity_grid_pos(actor_id)
	var target_pos: Vector2i = get_entity_grid_pos(target_id)

	# If the actor itself is not placed on the board, we cannot move it.
	if from_pos == CombatEntities.GRID_POS_UNSET:
		return

	# Shrine/objective fallback:
	# In some shrine stages, the shrine entity id used for targeting may not
	# resolve cleanly back into a placed entity (e.g. legacy ids or snapshots).
	# If the direct lookup failed, but this is a shrine-style objective, try
	# to resolve the shrine entity directly from the current allies array and
	# use its grid_pos as the movement target.
	if target_pos == CombatEntities.GRID_POS_UNSET:
		var objective_s: String = String(_state.get("objective", ""))
		var is_shrine_objective := (
			objective_s == "purify_shrine" or
			objective_s == CombatConstants.OBJECTIVE_PROTECT_SHRINE
		)
		if is_shrine_objective:
			var shrine_ent: Dictionary = CombatEntities.find_alive_shrine(_state.get("allies", []))
			if shrine_ent.size() > 0:
				target_pos = CombatEntities.get_grid_pos(shrine_ent)

	# If we still do not have a valid target position, bail out.
	if target_pos == CombatEntities.GRID_POS_UNSET:
		return

	# If already in range (Manhattan distance <= attack_range), do not convert
	# to MOVE; the attack can resolve as normal.
	var attack_range: int = int(_state.get("attack_range", 1))
	var dist: int = abs(target_pos.x - from_pos.x) + abs(target_pos.y - from_pos.y)
	if dist <= attack_range:
		return

	# Greedy Manhattan step toward target:
	var dx: int = target_pos.x - from_pos.x
	var dy: int = target_pos.y - from_pos.y
	var next_pos: Vector2i = from_pos

	# Prefer horizontal closing first, then vertical.
	if abs(dx) >= abs(dy):
		if dx != 0:
			next_pos.x += sign(dx)
	else:
		if dy != 0:
			next_pos.y += sign(dy)

	# Clamp into board bounds (defensive).
	next_pos = clamp_to_board(next_pos, _state)

	# If the step does not actually change position, bail.
	if next_pos == from_pos:
		return

	# Blocked? If there are alive entities in the target cell other than
	# our intended target, we don't move this turn.
	var occupants: Array = get_entities_at_pos(next_pos, true)
	var blocked := false
	for e in occupants:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var eid: int = int((e as Dictionary).get("id", -1))
		if eid != target_id:
			blocked = true
			break
	if blocked:
		return

	# Resolve the actor entity and update its grid_pos in-place.
	var ent: Variant = _find_entity(actor_id)
	if ent == null or typeof(ent) != TYPE_DICTIONARY:
		return
	CombatEntities.set_grid_pos(ent as Dictionary, next_pos)

	# Rewrite the action to be a MOVE for this turn.
	# We keep target_id so logs can still mention the intended target.
	action["original_type"] = t
	action["type"] = CombatConstants.ActionType.MOVE

	# Canonical movement keys (used by the new logger):
	action["from_pos"] = from_pos
	action["to_pos"] = next_pos

	# Legacy keys for older code paths / loggers:
	action["moved_from"] = from_pos
	action["moved_to"] = next_pos

# --- Spawn columns and anchor position helpers --------------------------------

func get_ally_spawn_columns() -> Array:
	# Returns the configured ally spawn columns from the current state.
	# If the state does not yet carry this metadata or it is malformed,
	# returns an empty array so callers can safely iterate.
	var cols = _state.get("ally_spawn_columns", [])
	if typeof(cols) == TYPE_ARRAY:
		return cols
	return []

func get_enemy_spawn_columns() -> Array:
	# Returns the configured enemy spawn columns from the current state.
	# If the state does not yet carry this metadata or it is malformed,
	# returns an empty array so callers can safely iterate.
	var cols = _state.get("enemy_spawn_columns", [])
	if typeof(cols) == TYPE_ARRAY:
		return cols
	return []

func get_shrine_grid_pos() -> Vector2i:
	# Returns the configured shrine anchor position from the current state.
	# If no shrine position is configured or the value is not a Vector2i,
	# returns GRID_POS_UNSET so callers can treat it as "no shrine on board".
	var pos = _state.get("shrine_grid_pos", CombatEntities.GRID_POS_UNSET)
	if typeof(pos) == TYPE_VECTOR2I:
		return pos
	return CombatEntities.GRID_POS_UNSET


func get_totem_static_grid_pos() -> Vector2i:
	# Returns the configured static totem anchor position from the current state.
	# If no totem position is configured or the value is not a Vector2i,
	# returns GRID_POS_UNSET so callers can treat it as "no static totem".
	var pos = _state.get("totem_static_grid_pos", CombatEntities.GRID_POS_UNSET)
	if typeof(pos) == TYPE_VECTOR2I:
		return pos
	return CombatEntities.GRID_POS_UNSET

# --- Shared lane / placement helpers -----------------------------------------
# These helpers provide a single, deterministic way to place entities on the
# invisible board using the configured spawn columns. They are intentionally
# generic so any objective (combat_trial, purify_shrine, protect_totem, etc.)
# can reuse them without re‑implementing grid math.
#
# Rules (MVP):
#   - Entities are placed column‑first using the provided spawn_columns.
#   - Rows are assigned by cycling through [0 .. board_rows-1] via cycle_row().
#   - Positions are clamped into the board via clamp_to_board().
#   - Non‑dictionary entries in the group are ignored defensively.

# --- Automatic grid placement for objectives that use default lanes ----------

func _auto_place_entities_for_objective() -> void:
	# Automatically place entities on the invisible grid for objectives that
	# rely on the default lane layout.
	var objective: String = String(_state.get("objective", "defeat"))
	var stage_modifiers: Dictionary = _state.get("stage_modifiers", {})
	var preserve_positions: bool = bool(stage_modifiers.get("preserve_positions", false))
	var cols: int = _get_board_cols(_state)
	var rows: int = _get_board_rows(_state)
	if cols <= 0 or rows <= 0:
		return

	# Shrine multi-wave support:
	# For wave 2+ of Purify Shrine / Protect Shrine, we preserve ALLY positions
	# (heroes + shrine) but still need to place freshly spawned ENEMIES.
	if preserve_positions and (
		objective == "purify_shrine" or
		objective == CombatConstants.OBJECTIVE_PROTECT_SHRINE
	):
		place_enemies_in_default_lanes()
		return

	match objective:
		# Generic defeat / combat trial style objectives
		"defeat", "combat_trial", CombatConstants.OBJECTIVE_DEFEAT_ENEMIES:
			# Both standalone battles and realm “combat_trial” stages use the
			# same default lane layout: allies on the left spawn columns,
			# enemies on the right spawn columns.
			place_allies_in_default_lanes()
			place_enemies_in_default_lanes()

		# Shrine protection / purify shrine stages
		"purify_shrine", CombatConstants.OBJECTIVE_PROTECT_SHRINE:
			# Shrine stages share the same default lanes for combatants, but
			# the shrine itself is anchored via COMBAT_SHRINE_GRID_POS on the
			# entity created by ObjectiveRunner. Placement helpers are careful
			# to skip shrine entities so we do not overwrite that anchor.
			place_allies_in_default_lanes()
			place_enemies_in_default_lanes()

		# Future objectives that might want to reuse the same default lanes
		"protect_totem", CombatConstants.OBJECTIVE_PROTECT_TOTEM:
			# Protect Totem stages will re-use the same basic lane layout for
			# allies/enemies. The totem itself is anchored by ObjectiveRunner
			# using COMBAT_TOTEM_STATIC_GRID_POS or carried by a hero.
			place_allies_in_default_lanes()
			place_enemies_in_default_lanes()

		_:
			# Other objectives either do not use the grid yet or will handle
			# placement explicitly in their own setup routines.
			pass

func _place_group_in_spawn_columns(group: Array, spawn_columns: Array, start_row_index: int = 0) -> void:
	# Internal workhorse: mutates the given group in place, assigning grid_pos
	# to each dictionary entry according to the spawn_columns pattern.
	if typeof(group) != TYPE_ARRAY:
		return
	if typeof(spawn_columns) != TYPE_ARRAY or spawn_columns.is_empty():
		return

	var cols: Array[int] = []
	for c in spawn_columns:
		cols.append(int(c))

	var rows: int = _get_board_rows(_state)
	if rows <= 0:
		# Board not configured; skip placement to avoid fabricating positions.
		return

	var col_count: int = cols.size()
	if col_count <= 0:
		return

	for i in range(group.size()):
		var ent_v: Variant = group[i]
		if typeof(ent_v) != TYPE_DICTIONARY:
			continue

		var ent: Dictionary = ent_v

		# Do not move shrine entities via the generic lane placer; their
		# position is configured via COMBAT_SHRINE_GRID_POS and set by the
		# caller (e.g. ObjectiveRunner for Purify Shrine stages).
		if CombatEntities.is_shrine(ent):
			group[i] = ent
			continue

		var col_index: int = cols[i % col_count]
		var row_index: int = cycle_row(start_row_index + i, _state)
		var pos: Vector2i = Vector2i(col_index, row_index)
		pos = clamp_to_board(pos, _state)

		CombatEntities.set_grid_pos(ent, pos)
		group[i] = ent

func place_allies_in_default_lanes(start_row_index: int = 0) -> void:
	# Places all current allies into the configured ally spawn columns using
	# a simple lane pattern (row cycling). Safe to call multiple times; it
	# will overwrite existing grid_pos values for allies.
	var ally_cols: Array = get_ally_spawn_columns()
	if ally_cols.is_empty():
		return
	_place_group_in_spawn_columns(_state.get("allies", []), ally_cols, start_row_index)

func place_enemies_in_default_lanes(start_row_index: int = 0) -> void:
	# Places all current enemies into the configured enemy spawn columns using
	# the same deterministic lane pattern as allies.
	#
	# Shrine objectives always spawn enemies from the far edge of the board
	var enemy_cols: Array = get_enemy_spawn_columns()
	var obj_s: String = String(_state.get("objective", ""))

	# Shrine objectives always spawn enemies from the far edge of the board
	if obj_s == "purify_shrine":
		enemy_cols = HeroBal.COMBAT_SHRINE_ENEMY_SPAWN_COLUMNS
	if enemy_cols.is_empty():
		return
	_place_group_in_spawn_columns(_state.get("enemies", []), enemy_cols, start_row_index)

# MVP shrine behaviour:
# - The engine auto-designates a single "purifier" hero for Purify Shrine stages.
# - Post-MVP we may let the Keeper explicitly choose the purifier at stage start.
func _assign_designated_purifier() -> void:
	# MVP: only relevant for Purify Shrine objectives.
	var objective: String = String(_state.get("objective", ""))
	if objective != "purify_shrine":
		_state["designated_purifier_id"] = -1
		return

	var chosen_id: int = -1
	var best_score: int = -2147483648  # simple "minus infinity"

	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent: Dictionary = a

		# Shrines and dead allies can never be the purifier.
		if CombatEntities.is_shrine(ent):
			continue
		if not CombatEntities.is_alive(ent):
			continue

		var id_val: int = int(ent.get("id", -1))
		if id_val < 0:
			continue

		var score: int = _score_purifier_candidate(ent)

		if chosen_id == -1 or score > best_score or (score == best_score and id_val < chosen_id):
			chosen_id = id_val
			best_score = score

	_state["designated_purifier_id"] = chosen_id

# Scores a candidate hero for the purifier role. Focuses on faith and devout archetype.
func _score_purifier_candidate(ent: Dictionary) -> int:
	var score: int = 0

	# Prefer heroes whose archetype is explicitly devout.
	var arch_s: String = String(ent.get("archetype", "none"))
	if arch_s == "devout":
		score += HeroBal.PURIFIER_SCORE_DEVOUT_BONUS

	# Pull hero stats if present; we keep this flexible so lore / personality
	# stats like wisdom/faith can coexist with combat stats.
	if ent.has("stats") and typeof(ent.stats) == TYPE_DICTIONARY:
		var stats: Dictionary = ent.stats

		# Faith: primary signal for purifier role.
		if stats.has("faith"):
			score += int(stats.get("faith", 0)) * HeroBal.PURIFIER_SCORE_FAITH_WEIGHT

		# Wisdom: secondary tie-breaker (different key spellings allowed).
		if stats.has("wisdom"):
			score += int(stats.get("wisdom", 0)) * HeroBal.PURIFIER_SCORE_WISDOM_WEIGHT
		elif stats.has("wis"):
			score += int(stats.get("wis", 0)) * HeroBal.PURIFIER_SCORE_WISDOM_WEIGHT

	# Morale as a soft tie-breaker: more composed heroes are preferred.
	score += CombatEmotionSystem.get_morale(ent) * HeroBal.PURIFIER_SCORE_MORALE_WEIGHT

	return score

#
# Applies the outcome chosen by ActionResolver.should_refuse_turn(...)
# MVP: only "refuse" and "guard" are supported here. "retreat/abandon" is post-MVP
# and should be triggered by a separate, higher-severity fear check.
# Returns an effect dictionary shaped like other combat actions so the
# caller can append it to the round actions list.
func _apply_fear_outcome(fear_res: Dictionary, ent: Dictionary, ctx: Dictionary) -> Dictionary:
	var mode: String = String(fear_res.get("mode", "refuse"))
	var actor_id: int = int(ent.get("id", -1))
	if actor_id < 0:
		return {
			"ok": false,
			"type": CombatConstants.ActionType.REFUSE,
			"actor_id": actor_id,
			"notes": "fear_invalid_actor",
		}

	match mode:
		"guard":
			# Reuse existing guard resolver so we don't create a parallel system
			var guard_action: Dictionary = {
				"type": CombatConstants.ActionType.GUARD,
				"actor_id": actor_id,
				"target_id": actor_id,
				"notes": "fear_guard",
			}
			var guard_eff: Dictionary = ActionResolver.apply_minor(guard_action, ctx)
			guard_eff["reason"] = "fear"
			guard_eff["fear"] = int(fear_res.get("fear", 0))
			return guard_eff
		_:
			# Default/refuse path
			var refuse_action: Dictionary = {
				"type": CombatConstants.ActionType.REFUSE,
				"actor_id": actor_id,
				"notes": "fear_refusal",
			}
			var refuse_eff: Dictionary = ActionResolver.apply_major(refuse_action, ctx)
			refuse_eff["reason"] = "fear"
			refuse_eff["fear"] = int(fear_res.get("fear", 0))
			return refuse_eff


func _normalize_allies(allies: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in allies:
		match typeof(a):
			TYPE_INT:
				var id_val: int = int(a)
				var hero: Dictionary = _load_hero_by_id(id_val)
				var ent: Dictionary = _to_combat_entity(hero, id_val)
				out.append(ent)
			TYPE_DICTIONARY:
				var d_in: Dictionary = a
				# Ensure minimal shape; keep existing stats if present
				if not d_in.has("id"):
					d_in["id"] = 0

				# Shrine special-case: if an ally dict is marked as a shrine, we
				# preserve its provided shape and skip EmotionService hydration.
				# Shrines do not act and do not participate in morale/fear systems.
				if bool(d_in.get("is_shrine", false)):
					var shrine_out: Dictionary = d_in.duplicate(true)

					shrine_out["can_act"] = false
					shrine_out["fear"] = 0

					if not shrine_out.has("stats") or typeof(shrine_out["stats"]) != TYPE_DICTIONARY:
						var s := {
							EchoConstants.STAT_HP: int(shrine_out.get("hp", 0)),
							EchoConstants.STAT_MAX_HP: int(shrine_out.get("max_hp", shrine_out.get("hp", 0))),
							EchoConstants.STAT_ATK: 0,
							EchoConstants.STAT_DEF: 0,
							EchoConstants.STAT_AGI: 0,
							EchoConstants.STAT_MORALE: 0,
							EchoConstants.STAT_FEAR: 0,
						}
						shrine_out["stats"] = s
					else:
						var s2: Dictionary = shrine_out["stats"]
						if not s2.has(EchoConstants.STAT_HP):
							s2[EchoConstants.STAT_HP] = int(shrine_out.get("hp", 0))
						if not s2.has(EchoConstants.STAT_MAX_HP):
							s2[EchoConstants.STAT_MAX_HP] = int(shrine_out.get("max_hp", shrine_out.get("hp", 0)))
						shrine_out["stats"] = s2

					shrine_out["hp"] = int(shrine_out["stats"][EchoConstants.STAT_HP])
					shrine_out["max_hp"] = int(shrine_out["stats"][EchoConstants.STAT_MAX_HP])

					# Tags: ensure shrine participates in the generic entity model.
					# Canonical shrine tags for MVP:
					# ["ally", "structure", "structure:defense", "objective", "objective:shrine"].
					var shrine_tags: Array = ["ally", "structure", "structure:defense", "objective", "objective:shrine"]
					# Normalize tags container, then ensure canonical shrine tags are present.
					if not shrine_out.has("tags") or typeof(shrine_out["tags"]) != TYPE_ARRAY:
						shrine_out["tags"] = []
					CombatEntities.ensure_tags(shrine_out, shrine_tags)

					out.append(shrine_out)
					continue

				var d_out: Dictionary = d_in
				if not d_out.has("stats") or typeof(d_out["stats"]) != TYPE_DICTIONARY:
					d_out["stats"] = CombatEntities.fallback_stats_from_balance()
				else:
					d_out["stats"] = CombatEntities.fill_missing_stats_with_balance(d_out["stats"])
				if not d_out.has("fear"):
					d_out["fear"] = 0
				if not d_out.has("status"):
					d_out["status"] = "idle"

				# MVP hook: if EmotionService is available, hydrate morale/fear
				# for allies provided as dictionaries, so they still start from
				# the persisted emotional state rather than hardcoded defaults.
				var ent_id2: int = int(d_out.get("id", 0))
				if d_out.has("stats") and typeof(d_out["stats"]) == TYPE_DICTIONARY and ent_id2 > 0:
					var stats2: Dictionary = d_out["stats"]
					var fear2: int = int(d_out.get("fear", 0))
					var fear_hydrated: int = _hydrate_emotion_from_service(ent_id2, stats2, fear2)
					d_out["stats"] = stats2
					d_out["fear"] = fear_hydrated

				# Tags: ensure dictionary allies participate in the generic entity model.
				# Normalize tag container, then ensure "ally" is present.
				if not d_out.has("tags") or typeof(d_out["tags"]) != TYPE_ARRAY:
					d_out["tags"] = []
				CombatEntities.ensure_tags(d_out, ["ally"])

				out.append(d_out)
			_:
				pass
	return out

func _normalize_enemies(enemies: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in enemies:
		if typeof(e) != TYPE_DICTIONARY:
			continue

		# Ensure a stable id for determinism
		if not e.has("id"):
			e["id"] = 1000 + out.size()

		# Start from existing stats if present, else empty dict
		var s: Dictionary = {}
		if e.has("stats") and typeof(e.stats) == TYPE_DICTIONARY:
			s = (e.stats as Dictionary).duplicate(true)

		# Pull flat values if provided (we preserve existing numbers)
		var flat_hp_set: bool = e.has("hp")
		var flat_max_hp_set: bool = e.has("max_hp")
		var flat_atk_set: bool = e.has("atk")
		var flat_def_set: bool = e.has("def")
		var flat_agi_set: bool = e.has("agi")
		var flat_cha_set: bool = e.has("cha")
		var flat_int_set: bool = e.has("int")
		var flat_acc_set: bool = e.has("acc")
		var flat_eva_set: bool = e.has("eva")
		var flat_crit_set: bool = e.has("crit")

		# Write/ensure canonical stats, preferring provided values
		if flat_hp_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_HP, int(e.get("hp", HeroBal.FALLBACK_HP)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)

		if flat_max_hp_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(e.get("max_hp", int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_MAX_HP, int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP)))

		if flat_atk_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ATK, int(e.get("atk", HeroBal.FALLBACK_ATK)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ATK, HeroBal.FALLBACK_ATK)

		if flat_def_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_DEF, int(e.get("def", HeroBal.FALLBACK_DEF)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_DEF, HeroBal.FALLBACK_DEF)

		if flat_agi_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_AGI, int(e.get("agi", HeroBal.FALLBACK_AGI)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_AGI, HeroBal.FALLBACK_AGI)

		if flat_cha_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CHA, int(e.get("cha", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CHA, 0)

		if flat_int_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_INT, int(e.get("int", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_INT, 0)

		if flat_acc_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ACC, int(e.get("acc", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_ACC, 0)

		if flat_eva_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_EVA, int(e.get("eva", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_EVA, 0)

		if flat_crit_set:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CRIT, int(e.get("crit", 0)))
		else:
			CombatEntities.ensure_stat_int(s, EchoConstants.STAT_CRIT, 0)

		# Morale/Fear (enemies ignore morale in MVP but keep a neutral value for shape)
		CombatEntities.ensure_stat_int(s, EchoConstants.STAT_MORALE, HeroBal.FALLBACK_MORALE)
		CombatEntities.ensure_stat_int(s, EchoConstants.STAT_FEAR, int(e.get("fear", 0)))

		# Save back canonical stats
		e["stats"] = s

		# Backfill flat keys from stats when missing (compat with any legacy readers)
		if not flat_hp_set:
			e["hp"] = int(s.get(EchoConstants.STAT_HP, HeroBal.FALLBACK_HP))
		if not flat_max_hp_set:
			e["max_hp"] = int(s.get(EchoConstants.STAT_MAX_HP, e.get("hp", HeroBal.FALLBACK_HP)))
		if not flat_atk_set:
			e["atk"] = int(s.get(EchoConstants.STAT_ATK, HeroBal.FALLBACK_ATK))
		if not flat_def_set:
			e["def"] = int(s.get(EchoConstants.STAT_DEF, HeroBal.FALLBACK_DEF))
		if not flat_agi_set:
			e["agi"] = int(s.get(EchoConstants.STAT_AGI, HeroBal.FALLBACK_AGI))
		if not e.has("fear"):
			e["fear"] = int(s.get(EchoConstants.STAT_FEAR, 0))
		if not e.has("status"):
			e["status"] = "idle"

		# Tags: ensure every enemy entity participates in the generic entity model.
		# Normalize tag container, then ensure "enemy" tag is present.
		if not e.has("tags") or typeof(e["tags"]) != TYPE_ARRAY:
			e["tags"] = []
		CombatEntities.ensure_tags(e, ["enemy"])

		out.append(e)
	return out

# --- Ally hydration helpers --------------------------------------------------

static func _load_hero_by_id(id_val: int) -> Dictionary:
	# Path 1: Autoload object (usual in GDScript projects)
	if typeof(SaveService) != TYPE_NIL and SaveService.has_method("hero_get"):
		var hero1: Variant = SaveService.hero_get(int(id_val))
		if typeof(hero1) == TYPE_DICTIONARY:
			return hero1 as Dictionary
	# Path 2: Engine singleton (only if SaveService is exposed that way)
	if Engine.has_singleton("SaveService"):
		var svc: Variant = Engine.get_singleton("SaveService")
		if svc and svc.has_method("hero_get"):
			var hero2: Variant = svc.call("hero_get", int(id_val))
			if typeof(hero2) == TYPE_DICTIONARY:
				return hero2 as Dictionary
	# No source available → return empty to trigger safe fallbacks upstream
	return {}

static func _to_combat_entity(hero: Dictionary, fallback_id: int) -> Dictionary:
	# Build a combat entity from a hero record. Preserve existing stats if present,
	# otherwise create a safe, typed fallback block.
	var ent_id: int = int(hero.get("id", fallback_id))
	var name_s: String = String(hero.get("name", ""))
	var arch_s: String = String(hero.get("archetype", "none"))
	var stats_in: Dictionary = {}
	if hero.has("stats") and typeof(hero["stats"]) == TYPE_DICTIONARY:
		stats_in = hero["stats"]
	var stats_out: Dictionary = CombatEntities.fill_missing_stats(stats_in) if stats_in.size() > 0 else CombatEntities.fallback_stats()

	# MVP hook: hydrate initial morale/fear for this hero from EmotionService
	# when available, so combat always starts from the persisted emotional state.
	var fear_val: int = int(hero.get("fear", 0))
	if ent_id > 0:
		fear_val = _hydrate_emotion_from_service(ent_id, stats_out, fear_val)

	return {
		"id": ent_id,
		"name": name_s,
		"archetype": arch_s,
		"stats": stats_out,
		"fear": fear_val,
		"tags": ["ally", "hero"],
		"status": String(hero.get("status", "idle")),
	}
# Pull morale/fear for a hero from EmotionService when available.
# Returns the final fear value written into stats (so callers can mirror it
# into the flat `fear` field on the combat entity).
static func _hydrate_emotion_from_service(ent_id: int, stats: Dictionary, fallback_fear: int) -> int:
	var fear_val: int = fallback_fear

	# Try to locate EmotionService via the SaveService singleton/autoload.
	var emo: Variant = null
	if Engine.has_singleton("SaveService"):
		var svc: Variant = Engine.get_singleton("SaveService")
		if svc and svc.has_method("emotion_get_service"):
			emo = svc.call("emotion_get_service")
	elif typeof(SaveService) != TYPE_NIL and SaveService.has_method("emotion_get_service"):
		emo = SaveService.emotion_get_service()

	if emo == null:
		# No emotion system wired yet; keep whatever was passed in.
		return fear_val

	# Morale: source of truth is EmotionService; clamp to 0..100 for safety.
	if emo.has_method("get_morale"):
		var m_val: int = int(emo.call("get_morale", ent_id))
		stats[EchoConstants.STAT_MORALE] = max(0, min(100, m_val))

	# Fear: same pattern; also mirror into STAT_FEAR for consistency.
	if emo.has_method("get_fear"):
		fear_val = max(0, min(100, int(emo.call("get_fear", ent_id))))
		stats[EchoConstants.STAT_FEAR] = fear_val

	return fear_val


func _find_entity(id_val: int) -> Variant:
	for a in _state.get("allies", []):
		if int(a.get("id", -1)) == id_val:
			return a
	for e in _state.get("enemies", []):
		if int(e.get("id", -1)) == id_val:
			return e
	return null

func _side_of(id_val: int) -> String:
	for a in _state.get("allies", []):
		if int(a.get("id", -1)) == id_val:
			return "ALLY"
	for e in _state.get("enemies", []):
		if int(e.get("id", -1)) == id_val:
			return "ENEMY"
	return "UNKNOWN"


func _check_end() -> Dictionary:
	# Delegate core end-condition evaluation to CombatObjectives so that
	# defeat / purify_shrine and future objectives live in a single module.
	var objective: String = String(_state.get("objective", "defeat"))
	var round_limit: int = int(_state.get("round_limit", 10))

	var end_result: Dictionary = CombatObjectives.check_end(_state, objective, round_limit, HeroBal)

	# If the battle is still ongoing, CombatObjectives will have returned a
	# lightweight sentinel (e.g. {"ongoing": true}) and left `_state.over`
	# as `false`. No emotion payload is attached in that case.
	if not bool(_state.get("over", false)):
		return end_result

	# When the battle ends, enrich the result with the emotion payload while
	# preserving the existing result shape for callers.
	var emo_result: Dictionary = CombatEmotionSystem.build_emotion_result(_state)
	if emo_result.size() > 0:
		if not _state.has("result") or typeof(_state["result"]) != TYPE_DICTIONARY:
			_state["result"] = {}
		_state["result"]["emotion"] = emo_result
		end_result = _state["result"]

	return end_result

# --- Morale override API (persist across fights for QA/debug) ---------------
## Set/Update a morale override for an entity id. Also updates current state if present.
func morale_override_set(id_val: int, morale_value: int) -> void:
	var v : Variant = max(0, min(100, int(morale_value)))
	_morale_overrides[int(id_val)] = v
	# Update live entity if present
	var ent: Variant = _find_entity(int(id_val))
	if ent != null and typeof(ent) == TYPE_DICTIONARY:
		CombatEmotionSystem.write_morale(ent as Dictionary, v)

## Get an override if present; returns -1 if none.
func morale_override_get(id_val: int) -> int:
	if _morale_overrides.has(int(id_val)):
		return int(_morale_overrides[int(id_val)])
	return -1

## Clear all overrides or a single id when provided.
func morale_override_clear(id_val: int = -1) -> void:
	if int(id_val) >= 0:
		_morale_overrides.erase(int(id_val))
	else:
		_morale_overrides.clear()

## Applies overrides to the active _state (called after start_battle).
func _apply_morale_overrides() -> void:
	if _morale_overrides.is_empty():
		return
	# Allies
	for a in _state.get("allies", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var ent_a: Dictionary = a
		if CombatEntities.is_shrine(ent_a):
			continue
		var id_a := int(ent_a.get("id", -1))
		if id_a >= 0 and _morale_overrides.has(id_a):
			CombatEmotionSystem.write_morale(ent_a, int(_morale_overrides[id_a]))
	# Enemies (supported for completeness, even if MVP ignores morale for them)
	for e in _state.get("enemies", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id_e := int((e as Dictionary).get("id", -1))
		if id_e >= 0 and _morale_overrides.has(id_e):
			CombatEmotionSystem.write_morale(e as Dictionary, int(_morale_overrides[id_e]))

# Map numeric action types to canonical logger verbs
static func _action_type_to_verb(t: int) -> String:
	match t:
		CombatConstants.ActionType.ATTACK:        return "ATTACK"
		CombatConstants.ActionType.GUARD:         return "GUARD"
		CombatConstants.ActionType.MOVE:          return "MOVE"
		CombatConstants.ActionType.REFUSE:        return "REFUSE"
		CombatConstants.ActionType.PURIFY_SHRINE: return "PURIFY_SHRINE"
		_:                                        return ""
