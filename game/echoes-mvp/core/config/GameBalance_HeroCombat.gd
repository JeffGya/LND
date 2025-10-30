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