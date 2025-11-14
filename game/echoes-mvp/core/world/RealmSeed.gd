extends Resource
class_name RealmSeed
## RealmSeed
## Deterministic seed derivation helpers for Realms and their stages.
## Canon anchors:
##  - §6 World / Realm Structure: Realms are seeded structures.
##  - §12 Balance Curves & §13 Technical Model: deterministic generation.
##
## Responsibilities:
##  - Derive a realm-specific seed from the campaign seed + realm id + tier.
##  - Derive per-stage seeds from the realm seed + stage index.
##
## This file:
##  - does NOT call any RNG by itself,
##  - does NOT touch save/load directly,
##  - only performs simple, reproducible integer mixing.
##
## Usage:
##  - RealmGenerator.generate() should call:
##        var r_seed = RealmSeed.realm_seed(campaign_seed, realm_id, tier)
##        var s_seed = RealmSeed.stage_seed(r_seed, stage_index)
##  - Save/load should store the campaign_seed; realm/stage seeds can always
##    be recomputed from that master seed and identifiers.

# We keep all mixing within 32-bit signed range to avoid overflow issues.
const MASK_31BIT: int = 0x7fffffff

# Small, safe constants taken from classic linear congruential generator patterns.
const MUL_A: int = 1103515245
const ADD_A: int = 12345
const MUL_B: int = 196314165
const ADD_B: int = 907633515


static func _hash_string_to_int(text: String) -> int:
	## Simple, stable hash for turning realm_id into an integer key.
	## We intentionally keep this straightforward and 31-bit masked.
	## Note: In Godot 4, use String.unicode_at() instead of ord()/ord_at().
	var h: int = 0
	var length: int = text.length()
	for i in length:
		var code_point: int = text.unicode_at(i)
		h = (h * 31 + code_point) & MASK_31BIT
	return h


static func _mix3(a: int, b: int, c: int) -> int:
	## Mix three integers into a single deterministic 31-bit value.
	## This is NOT cryptographically secure; it is only meant to
	## distribute bits well enough for game RNG seeding.
	var x: int = int(a) & MASK_31BIT
	var y: int = int(b) & MASK_31BIT
	var z: int = int(c) & MASK_31BIT

	x = int((x * MUL_A + ADD_A) & MASK_31BIT)
	y = int((y * MUL_B + ADD_B) & MASK_31BIT)
	var mixed: int = (x ^ y ^ z) & MASK_31BIT

	# Avoid returning 0 as a seed; many RNGs treat seed=0 as special.
	if mixed == 0:
		mixed = 1
	return mixed


static func realm_seed(campaign_seed: int, realm_id: String, tier: int) -> int:
	## Derive a realm-specific seed from:
	##  - campaign_seed: the master seed for the player's run
	##  - realm_id: stable id (e.g. "vale_of_dust")
	##  - tier: difficulty tier
	##
	## Same (campaign_seed, realm_id, tier) tuple MUST always produce the
	## same result across runs and platforms.
	var realm_key: int = _hash_string_to_int(realm_id)
	var t: int = max(1, tier)  # defensive: clamp tier to >= 1
	return _mix3(campaign_seed, realm_key, t)


static func stage_seed(realm_seed_value: int, stage_index: int) -> int:
	## Derive a deterministic seed for a specific stage within a realm.
	##
	## Inputs:
	##  - realm_seed_value: output from realm_seed(...)
	##  - stage_index: 0-based index of the stage in the realm
	##
	## Same (realm_seed_value, stage_index) MUST always produce the
	## same result. Different indices should map to different seeds.
	var index_safe: int = max(0, stage_index)
	# Use index+1 so stage 0 does not collide with any "zero" padding.
	return _mix3(realm_seed_value, index_safe + 1, 0)


static func rng_for_realm(campaign_seed: int, realm_id: String, tier: int) -> RandomNumberGenerator:
	## Convenience helper: build an RNG seeded from realm_seed().
	var rng := RandomNumberGenerator.new()
	rng.seed = realm_seed(campaign_seed, realm_id, tier)
	return rng


static func rng_for_stage(realm_seed_value: int, stage_index: int) -> RandomNumberGenerator:
	## Convenience helper: build an RNG seeded from stage_seed().
	var rng := RandomNumberGenerator.new()
	rng.seed = stage_seed(realm_seed_value, stage_index)
	return rng
