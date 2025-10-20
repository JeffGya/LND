# SeedBook.gd — Pure seed derivation helpers
# These functions are PURE: no globals, no mutation, no timers, no randomness.
# They concatenate a stable "namespace string" and feed it into XXHash64.xxh64_string
# to get a 64-bit deterministic integer you can use as a seed for PCG32.

class_name SeedBook
extends RefCounted

const XXHash64 = preload("res://core/seed/XXHash64.gd")

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
