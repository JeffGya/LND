

extends Node

# Purify Shrine objective tests.
#
# These tests focus on the ObjectiveRunner shrine flow itself rather than the
# full combat engine. We stub the combat runner so we can deterministically
# exercise success / failure paths and shrine HP logic.

const ObjectiveRunnerScript = preload("res://core/world/ObjectiveRunner.gd")
const RealmModel            = preload("res://core/world/RealmModel.gd")
const StageModel            = preload("res://core/world/StageModel.gd")
const GameBalance_Realm     = preload("res://core/config/GameBalance_Realm.gd")

const TAG := "[test_purify_shrine]"

func _print(msg: String) -> void:
	print("%s %s" % [TAG, msg])

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_print("PASS: %s" % label)
	else:
		push_error("%s FAIL: %s" % [TAG, label])

func _assert_eq(a, b, label: String) -> void:
	if a == b:
		_print("PASS: %s" % label)
	else:
		push_error("%s FAIL: %s (expected=%s got=%s)" % [TAG, label, str(b), str(a)])

# Entry point used by the realms test harness (if wired).
func run_all() -> void:
	_print("Running Purify Shrine tests...")
	_test_purify_shrine_two_waves_success()
	_test_purify_shrine_fail_on_party_wipe()
	_test_purify_shrine_fail_on_shrine_hp_zero()
	_print("Purify Shrine tests complete.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_dummy_realm() -> RealmModel:
	var realm: RealmModel = RealmModel.new()
	# These fields mirror what RealmGenerator / logs use.
	realm.id = "vale_of_dust"
	realm.tier = 1
	realm.seed = 12345
	return realm


func _make_shrine_stage() -> StageModel:
	var stage: StageModel = StageModel.new()
	stage.objective_type = "purify_shrine"
	stage.encounter_seed = 98765
	stage.modifiers["fear_delta"] = 5

	var tier: int = 1
	# Mirror what RealmGenerator does when configuring shrine stages so the
	# ObjectiveRunner sees a realistic stage configuration.
	stage.modifiers["shrine_waves"] = GameBalance_Realm.get_purify_waves()
	stage.modifiers["morale_drain_per_wave"] = GameBalance_Realm.get_purify_morale_drain(tier)
	stage.modifiers["shrine_hp_max"] = GameBalance_Realm.get_purify_shrine_hp(tier)
	stage.modifiers["shrine_passive_drain_per_wave"] = GameBalance_Realm.get_purify_shrine_passive_drain_per_wave(tier)
	stage.modifiers["shrine_reward_multiplier"] = GameBalance_Realm.get_purify_reward_mult(tier)

	return stage


func _make_party_ids() -> Array[int]:
	# For these tests we only care that the party array is non-empty and
	# stable; the stubbed combat runner ignores the actual ids.
	return [1, 2, 3]


# Stub combat runners --------------------------------------------------------

# Always returns a successful combat result (no party wipe).
func _stub_combat_runner_always_win(party_ids: Array, enemies: Array, seed: int, round_limit: int) -> Dictionary:
	return {
		"success": true,
		"party_wiped": false,
		"meta": { "seed": seed },
	}


# Always wipes the party in the first wave.
func _stub_combat_runner_always_wipe(party_ids: Array, enemies: Array, seed: int, round_limit: int) -> Dictionary:
	return {
		"success": false,
		"party_wiped": true,
		"meta": { "seed": seed },
	}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_purify_shrine_two_waves_success() -> void:
	var realm := _make_dummy_realm()
	var stage := _make_shrine_stage()
	var party := _make_party_ids()

	var result: Dictionary = ObjectiveRunnerScript.run_stage(
		realm,
		stage,
		party,
		Callable(self, "_stub_combat_runner_always_win")
	)

	_assert_true(result.get("success", false), "Shrine succeeds when all waves are cleared and shrine survives.")

	var combat_v: Variant = result.get("combat", {})
	_assert_true(typeof(combat_v) == TYPE_DICTIONARY, "Combat summary is a dictionary for shrine stages.")
	if typeof(combat_v) != TYPE_DICTIONARY:
		return

	var combat: Dictionary = combat_v
	var waves_v: Variant = combat.get("waves", [])
	_assert_true(typeof(waves_v) == TYPE_ARRAY, "Combat summary contains waves array.")
	if typeof(waves_v) != TYPE_ARRAY:
		return

	var waves: Array = waves_v
	var expected_waves: int = int(stage.modifiers.get("shrine_waves", 2))
	_assert_eq(waves.size(), expected_waves, "Shrine runs exactly shrine_waves combats.")

	var hp_start := int(combat.get("shrine_hp_start", 0))
	var hp_end := int(combat.get("shrine_hp_end", 0))
	var hp_max := int(combat.get("shrine_hp_max", 0))

	_assert_eq(hp_start, hp_max, "Shrine HP starts at max.")
	_assert_true(hp_end > 0, "Shrine HP remains above 0 after successful run.")


func _test_purify_shrine_fail_on_party_wipe() -> void:
	var realm := _make_dummy_realm()
	var stage := _make_shrine_stage()
	var party := _make_party_ids()

	var result: Dictionary = ObjectiveRunnerScript.run_stage(
		realm,
		stage,
		party,
		Callable(self, "_stub_combat_runner_always_wipe")
	)

	_assert_false(result.get("success", true), "Shrine fails if the party wipes in wave 1.")

	var combat_v: Variant = result.get("combat", {})
	if typeof(combat_v) != TYPE_DICTIONARY:
		_assert_true(false, "Combat summary present on failure.")
		return

	var combat: Dictionary = combat_v
	var waves_v: Variant = combat.get("waves", [])
	if typeof(waves_v) != TYPE_ARRAY:
		_assert_true(false, "Waves array present on failure.")
		return

	var waves: Array = waves_v
	_assert_eq(waves.size(), 1, "Shrine stops after first wave on party wipe.")

	var hp_start := int(combat.get("shrine_hp_start", 0))
	var hp_end := int(combat.get("shrine_hp_end", 0))
	_assert_true(hp_end <= hp_start, "Shrine HP does not increase on failure.")


func _test_purify_shrine_fail_on_shrine_hp_zero() -> void:
	var realm := _make_dummy_realm()
	var stage := _make_shrine_stage()
	var party := _make_party_ids()

	# Force HP-based failure regardless of combat outcome by making the shrine
	# HP just enough to be fully drained across the configured waves.
	stage.modifiers["shrine_hp_max"] = 10
	stage.modifiers["shrine_passive_drain_per_wave"] = 10

	var result: Dictionary = ObjectiveRunnerScript.run_stage(
		realm,
		stage,
		party,
		Callable(self, "_stub_combat_runner_always_win")
	)

	_assert_false(result.get("success", true), "Shrine fails if shrine HP reaches 0 before all waves are cleared.")

	var combat_v: Variant = result.get("combat", {})
	if typeof(combat_v) != TYPE_DICTIONARY:
		_assert_true(false, "Combat summary present on HP-based failure.")
		return

	var combat: Dictionary = combat_v
	var hp_end := int(combat.get("shrine_hp_end", 9999))
	_assert_true(hp_end <= 0, "Shrine HP is <= 0 on HP-based failure.")

# Small helper because GDScript has assert() but we prefer non-fatal logging
# for this custom test harness.
func _assert_false(cond: bool, label: String) -> void:
	_assert_true(!cond, label)
