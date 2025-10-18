extends Node
class_name SeedService

var _campaign_seed: String = ""
var _book: SeedBook = SeedBook.new()

var _realm_rngs: Dictionary = {}
var _stage_rngs: Dictionary = {}
var _encounter_rngs: Dictionary = {}
var _combat_rngs: Dictionary = {}
var _loot_rngs: Dictionary = {}

func init_campaign(hex_seed: String) -> void:
    _campaign_seed = hex_seed
    _book = SeedBook.new()
    _book.campaign_seed = hex_seed
    _realm_rngs.clear()
    _stage_rngs.clear()
    _encounter_rngs.clear()
    _combat_rngs.clear()
    _loot_rngs.clear()

func prng_for_realm(realm_id: String) -> PCG32:
    if _realm_rngs.has(realm_id):
        return _realm_rngs[realm_id]
    var seed: int = _ensure_realm_seed(realm_id)
    var rng := PCG32.new_with_seed(seed)
    _realm_rngs[realm_id] = rng
    return rng

func prng_for_stage(realm_id: String, stage_index: int) -> PCG32:
    var stage_map := _ensure_stage_container(realm_id)
    if stage_map.has(stage_index):
        return stage_map[stage_index]
    var seed: int = _ensure_stage_seed(realm_id, stage_index)
    var rng := PCG32.new_with_seed(seed)
    stage_map[stage_index] = rng
    return rng

func prng_for_encounter(realm_id: String, stage_index: int, encounter_index: int) -> PCG32:
    var encounter_map := _ensure_encounter_container(realm_id, stage_index)
    if encounter_map.has(encounter_index):
        return encounter_map[encounter_index]
    var seed: int = _ensure_encounter_seed(realm_id, stage_index, encounter_index)
    var rng := PCG32.new_with_seed(seed)
    encounter_map[encounter_index] = rng
    return rng

func prng_for_combat(realm_id: String, stage_index: int, encounter_index: int, tick_key: String) -> PCG32:
    var combat_map := _ensure_combat_container(realm_id, stage_index, encounter_index)
    if combat_map.has(tick_key):
        return combat_map[tick_key]
    var seed: int = _ensure_combat_seed(realm_id, stage_index, encounter_index, tick_key)
    var rng := PCG32.new_with_seed(seed)
    combat_map[tick_key] = rng
    return rng

func prng_for_loot(realm_id: String, stage_index: int, encounter_index: int) -> PCG32:
    var loot_map := _ensure_loot_container(realm_id, stage_index)
    if loot_map.has(encounter_index):
        return loot_map[encounter_index]
    var seed: int = _ensure_loot_seed(realm_id, stage_index, encounter_index)
    var rng := PCG32.new_with_seed(seed)
    loot_map[encounter_index] = rng
    return rng

func snapshot_state() -> Dictionary:
    _book.cursors["combat"] = _collect_prng_states(_combat_rngs)
    _book.cursors["loot"] = _collect_prng_states(_loot_rngs)
    return {
        "campaign_seed": _campaign_seed,
        "book": {
            "campaign_seed": _book.campaign_seed,
            "subseeds": SeedBook._deep_copy(_book.subseeds),
            "cursors": SeedBook._deep_copy(_book.cursors),
        },
        "prng_states": {
            "realm": _collect_prng_states(_realm_rngs),
            "stage": _collect_prng_states(_stage_rngs),
            "encounter": _collect_prng_states(_encounter_rngs),
            "combat": _collect_prng_states(_combat_rngs),
            "loot": _collect_prng_states(_loot_rngs),
        },
    }

func restore_state(snapshot: Dictionary) -> void:
    var campaign := String(snapshot.get("campaign_seed", _campaign_seed))
    init_campaign(campaign)
    var book_data: Dictionary = snapshot.get("book", {})
    _book.campaign_seed = String(book_data.get("campaign_seed", campaign))
    _book.subseeds = SeedBook._deep_copy(book_data.get("subseeds", _book.subseeds))
    _book.cursors = SeedBook._deep_copy(book_data.get("cursors", _book.cursors))

    var prng_states: Dictionary = snapshot.get("prng_states", {})
    _realm_rngs = _rebuild_prng_tree(prng_states.get("realm", {}))
    _stage_rngs = _rebuild_prng_tree(prng_states.get("stage", {}))
    _encounter_rngs = _rebuild_prng_tree(prng_states.get("encounter", {}))
    _combat_rngs = _rebuild_prng_tree(prng_states.get("combat", {}))
    _loot_rngs = _rebuild_prng_tree(prng_states.get("loot", {}))

