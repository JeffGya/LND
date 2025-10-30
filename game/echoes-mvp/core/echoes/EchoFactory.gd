extends Resource
class_name EchoFactory

const PersonalityArchetype = preload("res://core/echoes/PersonalityArchetype.gd")
const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")

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

	hero["stats"] = _compute_stats(c, w, f)

	# Debug-time schema check
	if OS.is_debug_build():
		var v := Echo.validate(hero)
		if not v.ok:
			push_warning("EchoFactory.validate failed: %s" % v.message)

	return hero

# ----------------------
# Deterministic combat stat generation (MVP)
# ----------------------
static func _compute_stats(c: int, w: int, f: int) -> Dictionary:
	# Base formulas — deterministic, early-game compressed (pass 2)
	# Target after seeing live rolls: HP should sit mostly in 20–30 for typical 30–70 traits,
	# with high-roll heroes (all traits ~60+) still staying under ~32–34.
	# HP: 5 + courage×0.25 + faith×0.15  → clamp min 15
	var hp: int = _ri(
		float(HeroBal.HERO_HP_BASE)
		+ HeroBal.HERO_HP_COURAGE_MUL * float(c)
		+ HeroBal.HERO_HP_FAITH_MUL * float(f)
	)
	if hp < HeroBal.HERO_HP_MIN:
		hp = HeroBal.HERO_HP_MIN

	# ATK: 4 + courage×0.12 + faith×0.05  → ~10–15 for normal heroes
	var atk: int = _ri(
		float(HeroBal.HERO_ATK_BASE)
		+ HeroBal.HERO_ATK_COURAGE_MUL * float(c)
		+ HeroBal.HERO_ATK_FAITH_MUL * float(f)
	)
	if atk < 1:
		atk = 1

	# DEF: 2 + wisdom×0.12 + faith×0.08  → small but present, stays under ~12
	var def: int = _ri(
		float(HeroBal.HERO_DEF_BASE)
		+ HeroBal.HERO_DEF_WIS_MUL * float(w)
		+ HeroBal.HERO_DEF_FAITH_MUL * float(f)
	)
	if def < 0:
		def = 0

	# AGI: 2 + wisdom×0.08 + courage×0.08  → slightly lower than before to match smaller HP pool
	var agi: int = _ri(
		float(HeroBal.HERO_AGI_BASE)
		+ HeroBal.HERO_AGI_WIS_MUL * float(w)
		+ HeroBal.HERO_AGI_COUR_MUL * float(c)
	)
	if agi < 0:
		agi = 0

	# CHA: 1 + faith×0.08 + wisdom×0.08
	var cha: int = _ri(
		float(HeroBal.HERO_CHA_BASE)
		+ HeroBal.HERO_CHA_FAITH_MUL * float(f)
		+ HeroBal.HERO_CHA_WIS_MUL * float(w)
	)
	if cha < 0:
		cha = 0

	# INT: 4 + wisdom×0.22 + courage×0.04  → keep this a bit higher for future AI/decision use
	var intel: int = _ri(
		float(HeroBal.HERO_INT_BASE)
		+ HeroBal.HERO_INT_WIS_MUL * float(w)
		+ HeroBal.HERO_INT_COUR_MUL * float(c)
	)
	if intel < 0:
		intel = 0

	# --- MVP placeholders (deterministic but not yet active in combat) ---
	var acc: int = HeroBal.HERO_ACC_BASE
	var eva: int = HeroBal.HERO_EVA_BASE
	var crit: int = HeroBal.HERO_CRIT_BASE

	return {
		EchoConstants.STAT_HP: hp,
		EchoConstants.STAT_MAX_HP: hp,
		EchoConstants.STAT_ATK: atk,
		EchoConstants.STAT_DEF: def,
		EchoConstants.STAT_AGI: agi,
		EchoConstants.STAT_CHA: cha,
		EchoConstants.STAT_INT: intel,
		EchoConstants.STAT_ACC: acc,
		EchoConstants.STAT_EVA: eva,
		EchoConstants.STAT_CRIT: crit,
		EchoConstants.STAT_MORALE: 50,
		EchoConstants.STAT_FEAR: 0,
	}

# ----------------------
# Helpers
# ----------------------
# Integer rounding helper (class-scope to avoid local lambda issues on some builds)
static func _ri(x: float) -> int:
	return int(round(x))

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
