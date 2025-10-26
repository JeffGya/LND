extends Resource
class_name EchoFactory

const PersonalityArchetype = preload("res://core/echoes/PersonalityArchetype.gd")

## EchoFactory — deterministic Echo generation (Subtask 5)
##
## Contract:
##  • Pure function: builds a hero Dictionary WITHOUT id (HeroesIO assigns id).
##  • Deterministic seed derived from (campaign_seed, "summon", roster_count).
##  • RNG draw order MUST remain stable:
##      (1) gender bit  → (2) first name  → (3) last name  → (4) traits: courage,wisdom,faith
##    Changing this order will change deterministic outputs.
##  • Class at birth is always "none" (rank 1 Uncalled).
##  • Gender is metadata-only; no impact on stats/emotions.

static func summon_one(campaign_seed: int, roster_count: int, utc_now: String) -> Dictionary:
	return _build_hero(campaign_seed, EconomyConstants.RNG_CHANNEL_SUMMON, roster_count, utc_now)

static func summon_one_starter(campaign_seed: int, roster_count: int, utc_now: String) -> Dictionary:
	# Starter hero generation (free on New Game). Uses a separate RNG channel so
	# it never consumes from the paid summon stream and remains deterministic per campaign.
	return _build_hero(campaign_seed, EconomyConstants.RNG_CHANNEL_STARTER, roster_count, utc_now)

static func _build_hero(campaign_seed: int, channel: String, roster_count: int, utc_now: String) -> Dictionary:
	var local_seed := _derive_seed(campaign_seed, channel, roster_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = local_seed

	# (1) Gender bit (even → female, odd → male)
	var gender := EchoConstants.GENDER_FEMALE if (rng.randi() & 1) == 0 else EchoConstants.GENDER_MALE

	# (2) First name (gendered pool)
	var first := NameBank.pick_female_first(rng) if gender == EchoConstants.GENDER_FEMALE else NameBank.pick_male_first(rng)
	# (3) Last name
	var last := NameBank.pick_last(rng)
	var full_name := "%s %s" % [first, last]

	# (4) Trait rolls (uniform in bounds; bias knobs can be added later without changing signature)
	var c := _roll_in_range(rng, EchoConstants.TRAIT_ROLL_MIN, EchoConstants.TRAIT_ROLL_MAX)
	var w := _roll_in_range(rng, EchoConstants.TRAIT_ROLL_MIN, EchoConstants.TRAIT_ROLL_MAX)
	var f := _roll_in_range(rng, EchoConstants.TRAIT_ROLL_MIN, EchoConstants.TRAIT_ROLL_MAX)

	# Compute deterministic archetype based on rolled traits
	var arch := PersonalityArchetype.pick_archetype(c, w, f)

	var hero := {
		"name": full_name,
		"rank": 1,
		"class": EchoConstants.CLASS_NONE,
		"archetype": arch,
		"gender": gender,
		"traits": {"courage": c, "wisdom": w, "faith": f},
		"seed": local_seed,
		"created_utc": utc_now
	}

	# Debug-time schema check
	if OS.is_debug_build():
		var v := Echo.validate(hero)
		if not v.ok:
			push_warning("EchoFactory.validate failed: %s" % v.message)

	return hero

# ----------------------
# Helpers
# ----------------------
static func _derive_seed(campaign_seed: int, channel: String, index: int) -> int:
	# Use a stable hash of a compact string to avoid 64-bit overflow pitfalls.
	# Mixing back campaign_seed via XOR reduces trivial collisions.
	var material := "%d|%s|%d" % [campaign_seed, channel, index]
	var h := int(hash(material))
	return int(h ^ campaign_seed)

static func _roll_in_range(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	var span := hi - lo + 1
	var v := lo + int(floor(rng.randf() * float(span)))
	if v > hi:
		v = hi
	return v