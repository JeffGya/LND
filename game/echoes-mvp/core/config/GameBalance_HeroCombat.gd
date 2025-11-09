extends Resource
class_name GameBalance_HeroCombat
## GameBalance_HeroCombat
## Central place for ALL combat-related balance numbers for MVP.
## Anything that influences hero birth stats or basic training enemies
## should live here, so EchoFactory.gd and EnemyFactory.gd don’t hardcode.
##
## Canon notes:
##  - Mirrors “Legacy Never Dies” §9 (Combat) and §12 (Balance Curves).
##  - MVP heroes should spawn fragile (≈20–30 HP, 10–15 ATK).
##  - Enemies used for training should NOT one-shot heroes.
##  - Midgame 100–200 HP is NOT defined here (that’s progression/rank later).

# ---------------------------------------------------------
# HERO BIRTH STATS (used by EchoFactory.gd)
# These are the numbers we just rebalanced in EchoFactory.
# Keep them here so we can tweak without opening EchoFactory again.
# hp = 5 + courage*0.25 + faith*0.15  (floor 15)
# atk = 4 + courage*0.12 + faith*0.05
# def = 2 + wisdom*0.12 + faith*0.08
# agi = 2 + wisdom*0.08 + courage*0.08
# cha = 1 + faith*0.08 + wisdom*0.08
# int = 4 + wisdom*0.22 + courage*0.04
# All of these should stay typed to avoid Variant warnings.
# ---------------------------------------------------------
const HERO_HP_BASE: int = 5
const HERO_HP_COURAGE_MUL: float = 0.25
const HERO_HP_FAITH_MUL: float = 0.15
const HERO_HP_MIN: int = 15

const HERO_ATK_BASE: int = 4
const HERO_ATK_COURAGE_MUL: float = 0.12
const HERO_ATK_FAITH_MUL: float = 0.05

const HERO_DEF_BASE: int = 2
const HERO_DEF_WIS_MUL: float = 0.12
const HERO_DEF_FAITH_MUL: float = 0.08

const HERO_AGI_BASE: int = 2
const HERO_AGI_WIS_MUL: float = 0.08
const HERO_AGI_COUR_MUL: float = 0.08

const HERO_CHA_BASE: int = 1
const HERO_CHA_FAITH_MUL: float = 0.08
const HERO_CHA_WIS_MUL: float = 0.08

const HERO_INT_BASE: int = 4
const HERO_INT_WIS_MUL: float = 0.22
const HERO_INT_COUR_MUL: float = 0.04

# ---------------------------------------------------------
# POST-MVP / RESERVED COMBAT FIELDS
# These exist in the hero stats dictionary but are 0 for MVP.
# We keep them here so we know where to scale them later.
# ---------------------------------------------------------
const HERO_ACC_BASE: int = 0
const HERO_EVA_BASE: int = 0
const HERO_CRIT_BASE: int = 0

# ---------------------------------------------------------
# TRAINING / DUMMY ENEMIES (used by EnemyFactory.gd)
# This matches what we just tested:
#  - HP 40
#  - ATK 8 (you bumped to 8)
#  - DEF 4
#  - AGI 5
# If we want to make training easier/harder, we ONLY change here.
# ---------------------------------------------------------
const TRAINING_HP: int = 40
const TRAINING_MAX_HP: int = 40
const TRAINING_ATK: int = 8
const TRAINING_DEF: int = 4
const TRAINING_AGI: int = 5
const TRAINING_MORALE: int = 50
const TRAINING_FEAR: int = 0

# ---------------------------------------------------------
# FALLBACKS FOR PARTIAL/LEGACY ACTORS
# ActionResolver and CombatEngine can run into actors that
# don't have full stats yet. These are the safe defaults.
# ---------------------------------------------------------
const FALLBACK_HP: int = 10
const FALLBACK_ATK: int = 3
const FALLBACK_DEF: int = 0
const FALLBACK_AGI: int = 5
const FALLBACK_MORALE: int = 50
const MIN_DAMAGE: int = 1
const GUARD_DAMAGE_MULT: float = 0.5


# ---------------------------------------------------------
# COMBAT RHYTHM (global)
# Step-based rounds we’ve been testing were 5–6 rounds.
# Putting it here makes it easier to sync with ActionResolver later.
# ---------------------------------------------------------
const COMBAT_ROUND_LIMIT: int = 6
const COMBAT_FEAR_PER_ROUND: int = 1
const COMBAT_BASE_MORALE: int = 50

