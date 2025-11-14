extends RefCounted

## Realm generation & seed determinism tests (Subtask J)
##
## These are lightweight, script-level tests that can be invoked from a
## test harness or manually via GDScript:
##
##   var T = load("res://core/tests/realm/test_realm_generation.gd")
##   T.run_all()
##
## The goal is to prove:
##   - RealmSeed is stable for the same inputs.
##   - RealmGenerator is deterministic for the same inputs.
##   - RealmService.get_or_create() caches realms as expected.

const RealmSeed = preload("res://core/world/RealmSeed.gd")
const RealmGenerator = preload("res://core/world/RealmGenerator.gd")
const RealmService = preload("res://core/services/RealmService.gd")

static func _assert_true(cond: bool, label: String) -> void:
	if cond:
		print("[test_realm_generation] PASS: %s" % label)
	else:
		push_error("[test_realm_generation] FAIL: %s" % label)

static func _assert_eq(a, b, label: String) -> void:
	if a == b:
		print("[test_realm_generation] PASS: %s" % label)
	else:
		push_error("[test_realm_generation] FAIL: %s (got=%s, expected=%s)" % [
			label,
			str(a),
			str(b),
		])

## Entry point for convenience.
static func run_all() -> void:
	print("[test_realm_generation] Running realm generation tests...")
	test_realm_seed_stability()
	test_realm_generator_determinism()
	test_realm_service_cache()
	print("[test_realm_generation] All tests completed.")

## Test 1: RealmSeed stability for identical inputs.
static func test_realm_seed_stability() -> void:
	var campaign_seed := 1021013846
	var realm_id := "vale_of_dust"
	var tier := 1

	var s1 := RealmSeed.realm_seed(campaign_seed, realm_id, tier)
	var s2 := RealmSeed.realm_seed(campaign_seed, realm_id, tier)

	_assert_eq(s1, s2, "realm_seed must be stable for same inputs")

	var stage_seed_0_a := RealmSeed.stage_seed(s1, 0)
	var stage_seed_0_b := RealmSeed.stage_seed(s1, 0)
	_assert_eq(stage_seed_0_a, stage_seed_0_b, "stage_seed must be stable for same realm_seed/index")

## Test 2: RealmGenerator determinism for same inputs.
static func test_realm_generator_determinism() -> void:
	var campaign_seed := 1021013846
	var realm_id := "vale_of_dust"
	var tier := 1

	var r1 = RealmGenerator.generate(realm_id, tier, campaign_seed)
	var r2 = RealmGenerator.generate(realm_id, tier, campaign_seed)

	_assert_eq(r1.id, r2.id, "generated realms should share id")
	_assert_eq(r1.tier, r2.tier, "generated realms should share tier")
	_assert_eq(r1.seed, r2.seed, "generated realms should share seed")

	var count1: int = r1.stages.size()
	var count2: int = r2.stages.size()
	_assert_eq(count1, count2, "generated realms should have same stage count")

	for i in range(count1):
		var s1 = r1.stages[i]
		var s2 = r2.stages[i]
		_assert_eq(s1.objective_type, s2.objective_type, "stage %d objective_type matches" % i)
		_assert_eq(s1.encounter_seed, s2.encounter_seed, "stage %d encounter_seed matches" % i)
		_assert_eq(s1.modifiers, s2.modifiers, "stage %d modifiers match" % i)

## Test 3: RealmService cache returns the same instance for repeated calls.
static func test_realm_service_cache() -> void:
	RealmService.clear_cache()

	var campaign_seed := 1021013846
	var realm_id := "vale_of_dust"
	var tier := 1

	var r1 = RealmService.get_or_create(realm_id, tier, campaign_seed)
	var r2 = RealmService.get_or_create(realm_id, tier, campaign_seed)

	# For now we expect the exact same instance (cached), not just equal data.
	_assert_true(r1 == r2, "RealmService should cache realms per realm_id/tier key")
