extends Node
class_name RealmService
## RealmService
## Small orchestrator around Realm generation and caching.
##
## Canon anchors:
##  - Story: "As the Keeper I want seeded Realms" (Realm JSON created and cached).
##  - §6 World / Realm Structure: realms as seeded, sequential stages.
##  - §12 Balance Curves: determinism via seeds, not ad-hoc RNG.
##
## Responsibilities (MVP):
##  - Provide a single entry point to obtain a RealmModel for a realm_id/tier.
##  - Cache generated realms in memory keyed by (realm_id, tier).
##  - Track the currently active realm.
##  - Advance stages when a stage is completed and delegate rewards to EconomyService.
##
## Non-responsibilities:
##  - Does NOT do combat.
##  - Does NOT calculate rewards directly (that will be RealmRewardCalc).
##  - Does NOT talk to disk/save directly (save system will pass RealmModels in/out).

static var _realms: Dictionary = {}
static var _active_realm: RealmModel = null


static func _make_key(realm_id: String, tier: int) -> String:
	## Build a stable cache key from realm_id and tier.
	## Example: "vale_of_dust:1"
	var safe_tier: int = max(1, tier)
	return "%s:%d" % [realm_id, safe_tier]


static func get_cached(realm_id: String, tier: int) -> RealmModel:
	## Return a cached RealmModel for the given realm_id/tier if present,
	## or null if it has not been generated yet.
	var key: String = _make_key(realm_id, tier)
	if _realms.has(key):
		return _realms[key]
	return null


static func get_or_create(realm_id: String, tier: int, campaign_seed: int) -> RealmModel:
	## Main entry point: obtain a RealmModel for the given realm_id/tier.
	## If it exists in the cache, return that instance; otherwise generate
	## a new one using RealmGenerator and cache it.
	var key: String = _make_key(realm_id, tier)
	if _realms.has(key):
		return _realms[key]

	var realm: RealmModel = RealmGenerator.generate(realm_id, tier, campaign_seed)
	_realms[key] = realm

	# If there is no active realm yet, set this one as active by default.
	if _active_realm == null:
		_active_realm = realm

	return realm


static func set_active(realm: RealmModel) -> void:
	## Mark the given realm as the currently active realm.
	## If it is not yet present in the cache, it will be inserted using
	## its id and tier as key (defensive, to avoid dangling references).
	_active_realm = realm

	if realm == null:
		return

	var key: String = _make_key(realm.id, realm.tier)
	if not _realms.has(key):
		_realms[key] = realm


static func get_active() -> RealmModel:
	## Return the currently active realm, or null if none is active.
	return _active_realm


static func complete_stage() -> Dictionary:
	## Resolve and apply rewards for the current stage of the active realm,
	## mark it as completed, and advance to the next stage if possible.
	##
	## This function wires together:
	##  - RealmRewardCalc: to compute Ase/Ekwan/relic rewards.
	##  - EconomyService:  to apply those rewards to the player's bank.
	##  - RealmModel:      to update stage/realm completion state.
	##
	## Return shape (MVP):
	##  {
	##    "stage": StageModel or null,
	##    "stage_rewards": Dictionary,       # deltas applied for this stage
	##    "completion_rewards": Dictionary,  # deltas applied for realm clear (if any)
	##  }
	var result: Dictionary = {
		"stage": null,
		"stage_rewards": {},
		"completion_rewards": {},
	}

	if _active_realm == null:
		return result

	var stage: StageModel = _active_realm.get_current_stage()
	if stage == null:
		return result

	# 1) Compute per-stage rewards and apply them to the economy.
	var calc_stage_reward: Dictionary = RealmRewardCalc.stage_rewards(_active_realm, stage)
	var applied_stage_reward: Dictionary = EconomyService.apply_realm_stage_rewards(calc_stage_reward, _active_realm, stage)

	# 2) Mark stage as completed and advance to the next stage.
	stage.mark_completed()
	_active_realm.advance_to_next_stage()

	# 3) If the realm is now finished, compute and apply completion rewards.
	var completion_reward: Dictionary = {}
	if _active_realm.is_finished():
		var calc_completion: Dictionary = RealmRewardCalc.completion_rewards(_active_realm)
		completion_reward = EconomyService.apply_realm_completion_rewards(calc_completion, _active_realm)
		_active_realm.mark_completed()

	result["stage"] = stage
	result["stage_rewards"] = applied_stage_reward
	result["completion_rewards"] = completion_reward

	return result


static func clear_cache() -> void:
	## Clear all cached realms and reset the active realm.
	## Intended mainly for tests and debug tools.
	_realms.clear()
	_active_realm = null
