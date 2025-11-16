extends Node
class_name EmotionService

##
## EmotionService
##
## Central owner for per-hero emotional state (morale & fear).
##
## Responsibilities (Emotion & Morale Core epic, Subtask C):
##  - Provide a clean API for other systems (combat, shrine, realms, debug tools)
##    to read and modify morale/fear using hero ids.
##  - Clamp values into allowed ranges and emit useful debug logs.
##  - Delegate actual storage to the hero roster (HeroesIO + HeroModel).
##
## NOTE:
##  - This service does NOT own persistence itself; it relies on HeroesIO to
##    read/write hero dictionaries, and HeroModel to enforce emotion shape.
##  - Subtask C wires the core API; later subtasks (D/E/F) will call these
##    methods from combat, shrine, realms and debug console.
##

# ----------------------------------------
# Dependencies
# ----------------------------------------

var _heroes_io: HeroesIO = null


# ----------------------------------------
# Public setup
# ----------------------------------------

func setup(heroes_io: HeroesIO) -> void:
	## Called during game bootstrap to connect the service to the hero roster.
	## This should be passed the same HeroesIO instance that owns the campaign's
	## active heroes.
	_heroes_io = heroes_io
	if _heroes_io == null:
		push_warning("EmotionService.setup: heroes_io is null; emotion APIs will no-op.")


# ----------------------------------------
# Internal helpers
# ----------------------------------------

func _get_hero_model(hero_id: int) -> HeroModel:
	## Convenience: fetch a HeroModel view for the given hero id.
	## Returns null if heroes_io is not set or the hero cannot be found.
	if _heroes_io == null:
		push_warning("EmotionService._get_hero_model: heroes_io not set.")
		return null

	var model: HeroModel = _heroes_io.get_hero_model_by_id(hero_id)
	if model == null:
		push_warning("EmotionService._get_hero_model: hero_id=%d not found." % hero_id)
	return model


func _persist_hero_model(model: HeroModel) -> void:
	## Push updated HeroModel data back into the underlying roster.
	## For now we delegate to HeroesIO.update_hero_from_model, which updates
	## the in-memory hero dictionary (and therefore future reads / saves).
	if _heroes_io == null or model == null:
		return

	_heroes_io.update_hero_from_model(model)


# ----------------------------------------
# Core read API
# ----------------------------------------

func get_morale(hero_id: int) -> int:
	## Returns the hero's current morale value (0–100).
	var model := _get_hero_model(hero_id)
	if model == null:
		return 0
	return model.get_morale()


func get_fear(hero_id: int) -> int:
	## Returns the hero's current fear value (0–100).
	var model := _get_hero_model(hero_id)
	if model == null:
		return 0
	return model.get_fear()


func get_morale_base(hero_id: int) -> int:
	## Returns the hero's baseline morale value (0–100).
	var model := _get_hero_model(hero_id)
	if model == null:
		return 0
	return model.get_morale_base()


# ----------------------------------------
# Core write / delta API
# ----------------------------------------

func apply_delta(hero_id: int, morale_delta: int, fear_delta: int, source: String = "") -> void:
	##
	## Apply a delta to a single hero's emotional state.
	##
	## - hero_id: id of the hero in the roster.
	## - morale_delta: added to current morale (can be positive or negative).
	## - fear_delta: added to current fear (can be positive or negative).
	## - source: optional label for debug logs (e.g. "combat", "shrine:vale_of_dust").
	##
	var model := _get_hero_model(hero_id)
	if model == null:
		# Warning already emitted by _get_hero_model.
		return

	var before := model.get_emotion_snapshot()
	model.apply_emotion_delta(morale_delta, fear_delta)
	var after := model.get_emotion_snapshot()

	_persist_hero_model(model)

	var applied_morale_delta := int(after.get("morale_current", 0)) - int(before.get("morale_current", 0))
	var applied_fear_delta := int(after.get("fear_current", 0)) - int(before.get("fear_current", 0))

	var label := source
	if label == "":
		label = "unknown"

	print("[emotion] %s hero=%d Δmorale=%d Δfear=%d => morale=%d fear=%d" % [
		label,
		hero_id,
		applied_morale_delta,
		applied_fear_delta,
		int(after.get("morale_current", 0)),
		int(after.get("fear_current", 0)),
	])


# ----------------------------------------
# Shrine / realm helpers (used in later subtasks)
# ----------------------------------------

func apply_shrine_morale_drain(party_ids: Array, amount: int, realm_id: String) -> void:
	##
	## Apply a flat morale drain to all heroes in a party as part of shrine logic.
	## This is intentionally simple for MVP; later epics can make it scale with
	## Faith / Harmony / realm tier.
	##
	## - party_ids: Array of hero ids participating in the shrine defense.
	## - amount: morale lost per hero (positive integer, applied as -amount).
	## - realm_id: identifier for the realm, used only for logging context.
	##
	if amount == 0:
		return

	for id in party_ids:
		if typeof(id) != TYPE_INT:
			continue
		apply_delta(int(id), -amount, 0, "shrine:%s" % realm_id)


func apply_realm_fear_delta(party_ids: Array, fear_delta: int, ctx: Dictionary) -> void:
	##
	## Apply a fear_delta to all heroes in a party when a realm stage has a
	## stage-level fear effect. For MVP this is a simple additive change.
	##
	## - party_ids: Array of hero ids participating in the stage.
	## - fear_delta: added to current fear (can be positive or negative).
	## - ctx: context dictionary used for logging; expected keys include:
	##     "realm_id", "stage_index", "objective_type" (optional).
	##
	if fear_delta == 0:
		return

	var realm_label := str(ctx.get("realm_id", "unknown"))
	var stage_index := str(ctx.get("stage_index", ""))
	var objective := str(ctx.get("objective_type", ""))

	var label := "realm:%s" % realm_label
	if stage_index != "":
		label += ":stage_%s" % stage_index
	if objective != "":
		label += ":%s" % objective

	for id in party_ids:
		if typeof(id) != TYPE_INT:
			continue
		apply_delta(int(id), 0, fear_delta, label)


# ----------------------------------------
# Combat integration helper
# ----------------------------------------

func apply_combat_result(emo_block: Dictionary) -> void:
	##
	## Apply per-hero emotion deltas from a combat result payload.
	##
	## Expected shape:
	## emo_block = {
	##   "heroes": {
	##     hero_id: {
	##       "morale_delta": int,
	##       "fear_delta": int,
	##     },
	##     ...
	##   }
	## }
	##
	if emo_block.is_empty():
		return

	if not emo_block.has("heroes"):
		return

	var heroes_val = emo_block["heroes"]
	if typeof(heroes_val) != TYPE_DICTIONARY:
		return

	var heroes_dict: Dictionary = heroes_val

	for key in heroes_dict.keys():
		if typeof(key) != TYPE_INT:
			continue

		var hero_id: int = key
		var hero_payload_val = heroes_dict.get(hero_id, {})
		if typeof(hero_payload_val) != TYPE_DICTIONARY:
			continue

		var hero_payload: Dictionary = hero_payload_val

		var morale_delta: int = int(hero_payload.get("morale_delta", 0))
		var fear_delta: int = int(hero_payload.get("fear_delta", 0))

		if morale_delta == 0 and fear_delta == 0:
			continue

		# Label as combat so logs are easy to filter.
		apply_delta(hero_id, morale_delta, fear_delta, "combat")
