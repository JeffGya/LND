extends Resource
class_name StageModel
## StageModel
## Pure data container for a single stage inside a Realm.
## Canon anchors:
##  - §6 World / Realm Structure: Realms are made of sequential stages.
##  - §12 Balance Curves: stage structure plugs into pacing & rewards.
##
## This model is intentionally "dumb":
##  - no RNG
##  - no combat logic
##  - only fields + (de)serialization helpers
##
## RealmGenerator (Subtask D) will construct these, and RealmModel /
## save/load code will serialize them via to_dict()/from_dict().

# Index of this stage within its Realm (0-based, MVP = 0..4)
var index: int = 0

# High-level template that describes what happens in this stage.
# MVP templates:
#  - "combat_trial"
#  - "purify_shrine"
# Expandable later to "escort", "recover", etc.
var objective_type: String = ""

# Deterministic seed for anything that happens inside this stage
# (encounter composition, small variations, etc.).
var encounter_seed: int = 0

# Free-form modifiers applied to this stage.
# Examples (MVP suggestions, not enforced here):
#  - "fear_delta": int          # how much this stage tends to raise/lower fear
#  - "env_tags": Array[String]  # e.g. ["dust", "whispers"]
#  - "reward_bonus": float      # minor Ase/Ekwan adjustments
#
# Purify Shrine (objective_type == "purify_shrine") expected modifier keys:
#   - "shrine_waves": int
#         Number of combat waves for this shrine stage.
#         MVP uses 2, sourced from GameBalance_Realm.get_purify_waves().
#
#   - "morale_drain_per_wave": int
#         Amount of morale each participating hero loses after
#         each successful wave. Tier-scaled value provided by
#         GameBalance_Realm.get_purify_morale_drain(stage_tier).
#
#   - "shrine_reward_multiplier": float
#         Multiplier applied to the standard stage rewards for
#         shrines. Tier-scaled via
#         GameBalance_Realm.get_purify_reward_mult(stage_tier).
#
#   - "shrine_hp_max": int
#         Max HP for the shrine in this stage. Derived from
#         GameBalance_Realm.get_purify_shrine_hp(stage_tier) and used
#         by ObjectiveRunner to approximate the shrine "timer" at the
#         stage level.
#
#   - "shrine_passive_drain_per_wave": int
#         Amount of shrine HP lost automatically after each completed
#         wave. Derived from
#         GameBalance_Realm.get_purify_shrine_passive_drain_per_wave(stage_tier).
#         Per-round drain and an explicit shrine entity will be added
#         in the Combat Simulation Core epic.
#
# These keys allow ObjectiveRunner, Morale systems, and
# RealmRewardCalc to behave correctly without hard-coded numbers.
var modifiers: Dictionary = {}

# Runtime progress flag. Stored here so save/load can reconstruct
# which stages have already been cleared.
var is_completed: bool = false


func _init(
		_index: int = 0,
		_objective_type: String = "",
		_encounter_seed: int = 0,
		_modifiers: Dictionary = {}
	) -> void:
	## Convenience constructor for generators.
	index = _index
	objective_type = _objective_type
	encounter_seed = _encounter_seed
	# Duplicate to avoid accidentally sharing a mutable default dictionary.
	modifiers = _modifiers.duplicate(true) if _modifiers.size() > 0 else {}
	is_completed = false


func to_dict() -> Dictionary:
	## Serialize this StageModel to a Dictionary that can be written
	## to a save file or debug log. All fields are primitive or
	## Dictionary/Array so JSON conversion stays straightforward.
	return {
		"index": index,
		"objective_type": objective_type,
		"encounter_seed": encounter_seed,
		"modifiers": modifiers,
		"is_completed": is_completed,
	}


static func from_dict(data: Dictionary) -> StageModel:
	## Build a StageModel from a previously serialized Dictionary.
	## This function must be deterministic and have no side effects.
	var stage := StageModel.new()

	stage.index = int(data.get("index", 0))
	stage.objective_type = String(data.get("objective_type", ""))
	stage.encounter_seed = int(data.get("encounter_seed", 0))

	var raw_modifiers = data.get("modifiers", {})
	if typeof(raw_modifiers) == TYPE_DICTIONARY:
		# We duplicate to make sure we own our copy.
		stage.modifiers = (raw_modifiers as Dictionary).duplicate(true)
	else:
		stage.modifiers = {}

	stage.is_completed = bool(data.get("is_completed", false))

	return stage


func mark_completed() -> void:
	## Small helper to mark the stage as completed.
	## We keep it simple here so RealmModel / RealmService can
	## toggle this without knowing the internal field name.
	is_completed = true