func _ensure_realm_seed(realm_id: String) -> int:
    var realm_map: Dictionary = _book.subseeds["realm"]
    if realm_map.has(realm_id):
        return int(realm_map[realm_id])
    var seed := SeedBook.derive_realm_seed(_campaign_seed, realm_id)
    realm_map[realm_id] = seed
    return seed

func _ensure_stage_seed(realm_id: String, stage_index: int) -> int:
    var stage_map := _ensure_nested(_book.subseeds["stage"], realm_id)
    if stage_map.has(stage_index):
        return int(stage_map[stage_index])
    var realm_seed := _ensure_realm_seed(realm_id)
    var seed := SeedBook.derive_stage_seed(realm_seed, stage_index)
    stage_map[stage_index] = seed
    return seed

func _ensure_encounter_seed(realm_id: String, stage_index: int, encounter_index: int) -> int:
    var encounter_realm := _ensure_nested(_book.subseeds["encounter"], realm_id)
    var encounter_stage := _ensure_nested(encounter_realm, stage_index)
    if encounter_stage.has(encounter_index):
        return int(encounter_stage[encounter_index])
    var stage_seed := _ensure_stage_seed(realm_id, stage_index)
    var seed := SeedBook.derive_encounter_seed(stage_seed, encounter_index)
    encounter_stage[encounter_index] = seed
    return seed

func _ensure_combat_seed(realm_id: String, stage_index: int, encounter_index: int, tick_key: String) -> int:
    var combat_realm := _ensure_nested(_book.subseeds["combat"], realm_id)
    var combat_stage := _ensure_nested(combat_realm, stage_index)
    var combat_encounter := _ensure_nested(combat_stage, encounter_index)
    if combat_encounter.has(tick_key):
        return int(combat_encounter[tick_key])
    var enc_seed := _ensure_encounter_seed(realm_id, stage_index, encounter_index)
    var seed := SeedBook.derive_combat_seed(enc_seed, tick_key)
    combat_encounter[tick_key] = seed
    return seed

func _ensure_loot_seed(realm_id: String, stage_index: int, encounter_index: int) -> int:
    var loot_realm := _ensure_nested(_book.subseeds["loot"], realm_id)
    var loot_stage := _ensure_nested(loot_realm, stage_index)
    if loot_stage.has(encounter_index):
        return int(loot_stage[encounter_index])
    var enc_seed := _ensure_encounter_seed(realm_id, stage_index, encounter_index)
    var seed := SeedBook.derive_loot_seed(enc_seed)
    loot_stage[encounter_index] = seed
    return seed

func _ensure_stage_container(realm_id: String) -> Dictionary:
    return _ensure_nested(_stage_rngs, realm_id)

func _ensure_encounter_container(realm_id: String, stage_index: int) -> Dictionary:
    var realm_map := _ensure_nested(_encounter_rngs, realm_id)
    return _ensure_nested(realm_map, stage_index)

func _ensure_combat_container(realm_id: String, stage_index: int, encounter_index: int) -> Dictionary:
    var realm_map := _ensure_nested(_combat_rngs, realm_id)
    var stage_map := _ensure_nested(realm_map, stage_index)
    return _ensure_nested(stage_map, encounter_index)

func _ensure_loot_container(realm_id: String, stage_index: int) -> Dictionary:
    var realm_map := _ensure_nested(_loot_rngs, realm_id)
    return _ensure_nested(realm_map, stage_index)


func get_seed_book() -> SeedBook:
    return _book

static func _ensure_nested(container: Dictionary, key) -> Dictionary:
    if !container.has(key):
        container[key] = {}
    return container[key]

static func _collect_prng_states(source: Dictionary) -> Dictionary:
    var result := {}
    for key in source.keys():
        var value = source[key]
        if value is PCG32:
            result[key] = value.get_state()
        elif typeof(value) == TYPE_DICTIONARY:
            result[key] = _collect_prng_states(value)
    return result

static func _rebuild_prng_tree(states: Dictionary) -> Dictionary:
    var result := {}
    for key in states.keys():
        var value = states[key]
        if typeof(value) == TYPE_DICTIONARY and value.has("state"):
            var rng := PCG32.new()
            rng.set_state(value)
            result[key] = rng
        elif typeof(value) == TYPE_DICTIONARY:
            result[key] = _rebuild_prng_tree(value)
    return result
