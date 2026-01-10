extends Resource
class_name ObjectiveRunner
## ObjectiveRunner
## Lightweight bridge between Realm stages and the combat harness.
##
## Canon anchors:
##  - Story: "As the Keeper I want seeded Realms" — stages must actually
##    trigger objectives, not just exist as JSON.
##  - §6 World / Realm Structure: stage objectives (Combat Trial, Purify Shrine).
##  - §9 Combat & Simulation: deterministic combat driven by seeds.
##
## Design:
##  - Pure coordination: given a Realm + Stage + hero party, decide what
##    to run for that objective and call the provided combat harness.
##  - No direct economy or Realm progression here: rewards and stage
##    advancement remain in RealmService + EconomyService.
##  - Deterministic: we pass stage.encounter_seed to the combat harness
##    so it can seed its RNG however it likes, but outputs are stable
##    for the same inputs.


const EnemyFactory = preload("res://core/combat/EnemyFactory.gd")
const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")


static func run_stage(
		realm: RealmModel,
		stage: StageModel,
		hero_party: Array,
		combat_runner: Callable
	) -> Dictionary:
	## Execute the appropriate objective behavior for the given stage.
	##
	## Inputs:
	##  - realm: RealmModel (active realm, tier, virtue, seed)
	##  - stage: StageModel (objective_type, encounter_seed, modifiers)
	##  - hero_party: Array of heroes in the shape expected by the combat harness
	##  - combat_runner: Callable that runs combat:
	##        func(
	##          hero_party: Array,
	##          enemies: Array,
	##          seed: int,
	##          max_rounds: int,
	##          objective_type: String,
	##          stage_modifiers: Dictionary
	##        ) -> Dictionary
	##    For Realm stages we pass max_rounds = -1 to indicate "no artificial round cap"
	##    (combat should run until a true victory/defeat condition is reached), and we
	##    always provide the stage.objective_type and stage.modifiers so the harness
	##    can configure CombatEngine (objective, grid usage, etc.) appropriately.
	##
	## Output shape (MVP):
	##  {
	##    "objective_type": String,
	##    "realm_id": String,
	##    "stage_index": int,
	##    "success": bool,
	##    "combat": Dictionary,   # raw result from combat harness (or stub)
	##  }
	# Ensure hero_party is an untyped Array so we can safely append
	# special entities (like the shrine) even if the caller passed a
	# typed array (e.g. Array[HeroModel]).
	var hero_party_untyped: Array = []
	hero_party_untyped.assign(hero_party)

	var result: Dictionary = {
		"objective_type": stage.objective_type if stage != null else "",
		"realm_id": realm.id if realm != null else "",
		"stage_index": stage.index if stage != null else -1,
		"success": false,
		"combat": {},
	}

	if realm == null or stage == null:
		result["combat"] = {
			"success": false,
			"log": ["[ObjectiveRunner] Missing realm or stage; cannot run objective."],
		}
		return result

	match stage.objective_type:
		"combat_trial":
			return _run_combat_trial(realm, stage, hero_party_untyped, combat_runner, result)
		"purify_shrine":
			return _run_purify_shrine(realm, stage, hero_party_untyped, combat_runner, result)
		_:
			# Unknown objective: treat as auto-success for MVP, but log it.
			result["success"] = true
			result["combat"] = {
				"success": true,
				"log": [
					"[ObjectiveRunner] Unknown objective_type='%s' treated as auto-success." \
					% stage.objective_type
				],
			}
			return result


static func _run_combat_trial(
		realm: RealmModel,
		stage: StageModel,
		hero_party: Array,
		combat_runner: Callable,
		result: Dictionary
	) -> Dictionary:
	## Run a Combat Trial objective:
	##  - Build realm-aware enemy pack via EnemyFactory.
	##  - Invoke the combat harness with hero_party, enemies, and the stage seed.
	##  - Consider the trial successful if the harness reports success=true.
	var enemies: Array = EnemyFactory.spawn_realm_pack(realm, stage)

	var combat_result: Dictionary = {}
	if combat_runner != null and combat_runner.is_valid():
		# We delegate seeding to the harness by passing encounter_seed.
		# For Realm stages, we disable the demo round cap by passing max_rounds = -1,
		# so combat runs until a true victory/defeat condition is reached.
		combat_result = combat_runner.call(
			hero_party,
			enemies,
			stage.encounter_seed,
			-1,
			stage.objective_type,
			stage.modifiers
		)
	else:
		# Safe fallback for MVP if no harness is wired yet.
		combat_result = {
			"success": true,
			"log": [
				"[ObjectiveRunner] No combat_runner configured; Combat Trial auto-success.",
			],
		}

	var success: bool = bool(combat_result.get("success", true))
	result["success"] = success
	result["combat"] = combat_result

	# Propagate per-hero emotion changes from the combat result into the
	# global EmotionService so that realms/shrine can build on persistent
	# morale/fear across the campaign.
	_apply_combat_emotion_result(realm, stage, hero_party, combat_result, "realm_combat_trial")

	return result