# ---------------------------------------------------------
# COMBAT LOGGING (MVP)
# Source: Notion story “As the Keeper I want readable combat logs”
# Purpose: single-line combat entries, controlled by design.
# All combat loggers / formatters should read from here.
# ---------------------------------------------------------
const LOG_ENABLED: bool = true

# Which high-level combat actions should always produce a line.
# Keep these UPPERCASE to match verbs emitted by CombatEngine.
const LOG_ACTIONS: Array[String] = [
    "ATTACK",
    "GUARD",
    "REFUSE",
    "KO",
    "TICK"
]

# Visual/detail flags — used by core/combat/CombatLog.gd later.
# Toggle these during testing to drop/enable parts of the line.
const LOG_SHOW_HP: bool = true              # → [29/40]
const LOG_SHOW_DMG_BREAKDOWN: bool = true   # → [ATK 15 → DEF 4]
const LOG_SHOW_GUARD: bool = true           # → [guard=2]
const LOG_SHOW_INTERNAL: bool = false       # → PRNG, raw rolls, seed, etc (MVP: off)

# Controls the order of tags in the final line.
# Normalizer/formatter will map concrete tags to these buckets.
const LOG_TAG_ORDER: Array[String] = [
    "hp",           # [29/40], [KO]
    "guard",        # [guard=2]
    "dmg_breakdown",
    "other"
]

# ---------------------------------------------------------
# LOGGING VERBOSITY PROFILES (MVP+)
# Switch between player-friendly and QA-rich logs from config only.
# Code should prefer these resolved flags (profile + overrides) over
# the raw LOG_SHOW_* constants above. The older flags remain for
# backward compatibility during the transition.
# ---------------------------------------------------------
const LOGGING_PROFILES := {
    "mvp": {
        "show_hp": true,
        "show_guard": false,
        "show_dmg_breakdown": false,
        "show_internal": false,
    },
    "designer": {
        "show_hp": true,
        "show_guard": true,
        "show_dmg_breakdown": true,
        "show_internal": false,
    },
    "qa": {
        "show_hp": true,
        "show_guard": true,
        "show_dmg_breakdown": true,
        "show_internal": true,
    },
}

# Active profile — change this to switch global verbosity.
const LOG_PROFILE: String = "mvp"

# Optional per-flag overrides. If null, the active profile value is used.
const LOG_OVERRIDE_SHOW_HP: Variant = null
const LOG_OVERRIDE_SHOW_GUARD: Variant = null
const LOG_OVERRIDE_SHOW_DMG_BREAKDOWN: Variant = null
const LOG_OVERRIDE_SHOW_INTERNAL: Variant = null

# ---------------------------------------------------------
# FEAR → REFUSAL (MVP)
# Source: Notion userstory “As the Keeper I want fear to push refusal”
# Canon: Legacy Never Dies §9 (Combat) / Echo Behavior Matrix
# These values are the single source of truth for fear-driven refusal.
# Do NOT hardcode these numbers inside CombatEngine or ActionResolver.
# ---------------------------------------------------------
const FEAR_REFUSAL_THRESHOLD: int = 70  # at or above this, fear can override normal action
const FEAR_MAX: int = 100               # clamp fear so probability math stays sane
const FEAR_REFUSAL_BASE_CHANCE: float = 0.35  # 35% at threshold
const FEAR_REFUSAL_PER_10_OVER: float = 0.05  # +5% for every 10 fear over threshold
const FEAR_REFUSAL_ACTIONS: Array[String] = [
    "refuse",  # full skip, log it
    "guard"    # still helpful, defensive stance
    # "retreat"  # POST-MVP: use separate abandon/retreat trigger, not normal fear refusal
]

# Fear gain sources (MVP)
# These are used by CombatEngine to actually push units toward the refusal threshold.
# If these are too low, fear-based refusal will basically never trigger in short fights.
const FEAR_PER_HIT: int = 2        # when a unit is successfully hit
const FEAR_PER_ALLY_KO: int = 4    # when an ally goes down/KO
const FEAR_PER_FOCUS_HIT: int = 1  # extra when same unit is hit multiple times in one round