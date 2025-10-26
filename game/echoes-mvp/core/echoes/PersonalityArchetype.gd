extends RefCounted
class_name PersonalityArchetype

# PersonalityArchetype.gd
# ------------------------
# MVP deterministic mapping from {Courage, Wisdom, Faith} to a single personality archetype.
# Canon: "Guidance > Control" — this colors dialogue/behavior only (no stat changes at MVP).
# Deterministic fairness: no RNG; same inputs always yield the same archetype.

# We preload EchoConstants to reference the canonized archetype strings in one place.
const EchoConstants = preload("res://core/echoes/EchoConstants.gd")

# --- Tunable knobs (safe to adjust during balancing) ---
# A trait must exceed the mean of (C,W,F) by at least this amount AND be a unique max to count as "dominant".
const DOMINANCE_THRESHOLD: float = 8.0
# Banding edge for HIGH / MID / LOW classification around the mean (used when no dominance).
const BAND_EDGE: float = 5.0

# Public API
# Returns one of EchoConstants.ARCHETYPE_* strings
static func pick_archetype(c: int, w: int, f: int) -> String:
    # 1) Relative deltas vs mean capture which trait "sticks out" regardless of absolute scale.
    var mean := (c + w + f) / 3.0
    var dc := float(c) - mean
    var dw := float(w) - mean
    var df := float(f) - mean

    # 2) Dominance pass — if one trait is uniquely and clearly highest, pick a direct mapping.
    var max_delta := dc
    var max_key := "c"
    if dw > max_delta:
        max_delta = dw
        max_key = "w"
    if df > max_delta:
        max_delta = df
        max_key = "f"

    # Uniqueness: ensure there isn't a tie at the maximum.
    var max_count := 0
    for d in [dc, dw, df]:
        if abs(d - max_delta) < 0.0001:
            max_count += 1
    var is_unique_max := max_count == 1

    if is_unique_max and max_delta >= DOMINANCE_THRESHOLD:
        match max_key:
            "c":
                # Courage-dominant → Valiant
                return EchoConstants.ARCHETYPE_VALIANT
            "w":
                # Wisdom-dominant → Canny
                return EchoConstants.ARCHETYPE_CANNY
            "f":
                # Faith-dominant → Devout
                return EchoConstants.ARCHETYPE_DEVOUT

    # 3) Midline / tie rules — classify each delta into bands: HIGH (1), MID (0), LOW (-1)
    var bc := _band(dc)
    var bw := _band(dw)
    var bf := _band(df)

    # Ordered, deterministic rules (first match wins):
    # A) High Courage + High Faith → Loyal (steadfast, team-first)
    if bc == 1 and bf == 1:
        return EchoConstants.ARCHETYPE_LOYAL

    # B) High Courage + Low Faith → Proud (projecting strength, brittle under doubt)
    if bc == 1 and bf == -1:
        return EchoConstants.ARCHETYPE_PROUD

    # C) Low Courage + High Wisdom → Stoic (calm, steady)
    if bc == -1 and bw == 1:
        return EchoConstants.ARCHETYPE_STOIC

    # D) High Faith (with Wisdom at least Mid) → Empathic (attuned to others)
    if bf == 1 and bw >= 0:
        return EchoConstants.ARCHETYPE_EMPATHIC

    # E) High Wisdom + Courage Mid (balanced) → Ambitious (forward-leaning, strategic)
    if bw == 1 and bc == 0:
        return EchoConstants.ARCHETYPE_AMBITIOUS

    # E2) High Courage + High Wisdom + Faith Mid → Ambitious (lead-forward, strategic)
    if bc == 1 and bw == 1 and bf == 0:
        return EchoConstants.ARCHETYPE_AMBITIOUS

    # F) Fallback for ties/uncertain spreads → Reflective (hesitant under pressure; asks questions)
    return EchoConstants.ARCHETYPE_REFLECTIVE

# Helper: band a delta into LOW (-1), MID (0), HIGH (1)
static func _band(delta: float) -> int:
    if delta >= BAND_EDGE:
        return 1
    if delta <= -BAND_EDGE:
        return -1
    return 0

# ---------------------------------------------------
# Behavior & Dialogue Hooks (MVP non-invasive helpers)
# ---------------------------------------------------
# These helpers do not modify any stats or logic. They serve as stable lookup
# tables for future AI and dialogue systems to interpret personality flavor.
# They can safely be used anywhere in the codebase without creating dependencies.

# Returns a light-touch combat attitude tag for AI bias hints.
static func combat_bias(arch: String) -> String:
    match arch:
        EchoConstants.ARCHETYPE_LOYAL:
            return "steadfast"
        EchoConstants.ARCHETYPE_PROUD:
            return "aggressive"
        EchoConstants.ARCHETYPE_REFLECTIVE:
            return "cautious"
        EchoConstants.ARCHETYPE_VALIANT:
            return "aggressive"
        EchoConstants.ARCHETYPE_CANNY:
            return "balanced"
        EchoConstants.ARCHETYPE_DEVOUT:
            return "steadfast"
        EchoConstants.ARCHETYPE_STOIC:
            return "steadfast"
        EchoConstants.ARCHETYPE_EMPATHIC:
            return "supportive"
        EchoConstants.ARCHETYPE_AMBITIOUS:
            return "balanced"
        _:
            # Fallback for unknown keys
            return "balanced"

# Returns a stable dialogue voice key (e.g., for selecting tone variants).
static func dialogue_key(arch: String) -> String:
    match arch:
        EchoConstants.ARCHETYPE_LOYAL:
            return "voice_loyal"
        EchoConstants.ARCHETYPE_PROUD:
            return "voice_proud"
        EchoConstants.ARCHETYPE_REFLECTIVE:
            return "voice_reflective"
        EchoConstants.ARCHETYPE_VALIANT:
            return "voice_valiant"
        EchoConstants.ARCHETYPE_CANNY:
            return "voice_canny"
        EchoConstants.ARCHETYPE_DEVOUT:
            return "voice_devout"
        EchoConstants.ARCHETYPE_STOIC:
            return "voice_stoic"
        EchoConstants.ARCHETYPE_EMPATHIC:
            return "voice_empathic"
        EchoConstants.ARCHETYPE_AMBITIOUS:
            return "voice_ambitious"
        _:
            # Neutral fallback for unknown archetypes
            return "voice_neutral"