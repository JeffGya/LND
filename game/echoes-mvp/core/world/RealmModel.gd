extends Resource
class_name RealmModel
## RealmModel
## Pure data container representing a single Realm run/layout.
## Canon anchors:
##  - §6 World / Realm Structure: Realms as sequential stages.
##  - §8 Economy & Progression: Realms as sources of Ase/Ekwan.
##  - §12 Balance Curves: tier and stage structure drive pacing.
##
## This model is intentionally "dumb":
##  - no RNG
##  - no combat logic
##  - only fields + helpers + (de)serialization
##
## RealmGenerator (Subtask D) will construct instances of this,
## and RealmService / save/load will serialize via to_dict()/from_dict().

const INVALID_STAGE_INDEX: int = -1

# Stable realm identifier, must match keys in GameBalance_Realm.REALM_LIST
# e.g. "vale_of_dust", "shrouded_grove".
var id: String = ""

# Display name for UI / logs, e.g. "Vale of Dust".
var name: String = ""

# Virtue theme, e.g. "courage", "wisdom".
var virtue: String = ""

# Difficulty tier (1..N), used with GameBalance_Realm.get_tier_scalars().
var tier: int = 1

# Deterministic seed used to construct this realm's stages.
# Derived from (campaign_seed, realm_id, tier) by RealmSeed in Subtask C.
var seed: int = 0

# Ordered sequence of stages for this realm run.
# MVP: size() == 5, but not enforced here to keep it future-proof.
var stages: Array[StageModel] = []

# Index of the current/active stage (0-based).
# INVALID_STAGE_INDEX means "no active stage selected yet".
var current_stage_index: int = INVALID_STAGE_INDEX

# True if this RealmModel was reconstructed from a save file
# rather than freshly generated. Helpful for debugging and logs.
var restored: bool = false

# Optional aggregate completion flag for the entire realm.
# RealmService can toggle this once all stages are completed.
var is_completed: bool = false


func _init(
		_id: String = "",
		_name: String = "",
		_virtue: String = "",
		_tier: int = 1,
		_seed: int = 0,
		_stages: Array[StageModel] = []
	) -> void:
	## Convenience constructor for generators.
	id = _id
	name = _name
	virtue = _virtue
	tier = _tier
	seed = _seed

	# Only override the default stages array if a non-empty list was provided.
	if _stages.size() > 0:
		stages = _stages.duplicate(true)

	current_stage_index = 0 if stages.size() > 0 else INVALID_STAGE_INDEX
	restored = false
	is_completed = false


func to_dict() -> Dictionary:
	## Serialize this RealmModel to a Dictionary suitable for saving
	## or debug logging. The structure is intentionally simple so it
	## can be JSON-encoded without loss.
	var stage_dicts: Array = []
	stage_dicts.resize(stages.size())
	for i in stages.size():
		var stage: StageModel = stages[i]
		stage_dicts[i] = stage.to_dict()

	return {
		"id": id,
		"name": name,
		"virtue": virtue,
		"tier": tier,
		"seed": seed,
		"current_stage_index": current_stage_index,
		"restored": restored,
		"is_completed": is_completed,
		"stages": stage_dicts,
	}


static func from_dict(data: Dictionary) -> RealmModel:
	## Build a RealmModel from a previously serialized Dictionary.
	## This function must be deterministic and side-effect free.
	var model := RealmModel.new()

	model.id = String(data.get("id", ""))
	model.name = String(data.get("name", ""))
	model.virtue = String(data.get("virtue", ""))
	model.tier = int(data.get("tier", 1))
	model.seed = int(data.get("seed", 0))

	var stages_array: Array = data.get("stages", [])
	model.stages.clear()
	for entry in stages_array:
		if typeof(entry) == TYPE_DICTIONARY:
			var stage_dict: Dictionary = entry
			var stage: StageModel = StageModel.from_dict(stage_dict)
			model.stages.append(stage)

	model.current_stage_index = int(data.get("current_stage_index", 0))
	if model.current_stage_index < 0 or model.current_stage_index >= model.stages.size():
		model.current_stage_index = (0 if model.stages.size() > 0 else INVALID_STAGE_INDEX)

	model.restored = bool(data.get("restored", true))
	model.is_completed = bool(data.get("is_completed", false))

	return model


func get_stage_count() -> int:
	## Returns the number of stages in this realm.
	return stages.size()


func get_current_stage() -> StageModel:
	## Returns the currently active stage, or null if none is active.
	if current_stage_index < 0 or current_stage_index >= stages.size():
		return null
	return stages[current_stage_index]


func is_finished() -> bool:
	## Returns true if the realm is considered finished.
	## Priority:
	##  1) Respect explicit is_completed flag, if set.
	##  2) Otherwise, check if all stages are marked completed.
	if is_completed:
		return true

	if stages.is_empty():
		return false

	for stage in stages:
		var s: StageModel = stage
		if not s.is_completed:
			return false

	return true


func advance_to_next_stage() -> void:
	## Moves current_stage_index to the next stage if possible.
	## Does nothing if already at the last stage or no stages exist.
	if stages.is_empty():
		return

	if current_stage_index == INVALID_STAGE_INDEX:
		current_stage_index = 0
		return

	if current_stage_index < stages.size() - 1:
		current_stage_index += 1
	else:
		# We reached (or passed) the last stage; RealmService may
		# choose to call mark_completed() once rewards are granted.
		current_stage_index = stages.size() - 1


func mark_completed() -> void:
	## Marks the realm as completed. RealmService should call this
	## when the final stage is cleared and rewards are granted.
	is_completed = true
