# SeedBook.gd — Pure seed derivation helpers
# These functions are PURE: no globals, no mutation, no timers, no randomness.
# They concatenate a stable "namespace string" and feed it into XXHash64.xxh64_string
# to get a 64-bit deterministic integer you can use as a seed for PCG32.

extends RefCounted

# --- Small helper: canonicalize user/context text so "Economy", " economy ", "ECONOMY"
# all hash the same. This avoids surprising differences from casing/whitespace.
static func _canon(s: String) -> String:
	# If later you want true Unicode normalization, do it here.
	return s.strip_edges().to_lower()

# Campaign seed from human inputs (only if you DON'T already have one).
# If you already store `campaign_seed` as an int somewhere, you can skip this.
static func campaign_seed_from_inputs(player_id: String, mode: String, world_key: String) -> int:
	var buf := "campaign|pid=" + _canon(player_id) \
		+ "|mode=" + _canon(mode) \
		+ "|world=" + _canon(world_key)
	# Single stable hash → one 64-bit int. Deterministic across runs/machines.
	return XXHash64.xxh64_string(buf)

# Derive a seed for a top-level SYSTEM stream (e.g., "combat", "economy", "ai")
# Using 'sys|' keeps namespaces distinct so keys don't collide with others (like "realm|").
static func derive_for_system(campaign_seed: int, system_key: String) -> int:
	var buf := "sys|" + str(campaign_seed) + "|" + _canon(system_key)
	return XXHash64.xxh64_string(buf)

# Derive a seed per REALM index (0,1,2...)
static func derive_for_realm(campaign_seed: int, realm_index: int) -> int:
	var buf := "realm|" + str(campaign_seed) + "|" + str(realm_index)
	return XXHash64.xxh64_string(buf)

# Derive for an arbitrary hierarchical SCOPE path (e.g., "realm/3/encounter/12/loot")
# Tip: Build paths consistently in your callers so the same path always produces the same seed.
static func derive_for_scope(campaign_seed: int, scope_path: String) -> int:
	var path := _canon(scope_path)          # normalize spacing/case
	var buf := "scope|" + str(campaign_seed) + "|" + path
	return XXHash64.xxh64_string(buf)

# Optional: include an extra "salt" so you can split two independent streams for the same scope.
# Example usage: derive_with_salt(campaign_seed, "combat", "damage") vs "ai"
static func derive_with_salt(campaign_seed: int, scope_key: String, salt: String) -> int:
	var buf := "salt|" + str(campaign_seed) + "|" + _canon(scope_key) + "|" + _canon(salt)
	return XXHash64.xxh64_string(buf)

# =============================================================
# Seed inspector accessors (Step 2)
# Read-only wrappers that delegate to RNCatalogIO and SaveService
# =============================================================

static func _realm_key(realm_id: String) -> String:
	return "realm:%s" % realm_id

static func _stage_key(realm_id: String, stage_index: int) -> String:
	return "stage:%s:%d" % [realm_id, stage_index]

## Canonical campaign seed accessor (persisted as String)
static func get_campaign_seed() -> String:
	return RNCatalogIO.get_campaign_seed()

## Deterministic realm seed; ensures the realm stream exists and returns its subseed
static func get_realm_seed(realm_id: String) -> String:
	var key := _realm_key(realm_id)
	RNCatalogIO.ensure_stream(key)
	return RNCatalogIO.get_subseed(key, "")

## Deterministic stage seed; derived from the realm stream
static func get_stage_seed(realm_id: String, stage_index: int) -> String:
	var parent_key := _realm_key(realm_id)
	var key := _stage_key(realm_id, stage_index)
	RNCatalogIO.ensure_stream(parent_key)
	RNCatalogIO.ensure_stream(key, parent_key)
	return RNCatalogIO.get_subseed(key, "")

## Snapshot of all known PRNG cursors (stream -> int)
static func get_cursors() -> Dictionary:
	return (RNCatalogIO.pack_current().get("cursors", {}) as Dictionary).duplicate(true)

## Convenience bundle for /seed_info printing
static func get_all_seed_info() -> Dictionary:
	var snap := SaveService.snapshot()
	var info := {
		"campaign_seed": get_campaign_seed(),
		"realms": [],
		"stages": [],
		"cursors": get_cursors()
	}
	var realms: Array = (snap.get("realm_states", []) as Array)
	for r in realms:
		var rd := r as Dictionary
		var realm_id := String(rd.get("realm_id", ""))
		var stage_index := int(rd.get("stage_index", 0))
		# realm row
		var realm_seed := get_realm_seed(realm_id)
		info["realms"].append({
			"realm_id": realm_id,
			"realm_seed": realm_seed,
			"stage_index": stage_index
		})
		# stage row
		var stage_seed := get_stage_seed(realm_id, stage_index)
		info["stages"].append({
			"realm_id": realm_id,
			"stage_index": stage_index,
			"stage_seed": stage_seed
		})
	return info
