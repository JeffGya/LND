

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
	##        func(hero_party: Array, enemies: Array, seed: int) -> Dictionary
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
		combat_result = combat_runner.call(hero_party, enemies, stage.encounter_seed)
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
	##  - Reuse the same combat flow as Combat Trial but with smaller packs
	##    (already handled by EnemyFactory._get_pack_size_for_stage()).
	##  - We do NOT yet apply fear/morale changes here; that will be wired
	##    in once the EmotionService is in place.
	var enemies: Array = EnemyFactory.spawn_realm_pack(realm, stage)

	var combat_result: Dictionary = {}
	if combat_runner != null and combat_runner.is_valid():
		combat_result = combat_runner.call(hero_party, enemies, stage.encounter_seed)
	else:
		combat_result = {
			"success": true,
			"log": [
				"[ObjectiveRunner] No combat_runner configured; Purify Shrine auto-success.",
			],
		}

	var success: bool = bool(combat_result.get("success", true))
	result["success"] = success
	result["combat"] = combat_result
	return result
