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

# ------------------
# Gender (metadata only)
# ------------------
# Purely descriptive for naming/UX; no effect on stats or emotions.
const GENDER_FEMALE: String = "female"
const GENDER_MALE:   String = "male"
const GENDER_POOL := [GENDER_FEMALE, GENDER_MALE]

# ---------------------------
# Optional class rarity/weight
# ---------------------------
# Used later when classes begin to emerge; MVP may ignore these.

const CLASS_WEIGHTS := {
    CLASS_GUARDIAN: 0.8,
    CLASS_WARRIOR:  1.0,
    CLASS_ARCHER:   0.9
}

# ------------------
# Personality Archetypes (MVP)
# ------------------
# Canon §5 Heroes / Echoes of Personality
# These archetypes color dialogue and behavior; they do not affect stats or balance.
# Deterministic assignment based on {Courage, Wisdom, Faith}.
# Each archetype represents a behavioral or emotional tendency — not good/evil polarity.

const ARCHETYPE_LOYAL: String      = "loyal"      # Steadfast, team-first, trusts the Keeper; morale stable.
const ARCHETYPE_PROUD: String      = "proud"      # Bold, self-driven, hates appearing weak; morale swings high.
const ARCHETYPE_REFLECTIVE: String = "reflective" # Thoughtful yet hesitant; seeks reassurance and understanding.
const ARCHETYPE_VALIANT: String    = "valiant"    # Courageous and idealistic; charges ahead for a cause.
const ARCHETYPE_CANNY: String      = "canny"      # Clever and pragmatic; prefers strategy over emotion.
const ARCHETYPE_DEVOUT: String     = "devout"     # Faith-anchored and calm; unshaken by fear or corruption.
const ARCHETYPE_STOIC: String      = "stoic"      # Reserved and composed; steady under pressure.
const ARCHETYPE_EMPATHIC: String   = "empathic"   # Compassionate; senses allies’ moods and responds softly.
const ARCHETYPE_AMBITIOUS: String  = "ambitious"  # Driven, goal-focused; seeks leadership and progress.

# Canonical ordered list of archetypes for iteration / random access
const ARCHETYPES := [
    ARCHETYPE_LOYAL,
    ARCHETYPE_PROUD,
    ARCHETYPE_REFLECTIVE,
    ARCHETYPE_VALIANT,
    ARCHETYPE_CANNY,
    ARCHETYPE_DEVOUT,
    ARCHETYPE_STOIC,
    ARCHETYPE_EMPATHIC,
    ARCHETYPE_AMBITIOUS
]

# Human-readable metadata for UI / logs / tests
const ARCHETYPE_META := {
    ARCHETYPE_LOYAL:      {"display_name": "Loyal",      "blurb": "Steadfast and trusting; morale steady under adversity."},
    ARCHETYPE_PROUD:      {"display_name": "Proud",      "blurb": "Confident and bold; morale rises or falls sharply."},
    ARCHETYPE_REFLECTIVE: {"display_name": "Reflective", "blurb": "Thoughtful, cautious under pressure; seeks reassurance before acting."},
    ARCHETYPE_VALIANT:    {"display_name": "Valiant",    "blurb": "Courageous and idealistic; leads the charge with heart."},
    ARCHETYPE_CANNY:      {"display_name": "Canny",      "blurb": "Strategic and clever; values advantage and timing."},
    ARCHETYPE_DEVOUT:     {"display_name": "Devout",     "blurb": "Faith-centered; calm and confident against fear."},
    ARCHETYPE_STOIC:      {"display_name": "Stoic",      "blurb": "Unflappable; quiet strength and composure."},
    ARCHETYPE_EMPATHIC:   {"display_name": "Empathic",   "blurb": "Emotionally attuned; responds to allies’ states."},
    ARCHETYPE_AMBITIOUS:  {"display_name": "Ambitious",  "blurb": "Goal-oriented and assertive; seeks growth and recognition."}
}