static func _run_purify_shrine(
		realm: RealmModel,
		stage: StageModel,
		hero_party: Array,
		combat_runner: Callable,
		result: Dictionary
	) -> Dictionary:
	## Run a Purify Shrine objective.
	##
	## MVP behavior:
	##  - Multi-wave survival trial with a draining shrine:
	##      * shrine_waves: how many waves must be cleared.
	##      * shrine_hp_max: starting HP for the shrine.
	##      * shrine_passive_drain_per_wave: legacy realm-side timer (now
	##        superseded by per-round drain in CombatEngine).
	##  - Wave success is determined by the combat harness "success" flag.
	##  - Shrine fails if:
	##      * any wave reports success=false, or
	##      * shrine_hp reaches 0 before all waves are completed.
	##  - Morale drain timing is tracked via morale_drain_per_wave but the
	##    actual morale adjustments will be wired in once the EmotionService
	##    is in place (Subtask F).
	##
	## Note: Per-round shrine drain, explicit shrine entity targeting, and the
	## Purify action will be implemented in the Combat Simulation Core epic.

	# Read shrine metadata from the stage modifiers, with safe defaults.
	var shrine_waves: int = int(stage.modifiers.get("shrine_waves", 2))
	if shrine_waves <= 0:
		shrine_waves = 1

	var shrine_hp_max: int = int(stage.modifiers.get("shrine_hp_max", 100))
	var shrine_hp: int = shrine_hp_max

	var morale_drain_per_wave: int = int(stage.modifiers.get("morale_drain_per_wave", 0))

	# Track final ally/shrine positions between waves so we can request
	# that the combat harness preserves them on subsequent waves.
	var last_ally_positions_by_id: Dictionary = {}
	var has_last_positions: bool = false

	var waves_results: Array = []
	var overall_success: bool = true
	var waves_cleared: int = 0
	var total_purify_uses: int = 0
	var total_purified_waves: int = 0
	var shrine_destroyed: bool = false

	for wave_index in range(shrine_waves):
		# Derive a deterministic seed per wave from the encounter_seed.
		var wave_seed: int = stage.encounter_seed + wave_index
		# Clear when a new wave begins and which seed it uses.
		print("[shrine] Wave %d/%d — seed=%d" % [wave_index + 1, shrine_waves, wave_seed])

		# Clone stage modifiers for this wave so we can inject per-wave
		# data (like preserved grid positions) without mutating the
		# original StageModel modifiers.
		var stage_modifiers_for_wave: Dictionary = stage.modifiers.duplicate(true)
		if has_last_positions:
			stage_modifiers_for_wave["ally_positions_by_id"] = last_ally_positions_by_id
			stage_modifiers_for_wave["preserve_positions"] = true

		# Decide shrine grid position for this wave. By default we use the
		# shared anchor from GameBalance_HeroCombat, but if we have a
		# remembered position for the shrine entity id (-1) from a
		# previous wave, reuse that so shrine location feels continuous.
		var shrine_grid_pos: Vector2i = HeroBal.COMBAT_SHRINE_GRID_POS
		if has_last_positions and last_ally_positions_by_id.has(-1):
			var shrine_pos_v: Variant = last_ally_positions_by_id.get(-1)
			if typeof(shrine_pos_v) == TYPE_VECTOR2I:
				shrine_grid_pos = shrine_pos_v

		# Build the enemy pack for this wave.
		var enemies: Array = EnemyFactory.spawn_realm_pack(realm, stage)

		# Build a shrine combat entity for this wave so the combat harness
		# can treat the shrine as a real participant (HP, targeting, logs).
		# HP values are normalized here so CombatEngine receives a clean,
		# deterministic baseline and can hydrate its own stats block.
		var shrine_hp_clamped: int = int(clamp(shrine_hp, 0, shrine_hp_max))
		var shrine_ent: Dictionary = {
			"id": -1,
			"name": "Shrine",
			"hp": shrine_hp_clamped,
			"max_hp": shrine_hp_max,
			"is_shrine": true,
			"can_act": false,
			# Grid placement for Purify Shrine: use the calculated (possibly persisted) position.
			"grid_pos": shrine_grid_pos,
			# Canonical shrine tags so the generic entity model and objectives can reason about it.
			"tags": ["ally", "structure", "structure:defense", "objective", "objective:shrine"],
		}

		# Compose the allies array for this wave: hero party + shrine entity.
		# We duplicate the hero_party array so we do not mutate the caller’s
		# list across waves.
		var allies_for_wave: Array = hero_party.duplicate()
		allies_for_wave.append(shrine_ent)

		var combat_result: Dictionary = {}
		if combat_runner != null and combat_runner.is_valid():
			# Purify Shrine uses the same "no round cap" behavior as other Realm stages.
			combat_result = combat_runner.call(
				allies_for_wave,
				enemies,
				wave_seed,
				-1,
				stage.objective_type,
				stage_modifiers_for_wave
			)
		else:
			# Safe fallback: treat as auto-success if no harness is wired.
			combat_result = {
				"success": true,
				"log": [
					"[ObjectiveRunner] No combat_runner configured; Purify Shrine auto-success.",
				],
				"wave_index": wave_index,
			}

		# Record wave index for debugging/telemetry.
		combat_result["wave_index"] = wave_index
		waves_results.append(combat_result)

		# Propagate per-hero emotion changes from this wave into EmotionService
		# so subsequent waves and future stages start from the updated state.
		_apply_combat_emotion_result(
			realm,
			stage,
			hero_party,
			combat_result,
			"purify_shrine_wave_%d" % (wave_index + 1)
		)

		# Allow the combat harness to report shrine HP and destruction if it
		# understands shrine entities. For MVP this is optional so older
		# harnesses still work without these fields.
		if combat_result.has("shrine_hp_remaining"):
			var shrine_hp_after_combat: int = int(combat_result.get("shrine_hp_remaining", shrine_hp))
			shrine_hp = shrine_hp_after_combat

		var wave_shrine_destroyed: bool = false
		if combat_result.has("shrine_destroyed"):
			wave_shrine_destroyed = bool(combat_result.get("shrine_destroyed", false))
			if wave_shrine_destroyed:
				shrine_hp = 0
				shrine_destroyed = true

		# Capture final ally + shrine grid positions from the combat
		# result (if provided) so we can request position preservation
		# on the next wave. This relies on the combat harness attaching
		# a `final_state` dictionary in the standard CombatEngine shape.
		if combat_result.has("final_state"):
			var final_state_v: Variant = combat_result.get("final_state")
			if typeof(final_state_v) == TYPE_DICTIONARY:
				var final_state: Dictionary = final_state_v
				var allies_final_v: Variant = final_state.get("allies", [])
				if typeof(allies_final_v) == TYPE_ARRAY:
					var allies_final: Array = allies_final_v
					last_ally_positions_by_id.clear()
					for ent_v in allies_final:
						if ent_v == null or typeof(ent_v) != TYPE_DICTIONARY:
							continue
						var ent: Dictionary = ent_v
						var id_val: int = int(ent.get("id", -1))
						# Allow shrine id (-1) to be tracked as well.
						if id_val < -1:
							continue
						var pos_v: Variant = ent.get("grid_pos", null)
						if typeof(pos_v) == TYPE_VECTOR2I:
							last_ally_positions_by_id[id_val] = pos_v
					has_last_positions = last_ally_positions_by_id.size() > 0

		# Basic wave outcome flags.
		var wave_success: bool = bool(combat_result.get("success", true))

		# Aggregate bookkeeping for summary/telemetry.
		if wave_success and not wave_shrine_destroyed:
			waves_cleared += 1

		var wave_purify_uses: int = int(combat_result.get("purify_uses", 0))
		if wave_purify_uses > 0:
			total_purify_uses += wave_purify_uses

		var wave_purified: bool = bool(combat_result.get("wave_purified", wave_purify_uses > 0))
		if wave_purified:
			total_purified_waves += 1

		if not wave_success or wave_shrine_destroyed:
			# Party wiped, harness reported failure, or shrine was destroyed
			# inside combat; treat this as an immediate failure for the
			# overall objective.
			overall_success = false
			break

		# Timing hook for shrine-specific morale drain. The actual morale
		# adjustments will be implemented once EmotionService is available.
		if morale_drain_per_wave != 0:
			# Example future call:
			#   EmotionService.apply_shrine_morale_drain(hero_party, morale_drain_per_wave)
			pass

	# Final success requires all required waves to have succeeded and the
	# shrine to still have HP remaining.
	var final_success: bool = overall_success and shrine_hp > 0
	result["success"] = final_success

	# Wrap the per-wave results and shrine HP data into the combat field so
	# callers can inspect each wave and shrine integrity if needed.
	var shrine_hp_clamped_end: int = max(shrine_hp, 0)
	var combat_summary: Dictionary = {
		"success": final_success,
		"waves": waves_results,
		"shrine_hp_max": shrine_hp_max,
		"shrine_hp_end": shrine_hp_clamped_end,
		"shrine_destroyed": shrine_destroyed or shrine_hp_clamped_end <= 0,
		"waves_cleared": waves_cleared,
		"shrine_waves_required": shrine_waves,
	}
	if total_purify_uses > 0:
		combat_summary["purify_uses_total"] = total_purify_uses
	if total_purified_waves > 0:
		combat_summary["waves_purified"] = total_purified_waves

	result["combat"] = combat_summary

	# Log a concise outcome summary for shrine stages so shrine runs are
	# easy to read from the console.
	var summary_line := "[shrine] Summary — success=%s, waves_cleared=%d/%d, shrine_hp=%d/%d" % [
		str(final_success),
		waves_cleared,
		shrine_waves,
		shrine_hp_clamped_end,
		shrine_hp_max,
	]
	if total_purify_uses > 0:
		summary_line += ", purify_uses=%d" % total_purify_uses
	print(summary_line)

	return result

