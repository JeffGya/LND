# res://core/sim/DemoSimHarness.gd
# Purpose: A tiny, deterministic "demo run" that prints a single multiline log.

extends Node

# NOTE: SeedService is an AutoLoad singleton. Call SeedService.* directly; do NOT preload it here.

static func build_log(campaign_seed: int) -> String:
	SeedService.init_with_campaign(campaign_seed)

	var out: String = ""
	out += "=== Demo Simulation Log ===\n"
	out += "Campaign seed: %d\n" % campaign_seed
	out += "----------------------------\n"

	# 1) Realm-scoped RNGs (independent streams)
	for realm_index in 2: # realms 0 and 1
		var rng := SeedService.rng_for_realm(realm_index)
		out += "Realm %d rolls:" % realm_index
		for i in 3:
			out += " %d" % rng.next_u32()
		out += "\n"

	# 2) System-scoped RNGs (independent of realms and each other)
	var sys_combat := SeedService.rng_for_system("combat")
	var sys_econ   := SeedService.rng_for_system("economy")

	out += "Combat rolls:"
	for i in 3:
		out += " %d" % sys_combat.next_u32()
	out += "\n"

	out += "Economy rolls:"
	for i in 3:
		out += " %d" % sys_econ.next_u32()
	out += "\n"

	# 3) Arbitrary scope path (nested/leaf scope)
	var scope_rng := SeedService.rng_for_scope("realm/1/encounter/5/loot")
	out += "Loot table rolls:"
	for i in 5:
		out += " %d" % scope_rng.next_u32()
	out += "\n"

	out += "----------------------------\n"
	out += "Simulation complete.\n"

	return out

static func run_demo(campaign_seed: int) -> void:
	print(build_log(campaign_seed))

func _ready() -> void:
	# Use your known stable campaign seed so repeated runs match byte-for-byte.
	var cs: int = 885677476959259660
	run_demo(cs)
