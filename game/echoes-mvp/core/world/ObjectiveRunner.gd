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
	##        func(hero_party: Array, enemies: Array, seed: int, max_rounds: int) -> Dictionary
	##    For Realm stages we pass max_rounds = -1 to indicate \"no artificial round cap\" 
	##    (combat should run until a true victory/defeat condition is reached).
	##
	## Output shape (MVP):
	##  {
	##    "objective_type": String,
	##    "realm_id": String,
	##    "stage_index": int,
	##    "success": bool,
	##    "combat": Dictionary,   # raw result from combat harness (or stub)
	##  }
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
			return _run_combat_trial(realm, stage, hero_party, combat_runner, result)
		"purify_shrine":
			return _run_purify_shrine(realm, stage, hero_party, combat_runner, result)
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
		combat_result = combat_runner.call(hero_party, enemies, stage.encounter_seed, -1)
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
	##      * shrine_passive_drain_per_wave: shrine HP lost after each
	##        successfully cleared wave (approximates the shrine timer).
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

	var shrine_drain_per_wave: int = int(stage.modifiers.get("shrine_passive_drain_per_wave", 0))
	var morale_drain_per_wave: int = int(stage.modifiers.get("morale_drain_per_wave", 0))

	var waves_results: Array = []
	var overall_success: bool = true

	for wave_index in range(shrine_waves):
		# Derive a deterministic seed per wave from the encounter_seed.
		var wave_seed: int = stage.encounter_seed + wave_index
		# Debug: mark the start of each shrine wave in the logs so it is
		# clear when a new wave begins and which seed it uses.
		print("[shrine] Wave %d/%d — seed=%d" % [wave_index + 1, shrine_waves, wave_seed])

		# Build the enemy pack for this wave.
		var enemies: Array = EnemyFactory.spawn_realm_pack(realm, stage)

		var combat_result: Dictionary = {}
		if combat_runner != null and combat_runner.is_valid():
			# Purify Shrine uses the same "no round cap" behavior as other Realm stages.
			combat_result = combat_runner.call(hero_party, enemies, wave_seed, -1)
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

		var wave_success: bool = bool(combat_result.get("success", true))
		if not wave_success:
			# Party wiped (or harness reported failure) in this wave.
			overall_success = false
			break

		# If the wave was successful, apply shrine passive HP drain.
		if shrine_drain_per_wave != 0:
			shrine_hp -= shrine_drain_per_wave
			# Debug: show shrine HP after passive drain so the \"timer\" is
			# visible while reading logs.
			print("[shrine] Shrine HP after wave %d: %d/%d (drain=%d)" \
				% [wave_index + 1, max(shrine_hp, 0), shrine_hp_max, shrine_drain_per_wave])
			if shrine_hp <= 0:
				# Shrine has fully drained before all waves were cleared.
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
	result["combat"] = {
		"success": final_success,
		"waves": waves_results,
		"shrine_hp_max": shrine_hp_max,
		"shrine_hp_end": max(shrine_hp, 0),
	}

	return result
