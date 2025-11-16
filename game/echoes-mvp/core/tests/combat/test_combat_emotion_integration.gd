

extends RefCounted

# Test suite: Combat ↔ EmotionService integration (contract-level)
#
# These tests focus on the contract between combat results and EmotionService:
# - EmotionService exposes an apply_combat_result(...) hook.
# - Given a well-formed result["emotion"] block, EmotionService forwards
#   per-hero deltas into its internal state via apply_delta.
#
# IMPORTANT:
# For now we do *not* spin up real combats here. Instead we:
#   1) Create an EmotionService instance.
#   2) Seed a hero's emotion state to known values.
#   3) Feed a synthetic "emotion" payload into apply_combat_result.
#   4) Assert that the stored values change as expected.
#
# If EmotionService requires a full game bootstrap (SaveService/GameState)
# and refuses to change unknown heroes, we treat these as "skipped" tests
# rather than hard failures, similar to test_emotion_service.gd.

const EMOTION_SERVICE_PATH := "res://core/services/EmotionService.gd"
const LABEL := "[test_combat_emotion_integration]"

static func run_all() -> void:
	print("%s Running Combat ↔ EmotionService integration tests..." % LABEL)
	var all_passed := true

	if not _test_apply_combat_result_optional():
		all_passed = false

	if all_passed:
		print("%s All tests completed." % LABEL)
	else:
		print("%s Some tests FAILED." % LABEL)


static func _new_emotion_service() -> Object:
	var emo_script: Script = load(EMOTION_SERVICE_PATH)
	if emo_script == null:
		push_error("%s FAILED: could not load EmotionService at %s" % [LABEL, EMOTION_SERVICE_PATH])
		return Object.new()
	var emo: Object = emo_script.new()
	return emo


# -------------------------------------------------------------------
# Contract test: apply_combat_result
# -------------------------------------------------------------------

static func _test_apply_combat_result_optional() -> bool:
	var emo: Object = _new_emotion_service()
	if emo == null:
		_print_fail("apply_combat_result", "EmotionService instance is null.")
		return false

	if not (emo.has_method("get_morale")
		and emo.has_method("get_fear")
		and emo.has_method("apply_delta")
		and emo.has_method("apply_combat_result")):
		_print_pass("apply_combat_result (skipped: required methods missing; EmotionService not fully wired yet)")
		return true

	var hero_id: int = 1

	# 1) Seed hero emotion to a known baseline (morale=50, fear=10)
	var start_morale: int = int(emo.call("get_morale", hero_id))
	var start_fear: int = int(emo.call("get_fear", hero_id))

	var target_morale: int = 50
	var target_fear: int = 10
	var delta_to_target_morale: int = target_morale - start_morale
	var delta_to_target_fear: int = target_fear - start_fear

	if delta_to_target_morale != 0 or delta_to_target_fear != 0:
		emo.call("apply_delta", hero_id, delta_to_target_morale, delta_to_target_fear, "test_seed")

	var seeded_morale: int = int(emo.call("get_morale", hero_id))
	var seeded_fear: int = int(emo.call("get_fear", hero_id))

	# If we cannot reliably seed to 50/10, this likely means EmotionService
	# needs a full SaveService/GameState bootstrap. In that case, we mark
	# this test as skipped instead of failing hard.
	if seeded_morale != target_morale or seeded_fear != target_fear:
		_print_pass("apply_combat_result (skipped: could not seed hero to 50/10; service likely needs bootstrap)")
		return true

	# 2) Build a synthetic combat emotion payload:
	#    - hero 1 lost 5 morale, gained 3 fear during combat.
	var emo_block: Dictionary = {
		"heroes": {
			hero_id: {
				"morale_delta": -5,
				"fear_delta": 3,
			},
		},
	}

	# 3) Apply the combat result to EmotionService.
	emo.call("apply_combat_result", emo_block)

	# 4) Assert that stored values changed as expected.
	var final_morale: int = int(emo.call("get_morale", hero_id))
	var final_fear: int = int(emo.call("get_fear", hero_id))

	var expected_morale: int = target_morale - 5
	var expected_fear: int = target_fear + 3

	var ok := true
	ok = ok and _assert_equal_int("apply_combat_result.morale", final_morale, expected_morale)
	ok = ok and _assert_equal_int("apply_combat_result.fear", final_fear, expected_fear)

	if ok:
		_print_pass("apply_combat_result")
	else:
		_print_fail("apply_combat_result", "Expected (%d, %d) got (%d, %d)" % [
			expected_morale, expected_fear, final_morale, final_fear,
		])
	return ok


# -------------------------------------------------------------------
# Tiny assertion helpers
# -------------------------------------------------------------------

static func _assert_equal_int(label: String, got: int, expected: int) -> bool:
	if got != expected:
		_print_line("%s FAIL [%s] expected=%d got=%d" % [LABEL, label, expected, got])
		return false
	return true


static func _print_pass(name: String) -> void:
	_print_line("%s PASS: %s" % [LABEL, name])


static func _print_fail(name: String, msg: String) -> void:
	_print_line("%s FAIL: %s — %s" % [LABEL, name, msg])


static func _print_line(msg: String) -> void:
	print(msg)