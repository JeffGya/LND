extends Resource
class_name RealmRewardCalc
## RealmRewardCalc
## Computes Ase/Ekwan (and future relic) rewards for Realm stages and completion.
##
## Canon anchors:
##  - §6 World / Realm Structure: realms as primary adventure loops.
##  - §8 Economy & Progression: Realms feed Ase/Ekwan, no hard stalls.
##  - §12 Balance Curves: tier scalars + base yields define pacing.
##
## Design:
##  - Pure logic, static helpers only (no state, no RNG side effects).
##  - Deterministic: given the same RealmModel/StageModel and config,
##    rewards are identical across runs.
##  - Application (actually granting Ase/Ekwan) is handled elsewhere
##    (e.g., EconomyService + RealmService).

# Chance for a stage to drop a relic in MVP (0.0–1.0).
# This is intentionally conservative; later we can move this into config.
const RELIC_STAGE_CHANCE: float = 0.25


static func stage_rewards(realm: RealmModel, stage: StageModel) -> Dictionary:
    ## Compute per-stage rewards for a cleared stage.
    ## Inputs:
    ##  - realm: RealmModel for context (tier, virtue, etc.).
    ##  - stage: StageModel that was just completed.
    ##
    ## Output shape (MVP):
    ##  {
    ##    "ase": int,
    ##    "ekwan": int,
    ##    "relic_roll": {
    ##        "awarded": bool,
    ##        "rarity": String, # "" if none
    ##    },
    ##  }
    ##
    ## NOTE: This function only computes values; it does NOT mutate
    ## any global state or services.
    var base: Dictionary = GameBalance_Realm.get_reward_base()
    var scalars: Dictionary = GameBalance_Realm.get_tier_scalars(realm.tier)

    var base_ase: int = int(base.get("ase", 0))
    var base_ekwan: int = int(base.get("ekwan", 0))

    var ase_mul: float = float(scalars.get("ase_reward_mul", 1.0))
    var ekwan_mul: float = float(scalars.get("ekwan_drop_mul", 1.0))

    # Tier-scaled rewards.
    var ase: int = int(round(base_ase * ase_mul))
    var ekwan: int = int(round(base_ekwan * ekwan_mul))

    # Objective-specific tilt (very gentle to avoid breaking pacing).
    match stage.objective_type:
        "combat_trial":
            # Combat trials lean slightly Ase-heavy.
            ase = int(round(ase * 1.1))
        "purify_shrine":
            # Shrine purification gives a small Ekwan tilt (offerings, relic dust).
            ekwan = int(round(ekwan * 1.1))
        _:
            pass

    # Shrine-specific reward multiplier: shrine stages are slightly more
    # rewarding than standard combat at the same tier, using config-driven
    # knobs rather than hard-coded constants.
    if stage.objective_type == "purify_shrine":
        var shrine_mult: float = 1.0
        # Prefer a stage-level override when present so RealmGenerator can
        # bake the chosen multiplier into modifiers for debugging/inspection.
        if stage.modifiers.has("shrine_reward_multiplier"):
            shrine_mult = float(stage.modifiers.get("shrine_reward_multiplier", 1.0))
        else:
            # Fallback to tier-based config helper in GameBalance_Realm.
            shrine_mult = GameBalance_Realm.get_purify_reward_mult(realm.tier)
        if shrine_mult != 1.0:
            ase = int(round(ase * shrine_mult))
            ekwan = int(round(ekwan * shrine_mult))

    # Optional stage-level modifier hook (e.g., "reward_bonus": 0.1).
    if stage.modifiers.has("reward_bonus"):
        var bonus: float = float(stage.modifiers.get("reward_bonus", 0.0))
        if bonus != 0.0:
            ase = int(round(ase * (1.0 + bonus)))
            ekwan = int(round(ekwan * (1.0 + bonus)))

    # Enforce "no hard stalls": a cleared stage should not yield negative
    # returns. We keep at least 1 Ase for a successful clear.
    if ase < 1:
        ase = 1
    if ekwan < 0:
        ekwan = 0

    var relic_roll: Dictionary = _roll_relic(base, realm, stage)

    return {
        "ase": ase,
        "ekwan": ekwan,
        "relic_roll": relic_roll,
    }


static func completion_rewards(realm: RealmModel) -> Dictionary:
    ## Compute a small completion bonus when the entire realm is cleared.
    ##
    ## Design intent:
    ##  - Reward scales with tier and number of stages.
    ##  - Acts as a light "realm clear" bonus on top of per-stage rewards.
    ##  - Never negative; zero is allowed but unlikely with current config.
    var base: Dictionary = GameBalance_Realm.get_reward_base()
    var scalars: Dictionary = GameBalance_Realm.get_tier_scalars(realm.tier)

    var base_ase: int = int(base.get("ase", 0))
    var base_ekwan: int = int(base.get("ekwan", 0))

    var ase_mul: float = float(scalars.get("ase_reward_mul", 1.0))
    var ekwan_mul: float = float(scalars.get("ekwan_drop_mul", 1.0))

    var stage_count: int = max(1, realm.get_stage_count())

    # Completion bonus: roughly half a stage of Ase per stage, and a
    # quarter-stage of Ekwan per stage, scaled by tier.
    var ase_bonus: int = int(round(base_ase * ase_mul * 0.5 * stage_count))
    var ekwan_bonus: int = int(round(base_ekwan * ekwan_mul * 0.25 * stage_count))

    if ase_bonus < 0:
        ase_bonus = 0
    if ekwan_bonus < 0:
        ekwan_bonus = 0

    return {
        "ase": ase_bonus,
        "ekwan": ekwan_bonus,
    }


static func _roll_relic(base: Dictionary, realm: RealmModel, stage: StageModel) -> Dictionary:
    ## MVP relic roll:
    ##  - Uses stage.encounter_seed (mixed with realm.seed) to remain deterministic.
    ##  - Has a simple global chance (RELIC_STAGE_CHANCE) to award any relic.
    ##  - If awarded, uses REWARD_BASE["relic_weights"] to pick rarity.
    ##
    ## Output:
    ##  {
    ##    "awarded": bool,
    ##    "rarity": String, # "common"/"rare"/... or "" if none
    ##  }
    var relic_weights = base.get("relic_weights", {})
    if typeof(relic_weights) != TYPE_DICTIONARY or (relic_weights as Dictionary).is_empty():
        return {
            "awarded": false,
            "rarity": "",
        }

    var weights: Dictionary = relic_weights

    # Deterministic RNG: mix realm.seed and stage.encounter_seed.
    var seed_value: int = (realm.seed + stage.encounter_seed) & 0x7fffffff
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value

    if rng.randf() >= RELIC_STAGE_CHANCE:
        return {
            "awarded": false,
            "rarity": "",
        }

    # Weighted rarity selection.
    var keys: Array = weights.keys()
    keys.sort() # stable order

    var total: int = 0
    for key in keys:
        var w: int = int(weights.get(key, 0))
        if w > 0:
            total += w

    if total <= 0:
        return {
            "awarded": false,
            "rarity": "",
        }

    var roll: int = rng.randi_range(1, total)
    var cumulative: int = 0
    var chosen_rarity: String = ""

    for key in keys:
        var value: int = int(weights.get(key, 0))
        if value <= 0:
            continue
        cumulative += value
        if roll <= cumulative:
            chosen_rarity = String(key)
            break

    if chosen_rarity == "":
        # Fallback, though the loop above should always pick something.
        chosen_rarity = String(keys.back())

    return {
        "awarded": true,
        "rarity": chosen_rarity,
    }
