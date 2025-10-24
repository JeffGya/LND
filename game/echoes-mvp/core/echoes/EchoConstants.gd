

# EchoConstants.gd
# Canon-aligned constants for Echo classes & traits (MVP scope).
# This file is a single source of truth imported by the EchoFactory, services, UI, and tests.
#
# Lore-aligned physical trio for MVP:
#   - Eban Warder  (Guardian / Tank)   -> code: "guardian"
#   - Akofena Blade (Warrior / Fighter) -> code: "warrior"
#   - Fawohodie Ranger (Archer / Ranged DPS) -> code: "archer"
# Keep "none" for Rank 1 (Uncalled). Classes emerge later through gameplay.
#
# Canon refs:
#   §5 Heroes / Echoes of Personality — virtues & emotional alignment
#   §8 Economy & Progression — summon consumes Ase (price lives in EconomyConstants)
#   §12 Balance Curves — deterministic pacing & tunables

class_name EchoConstants

# -----------------------------
# Class codes (stable storage)
# -----------------------------
const CLASS_NONE: String     = "none"
const CLASS_GUARDIAN: String = "guardian"  # Eban Warder (Tank)
const CLASS_WARRIOR: String  = "warrior"   # Akofena Blade (Fighter)
const CLASS_ARCHER: String   = "archer"    # Fawohodie Ranger (Ranged DPS)

# --------------------------------------
# Lightweight metadata for lookups / UI
# --------------------------------------
const CLASS_INFO := {
    CLASS_NONE: {
        "name": "None",
        "title": "Uncalled",
        "role": "Unassigned",
        "virtue": []
    },
    CLASS_GUARDIAN: {
        "name": "Eban Warder",
        "role": "Guardian / Tank",
        "virtue": ["faith", "harmony"]
    },
    CLASS_WARRIOR: {
        "name": "Akofena Blade",
        "role": "Warrior / Fighter",
        "virtue": ["courage", "legacy"]
    },
    CLASS_ARCHER: {
        "name": "Fawohodie Ranger",
        "role": "Archer / Ranged DPS",
        "virtue": ["wisdom", "freedom"]
    }
}

# ------------------
# MVP trait key set
# ------------------
# Subset of the full six-trait model; keep keys stable for save schema & tests.
const TRAIT_COURAGE: String = "courage"
const TRAIT_WISDOM:  String = "wisdom"
const TRAIT_FAITH:   String = "faith"

# Trait roll bounds used by the summon factory for MVP.
# Tunable later via balance curves; documented here for quick reference.
const TRAIT_ROLL_MIN: int = 30
const TRAIT_ROLL_MAX: int = 70

# ---------------------------
# Optional class rarity/weight
# ---------------------------
# Used later when classes begin to emerge; MVP may ignore these.
const CLASS_WEIGHTS := {
    CLASS_GUARDIAN: 1.0,
    CLASS_WARRIOR:  1.0,
    CLASS_ARCHER:   1.0
}