extends Resource
class_name GameBalance_Realm
## GameBalance_Realm
## Realm-level balance settings: difficulty tiers, encounter pacing,
## and realm emotion/virtue multipliers derived from the canon (§6 World / Realm Structure).
## This file does NOT define combat stats directly — it multiplies the hero/enemy
## baselines from GameBalance_HeroCombat.gd for realm contexts.
##
## MVP intent:
##  - Training fights stay in HeroCombat.
##  - Realms (when generated) read from here to scale HP/ATK/AGI per tier.
##  - Emotion-themed realms (Courage, Faith, Harmony) can buff/debuff.

# ---------------------------------------------------------
# ENCOUNTER PACING (per realm run)
# MVP realms should be short: 2–5 encounters.
# ---------------------------------------------------------
const REALM_MIN_ENCOUNTERS: int = 2
const REALM_MAX_ENCOUNTERS: int = 5
const REALM_DEFAULT_ENCOUNTERS: int = 3

# ---------------------------------------------------------
# DIFFICULTY TIERS (multipliers)
# These are multipliers applied on top of hero/enemy baselines.
# Example: tier 2 enemy HP = base_hp * TIER2_HP_MUL
# ---------------------------------------------------------
const TIER1_HP_MUL: float = 1.0
const TIER1_ATK_MUL: float = 1.0
const TIER1_AGI_MUL: float = 1.0

const TIER2_HP_MUL: float = 1.25
const TIER2_ATK_MUL: float = 1.15
const TIER2_AGI_MUL: float = 1.05

const TIER3_HP_MUL: float = 1.5
const TIER3_ATK_MUL: float = 1.3
const TIER3_AGI_MUL: float = 1.1

# ---------------------------------------------------------
# REALM LOOKUP HELPERS (MVP)
# These are tiny helpers so other systems don’t have to remember the
# exact constant names. CombatEngine / future RealmFactory can just call
# get_enemy_multipliers_for_tier(1) and get back a small dict.
# ---------------------------------------------------------
static func get_enemy_multipliers_for_tier(tier: int) -> Dictionary:
    var hp_mul: float = 1.0
    var atk_mul: float = 1.0
    var agi_mul: float = 1.0
    match tier:
        1:
            hp_mul = TIER1_HP_MUL
            atk_mul = TIER1_ATK_MUL
            agi_mul = TIER1_AGI_MUL
        2:
            hp_mul = TIER2_HP_MUL
            atk_mul = TIER2_ATK_MUL
            agi_mul = TIER2_AGI_MUL
        3:
            hp_mul = TIER3_HP_MUL
            atk_mul = TIER3_ATK_MUL
            agi_mul = TIER3_AGI_MUL
        _:
            # default to tier 1 for unknown tiers (MVP safety)
            hp_mul = TIER1_HP_MUL
            atk_mul = TIER1_ATK_MUL
            agi_mul = TIER1_AGI_MUL
    return {
        "hp_mul": hp_mul,
        "atk_mul": atk_mul,
        "agi_mul": agi_mul,
    }

static func get_encounter_pacing() -> Dictionary:
    return {
        "min": REALM_MIN_ENCOUNTERS,
        "max": REALM_MAX_ENCOUNTERS,
        "default": REALM_DEFAULT_ENCOUNTERS,
    }

# ---------------------------------------------------------
# EMOTION / VIRTUE REALM THEMES (canon §6B)
# Realms themed around a virtue get small bumps.
# These are intentionally small so they don't break the base pacing.
# ---------------------------------------------------------
const REALM_OF_COURAGE_ATK_MUL: float = 1.1
const REALM_OF_WISDOM_DEF_MUL: float = 1.1
const REALM_OF_FAITH_HP_MUL: float = 1.1
const REALM_OF_HARMONY_MORALE_MUL: float = 1.1

# ---------------------------------------------------------
# LOOT / REWARD SCAFFOLD (placeholder)
# We don't hook this up yet, but when realms drop extra Ase/Ekwan/Relics
# this is where we scale it per realm tier.
# ---------------------------------------------------------
const REWARD_ASE_MUL_TIER1: float = 1.0
const REWARD_ASE_MUL_TIER2: float = 1.25
const REWARD_ASE_MUL_TIER3: float = 1.5