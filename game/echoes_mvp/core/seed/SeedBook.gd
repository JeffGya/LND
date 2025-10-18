extends RefCounted
class_name SeedBook

var campaign_seed: String = ""
var subseeds := {
    "realm": {},
    "stage": {},
    "encounter": {},
    "combat": {},
    "loot": {},
}
var cursors := {
    "combat": {},
    "loot": {},
}

static func _hash_payload(payload: String) -> int:
    return XXHash64.xxh64_string(payload, 0)

static func derive_realm_seed(campaign: String, realm_id: String) -> int:
    return _hash_payload("%s|%s" % [campaign, realm_id])

static func derive_stage_seed(realm_seed: int, stage_index: int) -> int:
    return _hash_payload("%s|stage:%d" % [str(realm_seed), stage_index])

static func derive_encounter_seed(stage_seed: int, encounter_index: int) -> int:
    return _hash_payload("%s|enc:%d" % [str(stage_seed), encounter_index])

static func derive_combat_seed(enc_seed: int, tick_key: String) -> int:
    return _hash_payload("%s|combat:%s" % [str(enc_seed), tick_key])

static func derive_loot_seed(enc_seed: int) -> int:
    return _hash_payload("%s|loot" % [str(enc_seed)])

func clone() -> SeedBook:
    var copy := SeedBook.new()
    copy.campaign_seed = campaign_seed
    copy.subseeds = {
        "realm": _deep_copy(subseeds["realm"]),
        "stage": _deep_copy(subseeds["stage"]),
        "encounter": _deep_copy(subseeds["encounter"]),
        "combat": _deep_copy(subseeds["combat"]),
        "loot": _deep_copy(subseeds["loot"]),
    }
    copy.cursors = {
        "combat": _deep_copy(cursors["combat"]),
        "loot": _deep_copy(cursors["loot"]),
    }
    return copy

static func _deep_copy(value):
    if typeof(value) == TYPE_DICTIONARY:
        var result := {}
        for key in value.keys():
            result[key] = _deep_copy(value[key])
        return result
    elif typeof(value) == TYPE_ARRAY:
        var arr: Array = []
        for element in value:
            arr.append(_deep_copy(element))
        return arr
    else:
        return value
