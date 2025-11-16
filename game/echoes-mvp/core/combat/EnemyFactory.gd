# core/combat/EnemyFactory.gd
# -----------------------------------------------------------------------------
# MVP enemy generator: deterministic dummy packs for early combat testing.
# This module is pure (no singletons, no IO) so the same inputs → same outputs.
#
# Canon notes
#  - §3 Round cadence visibility: simple, readable enemies for early logs.
#  - §6 Realms later: we keep the API so internals can swap to realm packs.
#  - §9 Determinism: explicit seed; stable id order; no hidden randomness.
#  - §12 Balance: numbers are gentle placeholders until curves are wired.
# -----------------------------------------------------------------------------
class_name EnemyFactory

const HeroBal = preload("res://core/config/GameBalance_HeroCombat.gd")
const RealmBal = preload("res://core/config/GameBalance_Realm.gd")

## MVP baseline stats for dummy enemies. Easy to read in logs.
const DUMMY_BASE := {
	"rank": 1,
	"hp": HeroBal.TRAINING_HP,
	"max_hp": HeroBal.TRAINING_MAX_HP,
	"atk": HeroBal.TRAINING_ATK,
	"def": HeroBal.TRAINING_DEF,
	"agi": HeroBal.TRAINING_AGI,
	"morale": HeroBal.TRAINING_MORALE,
	"fear": HeroBal.TRAINING_FEAR,
}

## Realm-aware enemy family mapping for MVP.
## We keep this lean: different names/tags per realm, with stat multipliers
## driven by GameBalance_Realm tier scalars.
const REALM_ENEMY_FAMILY := {
	"vale_of_dust": "wraith",
	"shrouded_grove": "seer",
}

## Spawn a pack of enemies themed around the given Realm/Stage.
##
## @param realm RealmModel - the active realm (virtue, tier, id)
## @param stage StageModel  - the current stage (objective_type, encounter_seed)
## @param wave_index int - optional wave index for multi-wave objectives (default -1)
## @return Array[Dictionary] - enemies in stable order (id asc), suitable for
##         the existing combat harness (same shape as spawn_dummy_pack).
static func spawn_realm_pack(realm, stage, wave_index: int = -1) -> Array[Dictionary]:
	if realm == null or stage == null:
		return []

	var pack_size: int = _get_pack_size_for_stage(realm, stage, wave_index)

	# Deterministic RNG for future small variations (elite markers, etc.).
	# For MVP we do not yet vary stats per enemy, but keeping the RNG seeded
	# means we can safely add that later without breaking determinism.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seed: int = int(stage.encounter_seed)
	if wave_index >= 0:
		# For multi-wave objectives (e.g. Purify Shrine), offset the seed
		# per wave so future small variations remain deterministic per wave.
		seed += wave_index
	rng.seed = seed

	var family: String = _get_family_for_realm(realm)

	# Tier-based stat multipliers from GameBalance_Realm.
	var scalars: Dictionary = RealmBal.get_tier_scalars(realm.tier)
	var power: Dictionary = scalars.get("enemy_power", {})
	var hp_mul: float = float(power.get("hp_mul", 1.0))
	var atk_mul: float = float(power.get("atk_mul", 1.0))
	var agi_mul: float = float(power.get("agi_mul", 1.0))

	var out: Array[Dictionary] = []

	for i in range(pack_size):
		var local_id: int = 2000 + i  # keep distinct from spawn_dummy_pack ids
		var name: String = _build_enemy_name(family, realm, i)

		# Apply tier multipliers on top of MVP dummy baseline.
		var enemy: Dictionary = {
			"id": local_id,
			"name": name,
			"rank": DUMMY_BASE.rank,
			"hp": int(round(DUMMY_BASE.hp * hp_mul)),
			"max_hp": int(round(DUMMY_BASE.max_hp * hp_mul)),
			"atk": int(round(DUMMY_BASE.atk * atk_mul)),
			"def": DUMMY_BASE.def, # kept flat for MVP; curves can adjust later
			"agi": int(round(DUMMY_BASE.agi * agi_mul)),
			"morale": DUMMY_BASE.morale,
			"fear": DUMMY_BASE.fear,
			"tags": ["realm", realm.id, family],
		}

		out.append(enemy)

	# Ensure stable order by id.
	out.sort_custom(Callable(EnemyFactory, "_cmp_id_asc"))
	return out


## Decide pack size based on objective type (MVP-lean).
## For shrine stages we delegate to GameBalance_Realm so pack sizes are
## tier- and wave-aware without hard-coding values here.
static func _get_pack_size_for_stage(realm, stage, wave_index: int) -> int:
	var obj_type := String(stage.objective_type)
	match obj_type:
		"combat_trial":
			# Core combat test: small group, not a swarm.
			return 3
		"purify_shrine":
			# Shrine: use balance config for pack sizing. MVP ignores tier
			# inside get_purify_pack_size, but the signature is future-proof.
			var tier: int = 1
			if realm != null and "tier" in realm:
				tier = int(realm.tier)
			var w_index: int = max(wave_index, 0)
			return RealmBal.get_purify_pack_size(tier, w_index)
		_:
			return 2


## Map a realm to an enemy family token used for naming and tagging.
static func _get_family_for_realm(realm) -> String:
	if realm == null:
		return "wraith"
	return REALM_ENEMY_FAMILY.get(realm.id, "wraith")


## Build a readable enemy name based on family and realm context.
static func _build_enemy_name(family: String, realm, index: int) -> String:
	var base: String = ""
	match family:
		"wraith":
			base = "Dust Wraith"
		"seer":
			base = "Grove Seer"
		_:
			base = "Realm Foe"

	# Example: "Dust Wraith #1", "Grove Seer #2"
	return "%s #%d" % [base, index + 1]

## Generates a deterministic array of dummy enemies for testing the round loop.
##
## @param count int - number of enemies desired (negative → clamped to 0)
## @param seed  int - explicit seed to ensure reproducible outputs
## @return Array[Dictionary] - enemies in stable order (id asc)
static func spawn_dummy_pack(count: int, seed: int) -> Array[Dictionary]:
	var n: int = max(count, 0)
	# We set up an RNG for future tiny variations, but keep MVP dummies fixed.
	# Keeping the RNG seeded ensures we can introduce realm-based variance later
	# without breaking the signature or determinism guarantees.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed

	var out: Array[Dictionary] = []
	for i in range(n):
		var local_id: int = 1000 + i  # avoid clashing with typical hero ids
		var name: String = "Training Wraith #%d" % (i + 1)

		# Copy baseline and build the dictionary explicitly (no mutation of const)
		var enemy: Dictionary = {
			"id": local_id,
			"name": name,
			"rank": DUMMY_BASE.rank,
			"hp": DUMMY_BASE.hp,
			"max_hp": DUMMY_BASE.max_hp,
			"atk": DUMMY_BASE.atk,
			"def": DUMMY_BASE.def,
			"agi": DUMMY_BASE.agi,
			"morale": DUMMY_BASE.morale,
			"fear": DUMMY_BASE.fear,
			"tags": ["dummy"],
		}

		out.append(enemy)

	# Defensive: ensure stable order by id even if future variants add shuffling.
	out.sort_custom(Callable(EnemyFactory, "_cmp_id_asc"))
	return out

# Comparator: sort by id ascending
static func _cmp_id_asc(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("id", 0)) < int(b.get("id", 0))
