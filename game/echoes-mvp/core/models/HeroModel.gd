extends Resource
class_name HeroModel

##
## HeroModel — canonical in-memory representation of a hero.
##
## This script mirrors the hero dictionary schema currently used by HeroesIO
## (id, name, class, arch, traits, stats, etc.) and adds explicit helpers
## for emotional state, which now live in a dedicated `emotion` dictionary
## instead of being mixed into `stats`.
##
## Emotion & Morale Core epic:
##  - emotion.morale_base     — slow-moving baseline (Sanctum, long-term effects).
##  - emotion.morale_current  — current morale in play (battles, shrine, events).
##  - emotion.fear_current    — current fear in play.
##  - EmotionService will read/write these via HeroModel instead of dealing
##    with ad-hoc dictionaries.
##
## NOTE (MVP):
##  - stats continues to hold combat stats (hp, atk, def, etc.).
##  - emotion is now the canonical home for morale/fear.
##  - When loading legacy data that used stats.morale / stats.fear,
##    we migrate those values into the emotion block.
##

# ----------------------------
# Basic identity & archetype
# ----------------------------

var id: int = -1
var name: String = ""
var rank: int = 1

# "class" is a reserved-ish word in GDScript contexts, so we avoid using it
# as a property name directly.
var hero_class: String = ""        # maps to dictionary key "class"
var archetype: String = ""         # maps to dictionary key "arch"
var gender: String = ""            # optional, maps to dictionary key "gender"

# High-level trait & stat dictionaries
var traits: Dictionary = {}        # courage, wisdom, faith, etc.
var stats: Dictionary = {}         # hp, attack, defense, agility, charisma, etc.

# Dedicated emotional state block (MVP)
#   morale_base, morale_current, fear_current
var emotion: Dictionary = {}


# ----------------------------
# Emotion constants (MVP)
# ----------------------------

const MORALE_MIN: int = 0
const MORALE_MAX: int = 100
const FEAR_MIN: int = 0
const FEAR_MAX: int = 100

# Defaults are aligned with emotion_mvp.md:
#  - morale_default around a steady baseline
#  - fear_default low but non-zero if we want a hint of tension later
const MORALE_DEFAULT: int = 60
const FEAR_DEFAULT: int = 5

# Keys used inside emotion dictionary
const KEY_MORALE_BASE := "morale_base"
const KEY_MORALE_CURRENT := "morale_current"
const KEY_FEAR_CURRENT := "fear_current"

# Legacy keys that used to live in stats (for migration only)
const LEGACY_KEY_MORALE := "morale"
const LEGACY_KEY_FEAR := "fear"


# ----------------------------
# Construction & conversion
# ----------------------------

static func from_dict(data: Dictionary) -> HeroModel:
	## Build a HeroModel from a dictionary as produced/consumed by HeroesIO.
	var h := HeroModel.new()

	h.id = int(data.get("id", -1))
	h.name = str(data.get("name", ""))
	h.rank = int(data.get("rank", 1))

	h.hero_class = str(data.get("class", ""))
	h.archetype = str(data.get("arch", ""))
	h.gender = str(data.get("gender", ""))

	# Deep-copy trait and stat dictionaries so HeroModel is not aliasing the
	# original dictionaries. This avoids surprising side-effects.
	var traits_dict: Dictionary = data.get("traits", {})
	var stats_dict: Dictionary = data.get("stats", {})
	var emotion_dict: Dictionary = data.get("emotion", {})

	h.traits = traits_dict.duplicate(true)
	h.stats = stats_dict.duplicate(true)
	h.emotion = emotion_dict.duplicate(true)

	# Ensure emotion entries exist (and migrate any legacy stats-based fields),
	# then clamp them to valid ranges.
	h._ensure_emotion_defaults()

	return h


func to_dict() -> Dictionary:
	## Convert this HeroModel back into the dictionary format expected by HeroesIO.
	var d: Dictionary = {}

	d["id"] = id
	d["name"] = name
	d["rank"] = rank

	if hero_class != "":
		d["class"] = hero_class
	else:
		# Preserve possibility of existing data having "class" missing;
		# HeroesIO may fill defaults.
		d["class"] = ""

	if archetype != "":
		d["arch"] = archetype
	else:
		d["arch"] = ""

	if gender != "":
		d["gender"] = gender

	d["traits"] = traits.duplicate(true)

	# Make sure emotion values are present and clamped before exporting.
	_ensure_emotion_defaults()

	# Export stats separately from emotion.
	# Strip any legacy morale/fear keys from stats to avoid duplication;
	# emotion is the canonical home for these going forward.
	var stats_copy := stats.duplicate(true)
	if stats_copy.has(LEGACY_KEY_MORALE):
		stats_copy.erase(LEGACY_KEY_MORALE)
	if stats_copy.has(LEGACY_KEY_FEAR):
		stats_copy.erase(LEGACY_KEY_FEAR)

	d["stats"] = stats_copy
	d["emotion"] = emotion.duplicate(true)

	return d


# ----------------------------
# Emotion helpers
# ----------------------------