## Internal helper: apply per-hero emotion deltas from a combat result
## into EmotionService, if available. This keeps ObjectiveRunner focused
## on coordination while delegating clamping and storage to the service.
static func _apply_combat_emotion_result(
		realm: RealmModel,
		stage: StageModel,
		hero_party: Array,
		combat_result: Dictionary,
		source_label: String
	) -> void:
	if combat_result.is_empty():
		return
	if not combat_result.has("emotion"):
		return
	var emo_block: Dictionary = combat_result["emotion"]
	if typeof(emo_block) != TYPE_DICTIONARY:
		return
	if not emo_block.has("heroes"):
		return
	var heroes_dict: Dictionary = emo_block["heroes"]
	if typeof(heroes_dict) != TYPE_DICTIONARY or heroes_dict.size() == 0:
		return

	# Obtain EmotionService via the SaveService autoload/global, if present.
	var emo: Variant = null
	if typeof(SaveService) != TYPE_NIL and SaveService.has_method("emotion_get_service"):
		emo = SaveService.emotion_get_service()
	if emo == null:
		return

	for hero_id_key in heroes_dict.keys():
		var hero_id := int(hero_id_key)
		var payload: Dictionary = heroes_dict[hero_id_key]
		if typeof(payload) != TYPE_DICTIONARY:
			continue

		var morale_delta: int = int(payload.get("morale_delta", 0))
		var fear_delta: int = int(payload.get("fear_delta", 0))
		if morale_delta == 0 and fear_delta == 0:
			continue

		var ctx := "combat:%s:realm=%s:stage=%d:type=%s" % [
			source_label,
			realm.id if realm != null else "",
			stage.index if stage != null else -1,
			stage.objective_type if stage != null else "",
		]

		emo.apply_delta(hero_id, morale_delta, fear_delta, ctx)

		# For readability while scanning logs, show the applied deltas and
		# the resulting stored values.
		var morale_after: int = 0
		var fear_after: int = 0
		if emo.has_method("get_morale"):
			morale_after = int(emo.get_morale(hero_id))
		if emo.has_method("get_fear"):
			fear_after = int(emo.get_fear(hero_id))

		print(
			"[emotion] %s hero=%d Δmorale=%d Δfear=%d => morale=%d fear=%d"
			% [ctx, hero_id, morale_delta, fear_delta, morale_after, fear_after]
		)
