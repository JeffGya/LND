

extends RefCounted

## Realm reward pacing tests (Subtask J)
##
## These tests focus on:
##  - Non-negative rewards (no hard stalls).
##  - Monotonic scaling across tiers (higher tiers never pay less).
##  - Non-negative realm completion bonuses.
##
## They are intentionally light on exact numbers and instead assert the
## *shape* of the reward curves, so we can freely tune balance constants
## without rewriting tests.

const RealmModel = preload("res://core/world/RealmModel.gd")
const StageModel = preload("res://core/world/StageModel.gd")
const RealmRewardCalc = preload("res://core/world/RealmRewardCalc.gd")
const GameBalance_Realm = preload("res://core/config/GameBalance_Realm.gd")

static func _assert_true(cond: bool, label: String) -> void:
	if cond:
		print("[test_realm_rewards] PASS: %s" % label)
	else:
		push_error("[test_realm_rewards] FAIL: %s" % label)

static func _assert_eq(a, b, label: String) -> void:
	if a == b:
		print("[test_realm_rewards] PASS: %s" % label)
	else:
		push_error("[test_realm_rewards] FAIL: %s (got=%s, expected=%s)" % [
			label,
			str(a),
			str(b),
		])

## Convenience: aggregate all tests for manual or scripted runs.
static func run_all() -> void:
	print("[test_realm_rewards] Running realm reward tests...")
	test_stage_rewards_non_negative()
	test_tier_scaling_monotonic()
	test_completion_rewards_non_negative()
	print("[test_realm_rewards] All tests completed.")

## --- Helpers -----------------------------------------------------------------

static func _make_fake_realm(realm_id: String, tier: int, stage_count: int) -> RealmModel:
	# Construct a minimal RealmModel suitable for exercising RealmRewardCalc.
	var realm: RealmModel = RealmModel.new()
	realm.id = realm_id
	realm.tier = tier
	realm.seed = 123456789

	# Ensure stages array exists and fill with simple combat_trial stages.
	realm.stages.clear()
	for i in range(stage_count):
		var stg: StageModel = StageModel.new()
		stg.index = i
		stg.objective_type = "combat_trial"
		stg.encounter_seed = 1000 + i
		stg.modifiers = {"fear_delta": 5}
		realm.stages.append(stg)

	realm.current_stage_index = 0
	return realm

static func _first_stage(realm: RealmModel) -> StageModel:
	if realm.stages.is_empty():
		var dummy: StageModel = StageModel.new()
		dummy.index = 0
		dummy.objective_type = "combat_trial"
		dummy.encounter_seed = 0
		dummy.modifiers = {}
		return dummy
	return realm.stages[0]

## --- Tests -------------------------------------------------------------------

## Test 1: Stage rewards should be non-negative and provide at least 1 Ase on success.
static func test_stage_rewards_non_negative() -> void:
	var realm: RealmModel = _make_fake_realm("vale_of_dust", 1, 5)
	var stage: StageModel = _first_stage(realm)

	var rewards: Dictionary = RealmRewardCalc.stage_rewards(realm, stage)

	var ase: int = int(rewards.get("ase_delta", rewards.get("ase", 0)))
	var ekwan: int = int(rewards.get("ekwan_delta", rewards.get("ekwan", 0)))

	_assert_true(ase >= 1, "Stage Ase reward should be at least 1 for success.")
	_assert_true(ekwan >= 0, "Stage Ekwan reward should never be negative.")

## Test 2: Rewards should scale monotonically with tier (no lower rewards at higher tiers).
static func test_tier_scaling_monotonic() -> void:
	var realm_t1: RealmModel = _make_fake_realm("vale_of_dust", 1, 5)
	var realm_t2: RealmModel = _make_fake_realm("vale_of_dust", 2, 5)
	var realm_t3: RealmModel = _make_fake_realm("vale_of_dust", 3, 5)

	var s1: StageModel = _first_stage(realm_t1)
	var s2: StageModel = _first_stage(realm_t2)
	var s3: StageModel = _first_stage(realm_t3)

	var r1: Dictionary = RealmRewardCalc.stage_rewards(realm_t1, s1)
	var r2: Dictionary = RealmRewardCalc.stage_rewards(realm_t2, s2)
	var r3: Dictionary = RealmRewardCalc.stage_rewards(realm_t3, s3)

	var ase1: int = int(r1.get("ase_delta", r1.get("ase", 0)))
	var ase2: int = int(r2.get("ase_delta", r2.get("ase", 0)))
	var ase3: int = int(r3.get("ase_delta", r3.get("ase", 0)))

	var ek1: int = int(r1.get("ekwan_delta", r1.get("ekwan", 0)))
	var ek2: int = int(r2.get("ekwan_delta", r2.get("ekwan", 0)))
	var ek3: int = int(r3.get("ekwan_delta", r3.get("ekwan", 0)))

	_assert_true(ase2 >= ase1, "Tier 2 Ase must be >= Tier 1.")
	_assert_true(ase3 >= ase2, "Tier 3 Ase must be >= Tier 2.")
	_assert_true(ek2 >= ek1, "Tier 2 Ekwan must be >= Tier 1.")
	_assert_true(ek3 >= ek2, "Tier 3 Ekwan must be >= Tier 2.")

## Test 3: Realm completion rewards should never be negative.
static func test_completion_rewards_non_negative() -> void:
	var realm: RealmModel = _make_fake_realm("vale_of_dust", 1, 5)
	var completion: Dictionary = RealmRewardCalc.completion_rewards(realm)

	var ase: int = int(completion.get("ase_delta", completion.get("ase", 0)))
	var ekwan: int = int(completion.get("ekwan_delta", completion.get("ekwan", 0)))

	_assert_true(ase >= 0, "Completion Ase must not be negative.")
	_assert_true(ekwan >= 0, "Completion Ekwan must not be negative.")