func _ensure_emotion_defaults() -> void:
	## Ensure emotion.morale_base, emotion.morale_current and emotion.fear_current
	## exist and are within valid ranges.
	if emotion == null:
		emotion = {}

	# If we have no emotion block yet but there are legacy stats.morale / stats.fear
	# values, migrate them into the emotion dictionary.
	var migrated_from_stats := false
	if not emotion.has(KEY_MORALE_BASE) and not emotion.has(KEY_MORALE_CURRENT) and (stats != null):
		if stats.has(LEGACY_KEY_MORALE) or stats.has(LEGACY_KEY_FEAR):
			var legacy_morale := MORALE_DEFAULT
			var legacy_fear := FEAR_DEFAULT
			if stats.has(LEGACY_KEY_MORALE) and typeof(stats[LEGACY_KEY_MORALE]) == TYPE_INT:
				legacy_morale = int(stats[LEGACY_KEY_MORALE])
			if stats.has(LEGACY_KEY_FEAR) and typeof(stats[LEGACY_KEY_FEAR]) == TYPE_INT:
				legacy_fear = int(stats[LEGACY_KEY_FEAR])

			emotion[KEY_MORALE_BASE] = legacy_morale
			emotion[KEY_MORALE_CURRENT] = legacy_morale
			emotion[KEY_FEAR_CURRENT] = legacy_fear
			migrated_from_stats = true

	# If emotion is still missing fields, fill with defaults.
	if not emotion.has(KEY_MORALE_BASE) or typeof(emotion[KEY_MORALE_BASE]) != TYPE_INT:
		emotion[KEY_MORALE_BASE] = MORALE_DEFAULT

	if not emotion.has(KEY_MORALE_CURRENT) or typeof(emotion[KEY_MORALE_CURRENT]) != TYPE_INT:
		# If we just migrated from stats, this will already be set; otherwise
		# default to the base morale as the starting current value.
		emotion[KEY_MORALE_CURRENT] = int(emotion[KEY_MORALE_BASE])

	if not emotion.has(KEY_FEAR_CURRENT) or typeof(emotion[KEY_FEAR_CURRENT]) != TYPE_INT:
		emotion[KEY_FEAR_CURRENT] = FEAR_DEFAULT

	# Clamp values into the allowed ranges.
	emotion[KEY_MORALE_BASE] = clamp(int(emotion[KEY_MORALE_BASE]), MORALE_MIN, MORALE_MAX)
	emotion[KEY_MORALE_CURRENT] = clamp(int(emotion[KEY_MORALE_CURRENT]), MORALE_MIN, MORALE_MAX)
	emotion[KEY_FEAR_CURRENT] = clamp(int(emotion[KEY_FEAR_CURRENT]), FEAR_MIN, FEAR_MAX)


func get_morale() -> int:
	## Returns the hero's current morale value (0–100).
	_ensure_emotion_defaults()
	return int(emotion[KEY_MORALE_CURRENT])


func set_morale(value: int) -> void:
	## Set the hero's current morale, clamped to [MORALE_MIN, MORALE_MAX].
	_ensure_emotion_defaults()
	emotion[KEY_MORALE_CURRENT] = clamp(int(value), MORALE_MIN, MORALE_MAX)


func get_morale_base() -> int:
	## Returns the hero's baseline morale value (0–100).
	_ensure_emotion_defaults()
	return int(emotion[KEY_MORALE_BASE])


func set_morale_base(value: int) -> void:
	## Set the hero's baseline morale, clamped to [MORALE_MIN, MORALE_MAX].
	_ensure_emotion_defaults()
	emotion[KEY_MORALE_BASE] = clamp(int(value), MORALE_MIN, MORALE_MAX)
	# Optionally, keep current at least in range of base for MVP;
	# recovery/decay rules can refine this later.
	if int(emotion[KEY_MORALE_CURRENT]) < int(emotion[KEY_MORALE_BASE]):
		emotion[KEY_MORALE_CURRENT] = int(emotion[KEY_MORALE_BASE])


func get_fear() -> int:
	## Returns the hero's current fear value (0–100).
	_ensure_emotion_defaults()
	return int(emotion[KEY_FEAR_CURRENT])


func set_fear(value: int) -> void:
	## Set the hero's current fear, clamped to [FEAR_MIN, FEAR_MAX].
	_ensure_emotion_defaults()
	emotion[KEY_FEAR_CURRENT] = clamp(int(value), FEAR_MIN, FEAR_MAX)


# ----------------------------
# Convenience: bulk emotion API
# ----------------------------

func apply_emotion_delta(morale_delta: int, fear_delta: int) -> void:
	## Apply a delta to morale/fear, respecting clamping.
	set_morale(get_morale() + int(morale_delta))
	set_fear(get_fear() + int(fear_delta))


func get_emotion_snapshot() -> Dictionary:
	## Return a small dictionary with the current emotional state.
	_ensure_emotion_defaults()
	return {
		"morale_base": get_morale_base(),
		"morale_current": get_morale(),
		"fear_current": get_fear(),
	}