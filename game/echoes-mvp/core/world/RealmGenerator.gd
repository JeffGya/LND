extends Resource
class_name RealmGenerator
## RealmGenerator
## From config + seed => RealmModel (with StageModel children).
## Canon anchors:
##  - §6 World / Realm Structure: 5-stage Realms in MVP.
##  - §8 Economy & Progression: Realms as Ase/Ekwan sources (later via rewards).
##  - §12 Balance Curves: tier + seed drive pacing, not ad-hoc randomness.
##
## This generator is:
##  - deterministic: same (campaign_seed, realm_id, tier) => same RealmModel layout
##  - side-effect free: no saving, no combat, no global state
##  - data-first: only builds RealmModel/StageModel instances

static func generate(realm_id: String, tier: int, campaign_seed: int) -> RealmModel:
	## Build a RealmModel for the given realm_id, tier and campaign seed.
	## This is the canonical entry point used by RealmService and debug tools.
	##
	## Steps:
	##  1) Resolve realm meta from GameBalance_Realm.
	##  2) Derive a realm_seed via RealmSeed.realm_seed().
	##  3) Look up stage count for the realm (MVP: fixed 5).
	##  4) For each stage index:
	##       - derive a stage_seed
	##       - roll objective_type from REALM_OBJECTIVE_WEIGHTS
	##       - build minimal modifiers dict
	##       - construct StageModel
	##  5) Return a RealmModel filled with these stages.
	var meta: Dictionary = GameBalance_Realm.get_realm_meta(realm_id)
	if meta.is_empty():
		# Fallback: use the first realm in the config as a safe default.
		var all_ids: Array = GameBalance_Realm.get_realm_ids()
		if all_ids.is_empty():
			push_warning("RealmGenerator.generate(): No realms defined in GameBalance_Realm. Returning empty RealmModel.")
			return RealmModel.new()
		var fallback_id: String = String(all_ids[0])
		meta = GameBalance_Realm.get_realm_meta(fallback_id)
		realm_id = fallback_id

	var realm_name: String = String(meta.get("name", realm_id))
	var virtue: String = String(meta.get("virtue", ""))
	var default_tier: int = int(meta.get("default_tier", 1))
	var final_tier: int = tier if tier > 0 else default_tier

	# 2) Derive realm seed
	var r_seed: int = RealmSeed.realm_seed(campaign_seed, realm_id, final_tier)

	# 3) Resolve stage count (MVP: 5, but future-proof via config).
	var stage_count: int = GameBalance_Realm.get_stage_count(realm_id)
	if stage_count <= 0:
		# Failsafe: enforce at least one stage if config is mis-set.
		stage_count = 1

	# 4) Prepare objective weights once.
	var weights: Dictionary = GameBalance_Realm.get_objective_weights(realm_id)

	var stages: Array[StageModel] = []
	stages.resize(stage_count)

	for i in stage_count:
		var s_seed: int = RealmSeed.stage_seed(r_seed, i)
		var rng := RandomNumberGenerator.new()
		rng.seed = s_seed

		var objective_type: String = _choose_weighted_objective(weights, rng)
		var modifiers: Dictionary = _build_stage_modifiers(virtue, final_tier, objective_type)

		var stage := StageModel.new(i, objective_type, s_seed, modifiers)
		stages[i] = stage

	# 5) Construct RealmModel
	var realm := RealmModel.new(
		realm_id,
		realm_name,
		virtue,
		final_tier,
		r_seed,
		stages
	)

	return realm


static func _choose_weighted_objective(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	## Deterministically choose an objective_type from the given weights.
	## Example weights:
	##  {
	##    "combat_trial": 70,
	##    "purify_shrine": 30,
	##  }
	##
	## We sort keys to keep the iteration order stable across platforms.
	if weights.is_empty():
		return "combat_trial"

	var keys: Array = weights.keys()
	keys.sort() # stable ordering (String sort)

	var total: int = 0
	for key in keys:
		var w: int = int(weights.get(key, 0))
		if w > 0:
			total += w

	if total <= 0:
		# All weights are zero or negative; fall back to the first key.
		return String(keys[0])

	var roll: int = rng.randi_range(1, total)
	var cumulative: int = 0

	for key in keys:
		var weight_value: int = int(weights.get(key, 0))
		if weight_value <= 0:
			continue
		cumulative += weight_value
		if roll <= cumulative:
			return String(key)

	# Fallback (should not happen if logic above is correct).
	return String(keys.back())


static func _build_stage_modifiers(virtue: String, tier: int, objective_type: String) -> Dictionary:
	## Build a minimal modifiers dictionary for a stage.
	## MVP: we only encode fear pressure via tier scalars.
	## Later we can add env_tags, virtue-specific bonuses, etc.
	var scalars: Dictionary = GameBalance_Realm.get_tier_scalars(tier)
	var fear_add: int = int(scalars.get("fear_pressure_add", 0))

	var modifiers: Dictionary = {}
	modifiers["fear_delta"] = fear_add

	# MVP: keep env_tags empty; we can fill this in when we add more flavor.
	# Example future usage:
	#  if virtue == "courage":
	#      modifiers["env_tags"] = ["dust", "echoing_steps"]
	#  elif virtue == "wisdom":
	#      modifiers["env_tags"] = ["mist", "whispers"]

	# Purify Shrine objective-specific modifiers.
	# When this stage is a shrine (objective_type == "purify_shrine"),
	# we attach shrine tuning knobs here so ObjectiveRunner, morale
	# systems, and reward calculators can read them from StageModel.
	if objective_type == "purify_shrine":
		var waves: int = GameBalance_Realm.get_purify_waves()
		var drain: int = GameBalance_Realm.get_purify_morale_drain(tier)
		var mult: float = GameBalance_Realm.get_purify_reward_mult(tier)

		# Shrine HP and per-wave passive drain, approximating the shrine timer
		# at the stage level. Per-round drain and an explicit shrine entity
		# will be added in the Combat Simulation Core epic.
		var shrine_hp: int = GameBalance_Realm.get_purify_shrine_hp(tier)
		var shrine_drain: int = GameBalance_Realm.get_purify_shrine_passive_drain_per_wave(tier)

		modifiers["shrine_waves"] = waves
		modifiers["morale_drain_per_wave"] = drain
		modifiers["shrine_reward_multiplier"] = mult
		modifiers["shrine_hp_max"] = shrine_hp
		modifiers["shrine_passive_drain_per_wave"] = shrine_drain

	return modifiers
