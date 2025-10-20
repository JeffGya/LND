# SeedService.gd — Centralized, simple API to fetch PRNGs per scope.
# This will be AutoLoaded so you can call SeedService.* from anywhere.

extends Node
# ^ We extend Node (not RefCounted) because AutoLoads are Nodes in the scene tree.

# We depend on the *pure* SeedBook derivations and the PCG32 generator you built.
const SeedBook = preload("res://core/seed/SeedBook.gd")
const PCG32    = preload("res://core/seed/PCG32.gd")

# The seed that defines the *entire* campaign’s randomness timeline.
var campaign_seed: int = 0

# Internal cache so calls like rng_for_system("combat") return the SAME instance
# during a run. This avoids "losing your place" in the random stream.
# Key: String ("sys|combat", "realm|0", "scope|realm/1/encounter/5/loot")
# Val: PCG32 instance
var _cache := {}

# --- Public: Initialize the service with a campaign seed ----------------------

# Call this once at New Game (or Load Game with a saved seed).
func init_with_campaign(seed_value: int) -> void:
	campaign_seed = seed_value
	_cache.clear()  # Fresh run. Streams will be created lazily on first use.

# --- Internal: helpers to build stable cache keys (namespaces prevent collision)

static func _sys_key(system_key: String) -> String:
	# "sys|" namespace keeps it distinct from "realm|" and "scope|"
	return "sys|" + system_key

static func _realm_key(realm_index: int) -> String:
	return "realm|" + str(realm_index)

static func _scope_key(scope_path: String) -> String:
	# Keep paths consistent in callers: e.g., "realm/1/encounter/5/loot"
	return "scope|" + scope_path

# --- Public: PRNG factories (cached) -----------------------------------------

# Get a PRNG for a *system* (e.g., "combat", "economy", "ai").
# `stream` is optional: lets you split sub-streams if needed later.
func rng_for_system(system_key: String, stream: int = 54) -> PCG32:
	var k := _sys_key(system_key)
	if not _cache.has(k):
		# Derive a stable seed FROM the campaign seed + key
		var sd: int = SeedBook.derive_for_system(campaign_seed, system_key)
		# Create a PCG32 from that seed; cache it so we return the same instance next time.
		_cache[k] = PCG32.new_with_seed(sd, stream)
	return _cache[k]

# Get a PRNG for a specific REALM index (0,1,2…)
func rng_for_realm(realm_index: int, stream: int = 54) -> PCG32:
	var k := _realm_key(realm_index)
	if not _cache.has(k):
		var sd: int = SeedBook.derive_for_realm(campaign_seed, realm_index)
		_cache[k] = PCG32.new_with_seed(sd, stream)
	return _cache[k]

# Get a PRNG for an arbitrary hierarchical SCOPE path
# (e.g., "realm/1/encounter/5/loot"). Useful for fine-grained determinism.
func rng_for_scope(scope_path: String, stream: int = 54) -> PCG32:
	var k := _scope_key(scope_path)
	if not _cache.has(k):
		var sd: int = SeedBook.derive_for_scope(campaign_seed, scope_path)
		_cache[k] = PCG32.new_with_seed(sd, stream)
	return _cache[k]
