extends Node
class_name DemoSimHarness

const DEFAULT_CAMPAIGN_SEED := "0xA2B94D10"
const LOOT_TABLE := [
    "moon_glass",
    "sun_flower",
    "obsidian_shard",
    "ember_coal",
    "whisper_thread",
]
const ENEMY_PACKS := [
    "scavenger",
    "phantom",
    "wraith",
    "sentinel",
    "mimic",
]
const SCENARIO := [
    {"realm_id": "vale_of_dust", "stage": 1, "encounter": 0},
    {"realm_id": "vale_of_dust", "stage": 1, "encounter": 1},
    {"realm_id": "sundered_archive", "stage": 2, "encounter": 0},
]

var seed_service: SeedService
var _cached_snapshot: Dictionary = {}

func _init() -> void:
    seed_service = SeedService

func get_seed_service() -> SeedService:
    return _get_service()

func has_cached_snapshot() -> bool:
    return !_cached_snapshot.is_empty()

func run_once(campaign_seed: String = DEFAULT_CAMPAIGN_SEED, run_index: int = 1, reset: bool = true) -> String:
    var service := _get_service()
    if reset:
        service.init_campaign(campaign_seed)
    var lines: Array[String] = []
    lines.append("RUN %d" % run_index)
    for entry in SCENARIO:
        var realm_id: String = entry["realm_id"]
        var stage_index: int = entry["stage"]
        var encounter_index: int = entry["encounter"]

        var loot_rng := service.prng_for_loot(realm_id, stage_index, encounter_index)
        var loot_rolls: Array[String] = []
        for i in range(10):
            var loot_value := LOOT_TABLE[loot_rng.next_u32() % LOOT_TABLE.size()]
            loot_rolls.append(String(loot_value))

        var combat_rng := service.prng_for_combat(realm_id, stage_index, encounter_index, "initiative")
        var init_rolls: Array[String] = []
        for i in range(10):
            init_rolls.append("%.6f" % combat_rng.next_float())

        var encounter_rng := service.prng_for_encounter(realm_id, stage_index, encounter_index)
        var pack_rolls: Array[String] = []
        for i in range(10):
            var pack := ENEMY_PACKS[encounter_rng.next_u32() % ENEMY_PACKS.size()]
            pack_rolls.append(String(pack))

        var line := "realm=%s stage=%d enc=%d | loot=[%s] | init=[%s] | packs=[%s]" % [
            realm_id,
            stage_index,
            encounter_index,
            ", ".join(loot_rolls),
            ", ".join(init_rolls),
            ", ".join(pack_rolls),
        ]
        lines.append(line)
    return "\n".join(lines)

func snapshot_and_store() -> Dictionary:
    _cached_snapshot = _get_service().snapshot_state()
    return _cached_snapshot

func restore_cached_snapshot() -> void:
    if _cached_snapshot.is_empty():
        return
    _get_service().restore_state(_cached_snapshot)

func _get_service() -> SeedService:
    if seed_service == null:
        seed_service = SeedService
    return seed_service
